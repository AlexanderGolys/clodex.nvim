local fs = require("clodex.util.fs")
local History = require("clodex.history")
local notify = require("clodex.util.notify")

local TITLE_TRUNCATION_SUFFIX = "[...]"

---@class Clodex.TerminalSession
---@field key string
---@field kind 'project'|'free'
---@field cwd string
---@field title string
---@field cmd string[]
---@field env? table<string, string>
---@field runtime_key? string
---@field terminal_provider "snacks"|"term"
---@field project_root? string
---@field header_enabled boolean
---@field buf? number
---@field job_id? integer
---@field suppress_exit_warning boolean
---@field archived_line_count integer
---@field awaiting_response boolean
---@field active_prompt_title? string
---@field active_prompt_kind? string
---@field active_prompt_authoritative? boolean
---@field active_queue_item_title? string Compatibility with state snapshots produced by queue-aware tests.
---@field prompt_skill_name string
local Session = {}
Session.__index = Session

---@class Clodex.TerminalSession.Spec
---@field key string
---@field kind 'project'|'free'
---@field cwd string
---@field title string
---@field cmd string[]
---@field env? table<string, string>
---@field runtime_key? string
---@field terminal_provider? "snacks"|"term"
---@field project_root? string
---@field header_enabled? boolean
---@field prompt_skill_name? string

---@class Clodex.TerminalSession.Snapshot
---@field key string
---@field kind? 'project'|'free'
---@field cwd? string
---@field title? string
---@field project_root? string
---@field buf? integer
---@field buffer_valid boolean
---@field job_id? integer
---@field running boolean
---@field waiting_state? "question"|"permission"
---@field last_cli_line? string
---@field terminal_provider "snacks"|"term"
---@field env_keys? string[]
---@field active_prompt_title? string
---@field active_prompt_kind? string
---@field active_prompt_authoritative? boolean


local Snacks = {
    terminal = require("snacks.terminal"),
}

---@param provider string?
---@return "snacks"|"term"
local function normalize_terminal_provider(provider)
    if provider == "term" then
        return "term"
    end
    return "snacks"
end

---@param cmd string[]
---@param opts { cwd?: string, env?: table<string, string> }
---@param buf number
---@return snacks.win
local function start_with_snacks(cmd, opts, buf)
    local terminal = Snacks.terminal.open(cmd, {
        cwd = opts.cwd,
        env = opts.env,
        interactive = true,
        win = {
            buf = buf,
            enter = false,
            bo = {
                filetype = "clodex_terminal"
            }
        }
    })
    if terminal and terminal.hide then
        terminal:hide()
    end
    return terminal
end

---@param cmd string[]
---@param opts { cwd?: string, env?: table<string, string> }
---@param buf number
---@return boolean, integer?
local function start_with_term(cmd, opts, buf)
    local job_id
    local ok = pcall(vim.api.nvim_buf_call, buf, function()
        job_id = vim.fn.termopen(cmd, {
            cwd = opts.cwd,
            env = opts.env,
        })
    end)
    if not ok or type(job_id) ~= "number" or job_id <= 0 then
        return false, nil
    end
    return true, job_id
end

---@param buf integer
---@return integer?
local function terminal_job_id(buf)
    local ok, job_id = pcall(vim.api.nvim_buf_get_var, buf, "terminal_job_id")
    if ok and type(job_id) == "number" and job_id > 0 then
        return job_id
    end
end

---@param self Clodex.TerminalSession
---@return integer?
local function current_running_job(self)
    if self.job_id and vim.fn.jobwait({ self.job_id }, 0)[1] == -1 then
        return self.job_id
    end

    if not self:buf_valid() then
        return nil
    end

    local job_id = terminal_job_id(self.buf)
    if job_id and vim.fn.jobwait({ job_id }, 0)[1] == -1 then
        return job_id
    end
end

---@param session Clodex.TerminalSession
---@return string
local function window_title_text(session)
    if session.active_prompt_title and session.active_prompt_title ~= "" then
        return ("%s - %s"):format(session.title, session.active_prompt_title)
    end
    return session.title
end

---@param session Clodex.TerminalSession
local function sync_terminal_title(session)
    if session.buf ~= nil and vim.api.nvim_buf_is_valid(session.buf) then
        vim.b[session.buf].term_title = window_title_text(session)
    end
end

---@param session Clodex.TerminalSession
local function clear_non_authoritative_prompt(session)
    if session.active_prompt_authoritative then
        return
    end
    session.active_prompt_title = nil
    session.active_prompt_kind = nil
    sync_terminal_title(session)
