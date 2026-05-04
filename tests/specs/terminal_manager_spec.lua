describe("clodex.terminal.manager", function()
    local Manager

    before_each(function()
        package.loaded["clodex.terminal.manager"] = nil
        package.loaded["clodex.terminal.session"] = {
            new = function()
                error("session creation is not expected in this spec")
            end,
        }
        Manager = require("clodex.terminal.manager")
    end)

    after_each(function()
        package.loaded["clodex.terminal.manager"] = nil
        package.loaded["clodex.terminal.session"] = nil
    end)

    it("falls back to the current tab when showing a session for an invalid tab state", function()
        local manager = Manager.new({
            backend = "codex",
            terminal = {
                provider = "term",
                win = {},
            },
        })

        local opened = 0
        local expected_parent = vim.api.nvim_get_current_win()
        manager.open_window = function(_, session, parent_win)
            opened = opened + 1
            assert.are.equal(expected_parent, parent_win)
            return {
                win = vim.api.nvim_get_current_win(),
                on = function() end,
                hide = function() end,
            }
        end

        local archived = 0
        local state = {
            tabpage = 999999,
            window = nil,
            session_key = nil,
            has_visible_window = function()
                return false
            end,
            hide_window = function() end,
            clear_window = function() end,
            set_window = function(self, window, session_key)
                self.window = window
                self.session_key = session_key
            end,
        }
        local session = {
            key = "project:/tmp/demo",
            archive_history_chunk = function()
                archived = archived + 1
            end,
        }

        manager:show_in_tab(state, session)

        assert.are.equal(1, opened)
        assert.are.equal(vim.api.nvim_get_current_tabpage(), state.tabpage)
        assert.are.equal("project:/tmp/demo", state.session_key)
        assert.are.equal(0, archived)
    end)

    it("adopts an already visible session buffer instead of opening another terminal window", function()
        local manager = Manager.new({
            backend = "codex",
            terminal = {
                provider = "term",
                win = {},
            },
        })

        manager.open_window = function()
            error("visible session buffer should be reused")
        end

        local original_win = vim.api.nvim_get_current_win()
        local buf = vim.api.nvim_create_buf(false, true)
        vim.cmd("split")
        local terminal_win = vim.api.nvim_get_current_win()
        vim.api.nvim_win_set_buf(terminal_win, buf)
        vim.api.nvim_set_current_win(original_win)

        local state = {
            tabpage = vim.api.nvim_get_current_tabpage(),
            window = nil,
            session_key = nil,
            has_visible_window = function()
                return false
            end,
            hide_window = function() end,
            clear_window = function(self)
                self.window = nil
                self.session_key = nil
            end,
            set_window = function(self, window, session_key)
                self.window = window
                self.session_key = session_key
            end,
        }
        local session = {
            key = "project:/tmp/demo",
            buf = buf,
            archive_history_chunk = function() end,
        }

        manager:show_in_tab(state, session)

        assert.are.equal(terminal_win, state.window.win)
        assert.are.equal("project:/tmp/demo", state.session_key)
        assert.are.equal(terminal_win, vim.api.nvim_get_current_win())

        vim.api.nvim_win_close(terminal_win, true)
    end)

    it("treats a valid project session buffer as open even when the job is not running", function()
        local manager = Manager.new({
            backend = "codex",
            terminal = {
                provider = "term",
                win = {},
            },
        })
        manager.project_sessions["/tmp/demo"] = {
            kind = "project",
            project_root = "/tmp/demo",
            is_running = function()
                return false
            end,
            buf_valid = function()
                return true
            end,
        }

        assert.is_false(manager:is_project_session_running("/tmp/demo"))
        assert.is_true(manager:is_project_session_open("/tmp/demo"))
    end)

    it("syncs project-local skills before creating a project session", function()
        local original_session = package.loaded["clodex.terminal.session"]
        package.loaded["clodex.terminal.manager"] = nil
        package.loaded["clodex.terminal.session"] = {
            new = function(spec)
                return {
                    key = spec.key,
                    kind = spec.kind,
                    cwd = spec.cwd,
                    title = spec.title,
                    cmd = spec.cmd,
                    env = spec.env,
                    runtime_key = spec.runtime_key,
                    terminal_provider = spec.terminal_provider,
                    project_root = spec.project_root,
                    ensure_started = function()
                        return true
                    end,
                    is_running = function()
                        return true
                    end,
                    destroy = function() end,
                    update_identity = function() end,
                }
            end,
        }

        local synced = {}
        local manager_with_session = require("clodex.terminal.manager").new({
            backend = "codex",
            codex_cmd = { "codex" },
            terminal = {
                provider = "term",
                win = {},
            },
            mcp = {
                enabled = false,
            },
        }, {
            sync_prompt_skill = function(_, project)
                synced[#synced + 1] = project.root
            end,
        })
        local project = {
            name = "Demo",
            root = "/tmp/demo",
        }

        local first = manager_with_session:ensure_project_session(project)
        local second = manager_with_session:ensure_project_session(project)

        assert.is_not_nil(first)
        assert.are.same(first, second)
        assert.are.same({ "/tmp/demo" }, synced)

        package.loaded["clodex.terminal.manager"] = nil
        package.loaded["clodex.terminal.session"] = original_session
    end)
end)
