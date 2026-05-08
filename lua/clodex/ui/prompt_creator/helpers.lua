local KindRegistry = require("clodex.prompt.kind_registry")
local Prompt = require("clodex.prompt")
local Extmark = require("clodex.ui.extmark")
local ui_select = require("clodex.ui.select")
local util = require("clodex.util")
local fs = require("clodex.util.fs")
local ui_win = require("clodex.ui.win")

local Helpers = {}

-- Clamp value
---@param value integer
---@param minimum integer
---@param maximum integer
---@return integer
function Helpers.clamp(value, minimum, maximum)
    return util.clamp(value, minimum, maximum)
end

-- Create buffer
---@param preset Clodex.UiWin.BufferPreset
---@return integer
function Helpers.prompt_buffer(preset)
    return ui_win.create_buffer({
        preset = preset,
        bo = { bufhidden = "hide" },
    })
end

-- Border padding
---@param win? snacks.win
---@return integer
function Helpers.window_border_padding(win)
    if not win or not win.opts then
        return 0
    end
    local border = win.opts.border
    if border == nil or border == "none" then
        return 0
    end
    return 1
end

-- Close buffers
---@param bufs integer[]
function Helpers.close_buffer_windows(bufs)
    local targets = {} ---@type table<integer, boolean>
    for _, buf in ipairs(bufs) do
        if type(buf) == "number" and buf > 0 and vim.api.nvim_buf_is_valid(buf) then
            targets[buf] = true
        end
    end

    for _, winid in ipairs(vim.api.nvim_list_wins()) do
        local ok, buf = pcall(vim.api.nvim_win_get_buf, winid)
        if ok and targets[buf] then
            ui_win.close(winid)
        end
    end
end

