local LAYOUT = require("clodex.ui.prompt_creator.layout_config")

---@class Clodex.PromptCreator.ComposerLayout
---@field creator Clodex.PromptCreator
---@field title_buf integer
---@field body_buf integer
---@field title_win? snacks.win
---@field body_win? snacks.win
---@field title_block? Clodex.UiBlock
---@field body_block? Clodex.UiBlock
local ComposerLayout = {}
ComposerLayout.__index = ComposerLayout

local TITLE_MIN_WRAP_WIDTH = 16

---@param focus fun()
---@return string
local function schedule_insert_focus(focus)
    vim.schedule(focus)
    return vim.keycode("<Ignore>")
end

---@param creator Clodex.PromptCreator
---@return Clodex.PromptCreator.ComposerLayout
function ComposerLayout.new(creator)
    return setmetatable({
        creator = creator,
        title_buf = creator:prompt_buffer("text"),
        body_buf = creator:prompt_buffer("text"),
    }, ComposerLayout)
end

function ComposerLayout:open()
    self.title_win = self.creator:open_block(self, "title_block", "title_win", "layout_title", self.title_buf, {
        enter = true,
        border = "rounded",
        zindex = LAYOUT.prompt_content_zindex,
        title = " Title ",
        title_pos = "center",
        width = function()
            return self.creator:content_width()
        end,
        height = 1,
        row = function()
            return self.creator:title_row()
        end,
        col = function()
            return self.creator:content_col()
        end,
        view = "text",
        theme = "prompt_editor",
        bo = { modifiable = true },
    })
    self.body_win = self.creator:open_block(self, "body_block", "body_win", "layout_body", self.body_buf, {
        enter = false,
        border = "rounded",
        zindex = LAYOUT.prompt_content_zindex,
        title = " Details ",
        title_pos = "center",
        width = function()
            return self.creator:content_width()
        end,
        height = function()
            return self.creator:body_height()
        end,
        row = function()
            return self.creator:body_row()
        end,
        col = function()
            return self.creator:content_col()
        end,
        view = "wrapped_text",
        theme = "prompt_editor",
        bo = { modifiable = true },
    })
    self:apply_keymaps()
    self:update()
end

function ComposerLayout:apply_keymaps()
    if not vim.b[self.title_buf].clodex_prompt_keymaps_applied then
        self.creator:apply_first_slot_keymaps(self.title_buf)
        vim.keymap.set("i", "<CR>", function()
            self:split_title_at_cursor()
            return vim.keycode("<Ignore>")
        end, { buffer = self.title_buf, silent = true, expr = true })
        vim.keymap.set("n", "<Tab>", function()
            self:focus_body(false)
        end, { buffer = self.title_buf, silent = true })
        vim.keymap.set("n", "<Down>", function()
            self:focus_body(false)
        end, { buffer = self.title_buf, silent = true })
        vim.keymap.set("n", "<Up>", function()
            self:focus_body(false)
        end, { buffer = self.title_buf, silent = true })
        vim.keymap.set("i", "<S-Tab>", function()
            return schedule_insert_focus(function()
                self:focus_body(true)
            end)
        end, { buffer = self.title_buf, silent = true, expr = true })
        vim.keymap.set("i", "<Down>", function()
            return schedule_insert_focus(function()
                self:focus_body(true)
            end)
        end, { buffer = self.title_buf, silent = true, expr = true })
        vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
            buffer = self.title_buf,
            callback = function()
                vim.schedule(function()
                    self:normalize_title_continuation(true)
                end)
            end,
        })
        vim.b[self.title_buf].clodex_prompt_keymaps_applied = true
    end

    if not vim.b[self.body_buf].clodex_prompt_keymaps_applied then
        self.creator:apply_common_keymaps(self.body_buf)
        vim.keymap.set("n", "<Tab>", function()
            self:focus_title(false)
        end, { buffer = self.body_buf, silent = true })
        vim.keymap.set("i", "<S-Tab>", function()
            return schedule_insert_focus(function()
                self:focus_title(true)
            end)
        end, { buffer = self.body_buf, silent = true, expr = true })
        vim.keymap.set("i", "<Up>", function()
            return schedule_insert_focus(function()
                self:focus_title(true)
            end)
        end, { buffer = self.body_buf, silent = true, expr = true })
        vim.keymap.set("n", "<Down>", function()
            self:focus_title(false)
        end, { buffer = self.body_buf, silent = true })
        vim.keymap.set("n", "<Up>", function()
            self:focus_title(false)
        end, { buffer = self.body_buf, silent = true })
        vim.b[self.body_buf].clodex_prompt_keymaps_applied = true
    end
