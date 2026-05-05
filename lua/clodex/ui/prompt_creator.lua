local PromptAssets = require("clodex.prompt.assets")
local DraftStore = require("clodex.prompt.draft_store")
local KindRegistry = require("clodex.prompt.kind_registry")
local Prompt = require("clodex.prompt")
local PromptSubmit = require("clodex.prompt.submit")
local Extmark = require("clodex.ui.extmark")
local UiBlock = require("clodex.ui.panel.block")
local UiPanel = require("clodex.ui.panel.panel")
local Helpers = require("clodex.ui.prompt_creator.helpers")
local LAYOUT = require("clodex.ui.prompt_creator.layout_config")
local ui_select = require("clodex.ui.select")
local notify = require("clodex.util.notify")

---@class Clodex.PromptCreator.OpenOpts
---@field app Clodex.App
---@field project Clodex.Project
---@field context? Clodex.PromptContext.Capture
---@field projects? Clodex.Project[]
---@field active_project_root? string
---@field initial_kind? Clodex.PromptCategory
---@field submit_actions? Clodex.UiSelect.MultilineAction[]
---@field mode? "new"|"edit"
---@field lock_kind? boolean
---@field initial_draft? table
---@field on_submit fun(spec: Clodex.AppPromptActions.AddTodoSpec, action?: string, project?: Clodex.Project)
---@field on_close? fun(creator: Clodex.PromptCreator)

local DEFAULT_SUBMIT_ACTIONS = {
    { value = "save", label = "plan", key = "s", insert_key = "<C-s>", reset_key = "S" },
    { value = "queue", label = "queue", key = "<CR>", insert_key = "<C-q>" },
    { value = "exec", label = "implement", key = ".", insert_key = "<C-.>", reset_key = "<S-.>", reset_insert_key = "<C-S-.>" },
    { value = "chat", label = "chat", key = "c", insert_key = "<C-c>" },
}

local RESET_AFTER_SUBMIT_ACTIONS = {}

local TAB_NS = vim.api.nvim_create_namespace("clodex-prompt-creator-tabs")
local FOOTER_NS = vim.api.nvim_create_namespace("clodex-prompt-creator-footer")
local PROMPT_ACTIVE_NORMAL = "ClodexPromptFocusActive"
local PROMPT_EDITOR_NORMAL = "ClodexPromptEditorNormal"
local PROMPT_FOOTER_NORMAL = "ClodexPromptEditorFooter"

---@class Clodex.PromptCreator
---@field app Clodex.App
---@field panel Clodex.UiPanel
---@field projects Clodex.Project[]
---@field project Clodex.Project
---@field project_index integer
---@field active_project_root string
---@field context? Clodex.PromptContext.Capture
---@field submit_actions Clodex.UiSelect.MultilineAction[]
---@field mode "new"|"edit"
---@field lock_kind boolean
---@field on_submit fun(spec: Clodex.AppPromptActions.AddTodoSpec, action?: string, project?: Clodex.Project)
---@field kinds Clodex.PromptCategoryDef[]
---@field kind_index integer
---@field variant_index integer
---@field state table
---@field drafts Clodex.PromptDraftStore
---@field field_cache table<string, any>
---@field field_history table<string, any[]>
---@field layout Clodex.PromptCreator.ComposerLayout|Clodex.PromptCreator.ClipboardPreviewLayout?
---@field project_bg_buf integer
---@field project_buf integer
---@field kind_buf integer
---@field footer_buf integer
---@field variant_buf? integer
---@field preview_buf? integer
---@field project_bg_win? snacks.win
---@field project_win? snacks.win
---@field kind_win? snacks.win
---@field footer_win? snacks.win
---@field variant_win? snacks.win
---@field preview_win? snacks.win
---@field preview_placement? any
---@field is_closing boolean
---@field project_line_map integer[]
---@field kind_tab_spans { start_col: integer, end_col: integer, index: integer }[]
---@field variant_tab_spans { start_col: integer, end_col: integer, index: integer }[]
---@field autocmd_group? integer
---@field on_close? fun(creator: Clodex.PromptCreator)
local Creator = {}
Creator.__index = Creator

-- Open block
---@param owner table
---@param block_field string
---@param win_field string
---@param id string
---@param buf integer
---@param win_opts snacks.win.Config|{}
---@return snacks.win?, Clodex.UiBlock
function Creator:open_block(owner, block_field, win_field, id, buf, win_opts)
    local block = owner[block_field]
    if not block then
        block = UiBlock.new({ id = id, buf = buf, win = win_opts })
        owner[block_field] = block
        self.panel:add_block(block)
    else
        block.win_opts = vim.deepcopy(win_opts)
    end

    local win = block:open()
    if win and block:is_valid() then
        block:update()
        if self.state and self.state.kind then
            local prompt_hl = Prompt.title_group(self.state.kind)
            Helpers.update_winhl(win.win, { FloatBorder = prompt_hl, FloatTitle = prompt_hl })
        end
    end
    owner[win_field] = win
    self.panel:watch_window(win)
    return win, block
end

-- Create buffer
---@param preset Clodex.UiWin.BufferPreset
---@return integer
function Creator:prompt_buffer(preset)
    return Helpers.prompt_buffer(preset)
end

-- Remove block
---@param id string
function Creator:remove_block(id)
    if self.panel then
        self.panel:remove_block(id)
    end
end

local LAYOUT_BUILDERS = {
    composer = require("clodex.ui.prompt_creator.layouts.composer"),
    clipboard_preview = require("clodex.ui.prompt_creator.layouts.clipboard_preview"),
}

---@param value any
---@return boolean
local function blank(value)
    return type(value) ~= "string" or vim.trim(value) == ""
end

---@param draft table?
---@return table?
local function normalize_initial_draft(draft)
    if type(draft) ~= "table" then
        return draft
    end

    draft = vim.deepcopy(draft)
    local prompt = type(draft.prompt) == "string" and Prompt.parse(draft.prompt) or nil
    local title = type(draft.title) == "string" and draft.title or ""
    local title_prompt = title:find("\n", 1, true) and Prompt.parse(title) or nil
    local parsed = title_prompt or prompt
    if not parsed then
        return draft
    end

    if prompt or title_prompt or blank(draft.title) then
        draft.title = parsed.title
    end
    if blank(draft.details) and parsed.details then
        draft.details = parsed.details
    end
    draft.prompt = nil
    return draft
end

