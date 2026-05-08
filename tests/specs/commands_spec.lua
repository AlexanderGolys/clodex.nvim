describe("clodex.commands", function()
    local Commands
    local created
    local fake_clodex
    local notify_calls
    local original_notify
    local captured_prompt_context

    before_each(function()
        package.loaded["clodex.commands"] = nil
        package.loaded["clodex"] = nil
        package.loaded["clodex.app"] = nil

        created = {}
        notify_calls = {}
        captured_prompt_context = {
            selection_text = "print(value)",
            selection_start_row = 3,
            selection_end_row = 3,
            relative_path = "lua/example.lua",
        }
        fake_clodex = {
            toggle = function() end,
            open_queue_workspace = function() end,
            open_project_dashboard = function() end,
            open_history = function() end,
            toggle_backend = function() end,
            toggle_terminal_header = function() end,
            toggle_state_preview = function() end,
            toggle_mini_state_preview = function() end,
            debug_reload = function() end,
            add_project = function() end,
            open_project_readme_file = function() end,
            open_project_todo_file = function() end,
            open_project_dictionary_file = function() end,
            open_project_cheatsheet_file = function() end,
            toggle_project_cheatsheet_preview = function() end,
            add_project_cheatsheet_item = function() end,
            open_project_notes_picker = function() end,
            create_project_note = function() end,
            open_project_bookmarks_picker = function() end,
            add_project_bookmark = function() end,
            add_todo = function() end,
            add_line_linked_todo = function() end,
            add_bug_todo = function() end,
            implement_next_queued_item = function() end,
            implement_all_queued_items = function() end,
            add_prompt = function() end,
            new_session = function() end,
            compact_session = function() end,
            save_session = function() end,
        }

        package.loaded["clodex"] = fake_clodex
        package.loaded["clodex.app"] = {
            instance = function()
                return {
                    registry = {
                        list = function()
                            return {
                                {
                                    name = "demo",
                                    root = "/tmp/demo",
                                },
                                {
                                    name = "alpha",
                                    root = "/tmp/alpha",
                                },
                            }
                        end,
                        find_by_name_or_root = function(_, value)
                            if value == "demo" then
                                return {
                                    name = "demo",
                                    root = "/tmp/demo",
                                }
                            end
                        end,
                    },
                }
            end,
        }
        package.loaded["clodex.prompt.context"] = {
            capture = function(opts)
                if opts and opts.selection_mode then
                    return vim.deepcopy(captured_prompt_context)
                end
                return nil
            end,
        }

        original_notify = vim.notify
        vim.notify = function(message, level)
            notify_calls[#notify_calls + 1] = {
                message = message,
                level = level,
            }
        end

        _G._orig_create_user_command = vim.api.nvim_create_user_command
        vim.api.nvim_create_user_command = function(name, handler, opts)
            created[name] = {
                handler = handler,
                opts = opts,
            }
        end

        Commands = require("clodex.commands")
    end)

    after_each(function()
        vim.api.nvim_create_user_command = _G._orig_create_user_command
        _G._orig_create_user_command = nil
        vim.notify = original_notify
    end)

    it("registers the consolidated command families", function()
        Commands.register()

        assert.is_not_nil(created.Clodex)
        assert.is_not_nil(created.ClodexDebug)
        assert.is_not_nil(created.ClodexProject)
        assert.is_not_nil(created.ClodexSession)
        assert.is_nil(created["Clodex" .. "Todo"])
        assert.is_not_nil(created.ClodexPrompt)
        assert.is_true(created.ClodexPrompt.opts.range)
    end)

    it("routes session commands through the public API", function()
        Commands.register()

        local called
        fake_clodex.save_session = function(session_id)
            called = session_id
        end

        created.ClodexSession.handler({ args = "save session-123", fargs = { "save", "session-123" } })

        assert.are.equal("session-123", called)
    end)

    it("routes the session skill action through the public API", function()
        Commands.register()

        local called = 0
        fake_clodex.send_prompt_skill = function()
            called = called + 1
        end

        created.ClodexSession.handler({ args = "skill", fargs = { "skill" } })

        assert.are.equal(1, called)
    end)

    it("routes the experimental dashboard through its separate public API", function()
        Commands.register()

        local dashboard_calls = 0
        local workspace_calls = 0
        fake_clodex.open_project_dashboard = function()
            dashboard_calls = dashboard_calls + 1
        end
        fake_clodex.open_queue_workspace = function()
            workspace_calls = workspace_calls + 1
        end

        created.Clodex.handler({ args = "dashboard", fargs = { "dashboard" } })

        assert.are.equal(1, dashboard_calls)
        assert.are.equal(0, workspace_calls)
    end)

    it("offers enum and project completion for prompt commands", function()
        Commands.register()

        assert.is_true(vim.tbl_contains(created.ClodexPrompt.opts.complete("", "ClodexPrompt ", 13), "ask"))
        assert.is_true(vim.tbl_contains(created.ClodexPrompt.opts.complete("", "ClodexPrompt ", 13), "improvement"))
        assert.is_true(vim.tbl_contains(created.ClodexPrompt.opts.complete("", "ClodexPrompt ", 13), "fix"))
        assert.is_true(vim.tbl_contains(created.ClodexPrompt.opts.complete("", "ClodexPrompt ", 13), "feature"))
        assert.is_true(vim.tbl_contains(created.ClodexPrompt.opts.complete("", "ClodexPrompt ", 13), "restructure"))
        assert.is_true(vim.tbl_contains(created.ClodexPrompt.opts.complete("", "ClodexPrompt ", 13), "vision"))
        assert.is_true(vim.tbl_contains(created.ClodexPrompt.opts.complete("", "ClodexPrompt ", 13), "clean-up"))
        assert.is_true(vim.tbl_contains(created.ClodexPrompt.opts.complete("", "ClodexPrompt ", 13), "missing-docs"))
        assert.is_false(vim.tbl_contains(created.ClodexPrompt.opts.complete("", "ClodexPrompt ", 13), "demo"))
        assert.are.same({}, created.ClodexPrompt.opts.complete("", "ClodexPrompt ask ", 17))
    end)

    it("dispatches project todo commands through the project action API", function()
        Commands.register()

        local called = false
        fake_clodex.open_project_todo_file = function()
            called = true
        end

        created.ClodexProject.handler({ args = "todo", fargs = { "todo" } })

        assert.is_true(called)
    end)

    it("dispatches prompt kind aliases through the base prompt command", function()
        Commands.register()

        local called
        fake_clodex.add_prompt = function(opts)
            called = opts
        end

        created.ClodexPrompt.handler({ args = "explain", fargs = { "explain" } })

        assert.is_not_nil(called)
        assert.are.equal("ask", called.category)
    end)

    it("offers explicit backend completion for the top-level command", function()
        Commands.register()

        assert.are.same({
            "backend",
            "chat",
            "cli",
            "dashboard",
            "experimental-panel",
            "experimental_panel",
            "header",
            "history",
            "main-panel",
            "main_panel",
            "panel",
            "term",
            "term-header",
            "terminal",
            "terminal-header",
            "terminal_header",
        }, created.Clodex.opts.complete("", "Clodex ", 7))
        assert.are.same({ "codex", "opencode" }, created.Clodex.opts.complete("", "Clodex backend ", 15))
    end)

    it("routes explicit backend selection through the runtime backend setter", function()
        local called
        package.loaded["clodex.app"] = {
            instance = function()
                return {
                    registry = {
                        list = function()
                            return {}
                        end,
                    },
                    set_backend = function(_, backend)
                        called = backend
                    end,
                }
            end,
        }

        package.loaded["clodex.commands"] = nil
        Commands = require("clodex.commands")
        Commands.register()

        created.Clodex.handler({ args = "backend opencode", fargs = { "backend", "opencode" } })

        assert.are.equal("opencode", called)
    end)

    it("passes visual selection context to prompt commands", function()
        Commands.register()

        local called
        fake_clodex.add_prompt = function(opts)
            called = opts
        end

        created.ClodexPrompt.handler({
            args = "restructure",
            fargs = { "restructure" },
            range = 2,
        })

        assert.is_not_nil(called)
        assert.are.equal("restructure", called.category)
        assert.are.same(captured_prompt_context, called.context)
    end)

    it("rejects project targets for prompt commands", function()
        Commands.register()

        local called = false
        fake_clodex.add_prompt = function()
            called = true
        end

        created.ClodexPrompt.handler({
            args = "restructure demo",
            fargs = { "restructure", "demo" },
            range = 2,
        })

        assert.is_false(called)
        assert.matches("unexpected arguments 'demo'", notify_calls[#notify_calls].message)
    end)

    it("reports invalid enum arguments instead of dispatching", function()
        Commands.register()

        local called = false
        fake_clodex.toggle_backend = function()
            called = true
        end

        created.Clodex.handler({ args = "bogus", fargs = { "bogus" } })

        assert.is_false(called)
        assert.is_true(#notify_calls > 0)
        local saw_invalid = false
        for _, item in ipairs(notify_calls) do
            if type(item.message) == "string" and item.message:find("invalid action 'bogus'", 1, true) then
                saw_invalid = true
                break
            end
        end
        assert.is_true(saw_invalid)
    end)

    it("supports multiple lhs entries in a single keymap config", function()
        local keymaps = Commands.list_keymaps({
            keymaps = {
                refresh = {
                    lhs = { "<leader>pR", "<Home>R" },
                },
            },
        })

        local refresh_lhs = {}
        for _, item in ipairs(keymaps) do
            if item.field == "refresh" then
                refresh_lhs[#refresh_lhs + 1] = item.lhs
            end
        end

        assert.are.same({ "<leader>pR", "<Home>R" }, refresh_lhs)
    end)

    it("supports grouped new prompt keymaps with multi-mode and multi-lhs", function()
        local keymaps = Commands.list_keymaps({
            keymaps = {
                new_prompt = {
                    improvement = {
                        lhs = { "<leader>pI", "<Home>I" },
                        mode = { "n", "v" },
                    },
                },
            },
        })

        local improvement = {}
        for _, item in ipairs(keymaps) do
            if item.field == "new_improvement_prompt" then
                improvement[#improvement + 1] = {
                    lhs = item.lhs,
                    mode = item.mode,
                }
            end
        end

        assert.are.same({
            { lhs = "<leader>pI", mode = "n,v" },
            { lhs = "<Home>I", mode = "n,v" },
        }, improvement)
    end)

    it("supports multiple keymap descriptors per keymap field", function()
        local keymaps = Commands.list_keymaps({
            keymaps = {
                refresh = {
                    { lhs = "<leader>pR", mode = "n" },
                    { lhs = "<Home>R", mode = "v" },
                },
            },
        })

        local refresh = {}
        for _, item in ipairs(keymaps) do
            if item.field == "refresh" then
                refresh[#refresh + 1] = {
                    lhs = item.lhs,
                    mode = item.mode,
                }
            end
        end

        assert.are.same({
            { lhs = "<leader>pR", mode = "n" },
            { lhs = "<Home>R", mode = "v" },
        }, refresh)
    end)

    it("supports descriptor lists for grouped new prompt keymaps", function()
        local keymaps = Commands.list_keymaps({
            keymaps = {
                new_prompt = {
                    improvement = {
                        { lhs = "<leader>pI", mode = "n" },
                        { lhs = "<Home>I", mode = "v" },
                    },
                },
            },
        })

        local improvement = {}
        for _, item in ipairs(keymaps) do
            if item.field == "new_improvement_prompt" then
                improvement[#improvement + 1] = {
                    lhs = item.lhs,
                    mode = item.mode,
                }
            end
        end

        assert.are.same({
            { lhs = "<leader>pI", mode = "n" },
            { lhs = "<Home>I", mode = "v" },
        }, improvement)
    end)

    it("prefers grouped new prompt keymaps over legacy prompt fields", function()
        local keymaps = Commands.list_keymaps({
            keymaps = {
                new_improvement_prompt = {
                    lhs = "<leader>legacy",
                },
                new_prompt = {
                    improvement = {
                        lhs = "<leader>grouped",
                    },
                },
            },
        })

        local improvement_lhs = nil
        for _, item in ipairs(keymaps) do
            if item.field == "new_improvement_prompt" then
                improvement_lhs = item.lhs
                break
            end
        end

        assert.are.equal("<leader>grouped", improvement_lhs)
    end)

    it("merges grouped line_linked and legacy/new grouped home keymaps", function()
        local keymaps = Commands.list_keymaps({
            keymaps = {
                new_prompt = {
                    line_linked = {
                        { lhs = "<leader>pl", mode = "n" },
                    },
                    line_linked_home = {
                        { lhs = "<Home>l", mode = { "n", "i", "v", "x", "s", "o", "c", "t" } },
                    },
                },
            },
        })

        local line_linked = {}
        for _, item in ipairs(keymaps) do
            if item.field == "new_line_linked_prompt" then
                line_linked[#line_linked + 1] = {
                    lhs = item.lhs,
                    mode = item.mode,
                }
            end
        end

        assert.are.same({
            { lhs = "<leader>pl", mode = "n" },
            { lhs = "<Home>l", mode = "n,i,v,x,s,o,c,t" },
        }, line_linked)
    end)
end)
