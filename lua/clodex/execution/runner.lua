local Backend = require("clodex.backend")
local History = require("clodex.history")
local fs = require("clodex.util.fs")
local git = require("clodex.util.git")
local notify = require("clodex.util.notify")

local FINISHED_MESSAGE = "Direct Codex run finished for %s: %s"
local NOT_UPDATED_MESSAGE = "Direct Codex run finished for %s but did not update the implemented item automatically: %s"
local FAILED_MESSAGE = "Direct Codex run failed for %s: %s (exit %d)"

local RUN_OUTPUT_SCHEMA = {
    type = "object",
    additionalProperties = false,
    properties = {
        summary = {
            type = "string",
            description = "One short sentence summarizing the outcome or blocker.",
        },
        response = {
            type = "string",
            description = "Natural-language response for the user. Markdown is allowed.",
        },
    },
    required = { "summary", "response" },
}

---@class Clodex.ExecutionRunner
---@field app Clodex.App
---@field config Clodex.Config.Values
---@field active table<string, vim.SystemObj>
local Runner = {}
Runner.__index = Runner

---@param project Clodex.Project
---@param item Clodex.QueueItem
---@return string
local function run_key(project, item)
    return ("%s::%s"):format(project.root, item.id)
end

---@param execution Clodex.Workspace.Execution
---@param project Clodex.Project
---@param item Clodex.QueueItem
---@return string
local function run_dir(execution, project, item)
    return fs.join(execution:project_execution_dir(project), "runs", item.id)
end

---@param path string
---@return table?
local function read_json_file(path)
    local decoded = fs.read_json(path, nil)
    return type(decoded) == "table" and decoded or nil
end

local function run_finished_message(project, item)
    return FINISHED_MESSAGE:format(project.name, item.title)
end

local function run_not_updated_message(project, item)
    return NOT_UPDATED_MESSAGE:format(project.name, item.title)
end

local function run_failed_message(project, item, code)
    return FAILED_MESSAGE:format(project.name, item.title, code)
end

local function uses_prompt_skill(execution)
    return execution and execution.uses_prompt_skill and execution:uses_prompt_skill()
end

---@param message table?
---@return string?
local function response_summary(message)
    if type(message) ~= "table" then
        return nil
    end
    local summary = vim.trim(message.summary or "")
    return summary ~= "" and summary or nil
end

---@param project Clodex.Project
---@param item Clodex.QueueItem
---@param schema_path string
---@param output_path string
---@return string[]
local function build_command(project, item, schema_path, output_path)
    local cmd = {
        "exec",
        "--cd",
        project.root,
        "--skip-git-repo-check",
        "--full-auto",
        "--ephemeral",
        "--output-schema",
        schema_path,
        "--output-last-message",
        output_path,
    }
    if item.image_path and fs.is_file(item.image_path) then
        table.insert(cmd, "--image")
        table.insert(cmd, item.image_path)
    end
    table.insert(cmd, "-")
    return cmd
end

---@param app Clodex.App
---@param config Clodex.Config.Values
---@return Clodex.ExecutionRunner
function Runner.new(app, config)
    return setmetatable({
        app = app,
        config = config,
        active = {},
    }, Runner)
end

---@param config Clodex.Config.Values
function Runner:update_config(config)
    self.config = config
end

---@param project_root string
---@return boolean
function Runner:is_project_active(project_root)
    local prefix = ("%s::"):format(project_root)
    for key in pairs(self.active) do
        if vim.startswith(key, prefix) then
            return true
        end
    end
    return false
end

---@param project Clodex.Project
---@param item Clodex.QueueItem
---@param summary string?
---@return boolean
function Runner:complete_item(project, item, summary)
    local queue_name = self.app.queue:find_item(project, item.id)
    if queue_name ~= "implemented" then
        return false
    end

    local fallback_summary = vim.trim(summary or "")
    if fallback_summary == "" then
        return false
    end

    self.app.queue:update_implemented_item(project, item.id, {
        summary = fallback_summary,
        commit = git.head_commit(project.root, true),
        completed_at = os.date("!%Y-%m-%dT%H:%M:%SZ"),
    })
    if item.completion_target == "history" then
        self.app.queue:advance(project, item.id)
    end
    self.app.queue_actions:remember_workspace_revision(project)
    History.append_prompt_resolved(project.name, item.title, fallback_summary)
    return true
end

---@param project Clodex.Project
---@param item Clodex.QueueItem
---@param result vim.SystemCompleted
---@param run_dir string
---@param output_path string
function Runner:handle_completion(project, item, result, run_dir, output_path)
    local message = read_json_file(output_path)
    fs.remove(run_dir)

    if result.code == 0 then
        if uses_prompt_skill(self.app.execution) then
            notify.notify(run_finished_message(project, item))
        else
            local summary = response_summary(message)
            if self:complete_item(project, item, summary) then
                notify.notify(run_finished_message(project, item))
            else
                notify.warn(run_not_updated_message(project, item))
            end
        end
    else
        notify.error(run_failed_message(project, item, result.code))
    end

    self.app.project_details_store:touch_activity(project)
    self.app:refresh_changed_project_buffers()
    self.app:refresh_views()
end

---@param project Clodex.Project
---@param item Clodex.QueueItem
---@return boolean
function Runner:start(project, item)
    if not Backend.supports_direct_exec(self.config.backend) then
        notify.warn(
            ("%s direct exec mode is not supported yet; use the interactive session flow instead."):format(
                Backend.display_name(self.config.backend)
            )
        )
        return false
    end

    local key = run_key(project, item)
    if self.active[key] then
        notify.warn(("Direct Codex run is already active for %s: %s"):format(project.name, item.title))
        return false
    end

    local dir = run_dir(self.app.execution, project, item)
    local schema_path = fs.join(dir, "response.schema.json")
    local output_path = fs.join(dir, "last-message.json")
    local prompt = self.app.execution:dispatch_prompt(project, item)
    if prompt == "" then
        notify.warn(("Cannot run empty prompt for %s"):format(project.name))
        return false
    end

    local cmd = Backend.cli_cmd(self.config)
    vim.list_extend(cmd, build_command(project, item, schema_path, output_path))

    fs.write_json(schema_path, RUN_OUTPUT_SCHEMA)

    local ok, system = pcall(vim.system, cmd, {
        cwd = project.root,
        env = Backend.cli_env(self.config),
        text = true,
        stdin = prompt,
    }, vim.schedule_wrap(function(result)
        self.active[key] = nil
        self:handle_completion(project, item, result, dir, output_path)
    end))

    if not ok or not system then
        notify.error(("Could not start direct Codex run for %s: %s"):format(project.name, item.title))
        return false
    end

    self.active[key] = system
    self.app.project_details_store:touch_activity(project)
    return true
end

return Runner