-- Merge highlights
---@param winid integer
---@param mappings table<string, string>
function Helpers.update_winhl(winid, mappings)
    if winid == 0 or not vim.api.nvim_win_is_valid(winid) then
        return
    end

    local fields = {} ---@type table<string, string>
    for part in (vim.wo[winid].winhl or ""):gmatch("[^,]+") do
        local source, target = part:match("^([^:]+):(.+)$")
        if source and target then
            fields[source] = target
        end
    end
    for source, target in pairs(mappings) do
        fields[source] = target
    end

    local parts = {}
    for source, target in pairs(fields) do
        parts[#parts + 1] = ("%s:%s"):format(source, target)
    end
    table.sort(parts)
    vim.api.nvim_set_option_value("winhl", table.concat(parts, ","), { win = winid })
end

-- Hide cursor
---@param winid integer
---@param hl_group string
function Helpers.hide_window_cursor(winid, hl_group)
    Helpers.update_winhl(winid, {
        Cursor = hl_group,
        lCursor = hl_group,
        CursorIM = hl_group,
        TermCursor = hl_group,
        TermCursorNC = hl_group,
    })
end

-- Context base
---@param buf integer
---@return string?
function Helpers.prompt_context_base_at_cursor(buf)
    if not vim.api.nvim_buf_is_valid(buf) or vim.api.nvim_get_current_buf() ~= buf then
        return nil
    end

    local cursor_col = vim.api.nvim_win_get_cursor(0)[2]
    local line = vim.api.nvim_get_current_line()
    local start_col = cursor_col
    while start_col > 0 do
        if line:sub(start_col, start_col):match("[%w_&]") == nil then
            break
        end
        start_col = start_col - 1
    end

    local base = line:sub(start_col + 1, cursor_col)
    return base ~= "" and vim.startswith(base, "&") and base or nil
end

-- Project details
---@param app? Clodex.App
---@param project Clodex.Project
---@return Clodex.ProjectDetails.Snapshot?
function Helpers.project_details(app, project)
    local store = app and app.project_details_store or nil
    if not store then
        return nil
    end
    return store:get_cached(project) or (store.get and store:get(project)) or nil
end

-- Project context
---@param context? Clodex.PromptContext.Capture
---@param project Clodex.Project
---@return Clodex.PromptContext.Capture?
function Helpers.project_context(context, project)
    if not context then
        return nil
    end

    local updated = vim.deepcopy(context)
    updated.project_root = project.root
    if updated.file_path and updated.file_path ~= "" then
        if fs.is_relative_to(updated.file_path, project.root) then
            local relative = vim.fs.relpath(project.root, updated.file_path)
            updated.relative_path = relative and relative ~= "" and relative or vim.fs.basename(updated.file_path)
        else
            updated.relative_path = nil
        end
    end
    return updated
end

-- Normalize projects
---@param projects? Clodex.Project[]
---@param project Clodex.Project
---@return Clodex.Project[]
function Helpers.normalize_projects(projects, project)
    local items = {} ---@type Clodex.Project[]
    local seen = {} ---@type table<string, boolean>
    for _, item in ipairs(projects or {}) do
        if item and item.root and not seen[item.root] then
            seen[item.root] = true
            items[#items + 1] = item
        end
    end
    if project and project.root and not seen[project.root] then
        items[#items + 1] = project
    end
    return items
end

-- Clipboard text
---@return string?
function Helpers.read_clipboard_message_register()
    for _, register in ipairs({ "+", '"', "*" }) do
        local message = vim.trim((vim.fn.getreg(register) or ""):gsub("\r\n", "\n"))
        if message ~= "" then
            return message
        end
    end
end

-- Selection draft
---@param kind Clodex.PromptCategory
---@param context? Clodex.PromptContext.Capture
---@return table?
function Helpers.selection_seed(kind, context)
    if not context or not context.selection_text or kind == "bug" then
        return nil
    end

    local spec = Prompt.parse(Prompt.render(KindRegistry.get(kind).default_title, "&selection"))
    return spec and {
        title = spec.title,
        details = spec.details or "",
    } or nil
end

-- Preview fallback
---@param image_path string
---@return string[]
function Helpers.preview_fallback_lines(image_path)
    return {
        "# Clipboard image",
        "",
        ("`%s`"):format(image_path),
        "",
        "Inline preview unavailable. The prompt still keeps the attached image path.",
    }
end

-- Footer item
---@class Clodex.PromptCreator.FooterItem
---@field keys string[]
---@field label? string
---@field key_separator? string

-- Footer item
---@param keys string|string[]
---@param label? string
---@param key_separator? string
---@return Clodex.PromptCreator.FooterItem
function Helpers.footer_item(keys, label, key_separator)
    return {
        keys = type(keys) == "table" and keys or { keys },
        label = label,
        key_separator = key_separator,
    }
end

-- Footer rows
---@param insert_mode boolean
---@param has_variants boolean
---@param has_multiple_projects boolean
---@param link_actions? Clodex.PromptCreator.FooterItem[]
---@return Clodex.PromptCreator.FooterItem[][]
function Helpers.footer_rows(insert_mode, has_variants, has_multiple_projects, link_actions)
    if insert_mode then
        local actions = {
            Helpers.footer_item("C-←/→", "kind"),
        }
        if has_multiple_projects then
            actions[#actions + 1] = Helpers.footer_item("C-↑/↓", "project")
        end
        vim.list_extend(actions, link_actions or {})
        vim.list_extend(actions, {
            Helpers.footer_item("C-s", "plan"),
            Helpers.footer_item("C-m", "implement"),
            Helpers.footer_item("C-p", "plan impl"),
            Helpers.footer_item("C-c", "chat"),
        })
        return {
            {
                Helpers.footer_item({ "Tab", "S-Tab" }, nil, "/"),
                Helpers.footer_item("C-v", "image"),
            },
            actions,
        }
    end

    local row_one = {
        Helpers.footer_item({ "Tab", "↑/↓" }, nil, " or "),
        Helpers.footer_item({ "←/→", "h/l" }, "kind", " or "),
    }
    if has_multiple_projects then
        row_one[#row_one + 1] = Helpers.footer_item("C-↑/↓", "project")
    end
    if has_variants then
        row_one[#row_one + 1] = Helpers.footer_item("[/]", "source")
    end
    row_one[#row_one + 1] = Helpers.footer_item("C-v", "image")

    local row_two = {}
    vim.list_extend(row_two, link_actions or {})
    vim.list_extend(row_two, {
        Helpers.footer_item("s", "plan"),
        Helpers.footer_item("S"),
        Helpers.footer_item("󰌑 ", "queue"),
        Helpers.footer_item({ ".", "S-." }, "implement", " / "),
        Helpers.footer_item("p", "plan impl"),
        Helpers.footer_item("c", "chat"),
    })

    return {
        row_one,
        row_two,
    }
end

-- Footer text
---@param item Clodex.PromptCreator.FooterItem
---@return string
function Helpers.footer_item_text(item)
    if item.label == nil or item.label == "" then
        return table.concat(item.keys, item.key_separator or "/")
    end
    return ("%s: %s"):format(table.concat(item.keys, item.key_separator or "/"), item.label)
end

-- Footer render
---@param rows Clodex.PromptCreator.FooterItem[][]
---@param key_hl string
---@return string[], Clodex.Extmark[]
function Helpers.render_footer_rows(rows, key_hl)
    local lines = {}
    local marks = {} ---@type Clodex.Extmark[]
    for row_index, row in ipairs(rows) do
        local parts = {}
        local col = 0
        for _, item in ipairs(row) do
            local key_separator = item.key_separator or "/"
            local item_text = Helpers.footer_item_text(item)
            parts[#parts + 1] = item_text

            local key_col = col
            for index, key in ipairs(item.keys) do
                marks[#marks + 1] = Extmark.inline(row_index - 1, key_col, key_col + #key, key_hl)
                if item.keys[index + 1] then
                    key_col = key_col + #key + #key_separator
                end
            end

            col = col + #item_text + 3
        end
        lines[#lines + 1] = table.concat(parts, "   ")
    end
    return lines, marks
end

-- Normal key
---@param action Clodex.UiSelect.MultilineAction
---@return string?
function Helpers.normal_action_key(action)
    return action.key
end

-- Insert key
---@param action Clodex.UiSelect.MultilineAction
---@return string?
function Helpers.insert_action_key(action)
    return action.insert_key or action.key
end

-- Apply action
---@param creator Clodex.PromptCreator
---@param buf integer
---@param action Clodex.UiSelect.MultilineAction
---@param reset_actions table<string, boolean>
function Helpers.apply_action_keymaps(creator, buf, action, reset_actions)
    local submit = function(reset)
        creator:submit(action.value, { reset = reset == true or reset_actions[action.value] == true })
    end
    local normal_key = Helpers.normal_action_key(action)
    if normal_key and normal_key ~= "" then
        vim.keymap.set("n", normal_key, function()
            submit(false)
        end, { buffer = buf, silent = true })
    end
    local insert_key = Helpers.insert_action_key(action)
    if insert_key and insert_key ~= "" then
        vim.keymap.set("i", insert_key, function()
            submit(false)
        end, { buffer = buf, silent = true })
    end
    if action.reset_key and action.reset_key ~= "" then
        vim.keymap.set("n", action.reset_key, function()
            submit(true)
        end, { buffer = buf, silent = true })
    end
    if action.reset_insert_key and action.reset_insert_key ~= "" then
        vim.keymap.set("i", action.reset_insert_key, function()
            submit(true)
        end, { buffer = buf, silent = true })
    end
end

-- Tab hit
---@param spans { start_col: integer, end_col: integer, index: integer }[]
---@param column integer
---@return integer?
function Helpers.tab_index_at_column(spans, column)
    local col = math.max((tonumber(column) or 1) - 1, 0)
    for _, span in ipairs(spans) do
        if col >= span.start_col and col < span.end_col then
            return span.index
        end
    end
end

-- Layout fields
---@param kind Clodex.PromptCategory
---@param variant? string
---@return string[]
function Helpers.layout_draft_fields(kind, variant)
    local layout_id = KindRegistry.layout_id(kind, variant)
    if layout_id == "clipboard_preview" then
        return { "title" }
    end
    return { "title", "details" }
end

-- Context refresh
---@param buf integer
---@param context Clodex.PromptContext.Capture?
function Helpers.refresh_prompt_context(buf, context)
    ui_select.refresh_prompt_context(buf, context)
end

return Helpers
