local M = {}

local TERMINAL_FILETYPE = "clodex_terminal"
local DISABLED_FILETYPE_SECTIONS = { "statusline", "winbar" }

---@param values string[]|nil
---@param value string
---@return boolean
local function append_unique(values, value)
    values = values or {}
    if vim.tbl_contains(values, value) then
        return false
    end
    values[#values + 1] = value
    return true
end

---@param value string
---@param disabled table
---@param sections string[]
---@return boolean
local function append_terminal_filetype(value, disabled, sections)
    local changed = false
    for _, section in ipairs(sections) do
        local section_values = vim.deepcopy(disabled[section] or {})
        if append_unique(section_values, value) then
            disabled[section] = section_values
            changed = true
        end
    end
    return changed
end

---@return table?
local function lualine_config()
    if not package.loaded["lualine"] then
        return nil
    end

    local ok, lualine = pcall(require, "lualine")
    if not ok or type(lualine.get_config) ~= "function" or type(lualine.setup) ~= "function" then
        return nil
    end

    return {
        api = lualine,
        config = vim.deepcopy(lualine.get_config() or {}),
    }
end

---@param enabled boolean
---@return boolean
function M.ensure_terminal_disabled(enabled)
    if not enabled then
        return false
    end

    local state = lualine_config()
    if not state then
        return false
    end

    local config = state.config
    config.options = config.options or {}
    local disabled = vim.deepcopy(config.options.disabled_filetypes or {})

    local changed = append_terminal_filetype(TERMINAL_FILETYPE, disabled, DISABLED_FILETYPE_SECTIONS)
    if not changed then
        return false
    end

    config.options.disabled_filetypes = disabled
    state.api.setup(config)
    return true
end

return M
