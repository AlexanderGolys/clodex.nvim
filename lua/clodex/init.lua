-- @@@clodex.init

---@alias Clodex.PublicAction
---| "toggle"
---| "open_main_panel"
---| "toggle_state_preview"
---| "toggle_mini_state_preview"
---| "toggle_backend"
---| "jump_to_chat"
---| "refresh"
---| "add_project"
---| "rename_project"
---| "remove_project"
---| "toggle_terminal_header"
---| "clear_active_project"
---| "open_queue_workspace"
---| "open_project_dashboard"
---| "open_project_readme_file"
---| "open_project_todo_file"
---| "open_project_dictionary_file"
---| "open_project_cheatsheet_file"
---| "toggle_project_cheatsheet_preview"
---| "add_project_cheatsheet_item"
---| "open_project_notes_picker"
---| "create_project_note"
---| "add_project_bookmark"
---| "open_project_bookmarks_picker"
---| "add_todo"
---| "add_line_linked_todo"
---| "implement_next_queued_item"
---| "implement_all_queued_items"
---| "add_prompt"
---| "add_bug_todo"
---| "open_history"
---| "new_session"
---| "compact_session"
---| "save_session"
---| "send_prompt_skill"

--- Defines the clodex type for this module.
--- This annotation documents structured state so modules can pass data with consistent expectations.
---@class clodex
local M = {}
M.lualine = require("clodex.lualine")

local PUBLIC_ACTIONS = {
    "toggle",
    "open_main_panel",
    "toggle_state_preview",
    "toggle_mini_state_preview",
    "toggle_backend",
    "jump_to_chat",
    "refresh",
    "add_project",
    "rename_project",
    "remove_project",
    "toggle_terminal_header",
    "clear_active_project",
    "open_queue_workspace",
    "open_project_dashboard",
    "open_project_readme_file",
    "open_project_todo_file",
    "open_project_dictionary_file",
    "open_project_cheatsheet_file",
    "toggle_project_cheatsheet_preview",
    "add_project_cheatsheet_item",
    "open_project_notes_picker",
    "create_project_note",
    "add_project_bookmark",
    "open_project_bookmarks_picker",
    "add_todo",
    "add_line_linked_todo",
    "implement_next_queued_item",
    "implement_all_queued_items",
    "add_prompt",
    "add_bug_todo",
    "open_history",
    "new_session",
    "compact_session",
    "save_session",
    "send_prompt_skill",
} ---@type Clodex.PublicAction[]

local function app()
    return require("clodex.app").instance()
end

local function app_module()
    local ok, module = pcall(require, "clodex.app")
    if ok and type(module.instance) == "function" then
        return module
    end
end

local function current_app()
    local module = app_module()
    if not module then
        return nil
    end

    local ok, instance = pcall(module.instance)
    if ok then
        return instance
    end
end

---@param method Clodex.PublicAction
---@return fun(...): any
local function call(method)
    return function(...)
        local instance = app()
        return instance[method](instance, ...)
    end
end

local function current_config()
    local instance = current_app()
    if not instance or not instance.config then
        return {}
    end

    return vim.deepcopy(instance.config:get() or {})
end

local function reload_lazy_plugin()
    if vim.fn.exists(":Lazy") ~= 2 then
        return
    end
    pcall(vim.cmd, "Lazy reload clodex.nvim")
end

---@param opts? Clodex.Config.Values|{}
function M.setup(opts)
    app():setup(opts)
end

function M.register()
    require("clodex.commands").register()
end

for _, method in ipairs(PUBLIC_ACTIONS) do
    M[method] = call(method)
end

function M.new_session()
    return app():send_session_command("/new")
end

function M.compact_session()
    return app():send_session_command("/compact")
end

---@param session_id string
function M.save_session(session_id)
    return app():save_focused_queue_session(session_id)
end

function M.debug_reload()
    local opts = current_config()
    local old_app = current_app()
    local reload_state

    if old_app and type(old_app.capture_reload_state) == "function" then
        local ok, state = pcall(function()
            return old_app:capture_reload_state()
        end)
        if ok then
            reload_state = state
        end
    end
    if old_app and type(old_app.teardown_for_reload) == "function" then
        pcall(function()
            old_app:teardown_for_reload()
        end)
    end

    reload_lazy_plugin()
    for key in pairs(package.loaded) do
        if key:match("^clodex") then
            package.loaded[key] = nil
        end
    end

    require("clodex").setup(opts)
    local new_app = reload_state and current_app() or nil
    if new_app and type(new_app.restore_reload_state) == "function" then
        pcall(function()
            new_app:restore_reload_state(reload_state)
        end)
    end
    vim.notify("clodex reloaded", vim.log.levels.INFO)
end

return M