end

---@param cmd string[]
---@param opts { cwd?: string, env?: table<string, string> }
---@param buf number
---@return boolean, integer?
local function start_terminal_for_provider(cmd, opts, buf, provider)
    if provider == "term" then
        return start_with_term(cmd, opts, buf)
    end

    local ok, terminal = pcall(start_with_snacks, cmd, opts, buf)
    local job_id = ok and terminal_job_id(buf) or nil
    local started = ok and terminal ~= nil and type(job_id) == "number" and job_id > 0
    return started, job_id
end

---@param self Clodex.TerminalSession
---@return boolean
local function is_opencode_backend(self)
    if type(self.cmd) ~= "table" then
        return false
    end
    for _, arg in ipairs(self.cmd) do
        if type(arg) == "string" and arg:match("opencode") then
            return true
        end
    end
    return false
end

---@param text string
---@return string
local function bracketed_paste(text)
    return ("\027[200~%s\027[201~"):format(text)
end

local function normalize_prompt_text(self, text)
    local normalized = text:gsub("\r\n", "\n"):gsub("\r", "\n")
    if is_opencode_backend(self) then
        return normalized
    end
    return bracketed_paste(normalized)
end

---@param self Clodex.TerminalSession
---@param payload string
---@param error_message string
---@return boolean
local function send_terminal_payload(self, payload, error_message)
    if not self:ensure_started() or not self.job_id then
        return false
    end

    local ok = pcall(vim.fn.chansend, self.job_id, payload)
    if not ok then
        notify.error(error_message:format(self.cwd))
        return false
    end
    return true
end

---@param self Clodex.TerminalSession
local function submit_terminal_input(self)
    vim.defer_fn(function()
        if self.job_id then
            pcall(vim.fn.chansend, self.job_id, "\r")
        end
    end, 40)
end

---@param self Clodex.TerminalSession
local function attach_termclose_handler(self)
    vim.api.nvim_create_autocmd("TermClose", {
        buffer = self.buf,
        callback = function()
            self.job_id = nil
            self.awaiting_response = false
            local suppress_warning = self.suppress_exit_warning
            self.suppress_exit_warning = false
            local code = type(vim.v.event) == "table" and vim.v.event.status or 0
            if code ~= 0 and not suppress_warning then
                notify.warn(("Codex session exited with code %d at %s"):format(code, self.cwd))
            end
        end
    })
end

---@param text string
---@return string
local function statusline_escape(text)
    return ((text or ""):gsub("%%", "%%%%"))
end

