---@class Clodex.StatePreview.Config.Mini
---@field width integer
---@field height integer
---@field col integer
---@field winblend integer

---@class Clodex.StatePreview.Config
---@field min_width integer
---@field max_width integer
---@field max_height integer # Non-positive values mean "use full available height".
---@field row integer
---@field col integer
---@field winblend integer
---@field mini Clodex.StatePreview.Config.Mini

local M = {}

---@type Clodex.StatePreview.Config
local DEFAULTS = {
    min_width = 36,
    max_width = 72,
    max_height = 0,
    row = 1,
    col = 2,
    winblend = 18,
    mini = {
        width = 42,
        height = 11,
        col = 2,
        winblend = 0,
    },
}

---@return Clodex.StatePreview.Config
function M.defaults()
    return vim.deepcopy(DEFAULTS)
end

return M
