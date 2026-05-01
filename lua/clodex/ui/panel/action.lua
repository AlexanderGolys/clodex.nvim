---@alias Clodex.UiActionMode string|string[]

---@class Clodex.UiAction.Context
---@field panel? Clodex.UiPanel
---@field block? Clodex.UiBlock

---@class Clodex.UiAction.Config
---@field id? string
---@field mode? Clodex.UiActionMode
---@field lhs string
---@field label? string
---@field description? string
---@field callback fun(context: Clodex.UiAction.Context): any
---@field visible? boolean|fun(context: Clodex.UiAction.Context): boolean
---@field opts? vim.keymap.set.Opts

---@class Clodex.UiAction
---@field id string
---@field mode Clodex.UiActionMode
---@field lhs string
---@field label string
---@field description string
---@field callback fun(context: Clodex.UiAction.Context): any
---@field visible boolean|fun(context: Clodex.UiAction.Context): boolean
---@field opts vim.keymap.set.Opts
local Action = {}
Action.__index = Action

---@param opts Clodex.UiAction.Config
---@return Clodex.UiAction
function Action.new(opts)
    assert(opts and opts.lhs, "action lhs is required")
    assert(type(opts.callback) == "function", "action callback is required")

    return setmetatable({
        id = opts.id or opts.lhs,
        mode = opts.mode or "n",
        lhs = opts.lhs,
        label = opts.label or opts.lhs,
        description = opts.description or opts.label or opts.lhs,
        callback = opts.callback,
        visible = opts.visible == nil and true or opts.visible,
        opts = opts.opts or {},
    }, Action)
end

---@param context? Clodex.UiAction.Context
---@return boolean
function Action:is_visible(context)
    if type(self.visible) == "function" then
        return self.visible(context or {}) == true
    end
    return self.visible == true
end

---@param context? Clodex.UiAction.Context
---@return string?
function Action:footer_label(context)
    if not self:is_visible(context) then
        return nil
    end
    return self.label
end

---@param buf integer
---@param context? Clodex.UiAction.Context
function Action:apply(buf, context)
    local opts = vim.tbl_extend("force", { buffer = buf, silent = true }, self.opts)
    vim.keymap.set(self.mode, self.lhs, function()
        return self.callback(context or {})
    end, opts)
end

return Action