end

---@return integer
function ComposerLayout:title_wrap_width()
    return math.max(self.creator:content_width(), TITLE_MIN_WRAP_WIDTH)
end

---@param text string
---@param max_width integer
---@return string, string?
local function split_display_width(text, max_width)
    if vim.fn.strdisplaywidth(text) <= max_width then
        return text, nil
    end

    local hard_cut = #text
    for index = 1, #text do
        if vim.fn.strdisplaywidth(text:sub(1, index)) > max_width then
            hard_cut = math.max(index - 1, 1)
            break
        end
    end

    local cut = hard_cut
    for index = hard_cut, 1, -1 do
        if text:sub(index, index):match("%s") then
            cut = index - 1
            break
        end
    end

    if cut <= 0 then
        cut = hard_cut
    end

    local title = vim.trim(text:sub(1, cut))
    local overflow = vim.trim(text:sub(cut + 1))
    return title, overflow ~= "" and overflow or nil
end

---@param lines string[]
---@return string[]
local function nonempty_or_blank(lines)
    if #lines == 0 then
        return { "" }
    end
    if #lines == 1 and lines[1] == "" then
        return { "" }
    end
    return lines
end

---@param text string
---@return string[]
local function split_lines(text)
    local lines = vim.split(text or "", "\n", { plain = true })
    return nonempty_or_blank(lines)
end

---@param overflow string
---@param cursor_at_start? boolean
function ComposerLayout:prepend_details(overflow, cursor_at_start)
    overflow = vim.trim(overflow or "")
    if overflow == "" then
        return
    end

    local overflow_lines = split_lines(overflow)
    local body_lines = vim.api.nvim_buf_get_lines(self.body_buf, 0, -1, false)
    if #body_lines == 1 and body_lines[1] == "" then
        body_lines = {}
    end
    vim.list_extend(overflow_lines, body_lines)
    vim.api.nvim_buf_set_lines(self.body_buf, 0, -1, false, nonempty_or_blank(overflow_lines))

    if self.body_win and self.body_win:valid() then
        self:focus_body(true)
        local row = 1
        local inserted_line_count = #split_lines(overflow)
        local col = cursor_at_start and 0 or #(overflow_lines[inserted_line_count] or "")
        vim.api.nvim_win_set_cursor(self.body_win.win, { row, col })
    end
end

