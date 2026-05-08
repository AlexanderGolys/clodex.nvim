package.loaded["snacks.input"] = {
    input = function() end,
}
package.loaded["snacks.picker.select"] = {
    select = function() end,
}
package.loaded["snacks.terminal"] = {
    open = function()
        return {
            hide = function() end,
        }
    end,
}
package.loaded["clodex.ui.select"] = {
    has_active_input = function()
        return false
    end,
}

local App = require("clodex.app")
local Commands = require("clodex.commands")

describe("clodex.app", function()
    it("syncs bundled skills for every registered project", function()
        local alpha = { name = "Alpha", root = "/tmp/alpha" }
        local beta = { name = "Beta", root = "/tmp/beta" }
        local synced = {}
        local app = setmetatable({
            registry = {
                list = function()
                    return { alpha, beta }
                end,
            },
            execution = {
                sync_prompt_skill = function(_, project)
                    synced[#synced + 1] = project.root
                end,
            },
        }, App)

        app:sync_registered_project_skills()

        assert.are.same({ alpha.root, beta.root }, synced)
    end)

    it("sorts queue workspace projects by active state, running sessions, and project update timestamps", function()
        local alpha = { name = "Alpha", root = "/tmp/alpha" }
        local beta = { name = "Beta", root = "/tmp/beta" }
        local gamma = { name = "Gamma", root = "/tmp/gamma" }
        local delta = { name = "Delta", root = "/tmp/delta" }
        local epsilon = { name = "Epsilon", root = "/tmp/epsilon" }

        local timestamps = {
            [alpha.root] = { last_file_modified_at = 100 },
            [beta.root] = { last_file_modified_at = 300 },
            [gamma.root] = { last_file_modified_at = 50 },
            [delta.root] = { last_file_modified_at = 450 },
            [epsilon.root] = { last_codex_activity_at = 75 },
        }
        local running = {
            [beta.root] = true,
            [delta.root] = true,
        }

        local app = setmetatable({
            registry = {
                list = function()
                    return { alpha, beta, gamma, delta, epsilon }
                end,
            },
            current_tab = function()
                return { active_project_root = gamma.root }
            end,
            project_details_store = {
                get_cached = function(_, project)
                    return timestamps[project.root]
                end,
            },
            terminals = {
                is_project_session_working = function()
                    return false
                end,
            },
            is_project_session_running = function(_, project)
                return running[project.root] == true
            end,
            queue = {
                summary = function(_, project, session_running)
                    return {
                        project = project,
                        session_running = session_running,
                        last_updated_at = "",
                        counts = {
                            planned = 0,
                            queued = 0,
                            implemented = 0,
                            history = 0,
                        },
                        queues = {
                            planned = {},
                            queued = {},
                            implemented = {},
                            history = {},
                        },
                    }
                end,
            },
        }, App)

        local projects = app:projects_for_queue_workspace()

        assert.are.same({ gamma, delta, beta, alpha, epsilon }, projects)

        local projects_with_override = app:projects_for_queue_workspace(beta.root)

        assert.are.same({ beta, delta, alpha, gamma, epsilon }, projects_with_override)
    end)

    it("captures the selected backend in state snapshots", function()
        local app = setmetatable({
            config = {
                get = function()
                    return { backend = "opencode" }
                end,
            },
            terminals = {
                snapshot = function()
                    return {}
                end,
            },
            registry = {
                list = function()
                    return {}
                end,
                find_for_path = function()
                    return nil
                end,
            },
            current_tab = function()
                return {
                    snapshot = function()
                        return { tabpage = 1, has_visible_window = false }
                    end,
                }
            end,
            tabs = {
                snapshot = function()
                    return {}
                end,
            },
            project_bookmarks = {
                count = function()
                    return 0
                end,
            },
            project_notes = {
                count = function()
                    return 0
                end,
            },
            project_cheatsheet = {
                count = function()
                    return 0
                end,
                items = function()
                    return {}
                end,
            },
            is_project_working = function()
                return false
            end,
            is_project_session_running = function()
                return false
            end,
            resolve_target_from_path = function()
                return { kind = "free", cwd = vim.loop.cwd() }
            end,
        }, App)

        local snapshot = app:state_snapshot()

        assert.are.equal("opencode", snapshot.backend)
    end)

    it("reopens tracked CLI sessions with resume-previous before refreshing views", function()
        local calls = {}
        local app = setmetatable({
            terminals = {
                reopen_sessions_with_resume = function()
                    calls[#calls + 1] = "reopen"
                end,
            },
            refresh_views = function()
                calls[#calls + 1] = "refresh_views"
            end,
        }, App)

        app:refresh()

        assert.are.same({ "reopen", "refresh_views" }, calls)
    end)

    it("sends the prompt skill only from Clodex terminal buffers and re-enters terminal mode from normal mode", function()
        local original_startinsert = vim.cmd.startinsert
        local startinsert_calls = 0
        vim.cmd.startinsert = function()
            startinsert_calls = startinsert_calls + 1
        end

        local terminal_buf = vim.api.nvim_create_buf(false, true)
        vim.bo[terminal_buf].filetype = "clodex_terminal"
        local plain_buf = vim.api.nvim_create_buf(false, true)
        vim.bo[plain_buf].filetype = "lua"

        local inserted = 0
        local app = setmetatable({
            terminals = {
                session_by_buf = function(_, buf)
                    if buf ~= terminal_buf then
                        return nil
                    end
                    return {
                        insert_prompt_skill = function()
                            inserted = inserted + 1
                            return true
                        end,
                    }
                end,
            },
            refresh_views = function() end,
        }, App)

        local win = vim.api.nvim_get_current_win()
        vim.api.nvim_win_set_buf(win, plain_buf)
        assert.is_false(app:send_prompt_skill())

        vim.api.nvim_win_set_buf(win, terminal_buf)
        assert.is_true(app:send_prompt_skill())
        assert.are.equal(1, inserted)
        assert.are.equal(1, startinsert_calls)

        vim.cmd.startinsert = original_startinsert
    end)

    it("resolves tabs without an active project to the configured free root", function()
        local project = { name = "Alpha", root = "/tmp/alpha" }
        local app = setmetatable({
            config = {
                get = function()
                    return {
                        session = {
                            free_root = "~/clodex-free",
                        },
                    }
                end,
            },
            registry = {
                get = function()
                    return nil
                end,
                find_for_path = function()
                    return project
                end,
            },
        }, App)
        local state = {
            active_project_root = nil,
            clear_active_project = function() end,
        }

        local target = app:resolve_target_from_path(state, "/tmp/alpha/main.lua", true)

        assert.are.same({
            kind = "free",
            cwd = vim.fn.expand("~/clodex-free"),
        }, target)
        assert.are.equal(nil, state.active_project_root)
    end)

    it("lists the backend toggle command and keymap", function()
        local commands = Commands.list()
        local command_names = vim.tbl_map(function(item)
            return item.name
        end, commands)
        local keymaps = Commands.list_keymaps({
            keymaps = {
                toggle = { lhs = "<leader>pt" },
                queue_workspace = { lhs = "<leader>pq" },
                state_preview = { lhs = "<leader>ps" },
                backend_toggle = { lhs = "<leader>pb" },
                chat_toggle = { lhs = "<leader>pc" },
                chat_jump = { lhs = "<leader>pj" },
                chat_skill = { lhs = "<leader>pw" },
                refresh = { lhs = "<leader>pR" },
                new_prompt = {
                    bug = { lhs = "<leader>pB" },
                    improvement = { lhs = "<leader>pI" },
                    line_linked = { lhs = { "<leader>pl", "<Home>l" } },
                },
                go_to_readme = { lhs = "<leader>pM" },
            },
        })

        assert.is_true(vim.tbl_contains(command_names, "Clodex backend"))
        assert.is_true(vim.tbl_contains(command_names, "ClodexProject todo"))
        assert.is_false(vim.tbl_contains(command_names, "Clodex" .. "Todo"))
        assert.is_false(vim.tbl_contains(command_names, "ClodexPromptFile"))
        assert.is_true(vim.tbl_contains(
            vim.tbl_map(function(item)
                return item.lhs
            end, keymaps),
            "<leader>pb"
        ))
        assert.is_true(vim.tbl_contains(
            vim.tbl_map(function(item)
                return item.lhs
            end, keymaps),
            "<leader>pl"
        ))
        assert.is_true(vim.tbl_contains(
            vim.tbl_map(function(item)
                return item.lhs
            end, keymaps),
            "<Home>l"
        ))
        assert.is_true(vim.tbl_contains(
            vim.tbl_map(function(item)
                return item.lhs
            end, keymaps),
            "<leader>pM"
        ))
    end)

    it("surfaces hidden waiting sessions in a floating terminal", function()
        local current_tabpage = vim.api.nvim_get_current_tabpage()
        local opened_session
        local popup = {
            win = vim.api.nvim_get_current_win(),
            on = function() end,
        }
        local notify = require("clodex.util.notify")
        local original_warn = notify.warn
        local warnings = {}
        local waiting_session = {
            key = "/tmp/alpha",
            kind = "project",
            title = "Clodex: Alpha",
            project_root = "/tmp/alpha",
            active_queue_item_id = "queue-1",
            is_running = function()
                return true
            end,
            waiting_state = function()
                return "question"
            end,
        }
        local app = setmetatable({
            config = {
                get = function()
                    return {
                        terminal = {
                            blocked_input = {
                                enabled = true,
                            },
                        },
                    }
                end,
            },
            current_tab = function()
                return {
                    tabpage = current_tabpage,
                    active_project_root = "/tmp/alpha",
                    session_key = nil,
                }
            end,
            terminals = {
                sessions = function()
                    return { waiting_session }
                end,
                open_blocked_input_window = function(_, session, tabpage)
                    opened_session = { session = session, tabpage = tabpage }
                    return popup
                end,
            },
        }, App)

        notify.warn = function(message)
            warnings[#warnings + 1] = message
        end
        local ok, err = pcall(function()
            app:sync_blocked_input_window()
        end)
        notify.warn = original_warn
        assert.is_true(ok, err)

        assert.are.same(waiting_session, opened_session.session)
        assert.are.equal(current_tabpage, opened_session.tabpage)
        assert.are.equal(waiting_session.key, app.blocked_input_session_key)
        assert.are.same(popup, app.blocked_input_window)
        assert.are.same({ "Clodex session is waiting for user input: Clodex: Alpha" }, warnings)
    end)

    it("notifies when a hidden session waits for permission", function()
        local notify = require("clodex.util.notify")
        local original_warn = notify.warn
        local warning
        local waiting_session = {
            key = "/tmp/beta",
            kind = "project",
            title = "Clodex: Beta",
            project_root = "/tmp/beta",
            is_running = function()
                return true
            end,
            waiting_state = function()
                return "permission"
            end,
        }
        local app = setmetatable({
            config = {
                get = function()
                    return {
                        terminal = {
                            blocked_input = {
                                enabled = true,
                            },
                        },
                    }
                end,
            },
            current_tab = function()
                return {
                    tabpage = vim.api.nvim_get_current_tabpage(),
                    active_project_root = "/tmp/beta",
                    session_key = nil,
                }
            end,
            terminals = {
                sessions = function()
                    return { waiting_session }
                end,
                open_blocked_input_window = function()
                    return {
                        win = vim.api.nvim_get_current_win(),
                    }
                end,
            },
        }, App)

        notify.warn = function(message)
            warning = message
        end
        local ok, err = pcall(function()
            app:sync_blocked_input_window()
        end)
        notify.warn = original_warn
        assert.is_true(ok, err)

        assert.are.equal("Clodex session is waiting for permission: Clodex: Beta", warning)
    end)

    it("does not surface a waiting session already visible in the current tab", function()
        local opened = false
        local waiting_session = {
            key = "/tmp/alpha",
            kind = "project",
            title = "Clodex: Alpha",
            project_root = "/tmp/alpha",
            is_running = function()
                return true
            end,
            waiting_state = function()
                return "permission"
            end,
        }
        local app = setmetatable({
            config = {
                get = function()
                    return {
                        terminal = {
                            blocked_input = {
                                enabled = true,
                            },
                        },
                    }
                end,
            },
            current_tab = function()
                return {
                    tabpage = vim.api.nvim_get_current_tabpage(),
                    active_project_root = "/tmp/alpha",
                    session_key = "/tmp/alpha",
                }
            end,
            terminals = {
                sessions = function()
                    return { waiting_session }
                end,
                open_blocked_input_window = function()
                    opened = true
                end,
            },
        }, App)

        app:sync_blocked_input_window()

        assert.is_false(opened)
        assert.are.equal(nil, app.blocked_input_window)
    end)

    it("does not surface blocked-input popups while a workspace modal input is opening", function()
        local opened = false
        local waiting_session = {
            key = "/tmp/alpha",
            kind = "project",
            title = "Clodex: Alpha",
            project_root = "/tmp/alpha",
            is_running = function()
                return true
            end,
            waiting_state = function()
                return "question"
            end,
        }
        local app = setmetatable({
            config = {
                get = function()
                    return {
                        terminal = {
                            blocked_input = {
                                enabled = true,
                            },
                        },
                    }
                end,
            },
            queue_workspace = {
                modal_input_open = true,
            },
            current_tab = function()
                return {
                    tabpage = vim.api.nvim_get_current_tabpage(),
                    active_project_root = "/tmp/alpha",
                    session_key = nil,
                }
            end,
            terminals = {
                sessions = function()
                    return { waiting_session }
                end,
                open_blocked_input_window = function()
                    opened = true
                end,
            },
            close_blocked_input_window = function()
            end,
        }, App)

        app:sync_blocked_input_window()

        assert.is_false(opened)
        assert.are.equal(nil, app.blocked_input_window)
    end)
end)
