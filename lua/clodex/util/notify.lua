local M = {}

---@param message string
---@return { title: string, body: string, ft: string }
local function split_message(message)
    local text = vim.trim(message or "")
    if text == "" then
        return {
            title = "clodex.nvim",
            body = "",
            ft = "text",
        }
    end

    return {
        title = "clodex.nvim",
        body = text,
        ft = "text",
    }
end

--- Sends a plugin-scoped notification at a chosen severity level.
---@param message string
---@param level? integer
function M.notify(message, level)
    local parts = split_message(message)
    vim.notify(parts.body, level or vim.log.levels.INFO, {
        title = parts.title,
        ft = parts.ft,
    })
end

--- Sends an error-level notification with Codex CLI title.
---@param message string
function M.error(message)
    M.notify(message, vim.log.levels.ERROR)
end

--- Sends a warning-level notification with Codex CLI title.
---@param message string
function M.warn(message)
    M.notify(message, vim.log.levels.WARN)
end

return M