---@param focus_overflow? boolean
---@return boolean
function ComposerLayout:normalize_title_continuation(focus_overflow)
    if self.normalizing_title or not vim.api.nvim_buf_is_valid(self.title_buf) then
        return false
    end

    self.normalizing_title = true
    local title_lines = vim.api.nvim_buf_get_lines(self.title_buf, 0, -1, false)
    local title = title_lines[1] or ""
    local overflow_parts = {} ---@type string[]
    if #title_lines > 1 then
        for index = 2, #title_lines do
            overflow_parts[#overflow_parts + 1] = title_lines[index]
        end
    end

    local wrapped_title, wrapped_overflow = split_display_width(title, self:title_wrap_width())
    title = wrapped_title
    if wrapped_overflow then
        table.insert(overflow_parts, 1, wrapped_overflow)
    end

    if #title_lines ~= 1 or title_lines[1] ~= title then
        vim.api.nvim_buf_set_lines(self.title_buf, 0, -1, false, { title })
    end
    local overflow = vim.trim(table.concat(overflow_parts, "\n"))
    if overflow ~= "" then
        self:prepend_details(overflow, focus_overflow ~= false)
    end

    self.normalizing_title = false
    return overflow ~= ""
end

function ComposerLayout:split_title_at_cursor()
    if not self.title_win or not self.title_win:valid() then
        return
    end

    local cursor = vim.api.nvim_win_get_cursor(self.title_win.win)
    local lines = vim.api.nvim_buf_get_lines(self.title_buf, 0, -1, false)
    local line = lines[cursor[1]] or ""
    local col = cursor[2]
    local title = line:sub(1, col)
    local overflow_parts = { line:sub(col + 1) }
    for index = cursor[1] + 1, #lines do
        overflow_parts[#overflow_parts + 1] = lines[index]
    end

    self.normalizing_title = true
    vim.api.nvim_buf_set_lines(self.title_buf, 0, -1, false, { title })
    self.normalizing_title = false
    local overflow = table.concat(overflow_parts, "\n")
    if vim.trim(overflow) ~= "" then
        self:prepend_details(overflow, true)
    elseif self.body_win and self.body_win:valid() then
        self:focus_body(true)
        vim.api.nvim_win_set_cursor(self.body_win.win, { 1, 0 })
    end
end

---@return boolean
function ComposerLayout:should_focus_title_from_body()
    if not self.body_win or not self.body_win:valid() or vim.fn.pumvisible() == 1 then
        return false
    end
    return vim.api.nvim_win_get_cursor(self.body_win.win)[1] <= 1
end

function ComposerLayout:update()
    if self.title_block then
        self.title_block:update()
    end
    if self.body_block then
        self.body_block:update()
    end
end

---@param draft table
function ComposerLayout:set_draft(draft)
    vim.api.nvim_buf_set_lines(self.title_buf, 0, -1, false, { draft.title or "" })
    local lines = vim.split(draft.details or "", "\n", { plain = true })
    vim.api.nvim_buf_set_lines(self.body_buf, 0, -1, false, #lines > 0 and lines or { "" })
end

---@return table
function ComposerLayout:get_draft()
    return {
        title = vim.trim(vim.api.nvim_buf_get_lines(self.title_buf, 0, 1, false)[1] or ""),
        details = vim.trim(table.concat(vim.api.nvim_buf_get_lines(self.body_buf, 0, -1, false), "\n")),
    }
end

---@return string[]
function ComposerLayout:draft_fields()
    return { "title", "details" }
end

---@return integer[]
function ComposerLayout:buffers()
    return { self.title_buf, self.body_buf }
end

---@param insert_mode? boolean
function ComposerLayout:focus_title(insert_mode)
    if self.title_block then
        self.title_block:focus({ insert = insert_mode == true })
        self.creator:update_focus_highlights()
    end
end

---@param insert_mode? boolean
function ComposerLayout:focus_body(insert_mode)
    if self.body_block then
        self.body_block:focus({ insert = insert_mode == true })
        self.creator:update_focus_highlights()
    end
end

---@param insert_mode? boolean
function ComposerLayout:focus_default(insert_mode)
    self:focus_title(insert_mode == true)
end

---@param insert_mode? boolean
function ComposerLayout:focus_last(insert_mode)
    self:focus_body(insert_mode == true)
end

---@param winid? integer
---@return string?
function ComposerLayout:focused_slot(winid)
    winid = winid or vim.api.nvim_get_current_win()
    if self.title_win and self.title_win:valid() and winid == self.title_win.win then
        return "title"
    end
    if self.body_win and self.body_win:valid() and winid == self.body_win.win then
        return "body"
    end
end

---@param slot? string
---@param insert_mode? boolean
---@return boolean
function ComposerLayout:focus_slot(slot, insert_mode)
    if slot == "body" and self.body_block and self.body_block:focus({ insert = insert_mode == true }) then
        self.creator:update_focus_highlights()
        return true
    end
    local focused = self.title_block and self.title_block:focus({ insert = insert_mode == true }) or false
    if focused then
        self.creator:update_focus_highlights()
    end
    return focused
end

function ComposerLayout:close()
    self.creator:remove_block("layout_title")
    self.creator:remove_block("layout_body")
    self.title_win = nil
    self.body_win = nil
end

return ComposerLayout
