---@class Clodex.PromptAction.Keymap
---@field normal? string
---@field insert? string
---@field reset? string
---@field reset_insert? string

---@class Clodex.PromptAction.Config
---@field value string
---@field label string
---@field keymap? Clodex.PromptAction.Keymap
---@field key? string
---@field insert_key? string
---@field reset_key? string
---@field reset_insert_key? string

---@class Clodex.PromptAction
---@field value string
---@field label string
---@field keymap Clodex.PromptAction.Keymap
---@field key? string
---@field insert_key? string
---@field reset_key? string
---@field reset_insert_key? string
local Action = {}
Action.__index = Action

---@param opts Clodex.PromptAction.Config
---@return Clodex.PromptAction
function Action.new(opts)
    assert(opts and opts.value, "prompt action value is required")
    assert(opts.label, "prompt action label is required")

    local keymap = vim.tbl_extend("force", {
        normal = opts.key,
        insert = opts.insert_key,
        reset = opts.reset_key,
        reset_insert = opts.reset_insert_key,
    }, opts.keymap or {})

    return setmetatable({
        value = opts.value,
        label = opts.label,
        keymap = keymap,
        key = keymap.normal,
        insert_key = keymap.insert,
        reset_key = keymap.reset,
        reset_insert_key = keymap.reset_insert,
    }, Action)
end

---@param actions Clodex.PromptAction.Config[]|Clodex.PromptAction[]
---@return Clodex.PromptAction[]
function Action.list(actions)
    local normalized = {} ---@type Clodex.PromptAction[]
    for _, action in ipairs(actions or {}) do
        normalized[#normalized + 1] = getmetatable(action) == Action and action or Action.new(action)
    end
    return normalized
end

---@return string?
function Action:get_normal_key()
    return self.keymap.normal
end

---@return string?
function Action:get_insert_key()
    return self.keymap.insert or self.keymap.normal
end

---@return string?
function Action:get_reset_key()
    return self.keymap.reset
end

---@return string?
function Action:get_reset_insert_key()
    return self.keymap.reset_insert
end

---@param creator Clodex.PromptCreator
---@param buf integer
---@param reset_actions? table<string, boolean>
function Action:apply(creator, buf, reset_actions)
    local submit = function(reset)
        creator:submit(self.value, { reset = reset == true or (reset_actions or {})[self.value] == true })
    end

    local normal_key = self:get_normal_key()
    if normal_key and normal_key ~= "" then
        vim.keymap.set("n", normal_key, function()
            submit(false)
        end, { buffer = buf, silent = true })
    end

    local insert_key = self:get_insert_key()
    if insert_key and insert_key ~= "" then
        vim.keymap.set("i", insert_key, function()
            submit(false)
        end, { buffer = buf, silent = true })
    end

    local reset_key = self:get_reset_key()
    if reset_key and reset_key ~= "" then
        vim.keymap.set("n", reset_key, function()
            submit(true)
        end, { buffer = buf, silent = true })
    end

    local reset_insert_key = self:get_reset_insert_key()
    if reset_insert_key and reset_insert_key ~= "" then
        vim.keymap.set("i", reset_insert_key, function()
            submit(true)
        end, { buffer = buf, silent = true })
    end
end

---@param insert_mode boolean
---@return Clodex.PromptCreator.FooterItem?
function Action:footer_item(insert_mode)
    local key = insert_mode and self:get_insert_key() or self:get_normal_key()
    if not key or key == "" then
        return nil
    end

    if insert_mode or not self:get_reset_key() then
        return {
            keys = { key },
            label = self.label,
        }
    end

    return {
        keys = { key, self:get_reset_key() },
        label = self.label,
        key_separator = " / ",
    }
end

return Action
