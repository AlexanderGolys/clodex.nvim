local notify = require("clodex.util.notify")
local Prompt = require("clodex.prompt")
local PromptContext = require("clodex.prompt.context")

local M = {}

local did_register = false

---@class Clodex.CommandEnumChoice
---@field value string
---@field aliases string[]
---@field desc string

---@class Clodex.CommandEnum
---@field label string
---@field choices Clodex.CommandEnumChoice[]
---@field aliases table<string, string>
---@field completions string[]

---@class Clodex.CommandSpec
---@field name string
---@field desc string
---@field nargs? string
---@field invoke? string
---@field keep_open? boolean

---@class Clodex.KeymapSpec
---@field context string
---@field mode string
---@field lhs string
---@field desc string
---@field field? Clodex.KeymapField
---@field raw_mode? string|string[]

---@alias Clodex.KeymapField "toggle"|"main_panel"|"queue_workspace"|"state_preview"|"mini_state_preview"|"backend_toggle"|"chat_toggle"|"chat_jump"|"refresh"|"new_bug_prompt"|"new_improvement_prompt"|"new_line_linked_prompt"|"go_to_readme"

---@class Clodex.GlobalKeymapDefinition
---@field field Clodex.KeymapField
---@field mode string
---@field action string
---@field desc string

---@class Clodex.ResolvedKeymap
---@field mode string|string[]
---@field lhses string[]
---@field desc string
---@field opts vim.api.keyset.keymap

---@alias Clodex.Commands.KeymapValues Clodex.Config.Values|{ keymaps?: table<string, string|Clodex.Config.KeymapConfig|false> }

local NEW_PROMPT_FIELD_MAP = {
    new_bug_prompt = "bug",
    new_improvement_prompt = "improvement",
    new_line_linked_prompt = "line_linked",
}

---@class Clodex.RegisteredCommandSpec
---@field name string
---@field desc string
---@field nargs? string
---@field range? boolean|string|integer
---@field complete? fun(arg_lead: string, cmd_line: string, cursor_pos: integer): string[]
---@field handler fun(command: vim.api.keyset.create_user_command.command_args)

local function require_clodex()
    return require("clodex")
end

local function app_instance()
    return require("clodex.app").instance()
end

local function emit_commands_updated()
    pcall(vim.api.nvim_exec_autocmds, "User", {
        pattern = "ClodexCommandsUpdated",
    })
end

