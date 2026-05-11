local LAYOUT = require("clodex.ui.prompt_creator.layout_config")

---@class Clodex.PromptCreator.ClipboardPreviewLayout
---@field creator Clodex.PromptCreator
---@field title_buf integer
---@field preview_buf integer
---@field title_win? snacks.win
---@field preview_win? snacks.win
---@field title_block? Clodex.UiBlock
---@field preview_block? Clodex.UiBlock
local ClipboardPreviewLayout = {}
ClipboardPreviewLayout.__index = ClipboardPreviewLayout

---@param creator Clodex.PromptCreator
---@return Clodex.PromptCreator.ClipboardPreviewLayout
function ClipboardPreviewLayout.new(creator)
    return setmetatable({
        creator = creator,
        title_buf = creator:prompt_buffer("text"),
        preview_buf = creator:prompt_buffer("text"),
    }, ClipboardPreviewLayout)
end

function ClipboardPreviewLayout:open()
    self.title_win = self.creator:open_block(self, "title_block", "title_win", "layout_title", self.title_buf, {
        enter = true,
        border = "rounded",
        zindex = LAYOUT.prompt_content_zindex,
        title = " Comment ",
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
    self.preview_win = self.creator:open_block(self, "preview_block", "preview_win", "layout_preview", self.preview_buf, {
        enter = false,
        border = "rounded",
        zindex = LAYOUT.prompt_content_zindex,
        title = " Clipboard Preview ",
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
        theme = "prompt_footer",
        bo = { modifiable = false },
    })
    self:apply_keymaps()
    self:update()
end

function ClipboardPreviewLayout:apply_keymaps()
    if not vim.b[self.title_buf].clodex_prompt_keymaps_applied then
        self.creator:apply_first_slot_keymaps(self.title_buf)
        vim.keymap.set("n", "<Tab>", function()
            self:focus_preview()
        end, { buffer = self.title_buf, silent = true })
        vim.keymap.set("n", "<Down>", function()
            self:focus_preview()
        end, { buffer = self.title_buf, silent = true })
        vim.keymap.set("n", "<Up>", function()
            self:focus_preview()
        end, { buffer = self.title_buf, silent = true })
        vim.keymap.set("i", "<Tab>", function()
            self:focus_preview()
            return ""
        end, { buffer = self.title_buf, silent = true, expr = true })
        vim.keymap.set("i", "<Tab>", function()
            self:focus_preview()
            return ""
        end, { buffer = self.title_buf, silent = true, expr = true })
        vim.b[self.title_buf].clodex_prompt_keymaps_applied = true
    end
    if not vim.b[self.preview_buf].clodex_prompt_keymaps_applied then
        self.creator:apply_common_keymaps(self.preview_buf)
        vim.keymap.set("n", "<Tab>", function()
            self:focus_title()
        end, { buffer = self.preview_buf, silent = true })
        vim.keymap.set("n", "<Down>", function()
            self:focus_title()
        end, { buffer = self.preview_buf, silent = true })
        vim.keymap.set("n", "<Up>", function()
            self:focus_title()
        end, { buffer = self.preview_buf, silent = true })
        vim.b[self.preview_buf].clodex_prompt_keymaps_applied = true
    end
end

function ClipboardPreviewLayout:update()
    if self.title_block then
        self.title_block:update()
    end
    if self.preview_block then
        self.preview_block:update()
    end
end

---@param draft table
function ClipboardPreviewLayout:set_draft(draft)
    vim.api.nvim_buf_set_lines(self.title_buf, 0, -1, false, { draft.title or "" })
    local preview_text = draft.preview_text and vim.trim(draft.preview_text) or ""
    if preview_text == "" then
        preview_text = "No clipboard text found. Copy an error message and switch back to this tab."
    end
    vim.bo[self.preview_buf].modifiable = true
    vim.api.nvim_buf_set_lines(self.preview_buf, 0, -1, false, vim.split(preview_text, "\n", { plain = true }))
    vim.bo[self.preview_buf].modifiable = false
end

---@return table
function ClipboardPreviewLayout:get_draft()
    return {
        title = vim.trim(vim.api.nvim_buf_get_lines(self.title_buf, 0, 1, false)[1] or ""),
        preview_text = vim.trim(self.creator.state.preview_text or ""),
    }
end

---@return string[]
function ClipboardPreviewLayout:draft_fields()
    return { "title" }
end

---@return integer[]
function ClipboardPreviewLayout:buffers()
    return { self.title_buf, self.preview_buf }
end

---@param insert_mode? boolean
function ClipboardPreviewLayout:focus_default(insert_mode)
    if self.title_block then
        self.title_block:focus({ insert = insert_mode == true })
        self.creator:update_focus_highlights()
    end
end

---@param insert_mode? boolean
function ClipboardPreviewLayout:focus_title(insert_mode)
    self:focus_default(insert_mode == true)
end

function ClipboardPreviewLayout:focus_preview()
    if self.preview_block then
        self.preview_block:focus()
        self.creator:update_focus_highlights()
    end
end

function ClipboardPreviewLayout:focus_last()
    self:focus_preview()
end

---@param winid? integer
---@return string?
function ClipboardPreviewLayout:focused_slot(winid)
    winid = winid or vim.api.nvim_get_current_win()
    if self.title_block and self.title_block:is_valid() and winid == self.title_block:winid() then
        return "title"
    end
    if self.preview_block and self.preview_block:is_valid() and winid == self.preview_block:winid() then
        return "preview"
    end
end

---@param slot? string
---@param insert_mode? boolean
---@return boolean
function ClipboardPreviewLayout:focus_slot(slot, insert_mode)
    if slot == "preview" and self.preview_block and self.preview_block:focus() then
        self.creator:update_focus_highlights()
        return true
    end
    local focused = self.title_block and self.title_block:focus({ insert = insert_mode == true }) or false
    if focused then
        self.creator:update_focus_highlights()
    end
    return focused
end

function ClipboardPreviewLayout:close()
    self.creator:remove_block("layout_title")
    self.creator:remove_block("layout_preview")
    self.title_win = nil
    self.preview_win = nil
end

return ClipboardPreviewLayout
