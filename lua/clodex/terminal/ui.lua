local M = {}

local Backend = require("clodex.backend")
local Prompt = require("clodex.prompt")

local STATUSLINE_EXPR = "%!v:lua.require('clodex.terminal.ui').statusline()"
local WINBAR_EXPR = "%!v:lua.require('clodex.terminal.ui').winbar()"

local STATUSLINE_HL_PREFIX = "ClodexTerminalStatuslineDyn"
local TITLE_HL_PREFIX = "ClodexTerminalTitleDyn"
local WINDOW_HL_PREFIX = "ClodexTerminalWindowDyn"
local TITLE_FG = "#00AA00"
local TERMINAL_FILETYPE = "clodex_terminal"

local STATUSLINE_HL_PREFIXES = {
    STATUSLINE_HL_PREFIX,
    TITLE_HL_PREFIX,
    WINDOW_HL_PREFIX,
}

---@param buf integer
---@param name string
---@return string?
local function buffer_color(buf, name)
    local ok, value = pcall(vim.api.nvim_buf_get_var, buf, name)
    if not ok or type(value) ~= "string" or value == "" then
        return nil
    end
    if value:match("^#%x%x%x%x%x%x$") then
        return value:upper()
    end
end

---@param group string
---@param attr "fg"|"bg"
---@return string?
local function highlight_hex(group, attr)
    local ok, hl = pcall(vim.api.nvim_get_hl, 0, { name = group, link = false })
    if not ok or type(hl) ~= "table" or type(hl[attr]) ~= "number" then
        return nil
    end
    return string.format("#%06X", hl[attr])
end

local function terminal_background(buf)
    return highlight_hex("StatusLine", "bg")
        or buffer_color(buf, "terminal_color_background")
        or buffer_color(buf, "terminal_color_0")
        or highlight_hex("Normal", "bg")
end

---@param buf integer
---@return string?
local function terminal_window_fg(buf)
    return buffer_color(buf, "terminal_color_foreground")
        or highlight_hex("Normal", "fg")
end

---@param buf integer
---@return string?
local function terminal_statusline_fg(buf)
    return buffer_color(buf, "terminal_color_foreground")
        or highlight_hex("ClodexTerminalStatusline", "fg")
        or highlight_hex("Normal", "fg")
end

---@param session? Clodex.TerminalSession
---@return string
local function terminal_title_fg(session)
    local kind = session and session.active_prompt_kind or nil
    if kind and Prompt.categories.is_valid(kind) then
        return highlight_hex(Prompt.title_group(kind), "fg") or TITLE_FG
    end
    return TITLE_FG
end

---@param value string
---@return string
local function color_key(value)
    local key = value:gsub("#", "")
    return key
end

---@param win integer
---@param session? Clodex.TerminalSession
---@return string, string, string?, string, string
local function ensure_terminal_highlights(win, session)
    local buf = vim.api.nvim_win_get_buf(win)
    local bg = terminal_background(buf)
    local fg = terminal_statusline_fg(buf)
    local title_fg = terminal_title_fg(session)
    if not bg or not fg then
        return "ClodexTerminalStatuslineActive", "ClodexTerminalStatusline", nil, "DiagnosticOk", "DiagnosticOk"
    end

    local suffix = color_key(bg) .. "_" .. color_key(fg)
    local active = STATUSLINE_HL_PREFIX .. "Active_" .. suffix
    local inactive = STATUSLINE_HL_PREFIX .. "Inactive_" .. suffix
    vim.api.nvim_set_hl(0, inactive, { fg = fg, bg = bg })
    vim.api.nvim_set_hl(0, active, { fg = fg, bg = bg, bold = true })

    local title_suffix = color_key(bg) .. "_" .. color_key(title_fg)
    local title_active = TITLE_HL_PREFIX .. "Active_" .. title_suffix
    local title_inactive = TITLE_HL_PREFIX .. "Inactive_" .. title_suffix
    vim.api.nvim_set_hl(0, title_inactive, { fg = title_fg, bg = bg })
    vim.api.nvim_set_hl(0, title_active, { fg = title_fg, bg = bg, bold = true })

    local window_bg = terminal_background(buf)
    local window_fg = terminal_window_fg(buf)
    if not window_bg or not window_fg then
        return active, inactive, nil, title_active, title_inactive
    end
    local window = WINDOW_HL_PREFIX .. "_" .. color_key(window_bg) .. "_" .. color_key(window_fg)
    vim.api.nvim_set_hl(0, window, { fg = window_fg, bg = window_bg })
    return active, inactive, window, title_active, title_inactive
end

---@return Clodex.App?
local function clodex_instance()
    local ok, app = pcall(require, "clodex.app")
    if not ok then
        return nil
    end
    if not app or type(app.instance) ~= "function" then
        return nil
    end
    return app.instance()
