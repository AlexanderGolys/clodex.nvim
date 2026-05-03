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
        vim.keymap.set({ "n", "i" }, "<Tab>", function()
            self:focus_body()
        end, { buffer = self.title_buf, silent = true })
        vim.keymap.set("n", "<Down>", function()
            self:focus_body()
        end, { buffer = self.title_buf, silent = true })
        vim.keymap.set("i", "<Down>", function()
            vim.schedule(function()
                self:focus_body()
            end)
            return ""
        end, { buffer = self.title_buf, silent = true, expr = true })
        vim.keymap.set("i", "<CR>", function()
            vim.schedule(function()
                self:focus_body()
            end)
            return ""
        end, { buffer = self.title_buf, silent = true, expr = true })
        vim.b[self.title_buf].clodex_prompt_keymaps_applied = true
    end

    if not vim.b[self.body_buf].clodex_prompt_keymaps_applied then
        self.creator:apply_common_keymaps(self.body_buf)
        vim.keymap.set({ "n", "i" }, "<Tab>", function()
            self.creator:focus_project_list()
        end, { buffer = self.body_buf, silent = true })
        vim.keymap.set({ "n", "i" }, "<S-Tab>", function()
            self:focus_title()
        end, { buffer = self.body_buf, silent = true })
        vim.keymap.set({ "n", "i" }, "<Up>", function()
            if self:should_focus_title_from_body() then
                vim.schedule(function()
                    self:focus_title()
                end)
                return ""
            end
            return "<Up>"
        end, { buffer = self.body_buf, silent = true, expr = true })
        vim.b[self.body_buf].clodex_prompt_keymaps_applied = true
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

function ComposerLayout:focus_title()
    if self.title_block then
        self.title_block:focus({ insert = true })
    end
end

function ComposerLayout:focus_body()
    if self.body_block then
        self.body_block:focus({ insert = true })
    end
end

function ComposerLayout:focus_default()
    self:focus_title()
end

function ComposerLayout:focus_last()
    self:focus_body()
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
        return true
    end
    return self.title_block and self.title_block:focus({ insert = insert_mode == true }) or false
end

function ComposerLayout:close()
    self.creator:remove_block("layout_title")
    self.creator:remove_block("layout_body")
    self.title_win = nil
    self.body_win = nil
end

return ComposerLayout