-- New creator
---@param opts Clodex.PromptCreator.OpenOpts
---@return Clodex.PromptCreator
function Creator.new(opts)
    local kinds = {} ---@type Clodex.PromptCategoryDef[]
    for _, kind in ipairs(KindRegistry.list()) do
        if kind.id ~= "notworking" then
            kinds[#kinds + 1] = kind
        end
    end

    local initial_kind = KindRegistry.is_valid(opts.initial_kind) and opts.initial_kind or "todo"
    local projects = Helpers.normalize_projects(opts.projects, opts.project)
    local project = opts.project
    local project_index = 1
    local active_project_root = opts.active_project_root or opts.project.root
    for index, item in ipairs(projects) do
        if item.root == opts.project.root then
            project = item
            project_index = index
            break
        end
    end

    local kind_index = 1
    for index, kind in ipairs(kinds) do
        if kind.id == initial_kind then
            kind_index = index
            break
        end
    end

    local self = setmetatable({
        app = opts.app,
        projects = projects,
        project = project,
        project_index = project_index,
        active_project_root = active_project_root,
        context = Helpers.project_context(opts.context, project),
        submit_actions = vim.deepcopy(opts.submit_actions or DEFAULT_SUBMIT_ACTIONS),
        mode = opts.mode or "new",
        lock_kind = opts.lock_kind == true,
        on_submit = opts.on_submit,
        on_close = opts.on_close,
        kinds = kinds,
        kind_index = kind_index,
        variant_index = 1,
        state = {
            project = project,
            context = Helpers.project_context(opts.context, project),
            kind = initial_kind,
            variant = nil,
            title = "",
            details = "",
            image_path = opts.initial_draft and opts.initial_draft.image_path or nil,
            preview_text = "",
        },
        drafts = DraftStore.new(),
        field_cache = {},
        field_history = {},
        project_bg_buf = Helpers.prompt_buffer("scratch"),
        project_buf = Helpers.prompt_buffer("scratch"),
        kind_buf = Helpers.prompt_buffer("scratch"),
        footer_buf = Helpers.prompt_buffer("scratch"),
        is_closing = false,
        project_line_map = {},
        kind_tab_spans = {},
        variant_tab_spans = {},
    }, Creator)

    self.panel = UiPanel.new({
        id = "prompt_creator",
        background = {
            id = "background",
            buf = self.project_bg_buf,
            win = {
                enter = false,
                border = "none",
                backdrop = false,
                zindex = LAYOUT.prompt_background_zindex,
                width = function()
                    return self:project_background_width()
                end,
                height = function()
                    return self:project_background_height()
                end,
                row = function()
                    return self:project_background_row()
                end,
                col = function()
                    return self:project_background_col()
                end,
                view = "footer",
                theme = "prompt_footer",
                theme_overrides = {
                    normal = "ClodexPromptEditorFooter",
                    normal_nc = "ClodexPromptEditorFooter",
                    end_of_buffer = "ClodexPromptEditorFooter",
                },
            },
        },
        on_close = function()
            if not self.is_closing then
                self:close()
            end
        end,
    })
    self:prime_drafts(opts.initial_draft)
    return self
end

-- Prime drafts
---@param initial_draft? table
function Creator:prime_drafts(initial_draft)
    initial_draft = normalize_initial_draft(initial_draft)
    for _, kind in ipairs(self.kinds) do
        local default_mode = KindRegistry.default_mode(kind.id)
        for _, variant in ipairs(KindRegistry.modes(kind.id)) do
            local draft = kind.id == self.state.kind
                    and initial_draft
                    and variant.id == default_mode
                    and vim.deepcopy(initial_draft)
                or (variant.id == default_mode and Helpers.selection_seed(kind.id, self.context))
                or KindRegistry.default_draft(kind.id, variant.id)
            self.drafts:set(kind.id, variant.id, draft)
        end
    end
    self:sync_state_from_draft()
end

-- Current kind
---@return Clodex.PromptCategory
function Creator:kind()
    return self.kinds[self.kind_index].id
end

-- Visible variants
---@return table[]
function Creator:variants()
    local modes = KindRegistry.modes(self:kind())
    return #modes > 1 and modes or {}
end

-- Current variant
---@return string?
function Creator:variant()
    local current = KindRegistry.modes(self:kind())[self.variant_index]
    return current and current.id or nil
end

-- Sync state
function Creator:sync_state_from_draft()
    self.state.kind = self:kind()
    local kind_default_title = KindRegistry.get(self.state.kind).default_title or ""
    local variants = KindRegistry.modes(self.state.kind)
    self.variant_index = math.min(math.max(self.variant_index, 1), math.max(#variants, 1))
    self.state.variant = variants[self.variant_index] and variants[self.variant_index].id
        or KindRegistry.default_mode(self.state.kind)

    local default_draft = KindRegistry.default_draft(self.state.kind, self.state.variant)
    local draft = self:merge_cached_fields(
        self.state.kind,
        self.state.variant,
        self.drafts:get(self.state.kind, self.state.variant, default_draft),
        default_draft
    )
    self.state.title = ""
    self.state.details = ""
    self.state.image_path = nil
    self.state.preview_text = ""
    for key, value in pairs(draft) do
        self.state[key] = value
    end
    if self.mode == "new" and self.state.title == kind_default_title then
        self.state.title = ""
    end
    self.state.project = self.project
    self.state.context = self.context

    local variant = KindRegistry.mode(self.state.kind, self.state.variant)
    if variant.on_select then
        variant.on_select(self)
    end
end

-- Cache fields
---@param fields string[]
---@param draft table
function Creator:update_field_cache(fields, draft)
    for _, field in ipairs(fields) do
        if draft[field] ~= nil then
            local value = vim.deepcopy(draft[field])
            self.field_cache[field] = value
            self.field_history[field] = self.field_history[field] or {}
            local history = self.field_history[field]
            if not vim.deep_equal(history[#history], value) then
                history[#history + 1] = vim.deepcopy(value)
            end
        end
    end
end

-- Merge fields
---@param kind Clodex.PromptCategory
---@param variant? string
---@param draft table
---@param default_draft table
---@return table
function Creator:merge_cached_fields(kind, variant, draft, default_draft)
    local merged = vim.deepcopy(draft or {})
    for _, field in ipairs(Helpers.layout_draft_fields(kind, variant)) do
        local cached = self.field_cache[field]
        local current = merged[field]
        local default_value = default_draft[field]
        if cached ~= nil and (current == nil or current == "" or current == default_value) then
            merged[field] = vim.deepcopy(cached)
        end
    end
    return merged
end

-- Prompt context
---@return Clodex.PromptContext.Capture?
function Creator:prompt_context()
    return self.state.context or self.context
end

-- Refresh context
---@param buf integer
function Creator:refresh_prompt_context(buf)
    Helpers.refresh_prompt_context(buf, self:prompt_context())
end

-- Trigger context
---@param buf integer
function Creator:maybe_trigger_prompt_context_completion(buf)
    local base = Helpers.prompt_context_base_at_cursor(buf)
    if not base or vim.fn.pumvisible() == 1 or #ui_select.prompt_context_complete(0, base) == 0 then
        return
    end
    vim.schedule(function()
        if vim.api.nvim_buf_is_valid(buf) and vim.api.nvim_get_current_buf() == buf and vim.fn.pumvisible() ~= 1 then
            vim.api.nvim_feedkeys(vim.keycode("<C-x><C-u>"), "n", false)
        end
    end)
end

-- Refresh contexts
function Creator:refresh_layout_prompt_contexts()
    if not self.layout or not self.layout.context_buffers then
        return
    end
    for _, buf in ipairs(self.layout:context_buffers()) do
        if vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].modifiable then
            self:refresh_prompt_context(buf)
        end
    end
end

-- Open completion
---@param buf integer
function Creator:trigger_context_completion(buf)
    self:refresh_prompt_context(buf)
    vim.cmd.startinsert()
    vim.schedule(function()
        if vim.api.nvim_buf_is_valid(buf) and vim.api.nvim_get_current_buf() == buf then
            vim.api.nvim_feedkeys(vim.keycode("&<C-x><C-u>"), "n", false)
        end
    end)
end

-- Attach context
---@param buf integer
function Creator:attach_prompt_context(buf)
    if not vim.bo[buf].modifiable then
        return
    end
    self:refresh_prompt_context(buf)
    vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
        buffer = buf,
        callback = function()
            self:refresh_prompt_context(buf)
            if vim.api.nvim_get_current_buf() == buf and vim.api.nvim_get_mode().mode:sub(1, 1) == "i" then
                self:maybe_trigger_prompt_context_completion(buf)
            end
        end,
    })
    vim.api.nvim_create_autocmd("BufWipeout", {
        once = true,
        buffer = buf,
        callback = function()
            ui_select.clear_prompt_context(buf)
        end,
    })
    vim.keymap.set("n", "&", function()
        self:trigger_context_completion(buf)
    end, { buffer = buf, silent = true })
    vim.keymap.set("i", "&", function()
        self:refresh_prompt_context(buf)
        vim.schedule(function()
            if vim.api.nvim_buf_is_valid(buf) and vim.api.nvim_get_current_buf() == buf then
                self:maybe_trigger_prompt_context_completion(buf)
            end
        end)
        return "&"
    end, { buffer = buf, silent = true, expr = true })
end

---@param buf integer
function Creator:attach_editor_mode_events(buf)
    if not vim.bo[buf].modifiable then
        return
    end

    vim.api.nvim_create_autocmd({ "InsertEnter", "InsertLeave" }, {
        buffer = buf,
        callback = function(event)
            if self.footer_buf and vim.api.nvim_buf_is_valid(self.footer_buf) then
                self:render_footer(event.event == "InsertEnter")
            end
        end,
    })
end

-- Save draft
function Creator:save_current_draft()
    if not self.layout or not self.layout.get_draft then
        return
    end

    local draft = self.layout:get_draft()
    if not draft then
        return
    end
    if self.state.preview_text and draft.preview_text == nil then
        draft.preview_text = self.state.preview_text
    end
    self:update_field_cache(self.layout.draft_fields and self.layout:draft_fields() or {}, draft)
    self.drafts:set(
        self.state.kind,
        self.state.variant,
        vim.tbl_extend("force", draft, {
            image_path = self.state.image_path,
            preview_text = self.state.preview_text,
        })
    )
end

-- Clipboard text
---@return string?
function Creator:read_clipboard_message()
    return Helpers.read_clipboard_message_register()
end

---@return integer, integer
function Creator:editor_size()
    local ui = vim.api.nvim_list_uis()[1]
    return ui and ui.width or vim.o.columns, ui and ui.height or vim.o.lines
end

---@return integer
function Creator:total_width()
    local width = self:editor_size()
    local base_width = self.state.image_path and LAYOUT.base_width_with_image or LAYOUT.base_width_without_image
    return math.min(
        width - LAYOUT.creator_screen_margin_cols,
        base_width + self:project_panel_width() + LAYOUT.creator_panel_gap_cols
    )
end

---@return integer
function Creator:total_height()
    local _, height = self:editor_size()
    return math.min(height - LAYOUT.creator_screen_margin_rows, LAYOUT.creator_max_height)
end

---@return integer
function Creator:project_panel_width()
    return self:project_list_width() + (LAYOUT.project_picker_margin_cols * 2)
end

---@return integer
function Creator:project_background_width()
    local left, _, right = self:creator_frame_bounds()
    if left and right then
        return (right - left) + LAYOUT.prompt_background_margin + LAYOUT.prompt_background_margin_right
    end
    return self:total_width() + LAYOUT.creator_background_margin_cols + LAYOUT.prompt_background_margin_right
end

---@return integer
function Creator:project_background_height()
    local _, top, _, bottom = self:creator_frame_bounds()
    if top and bottom then
        return (bottom - top) + LAYOUT.prompt_background_margin + LAYOUT.prompt_background_margin_bottom
    end
    return self:total_height() + LAYOUT.prompt_background_margin + LAYOUT.prompt_background_margin_bottom
end

---@return integer
function Creator:preview_width()
    if not self.state.image_path then
        return 0
    end
    return Helpers.clamp(
        math.floor(self:total_width() * LAYOUT.preview_width_ratio),
        LAYOUT.preview_min_width,
        LAYOUT.preview_max_width
    )
end

---@return integer
function Creator:left_width()
    local preview_width = self:preview_width()
    local width = self:total_width() - preview_width
    return preview_width > 0 and width - LAYOUT.creator_panel_gap_cols or width
end

---@return integer
function Creator:project_list_width()
    local width = LAYOUT.project_list_min_width
    for _, project in ipairs(self.projects) do
        local details = Helpers.project_details(self.app, project)
        local icon = details and details.project_icon and (details.project_icon .. " ") or ""
        width = math.max(width, vim.fn.strdisplaywidth(icon .. project.name) + LAYOUT.project_name_padding)
    end
    return math.min(width, LAYOUT.project_list_max_width)
end

---@return integer
function Creator:content_width()
    return math.max(
        self:left_width() - self:project_panel_width() - LAYOUT.creator_panel_gap_cols,
        LAYOUT.content_min_width
    )
end

---@return integer
function Creator:left_col()
    local width = self:editor_size()
    return math.max(math.floor((width - self:total_width()) / 2), LAYOUT.min_window_offset)
end

---@return integer
function Creator:content_col()
    return self:left_col() + self:project_panel_width() + LAYOUT.creator_panel_gap_cols
end

---@return integer
function Creator:content_frame_col()
    return self:content_col() - LAYOUT.min_window_offset
end

---@return integer
function Creator:content_frame_width()
    return self:content_width() + (LAYOUT.min_window_offset * 2)
end

---@return integer
function Creator:top_row()
    local _, height = self:editor_size()
    return math.max(math.floor((height - self:total_height()) / 2), LAYOUT.min_window_offset)
end

---@return integer
function Creator:kind_row()
    return self:top_row()
end

---@return integer
function Creator:variant_row()
    return self:footer_row() - LAYOUT.footer_gap_rows
end

---@return integer
function Creator:title_row()
    return self:kind_row() + LAYOUT.title_gap_rows
end

---@return integer
function Creator:body_row()
    return self:title_row() + LAYOUT.body_gap_rows
end

---@return integer
function Creator:footer_row()
    return self:top_row() + self:total_height()
end

---@return integer
function Creator:body_height()
    local next_row = #self:variants() > 0 and self:variant_row() or self:footer_row()
    return math.max(next_row - self:body_row() - LAYOUT.footer_gap_rows, LAYOUT.body_min_height)
end

---@return integer
function Creator:clipboard_note_height()
    return Helpers.clamp(
        self:body_height() - LAYOUT.clipboard_note_reserved_rows,
        LAYOUT.clipboard_note_min_height,
        LAYOUT.clipboard_note_max_height
    )
end

---@return integer
function Creator:clipboard_preview_row()
    return self:body_row() + self:clipboard_note_height() + LAYOUT.clipboard_preview_gap_rows
end

---@return integer
function Creator:clipboard_preview_height()
    return math.max(
        self:footer_row() - self:clipboard_preview_row() - LAYOUT.footer_gap_rows,
        LAYOUT.clipboard_preview_min_height
    )
end

---@return integer
function Creator:preview_col()
    return self:left_col() + self:left_width() + LAYOUT.creator_panel_gap_cols
end

---@return integer
function Creator:preview_row()
    return self:title_row()
end

---@return integer
function Creator:preview_height()
    return math.max(self:footer_row() - self:preview_row() + LAYOUT.creator_panel_gap_cols, LAYOUT.preview_min_height)
end

---@return snacks.image.Opts
function Creator:preview_image_opts()
    local width = self:preview_width()
    local height = self:preview_height()
    if self.preview_win and self.preview_win:valid() then
        width = vim.api.nvim_win_get_width(self.preview_win.win)
        height = vim.api.nvim_win_get_height(self.preview_win.win)
    end
    width = math.max(width - LAYOUT.preview_image_inset, LAYOUT.min_window_offset)
    height = math.max(height - LAYOUT.preview_image_inset, LAYOUT.min_window_offset)
    return {
        src = self.state.image_path,
        width = width,
        max_width = width,
        height = height,
        max_height = height,
    }
end

---@return integer?, integer?, integer?, integer?
function Creator:creator_frame_bounds()
    local windows = {
        self.project_win,
        self.kind_win,
        self.variant_win,
        self.footer_win,
        self.preview_win,
        self.layout and self.layout.title_win or nil,
        self.layout and self.layout.body_win or nil,
        self.layout and self.layout.preview_win or nil,
    }
    local left, top, right, bottom
    for _, win in ipairs(windows) do
        if win and win:valid() then
            local config = vim.api.nvim_win_get_config(win.win)
            local border = Helpers.window_border_padding(win)
            local frame_left = config.col - border
            local frame_top = config.row - border
            local frame_right = config.col + config.width + border
            local frame_bottom = config.row + config.height + border
            left = left and math.min(left, frame_left) or frame_left
            top = top and math.min(top, frame_top) or frame_top
            right = right and math.max(right, frame_right) or frame_right
            bottom = bottom and math.max(bottom, frame_bottom) or frame_bottom
        end
    end
    return left, top, right, bottom
end

---@return integer
function Creator:project_row()
    return self:title_row()
end

---@return integer
function Creator:project_height()
    return math.max(self:footer_row() - self:project_row() + LAYOUT.footer_gap_rows, LAYOUT.min_window_offset)
end

---@return integer
function Creator:project_col()
    return self:left_col() + (LAYOUT.project_picker_margin_cols - LAYOUT.creator_background_margin_cols)
end

---@return integer
function Creator:project_background_row()
    local _, top = self:creator_frame_bounds()
    return top and top - LAYOUT.prompt_background_margin or self:top_row() - LAYOUT.creator_background_margin_rows
end

---@return integer
function Creator:project_background_col()
    local left = self:creator_frame_bounds()
    return left and left - LAYOUT.prompt_background_margin or self:left_col() - LAYOUT.creator_background_margin_cols
end

---@param buf integer
---@param labels { label: string, hl_group: string, active_hl_group: string, active_overlay_hl_group?: string }[]
---@param active_index integer
---@param total_width integer
---@return { start_col: integer, end_col: integer, index: integer }[]
function Creator:render_tab_line(buf, labels, active_index, total_width)
    local parts = {} ---@type string[]
    local marks = {} ---@type Clodex.Extmark[]
    local spans = {} ---@type { start_col: integer, end_col: integer, index: integer }[]
    local col = 0

    for index, entry in ipairs(labels) do
        if index > 1 then
            parts[#parts + 1] = " "
            col = col + 1
        end
        local text = string.rep(" ", LAYOUT.tab_padding) .. entry.label .. string.rep(" ", LAYOUT.tab_padding)
        local start_col = col
        local end_col = start_col + #text
        parts[#parts + 1] = text
        local is_active = index == active_index
        marks[#marks + 1] = Extmark.inline(0, start_col, end_col, is_active and entry.active_hl_group or entry.hl_group)
        if is_active and entry.active_overlay_hl_group then
            marks[#marks + 1] =
                Extmark.inline(0, start_col, end_col, entry.active_overlay_hl_group, 110, { hl_mode = "combine" })
        end
        spans[#spans + 1] = { start_col = start_col, end_col = end_col, index = index }
        col = end_col
    end

    local line = table.concat(parts)
    local pad = math.max(math.floor((total_width - vim.fn.strdisplaywidth(line)) / 2), 0)
    if pad > 0 then
        line = string.rep(" ", pad) .. line
        for _, span in ipairs(spans) do
            span.start_col = span.start_col + pad
            span.end_col = span.end_col + pad
        end
        for _, mark in ipairs(marks) do
            mark.start_pos[2] = mark.start_pos[2] + pad
            mark.end_pos[2] = mark.end_pos[2] + pad
        end
    end

    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { line })
    vim.bo[buf].modifiable = false
    vim.api.nvim_buf_clear_namespace(buf, TAB_NS, 0, -1)
    for _, mark in ipairs(marks) do
        mark:place(buf, TAB_NS)
    end
    return spans
end

---@return boolean
function Creator:in_insert_mode()
    return vim.api.nvim_get_mode().mode:sub(1, 1) == "i"
end

---@param layout table
---@param slot? string
---@return boolean
local function layout_has_slot(layout, slot)
    if not slot or not layout then
        return false
    end
    local win = layout[slot .. "_win"]
    return win and win.valid and win:valid() or false
end

---@param winid integer
---@param cursor integer[]
local function restore_cursor(winid, cursor)
    if not cursor or not vim.api.nvim_win_is_valid(winid) then
        return
    end
    local buf = vim.api.nvim_win_get_buf(winid)
    local line_count = math.max(vim.api.nvim_buf_line_count(buf), 1)
    local row = math.min(math.max(cursor[1] or 1, 1), line_count)
    local line = vim.api.nvim_buf_get_lines(buf, row - 1, row, false)[1] or ""
    local col = math.min(math.max(cursor[2] or 0, 0), #line)
    pcall(vim.api.nvim_win_set_cursor, winid, { row, col })
end

---@return { area: string, slot?: string, insert: boolean, cursor?: integer[] }?
function Creator:capture_focus_context()
    local current_win = vim.api.nvim_get_current_win()
    if self.layout and self.layout.focused_slot then
        local slot = self.layout:focused_slot(current_win)
        if slot then
            return {
                area = "layout",
                slot = slot,
                insert = self:in_insert_mode(),
                cursor = vim.api.nvim_win_get_cursor(current_win),
            }
        end
    end

    local candidates = {
        project = self.project_win,
        kind = self.kind_win,
        variant = self.variant_win,
        footer = self.footer_win,
        preview = self.preview_win,
    }
    for area, win in pairs(candidates) do
        if win and win:valid() and current_win == win.win then
            return { area = area, insert = false }
        end
    end
end

---@param context { area: string, slot?: string, insert: boolean, cursor?: integer[] }?
---@return boolean
function Creator:restore_focus_context(context)
    if not context then
        return false
    end
    if context.area == "layout" and self.layout and self.layout.focus_slot then
        if not layout_has_slot(self.layout, context.slot) or not self.layout:focus_slot(context.slot, context.insert) then
            return false
        end
        if not context.insert and self:in_insert_mode() then
            vim.cmd.stopinsert()
        end
        restore_cursor(vim.api.nvim_get_current_win(), context.cursor)
        return true
    end

    local win = ({
        project = self.project_win,
        kind = self.kind_win,
        variant = self.variant_win,
        footer = self.footer_win,
        preview = self.preview_win,
    })[context.area]
    if not win or not win:valid() then
        return false
    end
    vim.api.nvim_set_current_win(win.win)
    if not context.insert and self:in_insert_mode() then
        vim.cmd.stopinsert()
    end
    return true
end

-- Default focus
function Creator:focus_default()
    if self.layout and self.layout.focus_default then
        self.layout:focus_default()
    end
    self:update_focus_highlights()
end

---@param fn fun()
function Creator:without_close_watchers(fn)
    return self.panel:without_close_watchers(fn)
end

-- Focus projects
function Creator:focus_project_list()
    self:focus_creator_default()
end

-- Focus creator
---@param insert_mode? boolean
function Creator:focus_creator_default(insert_mode)
    if self:in_insert_mode() then
        vim.cmd.stopinsert()
    end
    vim.schedule(function()
        if self.layout and self.layout.focus_default then
            self.layout:focus_default(insert_mode == true)
        else
            self:focus_default()
        end
        self:update_focus_highlights()
    end)
end

-- Focus last
---@param insert_mode? boolean
function Creator:focus_creator_last_slot(insert_mode)
    if self:in_insert_mode() then
        vim.cmd.stopinsert()
    end
    vim.schedule(function()
        if self.layout and self.layout.focus_last then
            self.layout:focus_last(insert_mode == true)
        else
            self:focus_default()
        end
        self:update_focus_highlights()
    end)
end

-- Reset inputs
function Creator:reset_inputs()
    self.field_cache = {}
    self.field_history = {}
    self.variant_index = 1
    self.drafts = DraftStore.new()
    self:prime_drafts(nil)
    self:activate_layout({ area = "layout", slot = "title", insert = false })
    self:refresh()
end

---@param win snacks.win?
---@param mouse table
---@return boolean
function Creator:mouse_in_win(win, mouse)
    return win ~= nil and win:valid() and mouse.winid == win.win
end

---@param win snacks.win
---@param text_field boolean
function Creator:focus_mouse_win(win, text_field)
    if self:in_insert_mode() and not text_field then
        vim.cmd.stopinsert()
    end
    vim.api.nvim_set_current_win(win.win)
    self:update_focus_highlights()
end

---@param mouse table
---@return boolean
function Creator:handle_mouse(mouse)
    if self:mouse_in_win(self.project_win, mouse) then
        self:focus_creator_default()
        return true
    end
    if self:mouse_in_win(self.kind_win, mouse) then
        self:focus_mouse_win(self.kind_win, false)
        self:activate_kind_tab_at(mouse.column)
        return true
    end
    if self:mouse_in_win(self.variant_win, mouse) then
        self:focus_mouse_win(self.variant_win, false)
        self:activate_variant_tab_at(mouse.column)
        return true
    end

    local layout_slot = self.layout and self.layout.focused_slot and self.layout:focused_slot(mouse.winid) or nil
    if layout_slot and self.layout and self.layout.focus_slot then
        local win = vim.api.nvim_win_is_valid(mouse.winid) and mouse.winid or nil
        local buf = win and vim.api.nvim_win_get_buf(win) or nil
        local text_field = buf and vim.bo[buf].modifiable == true
        if self:in_insert_mode() and not text_field then
            vim.cmd.stopinsert()
        end
        self.layout:focus_slot(layout_slot, self:in_insert_mode() and text_field)
        return true
    end

    local passive_windows = {
        self.footer_win,
        self.preview_win,
    }
    for _, win in ipairs(passive_windows) do
        if self:mouse_in_win(win, mouse) then
            self:focus_mouse_win(win, false)
            return true
        end
    end
    return false
end

---@param buf integer
function Creator:apply_mouse_keymap(buf)
    vim.keymap.set({ "n", "i" }, "<LeftMouse>", function()
        self:handle_mouse(vim.fn.getmousepos())
    end, { buffer = buf, silent = true })
end

---@param index integer
function Creator:set_project_index(index)
    local project = self.projects[index]
    if not project or (self.project and self.project.root == project.root) then
        return
    end
    self.project_index = index
    self.project = project
    self.context = Helpers.project_context(self.context, project)
    self.state.project = project
    self.state.context = self.context
    self:render_project_list()
    self:refresh_layout_prompt_contexts()
end

---@param delta integer
function Creator:move_project(delta)
    if #self.projects > 1 then
        self:set_project_index(((self.project_index - 1 + delta) % #self.projects) + 1)
    end
end

-- Render projects
function Creator:render_project_list()
    local lines = {} ---@type string[]
    local marks = {} ---@type Clodex.Extmark[]
    self.project_line_map = {}
    local active_project_hl = Prompt.title_group(self.state.kind)
    local target_width = self:project_list_width()
    for index, project in ipairs(self.projects) do
        local details = Helpers.project_details(self.app, project)
        local icon = details and details.project_icon and (details.project_icon .. " ") or ""
        local line = " " .. icon .. project.name
        local padding = math.max(target_width - vim.fn.strdisplaywidth(line), 0)
        if padding > 0 then
            line = line .. string.rep(" ", padding)
        end
        lines[#lines + 1] = line
        self.project_line_map[#lines] = index
        local row = #lines - 1
        local is_selected = index == self.project_index
        local is_active_project = project.root == self.active_project_root
        if is_selected then
            marks[#marks + 1] = Extmark.inline(row, 0, #line, "ClodexPromptSourceTabActive")
            if is_active_project then
                marks[#marks + 1] = Extmark.inline(row, 0, #line, active_project_hl, 110, { hl_mode = "combine" })
            end
        else
            local highlight = is_active_project and active_project_hl or "ClodexPromptSourceTab"
            marks[#marks + 1] = Extmark.inline(row, 0, #line, highlight)
        end
    end

    vim.bo[self.project_buf].modifiable = true
    vim.api.nvim_buf_set_lines(self.project_buf, 0, -1, false, #lines > 0 and lines or { " No projects " })
    vim.bo[self.project_buf].modifiable = false
    vim.api.nvim_buf_clear_namespace(self.project_buf, TAB_NS, 0, -1)
    for _, mark in ipairs(marks) do
        mark:place(self.project_buf, TAB_NS)
    end
    if self.project_win and self.project_win:valid() then
        vim.api.nvim_win_set_cursor(self.project_win.win, { math.max(self.project_index, 1), 0 })
    end
end

-- Render background
function Creator:render_project_background()
    local lines = {}
    local line = string.rep(" ", self:project_background_width())
    for _ = 1, self:project_background_height() do
        lines[#lines + 1] = line
    end
    vim.bo[self.project_bg_buf].modifiable = true
    vim.api.nvim_buf_set_lines(self.project_bg_buf, 0, -1, false, lines)
    vim.bo[self.project_bg_buf].modifiable = false
end

function Creator:refresh_project_background()
    self:render_project_background()
    if not self.panel or not self.panel.background then
        return
    end
    self.project_bg_win = self.panel.background:open()
    self.panel.background:update()
end

---@return boolean
function Creator:has_window_in_current_tab()
    local current_tab = vim.api.nvim_get_current_tabpage()
    local windows = {
        self.project_win,
        self.kind_win,
        self.variant_win,
        self.footer_win,
        self.preview_win,
        self.layout and self.layout.title_win or nil,
        self.layout and self.layout.body_win or nil,
        self.layout and self.layout.preview_win or nil,
    }
    for _, win in ipairs(windows) do
        if win and win:valid() then
            local ok, tabpage = pcall(vim.api.nvim_win_get_tabpage, win.win)
            if ok and tabpage == current_tab then
                return true
            end
        end
    end
    return false
end

function Creator:refresh_current_tab_background()
    if self.is_closing or not self:has_window_in_current_tab() then
        return
    end
    self:refresh_project_background()
    self:apply_prompt_theme()
end

function Creator:setup_autocmds()
    if self.autocmd_group then
        return
    end

    self.autocmd_group = vim.api.nvim_create_augroup("clodex_prompt_creator_" .. self.project_bg_buf, {
        clear = true,
    })
    vim.api.nvim_create_autocmd({ "TabEnter", "WinEnter", "FocusGained", "VimResized" }, {
        group = self.autocmd_group,
        callback = function()
            vim.schedule(function()
                if self.autocmd_group then
                    self:refresh_current_tab_background()
                end
            end)
        end,
    })
end

-- Project keymaps
function Creator:apply_project_keymaps()
    self:apply_mouse_keymap(self.project_buf)
    vim.keymap.set({ "n", "i" }, "<Right>", function()
        self:focus_creator_default()
        return ""
    end, { buffer = self.project_buf, silent = true, expr = true })
    vim.keymap.set("n", "l", function()
        self:focus_creator_default()
        return ""
    end, { buffer = self.project_buf, silent = true, expr = true })
    vim.keymap.set("n", "<Tab>", function()
        self:focus_creator_default(false)
        return ""
    end, { buffer = self.project_buf, silent = true, expr = true })
    vim.keymap.set("i", "<S-Tab>", function()
        self:focus_creator_last_slot(true)
        return ""
    end, { buffer = self.project_buf, silent = true, expr = true })
    vim.keymap.set("n", "<Down>", function()
        self:move_project(1)
    end, { buffer = self.project_buf, silent = true })
    vim.keymap.set("n", "j", function()
        self:move_project(1)
    end, { buffer = self.project_buf, silent = true })
    vim.keymap.set("n", "<Up>", function()
        self:move_project(-1)
    end, { buffer = self.project_buf, silent = true })
    vim.keymap.set("n", "k", function()
        self:move_project(-1)
    end, { buffer = self.project_buf, silent = true })
    vim.keymap.set({ "n", "i" }, "<C-Down>", function()
        self:move_project(1)
    end, { buffer = self.project_buf, silent = true })
    vim.keymap.set({ "n", "i" }, "<C-Up>", function()
        self:move_project(-1)
    end, { buffer = self.project_buf, silent = true })
    for _, action in ipairs(self.submit_actions) do
        Helpers.apply_action_keymaps(self, self.project_buf, action, RESET_AFTER_SUBMIT_ACTIONS)
    end
    vim.keymap.set("n", "q", function()
        self:close()
    end, { buffer = self.project_buf, silent = true })
    vim.keymap.set("n", "<Esc>", function()
        self:close()
    end, { buffer = self.project_buf, silent = true })
end

---@param buf integer
function Creator:apply_first_slot_keymaps(buf)
    self:apply_common_keymaps(buf)
end

-- Render kinds
function Creator:render_kind_tabs()
    local labels = {}
    for _, kind in ipairs(self.kinds) do
        labels[#labels + 1] = {
            label = kind.label,
            hl_group = Prompt.kind_name_group(kind.id),
            active_hl_group = Prompt.title_active_group(kind.id),
        }
    end
    self.kind_tab_spans = self:render_tab_line(self.kind_buf, labels, self.kind_index, self:content_frame_width())
end

-- Render variants
function Creator:render_variant_tabs()
    local variants = self:variants()
    if #variants == 0 then
        self:remove_block("variant_tabs")
        self.variant_block = nil
        self.variant_win = nil
        self.variant_buf = nil
        self.variant_tab_spans = {}
        return
    end

    self.variant_buf = self.variant_buf or Helpers.prompt_buffer("scratch")
    if not vim.b[self.variant_buf].clodex_prompt_keymaps_applied then
        self:apply_common_keymaps(self.variant_buf)
        vim.b[self.variant_buf].clodex_prompt_keymaps_applied = true
    end
    local labels = {}
    for _, variant in ipairs(variants) do
        labels[#labels + 1] = {
            label = variant.label,
            hl_group = "ClodexPromptSourceTab",
            active_hl_group = "ClodexPromptSourceTabActive",
        }
    end
    self.variant_tab_spans = self:render_tab_line(self.variant_buf, labels, self.variant_index, self:content_frame_width())
    self.variant_win = self:open_block(self, "variant_block", "variant_win", "variant_tabs", self.variant_buf, {
        enter = false,
        border = "none",
        zindex = LAYOUT.prompt_content_zindex,
        width = function()
            return self:content_frame_width()
        end,
        height = 1,
        row = function()
            return self:variant_row()
        end,
        col = function()
            return self:content_frame_col()
        end,
        view = "footer",
        theme = "prompt_footer",
    })
end

---@param insert_mode? boolean
function Creator:render_footer(insert_mode)
    insert_mode = insert_mode == nil and self:in_insert_mode() or insert_mode
    local has_variants = #self:variants() > 0
    local has_multiple_projects = #self.projects > 1
    local key_hl = Prompt.title_group(self.state.kind)
    local lines, marks =
        Helpers.render_footer_rows(Helpers.footer_rows(insert_mode, has_variants, has_multiple_projects), key_hl)

    vim.bo[self.footer_buf].modifiable = true
    vim.api.nvim_buf_set_lines(self.footer_buf, 0, -1, false, lines)
    vim.bo[self.footer_buf].modifiable = false
    vim.api.nvim_buf_clear_namespace(self.footer_buf, FOOTER_NS, 0, -1)
    for _, mark in ipairs(marks) do
        mark:place(self.footer_buf, FOOTER_NS)
    end
end

-- Apply theme
function Creator:apply_prompt_theme()
    local prompt_hl = Prompt.title_group(self.state.kind)
    self.panel:set_accent(prompt_hl)
    local windows = {
        self.project_win,
        self.kind_win,
        self.footer_win,
        self.variant_win,
        self.preview_win,
        self.layout and self.layout.title_win or nil,
        self.layout and self.layout.body_win or nil,
        self.layout and self.layout.preview_win or nil,
    }
    for _, win in ipairs(windows) do
        if win and win.valid and win:valid() then
            Helpers.update_winhl(win.win, { FloatBorder = prompt_hl, FloatTitle = prompt_hl })
        end
    end
    if self.project_win and self.project_win:valid() then
        Helpers.hide_window_cursor(self.project_win.win, "ClodexPromptEditorNormal")
    end
    for _, win in ipairs({
        self.kind_win,
        self.variant_win,
        self.footer_win,
        self.preview_win,
        self.layout and self.layout.preview_win or nil,
    }) do
        if win and win:valid() then
            Helpers.hide_window_cursor(win.win, "ClodexPromptEditorFooter")
        end
    end
    self:update_focus_highlights()
end

---@param win snacks.win?
---@param inactive_hl string
function Creator:apply_focus_highlight(win, inactive_hl)
    if not win or not win.valid or not win:valid() then
        return
    end
    local active = vim.api.nvim_get_current_win() == win.win
    local normal_hl = active and PROMPT_ACTIVE_NORMAL or inactive_hl
    local border_hl = active and Prompt.focus_border_group(self.state.kind) or Prompt.title_group(self.state.kind)
    Helpers.update_winhl(win.win, {
        FloatBorder = border_hl,
        FloatTitle = border_hl,
        Normal = normal_hl,
        NormalFloat = normal_hl,
        NormalNC = normal_hl,
    })
end

function Creator:update_focus_highlights()
    self:apply_focus_highlight(self.project_win, PROMPT_FOOTER_NORMAL)
    self:apply_focus_highlight(self.kind_win, PROMPT_FOOTER_NORMAL)
    self:apply_focus_highlight(self.footer_win, PROMPT_FOOTER_NORMAL)
    self:apply_focus_highlight(self.variant_win, PROMPT_FOOTER_NORMAL)
    self:apply_focus_highlight(self.preview_win, PROMPT_FOOTER_NORMAL)
    self:apply_focus_highlight(self.layout and self.layout.title_win or nil, PROMPT_EDITOR_NORMAL)
    self:apply_focus_highlight(self.layout and self.layout.body_win or nil, PROMPT_EDITOR_NORMAL)
    self:apply_focus_highlight(self.layout and self.layout.preview_win or nil, PROMPT_FOOTER_NORMAL)
end

---@param column integer
function Creator:activate_kind_tab_at(column)
    local index = Helpers.tab_index_at_column(self.kind_tab_spans, column)
    if index and index ~= self.kind_index then
        self:switch_kind(index - self.kind_index)
    end
end

---@param column integer
function Creator:activate_variant_tab_at(column)
    local index = Helpers.tab_index_at_column(self.variant_tab_spans, column)
    if index and index ~= self.variant_index then
        self:switch_variant(index - self.variant_index)
    end
end

-- Ensure windows
function Creator:ensure_shell_windows()
    self:refresh_project_background()
    self.project_win = self:open_block(self, "project_block", "project_win", "project", self.project_buf, {
        enter = false,
        border = "rounded",
        zindex = LAYOUT.prompt_content_zindex,
        title = " Target Project ",
        title_pos = "center",
        width = function()
            return self:project_list_width()
        end,
        height = function()
            return self:project_height()
        end,
        row = function()
            return self:project_row()
        end,
        col = function()
            return self:project_col()
        end,
        view = "footer",
        theme = "prompt_footer",
    })
    if not vim.b[self.project_buf].clodex_prompt_keymaps_applied then
        self:apply_project_keymaps()
        vim.b[self.project_buf].clodex_prompt_keymaps_applied = true
    end
    if self.project_win and self.project_win:valid() then
        vim.wo[self.project_win.win].cursorline = true
    end
    self.kind_win = self:open_block(self, "kind_block", "kind_win", "kind_tabs", self.kind_buf, {
        enter = false,
        border = "none",
        zindex = LAYOUT.prompt_content_zindex,
        width = function()
            return self:content_frame_width()
        end,
        height = 2,
        row = function()
            return self:kind_row()
        end,
        col = function()
            return self:content_frame_col()
        end,
        view = "footer",
        theme = "prompt_footer",
    })
    if not vim.b[self.kind_buf].clodex_prompt_keymaps_applied then
        self:apply_common_keymaps(self.kind_buf)
        vim.b[self.kind_buf].clodex_prompt_keymaps_applied = true
    end
    self.footer_win = self:open_block(self, "footer_block", "footer_win", "footer", self.footer_buf, {
        enter = false,
        border = "rounded",
        zindex = LAYOUT.prompt_content_zindex,
        title = " Actions ",
        title_pos = "center",
        width = function()
            return self:content_width()
        end,
        height = 2,
        row = function()
            return self:footer_row()
        end,
        col = function()
            return self:content_col()
        end,
        view = "footer",
        theme = "prompt_footer",
    })
    if not vim.b[self.footer_buf].clodex_prompt_keymaps_applied then
        self:apply_common_keymaps(self.footer_buf)
        vim.b[self.footer_buf].clodex_prompt_keymaps_applied = true
    end
end

-- Preview fallback
function Creator:render_preview_fallback()
    if not self.preview_buf or not vim.api.nvim_buf_is_valid(self.preview_buf) then
        return
    end
    vim.bo[self.preview_buf].modifiable = true
    vim.bo[self.preview_buf].filetype = "markdown"
    vim.api.nvim_buf_set_lines(self.preview_buf, 0, -1, false, Helpers.preview_fallback_lines(self.state.image_path))
    vim.bo[self.preview_buf].modifiable = false
end

-- Render preview
function Creator:render_preview()
    if self.preview_placement and self.preview_placement.close then
        self.preview_placement:close()
        self.preview_placement = nil
    end

    if not self.state.image_path then
        self:remove_block("image_preview")
        self.preview_win = nil
        self.preview_buf = nil
        return
    end

    self.preview_buf = self.preview_buf or Helpers.prompt_buffer("scratch")
    if self.preview_block and self.preview_block:is_valid() then
        self.preview_win = self.preview_block.win
    else
        self.preview_win = self:open_block(self, "preview_block", "preview_win", "image_preview", self.preview_buf, {
            enter = false,
            border = "rounded",
            zindex = LAYOUT.prompt_content_zindex,
            title = " Clipboard Image ",
            title_pos = "center",
            width = function()
                return self:preview_width()
            end,
            height = function()
                return self:preview_height()
            end,
            row = function()
                return self:preview_row()
            end,
            col = function()
                return self:preview_col()
            end,
            view = "wrapped_text",
            theme = "prompt_footer",
        })
    end
    if not vim.b[self.preview_buf].clodex_prompt_keymaps_applied then
        self:apply_common_keymaps(self.preview_buf)
        vim.b[self.preview_buf].clodex_prompt_keymaps_applied = true
    end

    local ok, Snacks = pcall(require, "snacks")
    local terminal_env = ok
        and Snacks.image
        and Snacks.image.terminal
        and Snacks.image.terminal.env
        and Snacks.image.terminal.env()
        or nil
    local terminal_supports_images = terminal_env and terminal_env.supported == true
    if
        terminal_supports_images
        and Snacks.image.supports
        and Snacks.image.supports(self.state.image_path)
        and Snacks.image.placement
        and Snacks.image.placement.new
    then
        local placement = Snacks.image.placement.new(self.preview_buf, self.state.image_path, self:preview_image_opts())
        self.preview_placement = placement
        vim.defer_fn(function()
            if
                self.preview_placement ~= placement
                or not self.preview_buf
                or not vim.api.nvim_buf_is_valid(self.preview_buf)
            then
                return
            end
            if placement.ready and placement:ready() then
                return
            end
            if placement.close then
                placement:close()
            end
            if self.preview_placement == placement then
                self.preview_placement = nil
            end
            self:render_preview_fallback()
        end, 1500)
        return
    end
    self:render_preview_fallback()
end

---@param focus_context? { area: string, slot?: string, insert: boolean }
function Creator:activate_layout(focus_context)
    if self.layout and self.layout.close then
        self:without_close_watchers(function()
            self.layout:close()
        end)
    end
    local layout_id = KindRegistry.layout_id(self.state.kind, self.state.variant)
    local builder = LAYOUT_BUILDERS[layout_id] or LAYOUT_BUILDERS.composer
    self.layout = builder.new(self)
    self.layout:open()
    self.layout:set_draft(
        vim.tbl_extend(
            "force",
            self:merge_cached_fields(
                self.state.kind,
                self.state.variant,
                self.drafts:get(self.state.kind, self.state.variant, self.state),
                KindRegistry.default_draft(self.state.kind, self.state.variant)
            ),
            {
                title = self.state.title,
                details = self.state.details,
                image_path = self.state.image_path,
                preview_text = self.state.preview_text,
            }
        )
    )
    self:refresh_layout_prompt_contexts()
    self:render_preview()
    if not self:restore_focus_context(focus_context) then
        self:focus_default()
    end
end

-- Refresh creator
function Creator:refresh()
    self:ensure_shell_windows()
    self:render_project_list()
    self:render_kind_tabs()
    self:render_variant_tabs()
    self:render_footer()
    if self.layout and self.layout.update then
        self.layout:update()
    end
    self:render_preview()
    self:refresh_project_background()
    self:apply_prompt_theme()
end

---@param silent? boolean
function Creator:replace_clipboard_image(silent)
    local image_path = PromptAssets.save_clipboard_image(
        self.app.config:get().storage.workspaces_dir,
        self.project.root,
        self.state.kind
    )
    if not image_path then
        return
    end
    self.state.image_path = image_path
    self:save_current_draft()
    self:render_preview()
    self:refresh()
    if not silent then
        notify.notify(("Updated clipboard image for %s"):format(self.project.name))
    end
end

---@param delta integer
function Creator:switch_kind(delta)
    if self.lock_kind then
        return
    end
    local focus_context = self:capture_focus_context()
    self:save_current_draft()
    self.kind_index = ((self.kind_index - 1 + delta) % #self.kinds) + 1
    self.variant_index = 1
    self:sync_state_from_draft()
    self:activate_layout(focus_context)
    self:refresh()
    self:restore_focus_context(focus_context)
end

---@param delta integer
function Creator:switch_variant(delta)
    local variants = self:variants()
    if #variants == 0 then
        return
    end
    local focus_context = self:capture_focus_context()
    self:save_current_draft()
    self.variant_index = ((self.variant_index - 1 + delta) % #variants) + 1
    self:sync_state_from_draft()
    self:activate_layout(focus_context)
    self:refresh()
    self:restore_focus_context(focus_context)
end

---@param buf integer
function Creator:apply_common_keymaps(buf)
    self:apply_mouse_keymap(buf)
    vim.keymap.set("n", "<Tab>", function()
        self:focus_creator_default(false)
        return ""
    end, { buffer = buf, silent = true, expr = true })
    vim.keymap.set("i", "<S-Tab>", function()
        self:focus_creator_default(true)
        return ""
    end, { buffer = buf, silent = true, expr = true })
    vim.keymap.set("n", "<Down>", function()
        self:focus_creator_default(false)
    end, { buffer = buf, silent = true })
    vim.keymap.set("n", "<Up>", function()
        self:focus_creator_last_slot(false)
    end, { buffer = buf, silent = true })
    vim.keymap.set("n", "<Right>", function()
        self:switch_kind(1)
    end, { buffer = buf, silent = true })
    vim.keymap.set("n", "l", function()
        self:switch_kind(1)
    end, { buffer = buf, silent = true })
    vim.keymap.set("n", "<Left>", function()
        self:switch_kind(-1)
    end, { buffer = buf, silent = true })
    vim.keymap.set("n", "h", function()
        self:switch_kind(-1)
    end, { buffer = buf, silent = true })
    vim.keymap.set("n", "<C-Right>", function()
        self:switch_kind(1)
    end, { buffer = buf, silent = true })
    vim.keymap.set("n", "<C-Left>", function()
        self:switch_kind(-1)
    end, { buffer = buf, silent = true })
    vim.keymap.set("i", "<C-Right>", function()
        self:switch_kind(1)
    end, { buffer = buf, silent = true })
    vim.keymap.set("i", "<C-Left>", function()
        self:switch_kind(-1)
    end, { buffer = buf, silent = true })
    vim.keymap.set({ "n", "i" }, "<C-Down>", function()
        self:move_project(1)
    end, { buffer = buf, silent = true })
    vim.keymap.set({ "n", "i" }, "<C-Up>", function()
        self:move_project(-1)
    end, { buffer = buf, silent = true })
    vim.keymap.set("n", "]", function()
        self:switch_variant(1)
    end, { buffer = buf, silent = true })
    vim.keymap.set("n", "[", function()
        self:switch_variant(-1)
    end, { buffer = buf, silent = true })
    for _, action in ipairs(self.submit_actions) do
        Helpers.apply_action_keymaps(self, buf, action, RESET_AFTER_SUBMIT_ACTIONS)
    end
    vim.keymap.set({ "n", "i" }, "<C-v>", function()
        self:replace_clipboard_image(false)
    end, { buffer = buf, silent = true })
    vim.keymap.set("n", "q", function()
        self:close()
    end, { buffer = buf, silent = true })
    vim.keymap.set("n", "<Esc>", function()
        self:close()
    end, { buffer = buf, silent = true })
    self:attach_editor_mode_events(buf)
end

---@param action string
---@param opts? { reset?: boolean }
function Creator:submit(action, opts)
    self:save_current_draft()
    local draft = self.drafts:get(self.state.kind, self.state.variant, self.state)
    local spec = PromptSubmit.build_spec(vim.tbl_extend("force", self.state, draft))
    if not spec then
        notify.warn("Prompt title is required")
        return
    end

    local result = self.on_submit(spec, action, self.project)
    if result == false then
        return
    end
    if opts and opts.reset then
        self:reset_inputs()
        return
    end
    self:close()
end

---@param clear_layout? boolean
function Creator:close(clear_layout)
    if self.is_closing then
        return
    end

    self.is_closing = true
    if self.autocmd_group then
        pcall(vim.api.nvim_del_augroup_by_id, self.autocmd_group)
        self.autocmd_group = nil
    end
    local layout_buffers = self.layout and self.layout.buffers and self.layout:buffers() or {}
    local lingering_buffers = {
        self.project_bg_buf,
        self.project_buf,
        self.kind_buf,
        self.variant_buf,
        self.footer_buf,
        self.preview_buf,
    }
    vim.list_extend(lingering_buffers, layout_buffers)
    if self.preview_placement and self.preview_placement.close then
        self.preview_placement:close()
        self.preview_placement = nil
    end
    local closed_layout = self.layout
    if clear_layout ~= false and closed_layout and closed_layout.close then
        closed_layout:close()
    end
    self.panel:destroy()
    Helpers.close_buffer_windows(lingering_buffers)
    self.project_bg_win = nil
    self.project_win = nil
    self.kind_win = nil
    self.variant_win = nil
    self.footer_win = nil
    self.preview_win = nil
    if self.on_close then
        pcall(self.on_close, self)
    end
    self.is_closing = false
    if clear_layout ~= false and closed_layout then
        vim.defer_fn(function()
            if self.layout == closed_layout then
                self.layout = nil
            end
        end, 20)
    end
end

---@param opts Clodex.PromptCreator.OpenOpts
---@return Clodex.PromptCreator
function Creator.open(opts)
    local creator = Creator.new(opts)
    creator:setup_autocmds()
    creator:ensure_shell_windows()
    creator:render_kind_tabs()
    creator:render_variant_tabs()
    creator:render_footer()
    creator:activate_layout({ area = "layout", slot = "title", insert = false })
    creator:refresh()
    return creator
end

return Creator
