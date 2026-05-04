local Action = require("clodex.ui.panel.action")

---@return table
local function ui_win()
    return require("clodex.ui.win")
end

---@class Clodex.UiBlock.BufferConfig
---@field preset? Clodex.UiWin.BufferPreset|table<string, any>
---@field name? string
---@field listed? boolean
---@field scratch? boolean
---@field bo? table<string, any>

---@class Clodex.UiBlock.Config
---@field id string
---@field panel? Clodex.UiPanel
---@field buf? integer
---@field buffer? Clodex.UiBlock.BufferConfig
---@field win snacks.win.Config|{}
---@field actions? (Clodex.UiAction|Clodex.UiAction.Config)[]
---@field render? fun(block: Clodex.UiBlock)
---@field on_focus? fun(block: Clodex.UiBlock)
---@field on_close? fun(block: Clodex.UiBlock)
---@field close_on_destroy? boolean
---@field wipe_buffer? boolean

---@class Clodex.UiBlock
---@field id string
---@field panel? Clodex.UiPanel
---@field buf integer
---@field win? snacks.win
---@field win_opts snacks.win.Config|{}
---@field actions Clodex.UiAction[]
---@field focused boolean
---@field mode string
---@field accent? string
---@field render_callback? fun(block: Clodex.UiBlock)
---@field on_focus? fun(block: Clodex.UiBlock)
---@field on_close? fun(block: Clodex.UiBlock)
---@field close_on_destroy boolean
---@field wipe_buffer boolean
local Block = {}
Block.__index = Block

---@param value any
---@return Clodex.UiAction
local function normalize_action(value)
    if getmetatable(value) == Action then
        return value
    end
    return Action.new(value)
end

---@param win? snacks.win
local function close_snacks_window(win)
    if not win then
        return
    end

    local winid = win.win
    if win.close then
        pcall(function()
            win:close()
        end)
    else
        ui_win().close(winid)
    end
    if ui_win().is_valid(winid) then
        ui_win().close(winid)
    end
    if win.close then
        win.win = nil
    end
end

---@param win? snacks.win
---@param zindex any
local function apply_zindex(win, zindex)
    if type(zindex) ~= "number" or not win or not win.valid or not win:valid() then
        return
    end
    local ok, config = pcall(vim.api.nvim_win_get_config, win.win)
    if not ok or config.relative == "" then
        return
    end
    config.zindex = zindex
    pcall(vim.api.nvim_win_set_config, win.win, config)
end

