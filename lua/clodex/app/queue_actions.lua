local Backend = require("clodex.backend")
local History = require("clodex.history")
local Mcp = require("clodex.mcp")
local fs = require("clodex.util.fs")
local notify = require("clodex.util.notify")

local COMMIT_ICON = "󰜘 "

--- Moves/restricts options for queue rewind operations in queue actions.
--- The options are interpreted by App-level handlers when items are moved backward.
---@alias Clodex.AppQueueActions.RewindOpts { copy?: boolean, queue?: Clodex.QueueName, mark_not_working?: boolean, note?: string }

--- Defines the Clodex.AppQueueActions.MoveOpts type for this module.
--- This annotation documents structured state so modules can pass data with consistent expectations.
---@alias Clodex.AppQueueActions.MoveOpts { target_queue?: Clodex.QueueName, source_queue?: Clodex.QueueName, copy?: boolean }

--- Defines the Clodex.AppQueueActions type for this module.
--- This annotation documents structured state so modules can pass data with consistent expectations.
---@alias Clodex.AppQueueActions.Host Clodex.App

---@class Clodex.AppQueueActions
---@field app Clodex.AppQueueActions.Host
---@field workspace_revisions table<string, string?>
local QueueActions = {}
QueueActions.__index = QueueActions

local CONTINUE_AFTER_CLOSE_RETRY_MS = 250
local CONTINUE_AFTER_CLOSE_MAX_ATTEMPTS = 120

local function refresh_terminal_chrome()
    local ok, terminal_ui = pcall(require, "clodex.terminal.ui")
    if ok and terminal_ui and type(terminal_ui.refresh_all_chrome) == "function" then
        terminal_ui.refresh_all_chrome()
    end
end

---@class Clodex.AppQueueActions.AddTodoOpts
---@field queue? Clodex.QueueName
---@field implement? boolean
---@field run_mode? "interactive"|"exec"
---@field start_mode? "plan"

local PREVIOUS_QUEUE = {
    queued = "planned",
    implemented = "queued",
    history = "implemented",
}

local function touch_and_record_project(self, project)
    if not project then
        return
    end
    self:remember_workspace_revision(project)
    self.app.project_details_store:touch_activity(project)
end

local function touch_and_record_projects(self, ...)
    local total = select("#", ...)
    for i = 1, total do
        touch_and_record_project(self, select(i, ...))
    end
    self.app:refresh_views()
end

---@param actions Clodex.AppQueueActions
---@param project Clodex.Project
---@param item_id string
---@param queue_name? Clodex.QueueName
---@return Clodex.QueueName, Clodex.QueueItem?
local function find_item_in_queue(actions, project, item_id, queue_name)
    if queue_name then
        return actions.app.queue:find_item(project, item_id, queue_name)
    end
    return actions.app.queue:find_item(project, item_id)
end

---@param value any
---@return string
local function trimmed_text(value)
    if value == nil or value == vim.NIL then
        return ""
    end
    if type(value) == "string" then
        return vim.trim(value)
    end
    return vim.trim(tostring(value))
end