end

---@param win? integer
---@return Clodex.TerminalSession?
local function current_session(win)
    local instance = clodex_instance()
    if not instance or not instance.terminals then
        return nil
    end

    local target = win
    if type(target) ~= "number" or not vim.api.nvim_win_is_valid(target) then
        target = vim.api.nvim_get_current_win()
    end
    return instance.terminals:session_by_buf(vim.api.nvim_win_get_buf(target))
end

---@return boolean
local function use_clodex_terminal_chrome()
    local instance = clodex_instance()
    if not instance or not instance.config then
        return true
    end

    local config = instance.config:get()
    return Backend.normalize(config.backend) == "codex"
        and (not config.terminal or config.terminal.prefer_native_statusline ~= false)
end

---@return integer?
local function current_window()
    local win = vim.api.nvim_get_current_win()
    return vim.api.nvim_win_is_valid(win) and win or nil
end

---@return integer?
local function evaluated_window()
    local win = tonumber(vim.g.statusline_winid)
    if win and vim.api.nvim_win_is_valid(win) then
        return win
    end
    return current_window()
end

---@param win integer
---@return boolean
local function clodex_terminal_window(win)
    return type(win) == "number"
        and vim.api.nvim_win_is_valid(win)
        and vim.bo[vim.api.nvim_win_get_buf(win)].filetype == TERMINAL_FILETYPE
end

---@param win integer
---@param name string
---@return string
local function win_option(win, name)
    return vim.api.nvim_get_option_value(name, { scope = "local", win = win }) or ""
end

---@param win integer
---@param name string
---@param value string
local function set_win_option(win, name, value)
    vim.api.nvim_set_option_value(name, value, { scope = "local", win = win })
end

---@param win? integer
---@return integer|nil
local function resolve_window(win)
    if type(win) == "number" and vim.api.nvim_win_is_valid(win) then
        return win
    end
    return current_window()
end

---@param win integer
local function clear_window_chrome(win)
    if not vim.api.nvim_win_is_valid(win) then
        return
    end

    if win_option(win, "statusline") == STATUSLINE_EXPR then
        set_win_option(win, "statusline", "")
    end
    if win_option(win, "winbar") == WINBAR_EXPR then
        set_win_option(win, "winbar", "")
    end

    local winhl = win_option(win, "winhl")
    for _, prefix in ipairs(STATUSLINE_HL_PREFIXES) do
        if winhl:find(prefix, 1, true) ~= nil then
            set_win_option(win, "winhl", "")
            return
        end
    end
end

---@param win integer
local function apply_terminal_window_highlights(win)
    local active, inactive, window, title_active, title_inactive = ensure_terminal_highlights(win, current_session(win))
    local highlights = {
        "StatusLine:" .. active,
        "StatusLineNC:" .. inactive,
        "WinBar:" .. title_active,
        "WinBarNC:" .. title_inactive,
    }
    if window then
        highlights[#highlights + 1] = "Normal:" .. window
        highlights[#highlights + 1] = "NormalFloat:" .. window
        highlights[#highlights + 1] = "EndOfBuffer:" .. window
    end
    vim.wo[win].winhl = table.concat(highlights, ",")
end

---@param win? integer
function M.apply_window(win)
    local target = resolve_window(win)
    if not target then
        return
    end

    if not clodex_terminal_window(target) then
        clear_window_chrome(target)
        return
    end

    if not use_clodex_terminal_chrome() then
        clear_window_chrome(target)
        return
    end

    set_win_option(target, "statusline", STATUSLINE_EXPR)
    set_win_option(target, "winbar", WINBAR_EXPR)
    apply_terminal_window_highlights(target)
end

---@param win? integer
---@return string
function M.statusline(win)
    local target = type(win) == "number" and win or evaluated_window()
    if not target then
        return ""
    end

    local session = current_session(target)
    if not session then
        return ""
    end
    return session:statusline_text(target)
end

---@param win? integer
---@return string
function M.winbar(win)
    local target = type(win) == "number" and win or evaluated_window()
    local session = current_session(target)
    if not session then
        return ""
    end
    local width = target and vim.api.nvim_win_is_valid(target) and vim.api.nvim_win_get_width(target) or nil
    return session:winbar_text(width)
end

---@param win? integer
function M.refresh_chrome(win)
    M.apply_window(resolve_window(win))
end

function M.refresh_all_chrome()
    for _, win in ipairs(vim.api.nvim_list_wins()) do
        M.apply_window(win)
    end
    vim.schedule(function()
        for _, win in ipairs(vim.api.nvim_list_wins()) do
            M.apply_window(win)
        end
    end)
end

return M