---@param win? snacks.win
---@param hl_group? string
local function apply_accent(win, hl_group)
    if not hl_group or hl_group == "" or not win or not win.valid or not win:valid() then
        return
    end

    local winhl = vim.api.nvim_get_option_value("winhl", { win = win.win }) or ""
    local fields = {} ---@type table<string, string>
    for part in winhl:gmatch("[^,]+") do
        local source, target = part:match("^([^:]+):(.+)$")
        if source and target then
            fields[source] = target
        end
    end
    fields.FloatBorder = hl_group
    fields.FloatTitle = hl_group

    local parts = {}
    for source, target in pairs(fields) do
        parts[#parts + 1] = ("%s:%s"):format(source, target)
    end
    table.sort(parts)
    vim.api.nvim_set_option_value("winhl", table.concat(parts, ","), { win = win.win })
end

---@param opts Clodex.UiBlock.Config
---@return Clodex.UiBlock
function Block.new(opts)
    assert(opts and opts.id, "block id is required")

    local actions = {} ---@type Clodex.UiAction[]
    for _, action in ipairs(opts.actions or {}) do
        actions[#actions + 1] = normalize_action(action)
    end

    return setmetatable({
        id = opts.id,
        panel = opts.panel,
        buf = opts.buf or ui_win().create_buffer(opts.buffer or { preset = "scratch" }),
        win = nil,
        win_opts = vim.deepcopy(opts.win or {}),
        actions = actions,
        focused = false,
        mode = "normal",
        accent = nil,
        render_callback = opts.render,
        on_focus = opts.on_focus,
        on_close = opts.on_close,
        close_on_destroy = opts.close_on_destroy ~= false,
        wipe_buffer = opts.wipe_buffer == true,
    }, Block)
end

---@return boolean
function Block:is_valid()
    return self.win ~= nil and self.win.valid and self.win:valid() == true
end

---@return boolean
function Block:is_open()
    return self:is_valid()
end

---@return integer?
function Block:winid()
    return self:is_valid() and self.win.win or nil
end

---@return Clodex.UiAction[]
function Block:get_actions()
    return self.actions
end

---@param action Clodex.UiAction|Clodex.UiAction.Config
function Block:add_action(action)
    self.actions[#self.actions + 1] = normalize_action(action)
    if self.buf and vim.api.nvim_buf_is_valid(self.buf) then
        self.actions[#self.actions]:apply(self.buf, { panel = self.panel, block = self })
    end
end

function Block:apply_actions()
    if not self.buf or not vim.api.nvim_buf_is_valid(self.buf) then
        return
    end

    for _, action in ipairs(self.actions) do
        action:apply(self.buf, { panel = self.panel, block = self })
    end
end

function Block:render()
    if self.render_callback then
        self.render_callback(self)
    end
end

---@return snacks.win?
function Block:open()
    if self:is_valid() then
        return self.win
    end

    local opts = vim.deepcopy(self.win_opts)
    opts.buf = self.buf
    self.win = ui_win().open(opts)
    apply_zindex(self.win, self.win_opts.zindex)
    apply_accent(self.win, self.accent)
    self:apply_actions()
    self:render()
    return self.win
end

function Block:update()
    if self:is_valid() and self.win.update then
        self.win.opts = vim.tbl_deep_extend("force", self.win.opts or {}, self.win_opts)
        self.win:update()
        apply_zindex(self.win, self.win_opts.zindex)
        apply_accent(self.win, self.accent)
    end
    self:render()
end

---@param position { row?: integer|fun(): integer, col?: integer|fun(): integer }
function Block:set_position(position)
    self.win_opts.row = position.row or self.win_opts.row
    self.win_opts.col = position.col or self.win_opts.col
    self:update()
end

---@param size { width?: integer|fun(): integer, height?: integer|fun(): integer }
function Block:set_size(size)
    self.win_opts.width = size.width or self.win_opts.width
    self.win_opts.height = size.height or self.win_opts.height
    self:update()
end

---@param style table<string, any>
function Block:set_style(style)
    self.win_opts = vim.tbl_deep_extend("force", self.win_opts, style or {})
    local win_api = ui_win()
    if self:is_valid() and win_api.configure then
        win_api.configure(self.win.win, {
            view = self.win_opts.view,
            theme = self.win_opts.theme,
            theme_overrides = self.win_opts.theme_overrides,
            wo = self.win_opts.wo,
        })
    end
end

---@param hl_group string?
function Block:set_accent(hl_group)
    if not hl_group or hl_group == "" then
        return
    end

    self.accent = hl_group
    self:set_style({
        theme_overrides = {
            float_border = hl_group,
            float_title = hl_group,
        },
    })
    apply_accent(self.win, hl_group)
end

---@param mode string
function Block:set_mode(mode)
    self.mode = mode
end

---@param opts? { insert?: boolean }
---@return boolean
function Block:focus(opts)
    if not self:is_valid() then
        return false
    end

    self.focused = true
    vim.api.nvim_set_current_win(self.win.win)
    if opts and opts.insert then
        vim.cmd.startinsert()
    end
    if self.on_focus then
        self.on_focus(self)
    end
    return true
end

function Block:close()
    close_snacks_window(self.win)
    self.win = nil
    self.focused = false
    if self.on_close then
        self.on_close(self)
    end
end

function Block:destroy()
    if self.close_on_destroy then
        self:close()
    end
    if self.wipe_buffer and self.buf and vim.api.nvim_buf_is_valid(self.buf) then
        pcall(vim.api.nvim_buf_delete, self.buf, { force = true })
    end
end

return Block
