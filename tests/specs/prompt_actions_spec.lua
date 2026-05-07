describe("clodex.app.prompt_actions", function()
    local PromptActions
    local original_ui
    local original_creator
    local original_notify
    local original_context
    local creator_calls
    local pick_text_calls
    local picked_project
    local captured_projects

    before_each(function()
        package.loaded["clodex.app.prompt_actions"] = nil
        original_ui = package.loaded["clodex.ui.select"]
        original_creator = package.loaded["clodex.ui.prompt_creator"]
        original_notify = package.loaded["clodex.util.notify"]
        original_context = package.loaded["clodex.prompt.context"]
        creator_calls = {}
        pick_text_calls = 0
        picked_project = nil
        captured_projects = {}

        package.loaded["clodex.ui.select"] = {
            pick_project = function(_projects, _opts, on_choice)
                on_choice(picked_project)
            end,
            pick_text = function()
                pick_text_calls = pick_text_calls + 1
            end,
        }
        package.loaded["clodex.ui.prompt_creator"] = {
            open = function(opts)
                creator_calls[#creator_calls + 1] = vim.deepcopy(opts)
                return opts
            end,
        }
        package.loaded["clodex.util.notify"] = {
            notify = function() end,
            warn = function() end,
        }
        package.loaded["clodex.prompt.context"] = {
            capture = function(opts)
                captured_projects[#captured_projects + 1] = opts and opts.project or nil
                return {
                    relative_path = "lua/captured.lua",
                    project_root = opts and opts.project and opts.project.root or nil,
                    cursor_row = 12,
                }
            end,
        }

        PromptActions = require("clodex.app.prompt_actions")
    end)

    after_each(function()
        package.loaded["clodex.app.prompt_actions"] = nil
        package.loaded["clodex.ui.select"] = original_ui
        package.loaded["clodex.ui.prompt_creator"] = original_creator
        package.loaded["clodex.util.notify"] = original_notify
        package.loaded["clodex.prompt.context"] = original_context
    end)

    it("seeds the unified creator from the selected range", function()
        local actions = PromptActions.new({
            queue_actions = {
                add_project_todo = function() end,
            },
            queue_workspace = {
                prompt_title_width = function()
                    return 80
                end,
            },
        })
        local project = {
            name = "Demo",
            root = "/tmp/demo",
        }
        local context = {
            selection_text = "local value = 1",
            selection_start_row = 4,
            selection_end_row = 4,
            relative_path = "lua/demo.lua",
        }

        actions:prompt_for_category_kind(project, "restructure", {
            context = context,
        })

        assert.are.equal(1, #creator_calls)
        assert.are.equal(project.name, creator_calls[1].project.name)
        assert.are.equal("refactor", creator_calls[1].initial_kind)
        assert.are.same(context, creator_calls[1].context)
        assert.are.same({
            title = "Restructure the implementation",
            details = "&selection",
        }, creator_calls[1].initial_draft)
        assert.are.same({}, captured_projects)
    end)

    it("captures editor context by default when opening the creator", function()
        local actions = PromptActions.new({
            queue_actions = {
                add_project_todo = function() end,
            },
            queue_workspace = {
                prompt_title_width = function()
                    return 80
                end,
            },
        })
        local project = {
            name = "Demo",
            root = "/tmp/demo",
        }

        actions:open_creator(project)

        assert.are.equal(1, #creator_calls)
        assert.are.same(project, captured_projects[1])
        assert.are.same({
            relative_path = "lua/captured.lua",
            project_root = "/tmp/demo",
            cursor_row = 12,
        }, creator_calls[1].context)
    end)

    it("opens the bug creator when adding a bug todo", function()
        local actions = PromptActions.new({
            queue_actions = {
                add_project_todo = function() end,
            },
            registry = {
                list = function()
                    return {}
                end,
            },
        })
        local project = {
            name = "Demo",
            root = "/tmp/demo",
        }

        actions:add_bug_todo({ project = project })

        assert.are.equal(1, #creator_calls)
        assert.are.equal("bug", creator_calls[1].initial_kind)
    end)

    it("opens the creator with queue workspace project ordering", function()
        local alpha = {
            name = "Alpha",
            root = "/tmp/alpha",
        }
        local beta = {
            name = "Beta",
            root = "/tmp/beta",
        }
        local active_root
        local actions = PromptActions.new({
            current_tab = function()
                return {
                    active_project_root = beta.root,
                }
            end,
            projects_for_queue_workspace = function(_, root)
                active_root = root
                return { beta, alpha }
            end,
            queue_actions = {
                add_project_todo = function() end,
            },
        })

        actions:open_creator(alpha)

        assert.are.equal(beta.root, active_root)
        assert.are.same({ beta, alpha }, creator_calls[1].projects)
        assert.are.equal(beta.root, creator_calls[1].active_project_root)
    end)

    it("offers direct chat submit without queue persistence", function()
        local queued = false
        local dispatched_body
        local shown_session
        local refreshed = 0
        local active_root
        local actions = PromptActions.new({
            queue_actions = {
                add_project_todo = function()
                    queued = true
                end,
            },
            terminals = {
                ensure_project_session = function()
                    return {
                        dispatch_prompt = function(_, body)
                            dispatched_body = body
                            return true
                        end,
                    }
                end,
                show_in_tab = function(_, _, session)
                    shown_session = session
                end,
            },
            current_tab = function()
                return {
                    set_active_project = function(_, root)
                        active_root = root
                    end,
                }
            end,
            project_details_store = {
                touch_activity = function() end,
            },
            refresh_views = function()
                refreshed = refreshed + 1
            end,
            queue_workspace = {
                prompt_title_width = function()
                    return 80
                end,
            },
        })
        local project = {
            name = "Demo",
            root = "/tmp/demo",
        }

        actions:submit_prompt(project, {
            title = "Fix parser",
            details = "Use &file",
        }, "chat")

        assert.is_false(queued)
        assert.are.equal("Fix parser\n\nUse &file", dispatched_body)
        assert.is_not_nil(shown_session)
        assert.are.equal(project.root, active_root)
        assert.are.equal(1, refreshed)
    end)

    it("queues and implements run now through interactive execution", function()
        local queued_project
        local queued_spec
        local queued_opts
        local actions = PromptActions.new({
            config = {
                get = function()
                    return { backend = "opencode" }
                end,
            },
            queue_actions = {
                add_project_todo = function(_, project, spec, opts)
                    queued_project = project
                    queued_spec = spec
                    queued_opts = opts
                end,
            },
            queue_workspace = {
                prompt_title_width = function()
                    return 80
                end,
            },
        })
        local project = {
            name = "Demo",
            root = "/tmp/demo",
        }

        actions:submit_prompt(project, {
            title = "Fix parser",
            details = "Use &file",
        }, "exec")

        assert.are.same(project, queued_project)
        assert.are.same({
            title = "Fix parser",
            details = "Use &file",
        }, queued_spec)
        assert.are.same({
            queue = "queued",
            implement = true,
            run_mode = "interactive",
        }, queued_opts)
    end)

    it("defaults prompt picking to todo without opening the legacy kind picker", function()
        local resolved_project
        local resolved_category
        local actions = PromptActions.new({})
        picked_project = {
            name = "Demo",
            root = "/tmp/demo",
        }

        actions:pick_target({}, function(project, category)
            resolved_project = project
            resolved_category = category
        end)

        assert.are.same(picked_project, resolved_project)
        assert.are.equal("todo", resolved_category)
        assert.are.equal(0, pick_text_calls)
    end)

    it("keeps explicit prompt kinds without opening the legacy kind picker", function()
        local resolved_category
        local actions = PromptActions.new({})
        local project = {
            name = "Demo",
            root = "/tmp/demo",
        }

        actions:pick_target({ project = project, category = "bug" }, function(_, category)
            resolved_category = category
        end)

        assert.are.equal("bug", resolved_category)
        assert.are.equal(0, pick_text_calls)
    end)

    it("uses direct execution for run now on codex", function()
        local queued_opts
        local actions = PromptActions.new({
            config = {
                get = function()
                    return { backend = "codex" }
                end,
            },
            queue_actions = {
                add_project_todo = function(_, _, _, opts)
                    queued_opts = opts
                end,
            },
            queue_workspace = {
                prompt_title_width = function()
                    return 80
                end,
            },
        })

        actions:submit_prompt({
            name = "Demo",
            root = "/tmp/demo",
        }, {
            title = "Fix parser",
        }, "exec")

        assert.are.same({
            queue = "queued",
            implement = true,
            run_mode = "exec",
        }, queued_opts)
    end)

    it("queues and implements run now in Plan mode through interactive execution", function()
        local queued_opts
        local actions = PromptActions.new({
            config = {
                get = function()
                    return { backend = "codex" }
                end,
            },
            queue_actions = {
                add_project_todo = function(_, _, _, opts)
                    queued_opts = opts
                end,
            },
            queue_workspace = {
                prompt_title_width = function()
                    return 80
                end,
            },
        })

        actions:submit_prompt({
            name = "Demo",
            root = "/tmp/demo",
        }, {
            title = "Fix parser",
        }, "plan_exec")

        assert.are.same({
            queue = "queued",
            implement = true,
            run_mode = "interactive",
            start_mode = "plan",
        }, queued_opts)
    end)

    it("starts feature prompt implementation in Plan mode by default", function()
        local queued_opts
        local actions = PromptActions.new({
            config = {
                get = function()
                    return { backend = "codex" }
                end,
            },
            queue_actions = {
                add_project_todo = function(_, _, _, opts)
                    queued_opts = opts
                end,
            },
            queue_workspace = {
                prompt_title_width = function()
                    return 80
                end,
            },
        })

        actions:submit_prompt({
            name = "Demo",
            root = "/tmp/demo",
        }, {
            title = "Add import flow",
            kind = "feature",
        }, "exec")

        assert.are.same({
            queue = "queued",
            implement = true,
            run_mode = "interactive",
            start_mode = "plan",
        }, queued_opts)
    end)

    it("preserves Plan-mode start metadata when queueing feature prompts", function()
        local queued_opts
        local actions = PromptActions.new({
            config = {
                get = function()
                    return { backend = "codex" }
                end,
            },
            queue_actions = {
                add_project_todo = function(_, _, _, opts)
                    queued_opts = opts
                end,
            },
            queue_workspace = {
                prompt_title_width = function()
                    return 80
                end,
            },
        })

        actions:submit_prompt({
            name = "Demo",
            root = "/tmp/demo",
        }, {
            title = "Add import flow",
            kind = "feature",
        }, "queue")

        assert.are.same({
            queue = "queued",
            start_mode = "plan",
        }, queued_opts)
    end)

    it("closes the prompt creator after run now succeeds", function()
        local queued_project
        local queued_spec
        local queued_opts
        local actions = PromptActions.new({
            config = {
                get = function()
                    return { backend = "codex" }
                end,
            },
            queue_actions = {
                add_project_todo = function(_, project, spec, opts)
                    queued_project = project
                    queued_spec = spec
                    queued_opts = opts
                    return { id = "queued-item" }
                end,
            },
            queue_workspace = {
                prompt_title_width = function()
                    return 80
                end,
            },
        })
        local project = {
            name = "Demo",
            root = "/tmp/demo",
        }

        actions:open_creator(project)

        local result = creator_calls[1].on_submit({
            title = "Fix parser",
            details = "Use &file",
        }, "exec")

        assert.are.same(project, queued_project)
        assert.are.same({
            title = "Fix parser",
            details = "Use &file",
        }, queued_spec)
        assert.are.same({
            queue = "queued",
            implement = true,
            run_mode = "exec",
        }, queued_opts)
        assert.are.same({ id = "queued-item" }, result)
    end)
end)