---@param label string
---@param choices { value: string, aliases?: string[], desc: string }[]
---@return Clodex.CommandEnum
local function enum(label, choices)
    local aliases = {} ---@type table<string, string>
    local completions = {} ---@type string[]
    local normalized = {} ---@type Clodex.CommandEnumChoice[]

    for _, choice in ipairs(choices) do
        local names = { choice.value }
        for _, alias in ipairs(choice.aliases or {}) do
            names[#names + 1] = alias
        end
        normalized[#normalized + 1] = {
            value = choice.value,
            aliases = names,
            desc = choice.desc,
        }
        for _, alias in ipairs(names) do
            aliases[alias] = choice.value
            completions[#completions + 1] = alias
        end
    end

    table.sort(completions)
    return {
        label = label,
        choices = normalized,
        aliases = aliases,
        completions = completions,
    }
end

local CLODEX_ACTION = enum("action", {
    { value = "panel", desc = "Toggle the legacy queue workspace panel (deprecated)" },
    { value = "main-panel", aliases = { "main_panel" }, desc = "Toggle the main project panel" },
    { value = "dashboard", aliases = { "experimental-panel", "experimental_panel" }, desc = "Toggle the main project dashboard panel" },
    { value = "terminal", aliases = { "cli", "term", "chat" }, desc = "Toggle the project terminal" },
    { value = "history", desc = "Open global Clodex history" },
    { value = "backend", desc = "Toggle or set the active backend" },
    { value = "header", aliases = { "term-header", "terminal-header", "terminal_header" }, desc = "Toggle the active terminal header" },
})

local BACKEND_NAME = enum("backend", {
    { value = "codex", desc = "Use Codex CLI" },
    { value = "opencode", desc = "Use OpenCode CLI" },
})

local DEBUG_ACTION = enum("action", {
    { value = "panel", desc = "Toggle the debug state panel" },
    { value = "mini", aliases = { "mini-panel", "mini_panel" }, desc = "Toggle the compact debug panel" },
    { value = "reload", desc = "Reload clodex modules" },
})

local SESSION_ACTION = enum("action", {
    { value = "new", desc = "Start a new conversation in the active backend session" },
    { value = "compact", desc = "Ask the active backend session to compact the current conversation" },
    { value = "save", desc = "Save a session id on the focused implemented or history queue item" },
    { value = "skill", desc = "Paste and submit the queued-work skill in the active Clodex terminal" },
})

local PROJECT_ACTIONS = {
    { value = "add", desc = "Register the current workspace as a project", invoke = "ClodexProject add" },
    { value = "readme", desc = "Open the current project's README", invoke = "ClodexProject readme", method = "open_project_readme_file" },
    { value = "todo", desc = "Open the current project's TODO list", invoke = "ClodexProject todo", method = "open_project_todo_file" },
    { value = "dictionary", aliases = { "dict" }, desc = "Open the current project's dictionary", invoke = "ClodexProject dictionary", method = "open_project_dictionary_file" },
    { value = "cheatsheet", desc = "Open the current project's cheatsheet file", invoke = "ClodexProject cheatsheet", method = "open_project_cheatsheet_file" },
    { value = "cheatsheet-panel", aliases = { "cheatsheet_panel", "cheatsheet-preview", "cheatsheet_preview" }, desc = "Toggle the project cheatsheet preview", invoke = "ClodexProject cheatsheet-panel", method = "toggle_project_cheatsheet_preview" },
    { value = "cheatsheet-add", aliases = { "cheatsheet_add" }, desc = "Add a cheatsheet item", invoke = "ClodexProject cheatsheet-add", method = "add_project_cheatsheet_item" },
    { value = "notes", desc = "Open the current project's notes picker", invoke = "ClodexProject notes", method = "open_project_notes_picker" },
    { value = "note-add", aliases = { "note_add" }, desc = "Create a project note", invoke = "ClodexProject note-add", method = "create_project_note" },
    { value = "bookmarks", desc = "Open the current project's bookmarks picker", invoke = "ClodexProject bookmarks", method = "open_project_bookmarks_picker" },
    { value = "bookmark-add", aliases = { "bookmark_add" }, desc = "Add a bookmark at the current line", invoke = "ClodexProject bookmark-add", method = "add_project_bookmark" },
}

local PROJECT_ACTION_HANDLERS = {} ---@type table<string, string>
for _, action in ipairs(PROJECT_ACTIONS) do
    if action.method then
        PROJECT_ACTION_HANDLERS[action.value] = action.method
    end
end

local PROJECT_ACTION = enum("action", vim.tbl_map(function(action)
    return {
        value = action.value,
        aliases = action.aliases,
        desc = action.desc,
    }
end, PROJECT_ACTIONS))

---@return Clodex.CommandEnum
local function prompt_kind_enum()
    local choices = {} ---@type { value: string, aliases?: string[], desc: string }[]
    for _, category in ipairs(Prompt.categories.list()) do
        local value = category.id
        local aliases = vim.deepcopy(category.aliases or {})
        if category.id == "todo" then
            value = "improvement"
            aliases[#aliases + 1] = "todo"
        elseif category.id == "freeform" then
            value = "fix"
            aliases[#aliases + 1] = "freeform"
        elseif category.id == "refactor" then
            value = "restructure"
            aliases[#aliases + 1] = "refactor"
        elseif category.id == "idea" then
            value = "vision"
            aliases[#aliases + 1] = "idea"
        elseif category.id == "cleanup" then
            value = "clean-up"
            aliases[#aliases + 1] = "cleanup"
        end
        choices[#choices + 1] = {
            value = value,
            aliases = aliases,
            desc = category.default_title ~= "" and category.default_title or category.label,
        }
    end
    return enum("kind", choices)
end

local PROMPT_KIND = prompt_kind_enum()

local GLOBAL_KEYMAPS = {
    {
        field = "toggle",
        mode = "n",
        action = "toggle",
        desc = "Toggle Codex terminal",
    },
    {
        field = "main_panel",
        mode = "n",
        action = "open_main_panel",
        desc = "Toggle Clodex main panel",
    },
    {
        field = "queue_workspace",
        mode = "n",
        action = "open_queue_workspace",
        desc = "Open Clodex legacy queue workspace (deprecated)",
    },
    {
        field = "state_preview",
        mode = "n",
        action = "toggle_state_preview",
        desc = "Toggle Codex state preview panel",
    },
    {
        field = "mini_state_preview",
        mode = "n",
        action = "toggle_mini_state_preview",
        desc = "Toggle compact Codex state preview",
    },
    {
        field = "backend_toggle",
        mode = "n",
        action = "toggle_backend",
        desc = "Toggle Clodex backend",
    },
    {
        field = "chat_toggle",
        mode = "n",
        action = "toggle",
        desc = "Toggle Codex chat terminal",
    },
    {
        field = "chat_jump",
        mode = "n",
        action = "jump_to_chat",
        desc = "Jump to Clodex chat terminal and enter input mode",
    },
    {
        field = "refresh",
        mode = "n",
        action = "refresh",
        desc = "Refresh Clodex views",
    },
    {
        field = "new_bug_prompt",
        mode = "n",
        action = "add_bug_todo",
        desc = "Create a new bug prompt",
    },
    {
        field = "new_improvement_prompt",
        mode = "n",
        action = "add_todo",
        desc = "Create a new task prompt",
    },
    {
        field = "new_line_linked_prompt",
        mode = "n",
        action = "add_line_linked_todo",
        desc = "Create a new prompt linked to the current line",
    },
    {
        field = "go_to_readme",
        mode = "n",
        action = "open_project_readme_file",
        desc = "Open the current project README",
    },
} ---@type Clodex.GlobalKeymapDefinition[]

local REGISTERED_KEYMAPS = {} ---@type Clodex.KeymapSpec[]
local ALL_KEYMAP_MODES = { "n", "i", "v", "x", "s", "o", "c", "t" }

---@param mode string|string[]
---@return string|string[]
local function normalize_keymap_mode(mode)
    if type(mode) == "string" then
        if mode == "a" then
            return vim.deepcopy(ALL_KEYMAP_MODES)
        end
        return mode
    end

    if type(mode) ~= "table" then
        return mode
    end

    local normalized = {} ---@type string[]
    for _, item in ipairs(mode) do
        if item == "a" then
            vim.list_extend(normalized, ALL_KEYMAP_MODES)
        else
            normalized[#normalized + 1] = item
        end
    end
    return normalized
end

---@param mode string|string[]
---@return string
local function keymap_mode_label(mode)
    if type(mode) == "table" then
        return table.concat(mode, ",")
    end
    return mode
end

---@param values Clodex.Commands.KeymapValues
---@param field Clodex.KeymapField
---@param definition Clodex.GlobalKeymapDefinition
---@param value any
---@param definition Clodex.GlobalKeymapDefinition
---@return Clodex.ResolvedKeymap?
local function resolve_keymap_entry(value, definition)
    if value == false then
        return nil
    end

    local lhses = {} ---@type string[]
    local mode = definition.mode
    local opts = {
        desc = ("Clodex: %s"):format(definition.desc),
        silent = true,
        noremap = true,
    } ---@type vim.api.keyset.keymap

    local value_type = type(value)
    if value_type == "string" then
        if value == "" then
            return nil
        end
        lhses = { value }
    elseif value_type == "table" then
        if value.enabled == false or value.enable == false then
            return nil
        end
        local lhs_value = value.lhs or value.key or value[1]
        if type(lhs_value) == "string" then
            lhses = { lhs_value }
        elseif vim.islist(lhs_value) then
            for _, lhs in ipairs(lhs_value) do
                if type(lhs) == "string" and lhs ~= "" then
                    lhses[#lhses + 1] = lhs
                end
            end
        end
        if value.mode ~= nil then
            mode = normalize_keymap_mode(value.mode)
        end
        if type(value.desc) == "string" then
            opts.desc = value.desc
        end
        if type(value.opts) == "table" then
            for option_key, option_value in pairs(value.opts) do
                opts[option_key] = option_value
            end
        end
        for option_key, option_value in pairs(value) do
            local reserved_key = option_key == "lhs"
                or option_key == "key"
                or option_key == "mode"
                or option_key == "desc"
                or option_key == "enabled"
                or option_key == "enable"
                or option_key == "opts"
                or type(option_key) == "number"
            if not reserved_key then
                opts[option_key] = option_value
            end
        end
    else
        return nil
    end

    if #lhses == 0 then
        return nil
    end

    return {
        lhses = lhses,
        mode = normalize_keymap_mode(mode),
        desc = opts.desc,
        opts = opts,
    }
end

---@param resolved Clodex.ResolvedKeymap[]
---@param value any
---@param definition Clodex.GlobalKeymapDefinition
local function append_resolved_keymaps(resolved, value, definition)
    if value == nil then
        return
    end

    if type(value) == "table" and vim.islist(value) then
        for _, item in ipairs(value) do
            local keymap = resolve_keymap_entry(item, definition)
            if keymap then
                resolved[#resolved + 1] = keymap
            end
        end
        return
    end

    local keymap = resolve_keymap_entry(value, definition)
    if keymap then
        resolved[#resolved + 1] = keymap
    end
end

---@param values Clodex.Commands.KeymapValues
---@param field Clodex.KeymapField
---@param definition Clodex.GlobalKeymapDefinition
---@return Clodex.ResolvedKeymap[]
local function resolve_keymap(values, field, definition)
    local configured = values.keymaps or {}
    local value = configured[field]
    local new_prompt_key = NEW_PROMPT_FIELD_MAP[field]
    if new_prompt_key ~= nil and type(configured.new_prompt) == "table" then
        local nested_value = configured.new_prompt[new_prompt_key]
        if nested_value ~= nil then
            value = nested_value
        end
    end
    if value == nil and field ~= "new_line_linked_prompt" then
        return {}
    end

    local resolved = {} ---@type Clodex.ResolvedKeymap[]

    -- An explicit disable for the main line-linked keymap should disable the whole pair.
    if field == "new_line_linked_prompt" and value == false then
        return resolved
    end

    append_resolved_keymaps(resolved, value, definition)

    if field == "new_line_linked_prompt" then
        local line_linked_home = nil
        if type(configured.new_prompt) == "table" then
            line_linked_home = configured.new_prompt.line_linked_home
        end
        if line_linked_home == nil then
            line_linked_home = configured.new_line_linked_prompt_home
        end
        append_resolved_keymaps(resolved, line_linked_home, definition)
    end

    return resolved
end

---@param cmd_line string
---@param cursor_pos integer
---@return integer
local function completion_arg_index(cmd_line, cursor_pos)
    local before = cmd_line:sub(1, cursor_pos)
    local parts = vim.split(before, "%s+", { trimempty = true })
    if before:match("%s$") then
        return #parts
    end
    return math.max(#parts - 1, 0)
end

---@param enum_spec Clodex.CommandEnum
---@return string
local function enum_hint(enum_spec)
    return table.concat(enum_spec.completions, ", ")
end

---@param token string
---@param enum_spec Clodex.CommandEnum
---@param command_name string
---@return string?
local function resolve_enum(token, enum_spec, command_name)
    local value = enum_spec.aliases[token]
    if value ~= nil then
        return value
    end
    notify.error(("%s: invalid %s '%s'. Expected one of: %s"):format(
        command_name,
        enum_spec.label,
        token,
        enum_hint(enum_spec)
    ))
end

---@param command_name string
---@param args string[]
---@param expected string
---@return boolean
local function check_extra_args(command_name, args, expected)
    if #args == 0 then
        return true
    end
    notify.error(("%s: unexpected arguments '%s'. Expected %s"):format(
        command_name,
        table.concat(args, " "),
        expected
    ))
    return false
end

---@param command vim.api.keyset.create_user_command.command_args
---@return Clodex.PromptContext.Capture?
local function visual_selection_context(command)
    if not command or (command.range or 0) <= 0 then
        return nil
    end

    local selection_mode = vim.fn.visualmode()
    if selection_mode == "" then
        selection_mode = "v"
    end

    return PromptContext.capture({
        selection_mode = selection_mode,
    })
end

---@param enum_spec Clodex.CommandEnum
---@param arg_index integer
---@return fun(arg_lead: string, cmd_line: string, cursor_pos: integer): string[]
local function enum_completion(enum_spec, arg_index)
    return function(_, cmd_line, cursor_pos)
        if completion_arg_index(cmd_line, cursor_pos) ~= arg_index then
            return {}
        end
        return enum_spec.completions
    end
end

---@param cmd_line string
---@param cursor_pos integer
---@return string[]
local function completion_fargs(cmd_line, cursor_pos)
    local parts = vim.split(cmd_line:sub(1, cursor_pos), "%s+", { trimempty = true })
    table.remove(parts, 1)
    return parts
end

---@return fun(arg_lead: string, cmd_line: string, cursor_pos: integer): string[]
local function prompt_completion()
    return function(_, cmd_line, cursor_pos)
        if completion_arg_index(cmd_line, cursor_pos) == 1 then
            return PROMPT_KIND.completions
        end
        return {}
    end
end

---@return fun(arg_lead: string, cmd_line: string, cursor_pos: integer): string[]
local function clodex_completion()
    return function(_, cmd_line, cursor_pos)
        local index = completion_arg_index(cmd_line, cursor_pos)
        local fargs = completion_fargs(cmd_line, cursor_pos)
        local action = fargs[1] and CLODEX_ACTION.aliases[fargs[1]] or nil
        if index <= 1 then
            return CLODEX_ACTION.completions
        end
        if index == 2 and action == "backend" then
            return BACKEND_NAME.completions
        end
        return {}
    end
end

---@param command vim.api.keyset.create_user_command.command_args
---@param category? Clodex.PromptCategory
---@return table
local function prompt_command_opts(command, category)
    local context = visual_selection_context(command)
    return vim.tbl_extend("force", category and {
        category = category,
    } or {}, context and {
        context = context,
    } or {})
end

local function top_level_palette_specs()
    local specs = {
        { name = "Clodex", desc = "Toggle the queue workspace panel", invoke = "Clodex" },
        { name = "Clodex main-panel", desc = "Toggle the main project panel", invoke = "Clodex main-panel" },
        { name = "Clodex panel", desc = "Toggle the legacy queue workspace panel (deprecated)", invoke = "Clodex panel" },
        { name = "Clodex dashboard", desc = "Toggle the main project dashboard panel", invoke = "Clodex dashboard" },
        { name = "Clodex cli", desc = "Toggle the project terminal", invoke = "Clodex cli" },
        { name = "Clodex history", desc = "Open global Clodex history", invoke = "Clodex history" },
        { name = "Clodex backend", desc = "Toggle the active backend", invoke = "Clodex backend" },
        { name = "Clodex backend codex", desc = "Switch to the Codex backend", invoke = "Clodex backend codex" },
        { name = "Clodex backend opencode", desc = "Switch to the OpenCode backend", invoke = "Clodex backend opencode" },
        { name = "Clodex header", desc = "Toggle the active terminal header", invoke = "Clodex header" },
        { name = "ClodexDebug panel", desc = "Toggle the debug state panel", invoke = "ClodexDebug panel", keep_open = true },
        { name = "ClodexDebug mini", desc = "Toggle the compact debug panel", invoke = "ClodexDebug mini" },
        { name = "ClodexDebug reload", desc = "Reload clodex modules", invoke = "ClodexDebug reload" },
        { name = "ClodexSession new", desc = "Start a new backend conversation", invoke = "ClodexSession new" },
        { name = "ClodexSession compact", desc = "Compact the active backend conversation", invoke = "ClodexSession compact" },
        { name = "ClodexSession save", desc = "Save a session id on the focused queue item", invoke = "ClodexSession save" },
    } ---@type Clodex.CommandSpec[]

    for _, action in ipairs(PROJECT_ACTIONS) do
        specs[#specs + 1] = {
            name = action.invoke,
            desc = action.desc,
            invoke = action.invoke,
        }
    end

    return specs
end

---@return Clodex.CommandSpec[]
local function prompt_palette_specs()
    local specs = {
        { name = "ClodexPrompt", desc = "Pick a prompt category for the current project", invoke = "ClodexPrompt" },
    } ---@type Clodex.CommandSpec[]

    for _, category in ipairs(Prompt.categories.list()) do
        specs[#specs + 1] = {
            name = ("ClodexPrompt %s"):format(category.id),
            desc = ("Add a %s prompt"):format(category.label:lower()),
            invoke = ("ClodexPrompt %s"):format(category.id),
        }
    end

    return specs
end

---@return Clodex.CommandSpec[]
local function command_specs()
    local specs = top_level_palette_specs()
    vim.list_extend(specs, prompt_palette_specs())
    return specs
end

---@return Clodex.RegisteredCommandSpec[]
local function registered_command_specs()
    return {
        {
            name = "Clodex",
            desc = "Open the Clodex panel or run a top-level action",
            nargs = "*",
            complete = clodex_completion(),
            handler = function(command)
                local clodex = require_clodex()
                local token = command.fargs[1]
                local action = token and resolve_enum(token, CLODEX_ACTION, "Clodex") or "panel"
                if not action then
                    return
                end
                if action == "panel" then
                    if not check_extra_args("Clodex", vim.list_slice(command.fargs, 2), "at most one action argument") then
                        return
                    end
                    notify.warn("Clodex panel is deprecated; use Clodex main-panel")
                    clodex.open_queue_workspace()
                elseif action == "main-panel" then
                    if not check_extra_args("Clodex", vim.list_slice(command.fargs, 2), "at most one action argument") then
                        return
                    end
                    clodex.open_main_panel()
                elseif action == "dashboard" then
                    if not check_extra_args("Clodex", vim.list_slice(command.fargs, 2), "at most one action argument") then
                        return
                    end
                    clodex.open_project_dashboard()
                elseif action == "terminal" then
                    if not check_extra_args("Clodex", vim.list_slice(command.fargs, 2), "at most one action argument") then
                        return
                    end
                    clodex.toggle()
                elseif action == "history" then
                    if not check_extra_args("Clodex", vim.list_slice(command.fargs, 2), "at most one action argument") then
                        return
                    end
                    clodex.open_history()
                elseif action == "backend" then
                    local backend_token = command.fargs[2]
                    if not backend_token then
                        clodex.toggle_backend()
                        return
                    end
                    local backend = resolve_enum(backend_token, BACKEND_NAME, "Clodex")
                    if not backend then
                        return
                    end
                    if not check_extra_args("Clodex", vim.list_slice(command.fargs, 3), "at most one backend argument") then
                        return
                    end
                    app_instance():set_backend(backend)
                elseif action == "header" then
                    if not check_extra_args("Clodex", vim.list_slice(command.fargs, 2), "at most one action argument") then
                        return
                    end
                    clodex.toggle_terminal_header()
                end
            end,
        },
        {
            name = "ClodexDebug",
            desc = "Run a Clodex debugging action",
            nargs = "?",
            complete = enum_completion(DEBUG_ACTION, 1),
            handler = function(command)
                local clodex = require_clodex()
                local token = command.fargs[1]
                local action = token and resolve_enum(token, DEBUG_ACTION, "ClodexDebug") or "panel"
                if not action then
                    return
                end
                if not check_extra_args("ClodexDebug", vim.list_slice(command.fargs, 2), "at most one action argument") then
                    return
                end
                if action == "panel" then
                    clodex.toggle_state_preview()
                elseif action == "mini" then
                    clodex.toggle_mini_state_preview()
                elseif action == "reload" then
                    clodex.debug_reload()
                end
            end,
        },
        {
            name = "ClodexProject",
            desc = "Run a project-scoped Clodex action",
            nargs = "*",
            complete = enum_completion(PROJECT_ACTION, 1),
            handler = function(command)
                local clodex = require_clodex()
                local token = command.fargs[1]
                local action = token and resolve_enum(token, PROJECT_ACTION, "ClodexProject") or "add"
                if not action then
                    return
                end
                local trailing = vim.list_slice(command.fargs, 2)
                if action == "add" then
                    clodex.add_project({
                        name = #trailing > 0 and table.concat(trailing, " ") or nil,
                    })
                    return
                end
                if not check_extra_args("ClodexProject", trailing, "only an optional name for 'add'") then
                    return
                end
                local method = PROJECT_ACTION_HANDLERS[action]
                if method then
                    clodex[method]()
                end
            end,
        },
        {
            name = "ClodexSession",
            desc = "Run a backend session action",
            nargs = "*",
            complete = enum_completion(SESSION_ACTION, 1),
            handler = function(command)
                local clodex = require_clodex()
                local token = command.fargs[1]
                local action = token and resolve_enum(token, SESSION_ACTION, "ClodexSession") or "new"
                if not action then
                    return
                end
                if action == "new" then
                    if not check_extra_args("ClodexSession", vim.list_slice(command.fargs, 2), "at most one action argument") then
                        return
                    end
                    clodex.new_session()
                elseif action == "compact" then
                    if not check_extra_args("ClodexSession", vim.list_slice(command.fargs, 2), "at most one action argument") then
                        return
                    end
                    clodex.compact_session()
                elseif action == "save" then
                    local session_id = command.fargs[2]
                    if type(session_id) ~= "string" or session_id == "" then
                        notify.error("ClodexSession: missing session id")
                        return
                    end
                    if not check_extra_args("ClodexSession", vim.list_slice(command.fargs, 3), "one session id") then
                        return
                    end
                    clodex.save_session(session_id)
                elseif action == "skill" then
                    if not check_extra_args("ClodexSession", vim.list_slice(command.fargs, 2), "at most one action argument") then
                        return
                    end
                    clodex.send_prompt_skill()
                end
            end,
        },
        {
            name = "ClodexPrompt",
            desc = "Add a prompt with an optional category",
            nargs = "*",
            range = true,
            complete = prompt_completion(),
            handler = function(command)
                local clodex = require_clodex()
                local fargs = command.fargs
                local kind = nil ---@type Clodex.PromptCategory?
                local start_index = 1

                if fargs[1] and PROMPT_KIND.aliases[fargs[1]] ~= nil then
                    kind = resolve_enum(fargs[1], PROMPT_KIND, "ClodexPrompt")
                    if not kind then
                        return
                    end
                    start_index = 2
                end

                if not check_extra_args("ClodexPrompt", vim.list_slice(fargs, start_index), "at most one kind argument") then
                    return
                end

                clodex.add_prompt(prompt_command_opts(command, kind))
            end,
        },
    }
end

---@return Clodex.CommandSpec[]
function M.list()
    return command_specs()
end

---@param values Clodex.Commands.KeymapValues
---@return Clodex.KeymapSpec[]
function M.list_keymaps(values)
    local keymaps = {} ---@type Clodex.KeymapSpec[]
    for _, definition in ipairs(GLOBAL_KEYMAPS) do
        local resolved = resolve_keymap(values, definition.field, definition)
        for _, keymap in ipairs(resolved) do
            for _, lhs in ipairs(keymap.lhses) do
                keymaps[#keymaps + 1] = {
                    context = "Global",
                    mode = keymap_mode_label(keymap.mode),
                    lhs = lhs,
                    desc = keymap.desc,
                    field = definition.field,
                }
            end
        end
    end
    return keymaps
end

---@return Clodex.KeymapSpec[]
function M.list_registered_keymaps()
    return vim.deepcopy(REGISTERED_KEYMAPS)
end

---@param values Clodex.Commands.KeymapValues
function M.register_keymaps(values)
    for _, keymap in ipairs(REGISTERED_KEYMAPS) do
        pcall(vim.keymap.del, keymap.raw_mode or keymap.mode, keymap.lhs)
    end
    REGISTERED_KEYMAPS = {}

    for _, definition in ipairs(GLOBAL_KEYMAPS) do
        local resolved = resolve_keymap(values, definition.field, definition)
        for _, keymap in ipairs(resolved) do
            for _, lhs in ipairs(keymap.lhses) do
                vim.keymap.set(keymap.mode, lhs, function()
                    return require_clodex()[definition.action]()
                end, keymap.opts)
                REGISTERED_KEYMAPS[#REGISTERED_KEYMAPS + 1] = {
                    context = "Global",
                    mode = keymap_mode_label(keymap.mode),
                    raw_mode = keymap.mode,
                    lhs = lhs,
                    desc = keymap.desc,
                    field = definition.field,
                }
            end
        end
    end
end

function M.register()
    if did_register then
        return
    end
    did_register = true

    for _, spec in ipairs(registered_command_specs()) do
        local opts = {
            desc = spec.desc,
        }
        if spec.nargs ~= nil then
            opts.nargs = spec.nargs
        end
        if spec.complete ~= nil then
            opts.complete = spec.complete
        end
        if spec.range ~= nil then
            opts.range = spec.range
        end
        vim.api.nvim_create_user_command(spec.name, spec.handler, opts)
    end

    emit_commands_updated()
end

return M