---@param item Clodex.QueueItem
---@param opts Clodex.AppQueueActions.RewindOpts
---@return Clodex.QueueItem
local function rewind_item_spec(item, opts)
    local moved = vim.deepcopy(item)
    if not opts.mark_not_working then
        return moved
    end

    local sections = {} ---@type string[]

    local original_title = trimmed_text(moved.title)
    local original_details = trimmed_text(moved.details)
    local note = trimmed_text(opts.note)
    local commits = moved.history_commits or {}
    local commit_summary = trimmed_text(moved.history_summary)

    local header =
        "A previously implemented feature or fix is not working as expected. The original implementation needs to be investigated and fixed."
    sections[#sections + 1] = header

    local original_section = { "## Original Prompt" }
    if original_title ~= "" then
        original_section[#original_section + 1] = ("**Title:** %s"):format(original_title)
    end
    if original_details ~= "" then
        original_section[#original_section + 1] = original_details
    end
    if #original_section > 1 then
        sections[#sections + 1] = table.concat(original_section, "\n\n")
    end

    if #commits > 0 or commit_summary ~= "" then
        local impl_section = { "## Implementation Details" }
        if #commits > 0 then
            local commit_parts = {}
            for _, commit_id in ipairs(commits) do
                local short = commit_id:sub(1, 8)
                commit_parts[#commit_parts + 1] = ("`%s%s`"):format(COMMIT_ICON, short)
            end
            impl_section[#impl_section + 1] = ("**Commits:** %s"):format(table.concat(commit_parts, " "))
        end
        if commit_summary ~= "" then
            impl_section[#impl_section + 1] = ("**Summary:** %s"):format(commit_summary)
        end
        sections[#sections + 1] = table.concat(impl_section, "\n\n")
    end

    if note ~= "" then
        sections[#sections + 1] = "## User Note\n\n" .. note
    end

    local instructions =
        "## Instructions\n\nInvestigate why the previously implemented functionality is not working correctly. Review the original implementation, identify the regression or bug, and implement a fix. Ensure the behavior works as originally intended."
    sections[#sections + 1] = instructions

    moved.details = table.concat(sections, "\n\n")
    moved.prompt = ("%s\n\n%s"):format(moved.title, moved.details)
    moved.kind = "notworking"
    moved.history_summary = nil
    moved.history_commits = vim.deepcopy(commits)
    moved.history_completed_at = nil
    return moved
end

---@param item Clodex.QueueItem
---@return { backend: Clodex.Backend.Name, id: string }?
local function item_history_session(item)
    local session = type(item.history_session) == "table" and item.history_session or nil
    local backend = session and Backend.normalize(session.backend) or nil
    local id = session and type(session.id) == "string" and vim.trim(session.id) or nil
    if not backend or not id or id == "" then
        return nil
    end
    return {
        backend = backend,
        id = id,
    }
end

---@param actions Clodex.AppQueueActions
---@param item Clodex.QueueItem
---@return string?
local function resume_session_id_for_item(actions, item)
    if item.kind ~= "notworking" then
        return nil
    end
    local session = item_history_session(item)
    if not session then
        return nil
    end
    local config = actions.app.config and actions.app.config.get and actions.app.config:get() or nil
    local backend = config and Backend.normalize(config.backend) or "codex"
    if session.backend ~= backend then
        notify.warn(("Saved %s session cannot be resumed while %s backend is active"):format(
            Backend.display_name(session.backend),
            Backend.display_name(backend)
        ))
        return nil
    end
    return session.id
end

---@param session Clodex.TerminalSession
---@param item Clodex.QueueItem
---@return boolean
local function prepare_session_start_mode(session, item)
    if item.start_mode ~= "plan" then
        return true
    end
    return session:send("/plan")
end

---@return string
local function iso_utc_now()
    local timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ")
    return type(timestamp) == "string" and timestamp or ""
end

---@param actions Clodex.AppQueueActions
---@return boolean
local function review_after_completion_enabled(actions)
    local config = actions.app.config and actions.app.config.get and actions.app.config:get() or nil
    if not config or not config.prompt_execution then
        return false
    end
    return config.prompt_execution.review_after_completion == true
end

---@param item Clodex.QueueItem
---@return boolean
local function item_has_commits(item)
    return type(item.history_commits) == "table" and #item.history_commits > 0
end

---@param item Clodex.QueueItem
---@return string
local function review_prompt_details(item)
    local sections = {
        "Review the changes made for the completed queued task. Focus on correctness, regressions, missing tests, documentation drift, and whether the implementation matches the original request.",
    }

    local original = { "## Completed Prompt" }
    if vim.trim(item.title or "") ~= "" then
        original[#original + 1] = ("**Title:** %s"):format(item.title)
    end
    if vim.trim(item.details or "") ~= "" then
        original[#original + 1] = item.details
    end
    sections[#sections + 1] = table.concat(original, "\n\n")

    if vim.trim(item.history_summary or "") ~= "" then
        sections[#sections + 1] = "## Completion Summary\n\n" .. item.history_summary
    end

    if item_has_commits(item) then
        local commits = {}
        for _, commit in ipairs(item.history_commits) do
            commits[#commits + 1] = ("- `%s`"):format(commit)
        end
        sections[#sections + 1] = "## Commits To Review\n\n" .. table.concat(commits, "\n")
    end

    sections[#sections + 1] =
        "## Review Instructions\n\nUse a code-review stance. If the implementation is sound, close this review task with the reviewed commit id. If you find a problem, make the minimal fix or create a focused follow-up prompt."

    return table.concat(sections, "\n\n")
end

---@param actions Clodex.AppQueueActions
---@param project Clodex.Project
---@return Clodex.QueueItem?
local function create_completion_review_prompt(actions, project)
    if not review_after_completion_enabled(actions) then
        return nil
    end

    local item = actions.app.queue:queues(project).implemented[1]
    if not item or item.review_requested_at or not item_has_commits(item) then
        return nil
    end

    local review = actions.app.queue:add_todo(project, {
        title = ("Review changes for %s"):format(item.title),
        details = review_prompt_details(item),
        kind = "ask",
        queue = "queued",
        completion_target = "history",
        front = true,
    })
    actions.app.queue:update_item(project, item.id, {
        review_requested_at = iso_utc_now(),
    })
    return review
end

---@param app Clodex.AppQueueActions.Host
---@return Clodex.AppQueueActions
function QueueActions.new(app)
    return setmetatable({
        app = app,
        workspace_revisions = {},
        continuing_projects = {},
    }, QueueActions)
end

---@param actions Clodex.AppQueueActions
---@param project Clodex.Project
---@param session Clodex.TerminalSession
local function continue_after_closed_task(actions, project, session)
    if actions.continuing_projects[project.root] then
        return
    end

    create_completion_review_prompt(actions, project)
    local queued = actions.app.queue:queues(project).queued
    local next_item = queued[1]
    if not next_item then
        return
    end

    actions.continuing_projects[project.root] = true
    session:send("/new")
    local attempts = 0
    local function start_when_ready()
        attempts = attempts + 1
        if
            attempts < CONTINUE_AFTER_CLOSE_MAX_ATTEMPTS
            and type(session.is_working) == "function"
            and session:is_working()
        then
            vim.defer_fn(start_when_ready, CONTINUE_AFTER_CLOSE_RETRY_MS)
            return
        end

        actions.continuing_projects[project.root] = nil
        local current = actions.app.queue:queues(project).queued[1]
        if not current then
            actions.app:refresh_views()
            return
        end
        actions:start_queued_item(project, current.id, "interactive")
        actions.app:refresh_views()
    end
    vim.defer_fn(start_when_ready, CONTINUE_AFTER_CLOSE_RETRY_MS)
end

---@param project Clodex.Project
function QueueActions:remember_workspace_revision(project)
    self.workspace_revisions[project.root] = self.app.queue:workspace_revision(project)
end

---@param project Clodex.Project
---@param item_id string
---@return Clodex.QueueItem?
function QueueActions:refresh_queue_item_instructions(project, item_id)
    local _, _, item = self.app.queue:find_item(project, item_id)
    if not item then
        return
    end

    return self.app.queue:update_item(project, item_id, {
        execution_instructions = false,
    })
end

---@param project Clodex.Project
---@param item Clodex.QueueItem
---@return boolean
function QueueActions:dispatch_item(project, item)
    local session = self.app.terminals:ensure_project_session(project, {
        resume_session_id = resume_session_id_for_item(self, item),
    })
    if not session then
        notify.warn(("Could not start a Codex session for %s"):format(project.name))
        return false
    end

    if not prepare_session_start_mode(session, item) then
        notify.warn(("Could not start %s in Plan mode"):format(item.title))
        return false
    end
    session:set_active_prompt_title(item.title, item.kind)
    if not session:dispatch_prompt(self.app.execution:dispatch_prompt(project, item)) then
        session:set_active_prompt_title(nil)
        return false
    end
    touch_and_record_project(self, project)
    return true
end

---@param project Clodex.Project
---@param item_id string
---@param session_id string
---@param backend? Clodex.Backend.Name
---@return Clodex.QueueItem|false
function QueueActions:save_queue_item_session(project, item_id, session_id, backend)
    session_id = vim.trim(session_id or "")
    if session_id == "" then
        notify.warn("Session id is required")
        return false
    end
    local queue_name = self.app.queue:find_item(project, item_id)
    if queue_name ~= "implemented" and queue_name ~= "history" then
        notify.warn("Session ids can only be saved on implemented or history items")
        return false
    end
    local config = self.app.config and self.app.config.get and self.app.config:get() or nil
    local saved = self.app.queue:update_item(project, item_id, {
        history_session = {
            backend = Backend.normalize(backend or (config and config.backend)),
            id = session_id,
        },
    })
    if not saved then
        notify.warn("Queue item not found")
        return false
    end
    notify.notify(("Saved %s session for %s"):format(Backend.display_name(saved.history_session.backend), saved.title))
    touch_and_record_project(self, project)
    self.app:refresh_views()
    return saved
end

---@param project Clodex.Project
---@param item Clodex.QueueItem
---@return boolean
function QueueActions:dispatch_item_direct(project, item)
    if not self.app.exec_runner:start(project, item) then
        return false
    end

    touch_and_record_project(self, project)
    return true
end

---@param project Clodex.Project
---@param item_id string
---@param mode "interactive"|"exec"
---@return boolean
function QueueActions:start_queued_item(project, item_id, mode)
    local queue_name, _, queued_item = self.app.queue:find_item(project, item_id)
    if queue_name ~= "queued" or not queued_item then
        notify.warn("Only queued items can be implemented")
        return false
    end

    if mode == "exec" and self:dispatch_item_direct(project, queued_item) then
        return true
    end
    return self:dispatch_item(project, queued_item)
end

--- Checks configured queue workspace files for external updates.
--- This keeps the editor in sync when queued prompts complete through the MCP helper.
function QueueActions:poll_workspace_updates()
    self:poll_active_prompt_titles()

    local changed = false
    for _, project in ipairs(self.app.registry:list()) do
        local revision = self.app.queue:workspace_revision(project)
        if self.workspace_revisions[project.root] == nil then
            self.workspace_revisions[project.root] = revision
        elseif self.workspace_revisions[project.root] ~= revision then
            self.workspace_revisions[project.root] = revision
            changed = true
        end
    end

    if changed then
        self.app:refresh_views()
    end
end

--- Syncs active MCP task titles into open project terminal winbars.
--- The MCP helper owns active queued-task state, so terminal chrome polls its local
--- runtime file instead of guessing from the item that launched the agent.
---@return boolean
function QueueActions:poll_active_prompt_titles()
    if not self.app.config or not self.app.registry or not self.app.terminals then
        return false
    end

    local values = self.app.config:get()
    local changed = false
    for _, project in ipairs(self.app.registry:list()) do
        local session = self.app.terminals:project_session(project.root)
        if session then
            local active = fs.read_json(Mcp.active_state_path(values, project.root), nil)
            local title = type(active) == "table" and active.title or nil
            local kind = type(active) == "table" and active.kind or nil
            title = type(title) == "string" and vim.trim(title) or ""
            kind = type(kind) == "string" and vim.trim(kind) or nil
            local next_title = title ~= "" and title or nil
            local next_kind = next_title and kind or nil
            local closed_active_task = session.active_prompt_authoritative == true and next_title == nil
            -- Keep the prompt title shown while the queued MCP task is still being claimed.
            local has_pending_dispatch_title = session.active_prompt_title ~= nil
                and session.active_prompt_authoritative ~= true
                and next_title == nil
            if
                not has_pending_dispatch_title
                and (session.active_prompt_title ~= next_title or session.active_prompt_kind ~= next_kind)
            then
                session:set_active_prompt_title(next_title, next_kind, { authoritative = true })
                changed = true
            end
            if closed_active_task then
                continue_after_closed_task(self, project, session)
            end
        end
    end

    if changed then
        refresh_terminal_chrome()
        pcall(vim.cmd.redrawstatus)
    end
    return changed
end

--- Adds a new app queue actions entry and keeps related state aligned.
--- This function feeds the same workflow used by interactive and scripted callers.
---@param project Clodex.Project
---@param spec Clodex.AppPromptActions.AddTodoSpec
---@param opts? Clodex.AppQueueActions.AddTodoOpts
---@return Clodex.QueueItem?
function QueueActions:add_project_todo(project, spec, opts)
    opts = opts or {}
    local title = vim.trim(spec.title or "")
    if title == "" then
        notify.warn("Todo title is required")
        return
    end

    local normalized = self.app.prompt_actions:normalize_spec(project, {
        title = title,
        details = spec.details,
    })
    local queue_name = opts.queue == "queued" and "queued" or "planned"
    local item = self.app.queue:add_todo(project, {
        title = normalized.title,
        details = normalized.details,
        kind = spec.kind,
        image_path = spec.image_path,
        completion_target = spec.completion_target,
        start_mode = opts.start_mode,
        queue = queue_name,
    })
    if queue_name == "queued" then
        item = self:refresh_queue_item_instructions(project, item.id) or item
    end
    History.append_prompt_added(project.name, normalized.title, normalized.details, spec.kind)
    touch_and_record_project(self, project)
    local started = false
    if queue_name == "queued" and opts.implement then
        started = self:start_queued_item(project, item.id, opts.run_mode == "exec" and "exec" or "interactive")
    end

    if queue_name == "queued" and started then
        local queue_mode = opts.run_mode == "exec" and "direct" or "interactive"
        notify.notify(("Queued and started %s prompt for %s: %s"):format(
            queue_mode,
            project.name,
            normalized.title
        ))
    elseif queue_name == "queued" then
        notify.notify(("Queued prompt for %s: %s"):format(project.name, normalized.title))
    else
        notify.notify(("Added todo to %s: %s"):format(project.name, normalized.title))
    end
    touch_and_record_project(self, project)
    return item
end

---@param project Clodex.Project
---@param item_id string
---@param spec { title: string, details?: string, image_path?: string }
---@return Clodex.QueueItem|false
function QueueActions:edit_queue_item(project, item_id, spec)
    local title = vim.trim(spec.title or "")
    if title == "" then
        notify.warn("Todo title is required")
        return false
    end

    local normalized = self.app.prompt_actions:normalize_spec(project, {
        title = title,
        details = spec.details and vim.trim(spec.details) ~= "" and spec.details or nil,
    })
    local item = self.app.queue:update_item(project, item_id, {
        title = normalized.title,
        details = normalized.details or false,
        image_path = spec.image_path and vim.trim(spec.image_path) ~= "" and spec.image_path or false,
    })
    if not item then
        notify.warn("Queue item not found")
        return false
    end

    notify.notify(("Updated prompt for %s: %s"):format(project.name, item.title))
    self:refresh_queue_item_instructions(project, item_id)
    touch_and_record_project(self, project)
    return item
end

---@param project Clodex.Project
---@param item_id string
---@return boolean, "started"|"blocked"
function QueueActions:implement_queue_item(project, item_id)
    local queue_name, _, item = self.app.queue:find_item(project, item_id)
    local moved_from_planned = false

    if queue_name == "planned" then
        if not self.app.queue:advance(project, item_id) then
            notify.warn("Could not move the planned item to queued")
            return false, "blocked"
        end
        self:refresh_queue_item_instructions(project, item_id)
        queue_name, _, item = self.app.queue:find_item(project, item_id, "queued")
        moved_from_planned = true
    end

    if queue_name ~= "queued" or not item then
        notify.warn("Only planned or queued items can be implemented")
        return false, "blocked"
    end

    if self:start_queued_item(project, item_id, "interactive") then
        notify.notify(("Started %s prompt for %s: %s"):format(
            moved_from_planned and "planned" or "queued",
            project.name,
            item.title
        ))
        touch_and_record_projects(self, project)
        return true, "started"
    end

    if moved_from_planned then
        touch_and_record_projects(self, project)
    end

    return false, "blocked"
end

---@param project Clodex.Project
function QueueActions:implement_queued_items(project)
    local queued_items = vim.deepcopy(self.app.queue:queues(project).queued)
    if #queued_items == 0 then
        notify.warn(("No queued items for %s"):format(project.name))
        return
    end

    local sent = 0
    for _, item in ipairs(queued_items) do
        if self:start_queued_item(project, item.id, "interactive") then
            sent = sent + 1
        end
    end

    if sent > 0 then
        notify.notify(("Started %d queued prompt(s) for %s"):format(sent, project.name))
        touch_and_record_projects(self, project)
    end
end

---@param project Clodex.Project
function QueueActions:move_all_planned_items_to_queued(project)
    local planned_items = vim.deepcopy(self.app.queue:queues(project).planned)
    if #planned_items == 0 then
        notify.warn(("No planned items for %s"):format(project.name))
        return
    end

    local moved = 0
    for _, item in ipairs(planned_items) do
        if self.app.queue:advance(project, item.id) then
            self:refresh_queue_item_instructions(project, item.id)
            moved = moved + 1
        end
    end

    if moved > 0 then
        notify.notify(("Moved %d planned prompt(s) to queued for %s"):format(moved, project.name))
        touch_and_record_projects(self, project)
    end
end

---@param opts? Clodex.AppPromptActions.ResolveOpts
function QueueActions:implement_next_queued_item(opts)
    self.app.prompt_actions:pick_project(self.app.prompt_actions:resolve_project(opts), function(project)
        local next_item = self.app.queue:queues(project).queued[1]
        if not next_item then
            notify.warn(("No queued items for %s"):format(project.name))
            return
        end
        self:implement_queue_item(project, next_item.id)
    end)
end

---@param opts? Clodex.AppPromptActions.ResolveOpts
function QueueActions:implement_all_queued_items(opts)
    self.app.prompt_actions:pick_project(self.app.prompt_actions:resolve_project(opts), function(project)
        self:implement_queued_items(project)
    end)
end

---@param project Clodex.Project
---@param item_id string
function QueueActions:advance_queue_item(project, item_id)
    if not self.app.queue:advance(project, item_id) then
        notify.warn("Item cannot be moved further")
        return
    end
    self:refresh_queue_item_instructions(project, item_id)
    touch_and_record_projects(self, project)
end

---@param project Clodex.Project
---@param item_id string
---@param opts? Clodex.AppQueueActions.RewindOpts
function QueueActions:rewind_queue_item(project, item_id, opts)
    opts = opts or {}
    local queue_name, _, item = find_item_in_queue(self, project, item_id, opts.queue)
    local previous_queue = queue_name and PREVIOUS_QUEUE[queue_name] or nil
    if opts.mark_not_working and (queue_name == "implemented" or queue_name == "history") then
        previous_queue = "queued"
    end
    if not previous_queue or not item then
        notify.warn("Item cannot be moved back")
        return
    end
    local rewind_item = rewind_item_spec(item, opts)
    local clear_history = queue_name == "implemented" or queue_name == "history"

    local moved_item
    if opts.copy then
        moved_item = self.app.queue:put_item(project, previous_queue, rewind_item, {
            copy = true,
            clear_history = clear_history,
        })
    else
        if not self.app.queue:take_item(project, item_id, queue_name) then
            notify.warn("Queue item not found")
            return
        end
        moved_item = self.app.queue:put_item(project, previous_queue, rewind_item, {
            clear_history = clear_history,
        })
    end

    if moved_item then
        self:refresh_queue_item_instructions(project, moved_item.id)
    end
    touch_and_record_projects(self, project)
end

---@param project Clodex.Project
---@param item_id string
---@param target_project Clodex.Project
---@param opts? Clodex.AppQueueActions.MoveOpts
function QueueActions:move_queue_item_to_project(project, item_id, target_project, opts)
    opts = opts or {}
    local queue_name, _, item = find_item_in_queue(self, project, item_id, opts.source_queue)
    local target_queue = opts.target_queue or queue_name
    if not queue_name or not target_queue or not item then
        notify.warn("Queue item not found")
        return
    end

    if not opts.copy and not self.app.queue:take_item(project, item_id, queue_name) then
        notify.warn("Queue item not found")
        return
    end

    local moved = self.app.queue:put_item(target_project, target_queue, item, {
        copy = opts.copy == true,
        clear_history = queue_name == "history" and target_queue ~= "history",
    })
    if not moved then
        notify.warn("Failed to move queue item")
        return
    end

    notify.notify(("Moved '%s' to %s"):format(item.title, target_project.name))
    self:refresh_queue_item_instructions(target_project, moved.id)
    touch_and_record_projects(self, project, target_project)
end

---@param project Clodex.Project
---@param item_id string
function QueueActions:delete_queue_item(project, item_id)
    if not self.app.queue:delete_item(project, item_id) then
        notify.warn("Queue item not found")
        return
    end
    touch_and_record_project(self, project)
end

return QueueActions
