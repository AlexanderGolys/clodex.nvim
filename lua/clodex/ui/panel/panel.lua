local Block = require("clodex.ui.panel.block")

---@class Clodex.UiPanel.Config
---@field id string
---@field position? { row?: integer, col?: integer }
---@field size? { width?: integer, height?: integer }
---@field accent? string
---@field mode? string
---@field blocks? (Clodex.UiBlock|Clodex.UiBlock.Config)[]
---@field background? Clodex.UiBlock|Clodex.UiBlock.Config
---@field actions? (Clodex.UiAction|Clodex.UiAction.Config)[]
---@field focus_order? string[]
---@field on_close? fun(panel: Clodex.UiPanel)

---@class Clodex.UiPanel
---@field id string
---@field position { row?: integer, col?: integer }
---@field size { width?: integer, height?: integer }
---@field accent? string
---@field mode string
---@field blocks table<string, Clodex.UiBlock>
---@field background? Clodex.UiBlock
---@field block_order string[]
---@field focus_order string[]
---@field focused_block_id? string
---@field actions Clodex.UiAction[]
---@field close_watchers table<integer, integer>
---@field is_closing boolean
---@field suppress_close_events boolean
---@field on_close? fun(panel: Clodex.UiPanel)
local Panel = {}
Panel.__index = Panel

---@param value any
---@return Clodex.UiBlock
local function normalize_block(value)
    if getmetatable(value) == Block then
        return value
    end
    return Block.new(value)
end

---@param opts Clodex.UiPanel.Config
---@return Clodex.UiPanel
function Panel.new(opts)
    assert(opts and opts.id, "panel id is required")

    local self = setmetatable({
        id = opts.id,
        position = opts.position or {},
        size = opts.size or {},
        accent = opts.accent,
        mode = opts.mode or "normal",
        blocks = {},
        background = nil,
        block_order = {},
        focus_order = vim.deepcopy(opts.focus_order or {}),
        focused_block_id = nil,
        actions = vim.deepcopy(opts.actions or {}),
        close_watchers = {},
        is_closing = false,
        suppress_close_events = false,
        on_close = opts.on_close,
    }, Panel)

    if opts.background then
        self:set_background(opts.background)
    end
    for _, block in ipairs(opts.blocks or {}) do
        self:add_block(block)
    end
    return self
end

---@param block Clodex.UiBlock|Clodex.UiBlock.Config|nil
---@return Clodex.UiBlock?
function Panel:set_background(block)
    if self.background then
        self:unwatch_window(self.background.win)
        self.background:destroy()
    end
    if not block then
        self.background = nil
        return nil
    end

    local normalized = normalize_block(block)
    normalized.panel = self
    self.background = normalized
    if self.accent then
        normalized:set_accent(self.accent)
    end
    return normalized
end