---@param text string
---@param max_width? integer
---@return string
local function truncate_title(text, max_width)
    max_width = tonumber(max_width)
    if not max_width or max_width <= 0 or vim.fn.strdisplaywidth(text) <= max_width then
        return text
    end

    local suffix_width = vim.fn.strdisplaywidth(TITLE_TRUNCATION_SUFFIX)
    if max_width <= suffix_width then
        return TITLE_TRUNCATION_SUFFIX
    end

    local target_width = max_width - suffix_width
    local parts = {} ---@type string[]
    local width = 0
    local chars = vim.fn.strchars(text)
    for index = 0, chars - 1 do
        local char = vim.fn.strcharpart(text, index, 1)
        local char_width = vim.fn.strdisplaywidth(char)
        if width + char_width > target_width then
            break
        end
        parts[#parts + 1] = char
        width = width + char_width
    end

    return table.concat(parts) .. TITLE_TRUNCATION_SUFFIX
end

---@param spec Clodex.TerminalSession.Spec
---@return Clodex.TerminalSession
function Session.new(spec)
    spec = vim.deepcopy(spec)
    if spec.header_enabled == nil then
        spec.header_enabled = spec.kind == "free"
    end
    spec.terminal_provider = normalize_terminal_provider(spec.terminal_provider)
    spec.suppress_exit_warning = false
    spec.archived_line_count = 0
    spec.awaiting_response = false
    spec.prompt_skill_name = vim.trim(spec.prompt_skill_name or "prompt-nvim-clodex")
    return setmetatable(spec, Session)
end

---@param line string
---@return boolean
local function is_idle_line(line)
    line = vim.trim((line or ""):lower())
    if line == "" then
        return false
    end

    if line:find("per the queued-work contract", 1, true) and line:find("close response", 1, true) then
        return true
    end

    if line:find("ready", 1, true) then
        return true
    end

    if line:match("^[>%$#:]%s*$") then
        return true
    end

    if line:match("[%>%$#:]%s*$") and not line:find("error", 1, true) then
        return true
    end

    return false
end

---@return string
local function last_nonempty_line(buf)
    if buf == nil or not vim.api.nvim_buf_is_valid(buf) then
        return ""
    end

    local line_count = vim.api.nvim_buf_line_count(buf)
    for index = line_count - 1, 0, -1 do
        local line = vim.api.nvim_buf_get_lines(buf, index, index + 1, false)[1] or ""
        if vim.trim(line) ~= "" then
            return line
        end
    end

    return ""
end

local USER_WAIT_REASON_PATTERNS = {
    permission = {
        "permission",
        "approve",
        "approval",
        "allow",
        "yes/no",
        "grant access",
    },
    question = {
        "please provide",
        "let me know",
        "which ",
        "what ",
        "where ",
        "when ",
        "could you",
        "can you",
        "do you want",
        "would you like",
    },
}

local WAIT_SCAN_LIMIT = 24

---@param buf integer?
---@return string[]
local function recent_nonempty_lines(buf)
    if buf == nil or not vim.api.nvim_buf_is_valid(buf) then
        return {}
    end

    local line_count = vim.api.nvim_buf_line_count(buf)
    if line_count <= 0 then
        return {}
    end

    local start = math.max(line_count - WAIT_SCAN_LIMIT, 0)
    local lines = vim.api.nvim_buf_get_lines(buf, start, line_count, false)
    local recent = {}
    for _, line in ipairs(lines) do
        local trimmed = vim.trim(line)
        if trimmed ~= "" then
            recent[#recent + 1] = trimmed
        end
    end
    return recent
end

---@param lines string[]
---@return "question"|"permission"?
local function detect_waiting_state(lines)
    for index = #lines, 1, -1 do
        local line = lines[index]:lower()
        for _, pattern in ipairs(USER_WAIT_REASON_PATTERNS.permission) do
            if line:find(pattern, 1, true) then
                return "permission"
            end
        end
        if line:sub(-1) == "?" then
            return "question"
        end
        for _, pattern in ipairs(USER_WAIT_REASON_PATTERNS.question) do
            if line:find(pattern, 1, true) then
                return "question"
            end
        end
    end
end

---@return string
function Session:history_project_label()
    if self.kind == "project" then
        local project_label = self.title:gsub("^Clodex:%s*", "")
        return project_label
    end
    return self.cwd
end

---@return string[]
function Session:unarchived_lines()
    if not self:buf_valid() then
        return {}
    end

    local line_count = vim.api.nvim_buf_line_count(self.buf)
    if line_count <= self.archived_line_count then
        return {}
    end

    local lines = vim.api.nvim_buf_get_lines(self.buf, self.archived_line_count, line_count, false)
    while #lines > 0 and vim.trim(lines[1]) == "" do
        table.remove(lines, 1)
    end
    while #lines > 0 and vim.trim(lines[#lines]) == "" do
        table.remove(lines, #lines)
    end
    return lines
end

function Session:archive_history_chunk()
    local lines = self:unarchived_lines()
    if #lines == 0 then
        if self:buf_valid() then
            self.archived_line_count = vim.api.nvim_buf_line_count(self.buf)
        end
        return
    end

    History.append_conversation(self:history_project_label(), lines)
    if self:buf_valid() then
        self.archived_line_count = vim.api.nvim_buf_line_count(self.buf)
    end
end

--- Returns the title line shown in the terminal header when enabled.
--- The header is reused by free and project sessions to identify context at a glance.
--- It is included in terminal UI rendering and refreshed whenever session state changes.
function Session:header_text()
    if self.kind == "free" then
        return ("[Codex CLI] %s"):format(self.cwd)
    end
    return ("[Codex CLI] %s"):format(self.title)
end

---@class Clodex.TerminalSession.ActivePromptOpts
---@field authoritative? boolean

---@param title? string
---@param kind? string
---@param opts? Clodex.TerminalSession.ActivePromptOpts
function Session:set_active_prompt_title(title, kind, opts)
    title = vim.trim(title or "")
    self.active_prompt_title = title ~= "" and title or nil
    self.active_prompt_kind = self.active_prompt_title and kind or nil
    self.active_prompt_authoritative = self.active_prompt_title and opts and opts.authoritative == true or nil
    sync_terminal_title(self)
end

--- Toggles whether the header row is shown in the terminal buffer.
--- The new setting is applied immediately and persisted for the session lifecycle.
--- Callers use this for user-facing header visibility toggles.
function Session:toggle_header()
    self.header_enabled = not self.header_enabled
    return self.header_enabled
end

---@param max_width? integer
---@return string
function Session:winbar_text(max_width)
    local active_prompt_title = self.active_prompt_title
    if active_prompt_title and not self.active_prompt_authoritative and not self:is_working() then
        active_prompt_title = nil
    end
    if not self.header_enabled and not active_prompt_title then
        return ""
    end
    local header = self.header_enabled and self:header_text() or ""
    if active_prompt_title then
        header = header ~= "" and ("%s - %s"):format(header, active_prompt_title) or active_prompt_title
    end
    if max_width then
        header = truncate_title(header, math.max(max_width - 2, 1))
    end
    return (" %s "):format(statusline_escape(header))
end

---@return string
function Session:last_cli_line()
    if not self:buf_valid() then
        return ""
    end
    return vim.trim(last_nonempty_line(self.buf))
end

---@param win integer
---@return boolean
function Session:window_shows_bottom(win)
    if not self:buf_valid() or not vim.api.nvim_win_is_valid(win) then
        return true
    end
    local line_count = vim.api.nvim_buf_line_count(self.buf)
    if line_count <= 0 then
        return true
    end
    local info = vim.fn.getwininfo(win)[1]
    return not not (info and info.botline and info.botline >= line_count)
end

---@param win integer
---@return string
function Session:statusline_text(win)
    if self:window_shows_bottom(win) then
        return ""
    end
    return self:statusline_line_text()
end

---@return string
function Session:statusline_line_text()
    local line = self:last_cli_line()
    if line == "" then
        return ""
    end
    return (" %s "):format(statusline_escape(line))
end

---@return boolean
function Session:buf_valid()
    return self.buf ~= nil and vim.api.nvim_buf_is_valid(self.buf)
end

--- Checks a running condition for terminal session.
--- This gate keeps callers safe before continuing higher-level state transitions.
---@return boolean
function Session:is_running()
    local job_id = current_running_job(self)
    if not job_id then
        self.job_id = nil
        return false
    end

    self.job_id = job_id
    return true
end

---@return boolean
function Session:is_working()
    if not self:is_running() then
        self.awaiting_response = false
        clear_non_authoritative_prompt(self)
        return false
    end

    local line = self:last_cli_line()
    if is_idle_line(line) then
        self.awaiting_response = false
        clear_non_authoritative_prompt(self)
        return false
    end

    return self.awaiting_response or line ~= ""
end

---@return "question"|"permission"?
function Session:waiting_state()
    if not self:is_running() then
        return nil
    end
    if self.awaiting_response then
        return nil
    end
    if is_idle_line(self:last_cli_line()) then
        return detect_waiting_state(recent_nonempty_lines(self.buf))
    end
end

function Session:update_buffer_state()
    if not self:buf_valid() then
        return
    end

    vim.bo[self.buf].bufhidden = "hide"
    vim.bo[self.buf].swapfile = false
    vim.bo[self.buf].filetype = "clodex_terminal"
    vim.b[self.buf].clodex = {
        key = self.key,
        kind = self.kind,
        cwd = self.cwd,
        project_root = self.project_root,
    }
    -- Keep Neovim's terminal title metadata aligned with the visible Clodex title.
    -- Snacks and user statusline/winbar setups may read `b:term_title` for inactive terminals.
    sync_terminal_title(self)
    vim.keymap.set("n", "<localleader>h", "<Cmd>Clodex header<CR>", {
        buffer = self.buf,
        silent = true,
    })
    vim.keymap.set("t", "<localleader>h", "<C-\\><C-n><Cmd>Clodex header<CR>i", {
        buffer = self.buf,
        silent = true,
    })
    vim.keymap.set("n", "<localleader>s", function()
        if self:insert_prompt_skill() then
            vim.cmd.startinsert()
        end
    end, {
        buffer = self.buf,
        desc = "Clodex: Insert prompt skill",
        silent = true,
    })
    vim.keymap.set("t", "<localleader>s", function()
        self:insert_prompt_skill()
    end, {
        buffer = self.buf,
        desc = "Clodex: Insert prompt skill",
        silent = true,
    })
end

--- Starts the terminal if needed and initializes buffer state.
--- This is the main readiness gate used before any prompt is sent to a session.
---@return boolean
function Session:ensure_started()
    if self:buf_valid() and self:is_running() then
        self:update_buffer_state()
        return true
    end

    if not fs.is_dir(self.cwd) then
        self.job_id = nil
        if self:buf_valid() then
            pcall(vim.api.nvim_buf_delete, self.buf, { force = true })
        end
        self.buf = nil
        notify.error(("Codex session directory does not exist: %s"):format(self.cwd))
        return false
    end

    if self:buf_valid() then
        pcall(vim.api.nvim_buf_delete, self.buf, { force = true })
    end

    self.buf = vim.api.nvim_create_buf(false, true)
    self.archived_line_count = 0
    self:update_buffer_state()

    local started, job_id = start_terminal_for_provider(self.cmd, {
        cwd = self.cwd,
        env = self.env,
    }, self.buf, self.terminal_provider)
    if not started or type(job_id) ~= "number" or job_id <= 0 then
        self.job_id = nil
        if self:buf_valid() then
            pcall(vim.api.nvim_buf_delete, self.buf, { force = true })
        end
        self.buf = nil
        notify.error(("Failed to start Codex session in %s"):format(self.cwd))
        return false
    end

    self.job_id = job_id
    attach_termclose_handler(self)
    self:update_buffer_state()
    return true
end

--- Stops any running process and deletes terminal buffer state.
--- It is called during project shutdown and when switching away from removed sessions.
function Session:destroy()
    self:archive_history_chunk()
    if self:is_running() then
        self.suppress_exit_warning = true
        pcall(vim.fn.jobstop, self.job_id)
    end
    self.job_id = nil

    if self:buf_valid() then
        pcall(vim.api.nvim_buf_delete, self.buf, { force = true })
    end
    self.buf = nil
end

---@param text string
---@return boolean
function Session:send(text)
    text = vim.trim(text or "")
    if text == "" then
        return false
    end
    return send_terminal_payload(self, text .. "\n", "Failed to send prompt to Codex session at %s")
end

---@return boolean
function Session:insert_prompt_skill()
    local skill_name = vim.trim(self.prompt_skill_name or "")
    if skill_name == "" then
        return false
    end
    if not send_terminal_payload(self, ("$%s"):format(skill_name), "Failed to insert prompt skill into session at %s") then
        return false
    end
    self.awaiting_response = true
    submit_terminal_input(self)
    return true
end

---@param text string
---@return string
---@param text string
---@return boolean
function Session:dispatch_prompt(text)
    text = vim.trim(text or "")
    if text == "" then
        return false
    end
    local normalized = normalize_prompt_text(self, text)
    if not send_terminal_payload(self, normalized, "Failed to send prompt to session at %s") then
        return false
    end

    self.awaiting_response = true

    submit_terminal_input(self)
    return true
end

---@param spec Clodex.TerminalSession.Spec
function Session:update_identity(spec)
    self.key = spec.key
    self.kind = spec.kind
    self.cwd = spec.cwd
    self.title = spec.title
    self.cmd = vim.deepcopy(spec.cmd)
    self.env = spec.env and vim.deepcopy(spec.env) or nil
    self.runtime_key = spec.runtime_key
    self.terminal_provider = normalize_terminal_provider(spec.terminal_provider)
    self.project_root = spec.project_root
    self.prompt_skill_name = vim.trim(spec.prompt_skill_name or "prompt-nvim-clodex")
    if spec.header_enabled ~= nil then
        self.header_enabled = spec.header_enabled
    end
    if spec.suppress_exit_warning ~= nil then
        self.suppress_exit_warning = spec.suppress_exit_warning
    end
    self:update_buffer_state()
end

---@return Clodex.TerminalSession.Snapshot
function Session:snapshot()
    local buffer_valid = self:buf_valid()
    local env_keys = {} ---@type string[]
    local last_line = self:last_cli_line()
    for key in pairs(self.env or {}) do
        env_keys[#env_keys + 1] = key
    end
    table.sort(env_keys)
    return {
        key = self.key,
        kind = self.kind,
        cwd = self.cwd,
        title = self.title,
        project_root = self.project_root,
        buf = self.buf,
        buffer_valid = buffer_valid,
        job_id = self.job_id,
        running = self:is_running(),
        waiting_state = self:waiting_state(),
        last_cli_line = last_line,
        terminal_provider = self.terminal_provider,
        env_keys = env_keys,
        active_prompt_title = self.active_prompt_title,
        active_prompt_kind = self.active_prompt_kind,
        active_prompt_authoritative = self.active_prompt_authoritative,
    }
end

return Session
