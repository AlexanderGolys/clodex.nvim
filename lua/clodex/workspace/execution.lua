local fs = require("clodex.util.fs")

--- Generates and persists prompt-instruction payloads used by the Codex execution pipeline.
--- This object bridges queue items to terminal jobs and workspace mutations.
---@class Clodex.Workspace.Execution
---@field config Clodex.Config.Values
local Execution = {}
Execution.__index = Execution

local SOURCE_PATH = fs.normalize(debug.getinfo(1, "S").source:sub(2))
local REPO_ROOT = fs.dirname(fs.dirname(fs.dirname(fs.dirname(SOURCE_PATH))))
local REPO_SKILLS_DIR = fs.join(REPO_ROOT, ".codex", "skills")
local REPO_SKILL_TEMPLATE_PATH = fs.join(REPO_SKILLS_DIR, "prompt-nvim-clodex", "SKILL.md")

local function trim(value)
    return vim.trim(value or "")
end

---@param content string?
---@return table<string, string>
local function skill_frontmatter(content)
    if type(content) ~= "string" or not vim.startswith(content, "---\n") then
        return {}
    end

    local close_start = content:find("\n---", 4, true)
    if not close_start then
        return {}
    end

    local values = {} ---@type table<string, string>
    local header = content:sub(5, close_start - 1)
    for _, line in ipairs(vim.split(header, "\n", { plain = true })) do
        local key, value = line:match("^([%w_-]+):%s*(.-)%s*$")
        if key and value then
            values[key] = value:gsub('^"(.*)"$', "%1"):gsub("^'(.*)'$", "%1")
        end
    end
    return values
end