---@param block Clodex.UiBlock|Clodex.UiBlock.Config
---@return Clodex.UiBlock
function Panel:add_block(block)
    local normalized = normalize_block(block)
    if self.blocks[normalized.id] and self.blocks[normalized.id] ~= normalized then
        self:unwatch_window(self.blocks[normalized.id].win)
        self.blocks[normalized.id]:destroy()
    end
    normalized.panel = self
    self.blocks[normalized.id] = normalized
    if not vim.tbl_contains(self.block_order, normalized.id) then
        self.block_order[#self.block_order + 1] = normalized.id
    end
    if not vim.tbl_contains(self.focus_order, normalized.id) then
        self.focus_order[#self.focus_order + 1] = normalized.id
    end
    if self.accent then
        normalized:set_accent(self.accent)
    end
    return normalized
end

---@param id string
---@return Clodex.UiBlock?
function Panel:block(id)
    return self.blocks[id]
end

---@param id string
function Panel:remove_block(id)
    local block = self.blocks[id]
    if block then
        self:unwatch_window(block.win)
        block:destroy()
    end
    self.blocks[id] = nil
    self.block_order = vim.tbl_filter(function(value)
        return value ~= id
    end, self.block_order)
    self.focus_order = vim.tbl_filter(function(value)
        return value ~= id
    end, self.focus_order)
    if self.focused_block_id == id then
        self.focused_block_id = nil
    end
end

---@param win snacks.win?
function Panel:watch_window(win)
    if not win or not win.valid or not win:valid() then
        return
    end

    local winid = win.win
    if not winid or winid == 0 or self.close_watchers[winid] then
        return
    end

    self.close_watchers[winid] = vim.api.nvim_create_autocmd("WinClosed", {
        pattern = tostring(winid),
        once = true,
        callback = function()
            self.close_watchers[winid] = nil
            if self.suppress_close_events then
                return
            end
            self:close()
        end,
    })
end

function Panel:clear_window_watchers()
    for winid, autocmd in pairs(self.close_watchers) do
        self.close_watchers[winid] = nil
        pcall(vim.api.nvim_del_autocmd, autocmd)
    end
end

---@param win? snacks.win
function Panel:unwatch_window(win)
    local winid = win and win.win or nil
    local autocmd = winid and self.close_watchers[winid] or nil
    if not autocmd then
        return
    end
    self.close_watchers[winid] = nil
    pcall(vim.api.nvim_del_autocmd, autocmd)
end

---@param fn fun()
function Panel:without_close_watchers(fn)
    self.suppress_close_events = true
    local ok, result = pcall(fn)
    self.suppress_close_events = false
    if not ok then
        error(result)
    end
    return result
end

function Panel:open()
    if self.background then
        self.background:open()
    end
    for _, id in ipairs(self.block_order) do
        local block = self.blocks[id]
        if block then
            local win = block:open()
            self:watch_window(win)
        end
    end
end

function Panel:update()
    if self.background then
        self.background:update()
    end
    for _, id in ipairs(self.block_order) do
        local block = self.blocks[id]
        if block then
            block:update()
        end
    end
end

function Panel:refresh()
    self:update()
end

---@param id string
---@param opts? { insert?: boolean }
---@return boolean
function Panel:focus(id, opts)
    local block = self.blocks[id]
    if not block or not block:focus(opts) then
        return false
    end
    self.focused_block_id = id
    return true
end

---@param delta integer
---@param opts? { insert?: boolean }
---@return boolean
function Panel:move_focus(delta, opts)
    if #self.focus_order == 0 then
        return false
    end

    local index = 1
    for candidate_index, id in ipairs(self.focus_order) do
        if id == self.focused_block_id then
            index = candidate_index
            break
        end
    end

    for offset = 1, #self.focus_order do
        local next_index = ((index - 1 + (delta * offset)) % #self.focus_order) + 1
        if self:focus(self.focus_order[next_index], opts) then
            return true
        end
    end
    return false
end

---@param opts? { insert?: boolean }
---@return boolean
function Panel:focus_next(opts)
    return self:move_focus(1, opts)
end

---@param opts? { insert?: boolean }
---@return boolean
function Panel:focus_prev(opts)
    return self:move_focus(-1, opts)
end

---@param position { row?: integer, col?: integer }
function Panel:set_position(position)
    self.position = vim.tbl_extend("force", self.position, position or {})
    self:update()
end

---@param size { width?: integer, height?: integer }
function Panel:set_size(size)
    self.size = vim.tbl_extend("force", self.size, size or {})
    self:update()
end

---@param mode string
function Panel:set_mode(mode)
    self.mode = mode
    for _, id in ipairs(self.block_order) do
        self.blocks[id]:set_mode(mode)
    end
end

---@param hl_group string?
function Panel:set_accent(hl_group)
    self.accent = hl_group
    if self.background then
        self.background:set_accent(hl_group)
    end
    for _, id in ipairs(self.block_order) do
        self.blocks[id]:set_accent(hl_group)
    end
end

---@return Clodex.UiAction[]
function Panel:get_actions()
    local actions = vim.deepcopy(self.actions)
    local block = self.focused_block_id and self.blocks[self.focused_block_id] or nil
    if block then
        vim.list_extend(actions, block:get_actions())
    end
    return actions
end

function Panel:close()
    if self.is_closing then
        return
    end

    self.is_closing = true
    self:clear_window_watchers()
    self:without_close_watchers(function()
        if self.background then
            self.background:close()
        end
        for _, id in ipairs(self.block_order) do
            local block = self.blocks[id]
            if block then
                block:close()
            end
        end
    end)
    self.focused_block_id = nil
    self.is_closing = false
    if self.on_close then
        self.on_close(self)
    end
end

function Panel:destroy()
    if self.is_closing then
        return
    end

    self.is_closing = true
    self:clear_window_watchers()
    self:without_close_watchers(function()
        if self.background then
            self.background:destroy()
        end
        for _, id in ipairs(self.block_order) do
            local block = self.blocks[id]
            if block then
                block:destroy()
            end
        end
    end)
    self.background = nil
    self.blocks = {}
    self.block_order = {}
    self.focus_order = {}
    self.focused_block_id = nil
    self.is_closing = false
end

return Panel
