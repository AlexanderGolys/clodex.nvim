package.loaded["snacks.terminal"] = {
    open = function()
        return {
            hide = function() end,
        }
    end,
}

local Session = require("clodex.terminal.session")
local TerminalUi = require("clodex.terminal.ui")

local function buffer_map(buf, mode, lhs)
    local resolved_lhs = vim.api.nvim_replace_termcodes(lhs, true, true, true)
    for _, map in ipairs(vim.api.nvim_buf_get_keymap(buf, mode)) do
        if map.lhs == lhs or map.lhs == resolved_lhs then
            return map
        end
    end
end

describe("clodex.terminal.session", function()
    it("keeps the active-window statusline visible when the last line is visible", function()
        local buf = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
            "older output",
            "Codex ready",
        })

        local session = Session.new({
            key = "project:/tmp/demo",
            kind = "project",
            cwd = "/tmp/demo",
            title = "Clodex: Demo",
            cmd = { "codex" },
        })
        session.buf = buf

        vim.api.nvim_set_current_buf(buf)

        assert.are.equal(" Codex ready ", session:statusline_text(vim.api.nvim_get_current_win()))
    end)

    it("keeps the inactive-window statusline text identical to the active line text", function()
        local current_win = vim.api.nvim_get_current_win()
        local inactive_buf = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_buf_set_lines(inactive_buf, 0, -1, false, {
            "older output",
            "Codex ready",
        })

        local session = Session.new({
            key = "project:/tmp/demo",
            kind = "project",
            cwd = "/tmp/demo",
            title = "Clodex: Demo",
            cmd = { "codex" },
        })
        session.buf = inactive_buf

        vim.cmd("vsplit")
        local inactive_win = vim.api.nvim_get_current_win()
        vim.api.nvim_win_set_buf(inactive_win, inactive_buf)
        vim.api.nvim_win_set_height(inactive_win, 1)
        vim.api.nvim_set_current_win(current_win)

        assert.are.equal(" Codex ready ", session:statusline_text(inactive_win))
        assert.are.equal(session:statusline_line_text(), session:statusline_text(inactive_win))

        vim.api.nvim_win_close(inactive_win, true)
    end)

    it("keeps the inactive-window statusline visible when that window already shows the latest line", function()
        local current_win = vim.api.nvim_get_current_win()
        local inactive_buf = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_buf_set_lines(inactive_buf, 0, -1, false, {
            "older output",
            "Codex ready",
        })

        local session = Session.new({
            key = "project:/tmp/demo",
            kind = "project",
            cwd = "/tmp/demo",
            title = "Clodex: Demo",
            cmd = { "codex" },
        })
        session.buf = inactive_buf

        vim.cmd("vsplit")
        local inactive_win = vim.api.nvim_get_current_win()
        vim.api.nvim_win_set_buf(inactive_win, inactive_buf)
        vim.api.nvim_win_set_height(inactive_win, 10)
        vim.api.nvim_set_current_win(current_win)

        assert.are.equal(" Codex ready ", session:statusline_text(inactive_win))

        vim.api.nvim_win_close(inactive_win, true)
    end)

    it("treats a ready prompt as not working", function()
        local buf = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
            "older output",
            "Codex ready",
        })

        local session = Session.new({
            key = "project:/tmp/demo",
            kind = "project",
            cwd = "/tmp/demo",
            title = "Clodex: Demo",
            cmd = { "codex" },
        })
        session.buf = buf
        session.job_id = 123
        session.awaiting_response = true

        local original_jobwait = vim.fn.jobwait
        vim.fn.jobwait = function()
            return { -1 }
        end

        assert.is_false(session:is_working())
        assert.is_false(session.awaiting_response)

        vim.fn.jobwait = original_jobwait
    end)

    it("treats close-only contract responses as not working", function()
        local buf = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
            "Per the queued-work contract, I'm stopping after this close response.",
        })

        local session = Session.new({
            key = "project:/tmp/demo",
            kind = "project",
            cwd = "/tmp/demo",
            title = "Clodex: Demo",
            cmd = { "codex" },
        })
        session.buf = buf
        session.job_id = 123
        session.awaiting_response = true

        local original_jobwait = vim.fn.jobwait
        vim.fn.jobwait = function()
            return { -1 }
        end

        assert.is_false(session:is_working())
        assert.is_false(session.awaiting_response)

        vim.fn.jobwait = original_jobwait
    end)

    it("treats close-only contract wording variants as not working", function()
        local buf = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
            "Queued-work contract: stop after close response.",
        })

        local session = Session.new({
            key = "project:/tmp/demo",
            kind = "project",
            cwd = "/tmp/demo",
            title = "Clodex: Demo",
            cmd = { "codex" },
        })
        session.buf = buf
        session.job_id = 123
        session.awaiting_response = true

        local original_jobwait = vim.fn.jobwait
        vim.fn.jobwait = function()
            return { -1 }
        end

        assert.is_false(session:is_working())
        assert.is_false(session.awaiting_response)

        vim.fn.jobwait = original_jobwait
    end)

    it("treats non-ready output after dispatch as working", function()
        local buf = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
            "Thinking...",
        })

        local session = Session.new({
            key = "project:/tmp/demo",
            kind = "project",
            cwd = "/tmp/demo",
            title = "Clodex: Demo",
            cmd = { "codex" },
        })
        session.buf = buf
        session.job_id = 123
        session.awaiting_response = true

        local original_jobwait = vim.fn.jobwait
        vim.fn.jobwait = function()
            return { -1 }
        end

        assert.is_true(session:is_working())

        vim.fn.jobwait = original_jobwait
    end)

    it("recovers a running terminal job from the session buffer", function()
        local buf = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_buf_set_var(buf, "terminal_job_id", 321)

        local session = Session.new({
            key = "project:/tmp/demo",
            kind = "project",
            cwd = "/tmp/demo",
            title = "Clodex: Demo",
            cmd = { "codex" },
        })
        session.buf = buf

        local waited_job_id
        local original_jobwait = vim.fn.jobwait
        vim.fn.jobwait = function(job_ids)
            waited_job_id = job_ids[1]
            return { -1 }
        end

        assert.is_true(session:is_running())
        assert.are.equal(321, session.job_id)
        assert.are.equal(321, waited_job_id)

        vim.fn.jobwait = original_jobwait
    end)

    it("shows the active prompt title in the winbar only while working", function()
        local buf = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
            "Thinking...",
        })

        local session = Session.new({
            key = "project:/tmp/demo",
            kind = "project",
            cwd = "/tmp/demo",
            title = "Clodex: Demo",
            cmd = { "codex" },
        })
        session.buf = buf
        session.job_id = 123
        session.awaiting_response = true
        session:update_buffer_state()
        session:set_active_prompt_title("Fix queue dispatch")

        local original_jobwait = vim.fn.jobwait
        vim.fn.jobwait = function()
            return { -1 }
        end

        assert.are.equal(" Fix queue dispatch ", session:winbar_text())
        assert.are.equal("Clodex: Demo - Fix queue dispatch", vim.b[buf].term_title)

        vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
            "Codex ready",
        })

        assert.are.equal("", session:winbar_text())
        assert.is_nil(session.active_prompt_title)
        assert.is_nil(session.active_prompt_kind)
        assert.are.equal("Clodex: Demo", vim.b[buf].term_title)

        vim.fn.jobwait = original_jobwait
    end)

    it("keeps MCP authoritative prompt titles visible until explicitly cleared", function()
        local buf = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
            "Codex ready",
        })

        local session = Session.new({
            key = "project:/tmp/demo",
            kind = "project",
            cwd = "/tmp/demo",
            title = "Clodex: Demo",
            cmd = { "codex" },
        })
        session.buf = buf
        session.job_id = 123
        session:update_buffer_state()
        session:set_active_prompt_title("Authoritative prompt", "bug", { authoritative = true })

        local original_jobwait = vim.fn.jobwait
        vim.fn.jobwait = function()
            return { -1 }
        end

        assert.are.equal(" Authoritative prompt ", session:winbar_text())
        assert.are.equal("Authoritative prompt", session.active_prompt_title)
        assert.are.equal("bug", session.active_prompt_kind)
        assert.are.equal("Clodex: Demo - Authoritative prompt", vim.b[buf].term_title)

        session:set_active_prompt_title(nil, nil, { authoritative = true })

        assert.are.equal("", session:winbar_text())
        assert.is_nil(session.active_prompt_title)
        assert.is_nil(session.active_prompt_kind)
        assert.is_nil(session.active_prompt_authoritative)
        assert.are.equal("Clodex: Demo", vim.b[buf].term_title)

        vim.fn.jobwait = original_jobwait
    end)

    it("truncates long active prompt titles from the right with an omission marker", function()
        local buf = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
            "Thinking...",
        })

        local session = Session.new({
            key = "project:/tmp/demo",
            kind = "project",
            cwd = "/tmp/demo",
            title = "Clodex: Demo",
            cmd = { "codex" },
        })
        session.buf = buf
        session.job_id = 123
        session.awaiting_response = true
        session:set_active_prompt_title("Fix queue dispatch title overflow")

        local original_jobwait = vim.fn.jobwait
        vim.fn.jobwait = function()
            return { -1 }
        end

        assert.are.equal(" Fix queue[...] ", session:winbar_text(16))
        assert.are.equal(" Fix queue dispatch title overflow ", session:winbar_text(40))

        vim.fn.jobwait = original_jobwait
    end)

    it("uses the evaluated window when rendering an unfocused terminal winbar", function()
        local current_win = vim.api.nvim_get_current_win()
        local current_buf = vim.api.nvim_create_buf(false, true)
        vim.bo[current_buf].filetype = "clodex_terminal"
        vim.api.nvim_buf_set_lines(current_buf, 0, -1, false, { "Thinking..." })

        local unfocused_buf = vim.api.nvim_create_buf(false, true)
        vim.bo[unfocused_buf].filetype = "clodex_terminal"
        vim.api.nvim_buf_set_lines(unfocused_buf, 0, -1, false, { "Thinking..." })

        local current_session = Session.new({
            key = "project:/tmp/current",
            kind = "project",
            cwd = "/tmp/current",
            title = "Clodex: Current",
            cmd = { "codex" },
        })
        current_session.buf = current_buf
        current_session.job_id = 123
        current_session.awaiting_response = true
        current_session:set_active_prompt_title("Current prompt")

        local unfocused_session = Session.new({
            key = "project:/tmp/unfocused",
            kind = "project",
            cwd = "/tmp/unfocused",
            title = "Clodex: Unfocused",
            cmd = { "codex" },
        })
        unfocused_session.buf = unfocused_buf
        unfocused_session.job_id = 456
        unfocused_session.awaiting_response = true
        unfocused_session:set_active_prompt_title("Unfocused prompt")

        local app_module = package.loaded["clodex.app"]
        package.loaded["clodex.app"] = {
            instance = function()
                return {
                    terminals = {
                        session_by_buf = function(_, target_buf)
                            if target_buf == current_buf then
                                return current_session
                            end
                            if target_buf == unfocused_buf then
                                return unfocused_session
                            end
                        end,
                    },
                }
            end,
        }

        local original_jobwait = vim.fn.jobwait
        vim.fn.jobwait = function()
            return { -1 }
        end

        vim.api.nvim_win_set_buf(current_win, current_buf)
        vim.cmd("vsplit")
        local unfocused_win = vim.api.nvim_get_current_win()
        vim.api.nvim_win_set_buf(unfocused_win, unfocused_buf)
        vim.api.nvim_set_current_win(current_win)

        local original_statusline_winid = vim.g.statusline_winid
        vim.g.statusline_winid = unfocused_win

        assert.are.equal(" Unfocused prompt ", TerminalUi.winbar())

        vim.g.statusline_winid = original_statusline_winid
        vim.fn.jobwait = original_jobwait
        vim.api.nvim_win_close(unfocused_win, true)
        package.loaded["clodex.app"] = app_module
    end)

    it("detects when the session is waiting for user input", function()
        local buf = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
            "Could you confirm which project root I should use?",
            "Codex ready",
        })

        local session = Session.new({
            key = "project:/tmp/demo",
            kind = "project",
            cwd = "/tmp/demo",
            title = "Clodex: Demo",
            cmd = { "codex" },
        })
        session.buf = buf
        session.job_id = 123

        local original_jobwait = vim.fn.jobwait
        vim.fn.jobwait = function()
            return { -1 }
        end

        assert.are.equal("question", session:waiting_state())

        vim.fn.jobwait = original_jobwait
    end)

    it("detects when the session is waiting for permission", function()
        local buf = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
            "I need your permission to edit tracked files before I continue.",
            "Codex ready",
        })

        local session = Session.new({
            key = "project:/tmp/demo",
            kind = "project",
            cwd = "/tmp/demo",
            title = "Clodex: Demo",
            cmd = { "codex" },
        })
        session.buf = buf
        session.job_id = 123

        local original_jobwait = vim.fn.jobwait
        vim.fn.jobwait = function()
            return { -1 }
        end

        assert.are.equal("permission", session:waiting_state())

        vim.fn.jobwait = original_jobwait
    end)

    it("submits dispatched prompts immediately for Codex terminals", function()
        local sent = {}
        local original_chansend = vim.fn.chansend
        local original_defer_fn = vim.defer_fn
        vim.fn.chansend = function(job_id, text)
            sent[#sent + 1] = {
                job_id = job_id,
                text = text,
            }
            return #text
        end
        vim.defer_fn = function(fn)
            fn()
        end

        local session = Session.new({
            key = "project:/tmp/demo",
            kind = "project",
            cwd = "/tmp/demo",
            title = "Clodex: Demo",
            cmd = { "codex" },
        })
        session.job_id = 123
        session.ensure_started = function()
            return true
        end

        assert.is_true(session:dispatch_prompt("Fix parser\nAdd tests"))
        assert.are.same({
            {
                job_id = 123,
                text = "\027[200~Fix parser\nAdd tests\027[201~",
            },
            {
                job_id = 123,
                text = "\r",
            },
        }, sent)

        vim.fn.chansend = original_chansend
        vim.defer_fn = original_defer_fn
    end)

    it("keeps OpenCode prompt dispatch on the deferred submit path", function()
        local sent = {}
        local original_chansend = vim.fn.chansend
        local original_defer_fn = vim.defer_fn
        vim.fn.chansend = function(job_id, text)
            sent[#sent + 1] = {
                job_id = job_id,
                text = text,
            }
            return #text
        end
        vim.defer_fn = function(fn)
            fn()
        end

        local session = Session.new({
            key = "project:/tmp/demo",
            kind = "project",
            cwd = "/tmp/demo",
            title = "Clodex: Demo",
            cmd = { "opencode" },
        })
        session.job_id = 123
        session.ensure_started = function()
            return true
        end

        assert.is_true(session:dispatch_prompt("Fix parser\nAdd tests"))
        assert.are.same({
            {
                job_id = 123,
                text = "Fix parser\nAdd tests",
            },
            {
                job_id = 123,
                text = "\r",
            },
        }, sent)

        vim.fn.chansend = original_chansend
        vim.defer_fn = original_defer_fn
    end)

    it("inserts and submits the configured prompt skill", function()
        local sent = {}
        local original_chansend = vim.fn.chansend
        local original_defer_fn = vim.defer_fn
        vim.fn.chansend = function(job_id, text)
            sent[#sent + 1] = {
                job_id = job_id,
                text = text,
            }
            return #text
        end
        vim.defer_fn = function(fn)
            fn()
        end

        local session = Session.new({
            key = "project:/tmp/demo",
            kind = "project",
            cwd = "/tmp/demo",
            title = "Clodex: Demo",
            cmd = { "codex" },
            prompt_skill_name = "custom-skill",
        })
        session.job_id = 123
        session.ensure_started = function()
            return true
        end

        assert.is_true(session:insert_prompt_skill())
        assert.are.same({
            {
                job_id = 123,
                text = "$custom-skill",
            },
            {
                job_id = 123,
                text = "\r",
            },
        }, sent)
        assert.is_true(session.awaiting_response)

        vim.fn.chansend = original_chansend
        vim.defer_fn = original_defer_fn
    end)

    it("attaches prompt skill insertion maps in normal and terminal mode", function()
        local buf = vim.api.nvim_create_buf(false, true)
        local session = Session.new({
            key = "project:/tmp/demo",
            kind = "project",
            cwd = "/tmp/demo",
            title = "Clodex: Demo",
            cmd = { "codex" },
        })
        session.buf = buf

        session:update_buffer_state()

        assert.are.equal("Clodex: Insert prompt skill", buffer_map(buf, "n", "<localleader>s").desc)
        assert.are.equal("Clodex: Insert prompt skill", buffer_map(buf, "t", "<localleader>s").desc)
    end)


    it("can start sessions with the native Neovim terminal provider", function()
        local root = vim.fn.tempname()
        vim.fn.mkdir(root, "p")

        local termopen_calls = {}
        local original_termopen = vim.fn.termopen
        vim.fn.termopen = function(cmd, opts)
            termopen_calls[#termopen_calls + 1] = {
                cmd = vim.deepcopy(cmd),
                opts = vim.deepcopy(opts),
            }
            return 456
        end

        local session = Session.new({
            key = root,
            kind = "project",
            cwd = root,
            title = "Clodex: Demo",
            cmd = { "codex" },
            env = { DEMO = "1" },
            terminal_provider = "term",
        })

        assert.is_true(session:ensure_started())
        assert.are.equal(456, session.job_id)
        assert.are.equal("clodex_terminal", vim.bo[session.buf].filetype)
        assert.are.same({ "codex" }, termopen_calls[1].cmd)
        assert.are.equal(root, termopen_calls[1].opts.cwd)
        assert.are.same({ DEMO = "1" }, termopen_calls[1].opts.env)

        vim.fn.termopen = original_termopen
        session:destroy()
        vim.fn.delete(root, "rf")
    end)

    it("maps terminal statusline highlights onto terminal windows", function()
        vim.api.nvim_set_hl(0, "StatusLine", { fg = "#eeeeee", bg = "#445566" })

        local buf = vim.api.nvim_create_buf(false, true)
        vim.bo[buf].filetype = "clodex_terminal"
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "Codex ready" })
        vim.api.nvim_buf_set_var(buf, "terminal_color_background", "#112233")
        vim.api.nvim_buf_set_var(buf, "terminal_color_foreground", "#ddeeff")

        local session = Session.new({
            key = "project:/tmp/demo",
            kind = "project",
            cwd = "/tmp/demo",
            title = "Clodex: Demo",
            cmd = { "codex" },
        })
        session.buf = buf

        local app_module = package.loaded["clodex.app"]
        package.loaded["clodex.app"] = {
            instance = function()
                return {
                    config = {
                        get = function()
                            return { backend = "codex" }
                        end,
                    },
                    terminals = {
                        session_by_buf = function(_, target_buf)
                            if target_buf == buf then
                                return session
                            end
                        end,
                    },
                }
            end,
        }

        local win = vim.api.nvim_get_current_win()
        local original_buf = vim.api.nvim_win_get_buf(win)
        vim.api.nvim_win_set_buf(win, buf)

        TerminalUi.apply_window(win)

        local active_name = vim.wo[win].winhl:match("StatusLine:([^,]+)")
        local inactive_name = vim.wo[win].winhl:match("StatusLineNC:([^,]+)")
        local winbar_name = vim.wo[win].winhl:match("WinBar:([^,]+)")
        local inactive_winbar_name = vim.wo[win].winhl:match("WinBarNC:([^,]+)")
        local normal_name = vim.wo[win].winhl:match("Normal:([^,]+)")

        assert.matches("ClodexTerminalStatuslineDynActive_445566_DDEEFF", active_name)
        assert.matches("ClodexTerminalStatuslineDynInactive_445566_DDEEFF", inactive_name)
        assert.matches("ClodexTerminalTitleDynActive_445566_00AA00", winbar_name)
        assert.matches("ClodexTerminalTitleDynInactive_445566_00AA00", inactive_winbar_name)
        assert.matches("ClodexTerminalWindowDyn_445566_DDEEFF", normal_name)

        local active = vim.api.nvim_get_hl(0, { name = active_name, link = false })
        local inactive = vim.api.nvim_get_hl(0, { name = inactive_name, link = false })
        local winbar = vim.api.nvim_get_hl(0, { name = winbar_name, link = false })
        local inactive_winbar = vim.api.nvim_get_hl(0, { name = inactive_winbar_name, link = false })
        local normal = vim.api.nvim_get_hl(0, { name = normal_name, link = false })

        assert.are.equal(0x445566, active.bg)
        assert.are.equal(0xDDEEFF, active.fg)
        assert.is_nil(active.bold)
        assert.are.equal(0x445566, inactive.bg)
        assert.are.equal(0xDDEEFF, inactive.fg)
        assert.are.equal(0x445566, winbar.bg)
        assert.are.equal(0x00AA00, winbar.fg)
        assert.is_true(winbar.bold)
        assert.are.equal(0x445566, inactive_winbar.bg)
        assert.are.equal(0x00AA00, inactive_winbar.fg)
        assert.are.equal(0x445566, normal.bg)
        assert.are.equal(0xDDEEFF, normal.fg)

        vim.api.nvim_set_hl(0, "ClodexPromptBugTitle", { fg = "#aa2222" })
        session:set_active_prompt_title("Bug prompt", "bug")
        TerminalUi.apply_window(win)

        local prompt_winbar_name = vim.wo[win].winhl:match("WinBar:([^,]+)")
        local prompt_inactive_winbar_name = vim.wo[win].winhl:match("WinBarNC:([^,]+)")
        local prompt_winbar = vim.api.nvim_get_hl(0, { name = prompt_winbar_name, link = false })
        local prompt_inactive_winbar = vim.api.nvim_get_hl(0, { name = prompt_inactive_winbar_name, link = false })

        assert.matches("ClodexTerminalTitleDynActive_445566_AA2222", prompt_winbar_name)
        assert.matches("ClodexTerminalTitleDynInactive_445566_AA2222", prompt_inactive_winbar_name)
        assert.are.equal(0xAA2222, prompt_winbar.fg)
        assert.are.equal(0xAA2222, prompt_inactive_winbar.fg)

        vim.api.nvim_win_set_buf(win, original_buf)
        package.loaded["clodex.app"] = app_module
    end)

    it("keeps OpenCode terminal windows on CLI-provided chrome", function()
        local buf = vim.api.nvim_create_buf(false, true)
        vim.bo[buf].filetype = "clodex_terminal"
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "opencode" })

        local session = Session.new({
            key = "project:/tmp/demo",
            kind = "project",
            cwd = "/tmp/demo",
            title = "Clodex: Demo",
            cmd = { "opencode" },
        })
        session.buf = buf

        local app_module = package.loaded["clodex.app"]
        package.loaded["clodex.app"] = {
            instance = function()
                return {
                    config = {
                        get = function()
                            return { backend = "opencode" }
                        end,
                    },
                    terminals = {
                        session_by_buf = function(_, target_buf)
                            if target_buf == buf then
                                return session
                            end
                        end,
                    },
                }
            end,
        }

        local win = vim.api.nvim_get_current_win()
        local original_buf = vim.api.nvim_win_get_buf(win)
        vim.api.nvim_win_set_buf(win, buf)
        vim.api.nvim_set_option_value("statusline", "%!v:lua.require('clodex.terminal.ui').statusline()", { scope = "local", win = win })
        vim.api.nvim_set_option_value("winbar", "%!v:lua.require('clodex.terminal.ui').winbar()", { scope = "local", win = win })
        vim.wo[win].winhl = table.concat({
            "StatusLine:ClodexTerminalStatuslineDynActive_445566_DDEEFF",
            "WinBar:ClodexTerminalTitleDynActive_445566_00AA00",
            "Normal:ClodexTerminalWindowDyn_445566_DDEEFF",
        }, ",")

        TerminalUi.apply_window(win)

        assert.are.equal("", vim.api.nvim_get_option_value("statusline", { scope = "local", win = win }))
        assert.are.equal("", vim.api.nvim_get_option_value("winbar", { scope = "local", win = win }))
        assert.are.equal("", vim.api.nvim_get_option_value("winhl", { scope = "local", win = win }))

        vim.api.nvim_win_set_buf(win, original_buf)
        package.loaded["clodex.app"] = app_module
    end)

    it("keeps Codex terminal windows on user statusline chrome when native chrome is disabled", function()
        local buf = vim.api.nvim_create_buf(false, true)
        vim.bo[buf].filetype = "clodex_terminal"
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "codex" })

        local session = Session.new({
            key = "project:/tmp/demo",
            kind = "project",
            cwd = "/tmp/demo",
            title = "Clodex: Demo",
            cmd = { "codex" },
        })
        session.buf = buf

        local app_module = package.loaded["clodex.app"]
        package.loaded["clodex.app"] = {
            instance = function()
                return {
                    config = {
                        get = function()
                            return {
                                backend = "codex",
                                terminal = {
                                    prefer_native_statusline = false,
                                },
                            }
                        end,
                    },
                    terminals = {
                        session_by_buf = function(_, target_buf)
                            if target_buf == buf then
                                return session
                            end
                        end,
                    },
                }
            end,
        }

        local win = vim.api.nvim_get_current_win()
        local original_buf = vim.api.nvim_win_get_buf(win)
        vim.api.nvim_win_set_buf(win, buf)
        vim.api.nvim_set_option_value("statusline", "%!v:lua.require('clodex.terminal.ui').statusline()", { scope = "local", win = win })
        vim.api.nvim_set_option_value("winbar", "%!v:lua.require('clodex.terminal.ui').winbar()", { scope = "local", win = win })
        vim.wo[win].winhl = table.concat({
            "StatusLine:ClodexTerminalStatuslineDynActive_445566_DDEEFF",
            "WinBar:ClodexTerminalTitleDynActive_445566_00AA00",
            "Normal:ClodexTerminalWindowDyn_445566_DDEEFF",
        }, ",")

        TerminalUi.apply_window(win)

        assert.are.equal("", vim.api.nvim_get_option_value("statusline", { scope = "local", win = win }))
        assert.are.equal("", vim.api.nvim_get_option_value("winbar", { scope = "local", win = win }))
        assert.are.equal("", vim.api.nvim_get_option_value("winhl", { scope = "local", win = win }))

        vim.api.nvim_win_set_buf(win, original_buf)
        package.loaded["clodex.app"] = app_module
    end)

    it("clears terminal chrome after leaving a terminal buffer", function()
        local terminal_buf = vim.api.nvim_create_buf(false, true)
        vim.bo[terminal_buf].filetype = "clodex_terminal"
        vim.api.nvim_buf_set_lines(terminal_buf, 0, -1, false, { "Codex ready" })

        local normal_buf = vim.api.nvim_create_buf(false, true)
        vim.bo[normal_buf].filetype = "markdown"

        local session = Session.new({
            key = "project:/tmp/demo",
            kind = "project",
            cwd = "/tmp/demo",
            title = "Clodex: Demo",
            cmd = { "codex" },
        })
        session.buf = terminal_buf

        local app_module = package.loaded["clodex.app"]
        package.loaded["clodex.app"] = {
            instance = function()
                return {
                    config = {
                        get = function()
                            return { backend = "codex" }
                        end,
                    },
                    terminals = {
                        session_by_buf = function(_, target_buf)
                            if target_buf == terminal_buf then
                                return session
                            end
                        end,
                    },
                }
            end,
        }

        local win = vim.api.nvim_get_current_win()
        local original_buf = vim.api.nvim_win_get_buf(win)
        vim.api.nvim_win_set_buf(win, terminal_buf)
        TerminalUi.apply_window(win)

        assert.are.equal("%!v:lua.require('clodex.terminal.ui').statusline()", vim.api.nvim_get_option_value("statusline", { scope = "local", win = win }))
        assert.are.equal("%!v:lua.require('clodex.terminal.ui').winbar()", vim.api.nvim_get_option_value("winbar", { scope = "local", win = win }))

        vim.api.nvim_win_set_buf(win, normal_buf)
        TerminalUi.refresh_chrome(win)

        assert.are.equal("", vim.api.nvim_get_option_value("statusline", { scope = "local", win = win }))
        assert.are.equal("", vim.api.nvim_get_option_value("winbar", { scope = "local", win = win }))
        assert.are.equal("", vim.api.nvim_get_option_value("winhl", { scope = "local", win = win }))

        vim.api.nvim_win_set_buf(win, original_buf)
        package.loaded["clodex.app"] = app_module
    end)
end)