---@param version string?
---@return integer[]
local function version_parts(version)
    local parts = {} ---@type integer[]
    for part in tostring(version or ""):gmatch("%d+") do
        parts[#parts + 1] = tonumber(part) or 0
    end
    return parts
end

---@param installed string?
---@param bundled string?
---@return boolean
local function version_is_older(installed, bundled)
    local installed_parts = version_parts(installed)
    local bundled_parts = version_parts(bundled)
    if #bundled_parts == 0 then
        return false
    end
    if #installed_parts == 0 then
        return true
    end
    local count = math.max(#installed_parts, #bundled_parts)
    for index = 1, count do
        local left = installed_parts[index] or 0
        local right = bundled_parts[index] or 0
        if left ~= right then
            return left < right
        end
    end
    return false
end

---@param path string
---@return string?
local function read_file(path)
    local file = io.open(path, "rb")
    if not file then
        return nil
    end
    local content = file:read("*a")
    file:close()
    return content
end

---@param installed_content string?
---@param bundled_content string
---@return boolean
local function skill_needs_sync(installed_content, bundled_content)
    if type(installed_content) ~= "string" or installed_content == "" then
        return true
    end
    local bundled_version = skill_frontmatter(bundled_content).version
    local installed_version = skill_frontmatter(installed_content).version
    if version_is_older(installed_version, bundled_version) then
        return true
    end
    return bundled_version == nil and installed_content ~= bundled_content
end

local function is_absolute_path(path)
    path = fs.normalize(path)
    return vim.startswith(path, "/") or path:match("^%a:[/\\]") ~= nil
end

--- Resolves the canonical project-local execution root.
--- The old `receipts_dir` option is still honored as the base artifacts directory for compatibility.
---@param config Clodex.Config.Values
---@param project_root string
---@return string
local function execution_dir(config, project_root)
    local dir = trim(config.prompt_execution.receipts_dir)
    if dir ~= "" then
        local expanded = fs.normalize(vim.fn.expand(dir))
        if is_absolute_path(expanded) then
            return expanded
        end
        return fs.join(project_root, expanded)
    end
    return fs.join(project_root, ".clodex", "prompt-executions")
end

---@param config Clodex.Config.Values
---@param project? Clodex.Project
---@return string
local function skills_dir(config, project)
    local dir = vim.trim(config.prompt_execution.skills_dir or "")
    if dir == "" then
        return ""
    end
    local expanded = fs.normalize(vim.fn.expand(dir))
    if project and not is_absolute_path(expanded) then
        return fs.join(project.root, expanded)
    end
    return expanded
end

---@param config Clodex.Config.Values
---@return string
local function skill_name(config)
    local name = trim(config.prompt_execution.skill_name)
    return name ~= "" and name or "prompt-nvim-clodex"
end

---@return string
local function repo_skill_content()
    local file = io.open(REPO_SKILL_TEMPLATE_PATH, "rb")
    if not file then
        error(("Could not open prompt skill template: %s"):format(REPO_SKILL_TEMPLATE_PATH))
    end

    local content = file:read("*a")
    file:close()
    if not content or content == "" then
        error(("Prompt skill template is empty: %s"):format(REPO_SKILL_TEMPLATE_PATH))
    end
    return content
end

---@return string[]
local function bundled_skill_names()
    if not fs.is_dir(REPO_SKILLS_DIR) then
        return { "prompt-nvim-clodex" }
    end

    local names = {}
    for _, entry in ipairs(vim.fn.readdir(REPO_SKILLS_DIR)) do
        local skill_file = fs.join(REPO_SKILLS_DIR, entry, "SKILL.md")
        if fs.is_file(skill_file) then
            names[#names + 1] = entry
        end
    end
    table.sort(names)
    return names
end

---@param name string
---@return string
local function bundled_skill_content(name)
    if name == "prompt-nvim-clodex" then
        return repo_skill_content()
    end

    local path = fs.join(REPO_SKILLS_DIR, name, "SKILL.md")
    local file = io.open(path, "rb")
    if not file then
        error(("Could not open bundled skill template: %s"):format(path))
    end

    local content = file:read("*a")
    file:close()
    if not content or content == "" then
        error(("Bundled skill template is empty: %s"):format(path))
    end
    return content
end

---@class Clodex.Workspace.ExecutionItem
---@field id string
---@field kind Clodex.PromptCategory
---@field prompt string
---@field completion_target? Clodex.QueueName
---@field image_path? string

---@param item Clodex.Workspace.ExecutionItem
---@return string
function Execution:queue_item_instructions(item)
    if self:uses_prompt_skill() then
        return ("$%s\r"):format(skill_name(self.config))
    end
    return item.prompt or ""
end

---@param config Clodex.Config.Values
---@return Clodex.Workspace.Execution
function Execution.new(config)
    local self = setmetatable({}, Execution)
    self.config = config
    return self
end

---@param config Clodex.Config.Values
function Execution:update_config(config)
    self.config = config
end

---@return boolean
function Execution:uses_prompt_skill()
    local dir = skills_dir(self.config)
    return dir ~= "" and trim(self.config.prompt_execution.skill_name) ~= ""
end

---@param project? Clodex.Project
---@return string
function Execution:skill_dir(project)
    return assert(skills_dir(self.config, project))
end

---@param project? Clodex.Project
---@return string
function Execution:skill_file(project)
    return fs.join(self:skill_dir(project), skill_name(self.config), "SKILL.md")
end

---@param project? Clodex.Project
---@return boolean
function Execution:sync_prompt_skill(project)
    if not self:uses_prompt_skill() then
        return false
    end

    local dir = self:skill_dir(project)
    local changed = false
    for _, name in ipairs(bundled_skill_names()) do
        local skill_file = fs.join(dir, name, "SKILL.md")
        local content = bundled_skill_content(name)
        if skill_needs_sync(read_file(skill_file), content) then
            fs.write_file(skill_file, content)
            changed = true
        end
    end
    return changed
end

---@param project Clodex.Project
---@return string
function Execution:project_execution_dir(project)
    return execution_dir(self.config, project.root)
end

---@param _project Clodex.Project
---@param item Clodex.Workspace.ExecutionItem
---@return string
function Execution:dispatch_prompt(_project, item)
    if self:uses_prompt_skill() then
        self:sync_prompt_skill(_project)
        return ("$%s\r"):format(skill_name(self.config))
    end

    return vim.trim(item.prompt or "")
end

return Execution
