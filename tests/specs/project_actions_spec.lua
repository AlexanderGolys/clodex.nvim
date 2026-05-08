local ProjectActions

describe("clodex.app.project_actions", function()
    local original_select
    local original_markdown_preview
    local original_notify
    local original_edit
    local original_snacks
    local picked_opts
    local picked_projects
    local picked_text_items
    local warned_messages
    local error_messages
    local icon_picker_opts

    before_each(function()
        package.loaded["clodex.app.project_actions"] = nil
        original_select = package.loaded["clodex.ui.select"]
        original_markdown_preview = package.loaded["clodex.ui.markdown_preview"]
        original_notify = package.loaded["clodex.util.notify"]
        original_snacks = package.loaded["snacks"]
        original_edit = vim.cmd.edit
        picked_opts = nil
        picked_projects = nil
        picked_text_items = nil
        icon_picker_opts = nil
        warned_messages = {}
        error_messages = {}
        package.loaded["clodex.ui.select"] = {
            pick_project = function(projects, opts, on_choice)
                picked_projects = projects
                picked_opts = opts
                on_choice(projects[1])
            end,
            pick_text = function(items, _opts, on_choice)
                picked_text_items = items
                on_choice(items[1])
            end,
        }
        package.loaded["snacks"] = {
            picker = {
                icons = function(opts)
                    icon_picker_opts = opts
                    opts.confirm({ close = function() end }, { icon = "★" })
                end,
            },
        }
        package.loaded["clodex.ui.markdown_preview"] = {
            new = function()
                return {}
            end,
        }
        package.loaded["clodex.util.notify"] = {
            warn = function(message)
                warned_messages[#warned_messages + 1] = message
            end,
            error = function(message)
                error_messages[#error_messages + 1] = message
            end,
            notify = function() end,
        }
        ProjectActions = require("clodex.app.project_actions")
    end)

    after_each(function()
        package.loaded["clodex.app.project_actions"] = nil
        package.loaded["clodex.ui.select"] = original_select
        package.loaded["clodex.ui.markdown_preview"] = original_markdown_preview
        package.loaded["clodex.util.notify"] = original_notify
        package.loaded["snacks"] = original_snacks
        vim.cmd.edit = original_edit
    end)

    it("asks new tabs to choose an active project instead of keeping the inherited one", function()
        local refresh_count = 0
        local touched_project
        local state = {
            active_project_root = "/tmp/alpha",
            prompted = false,
            has_prompted_project = function(self)
                return self.prompted
            end,
            mark_prompted_project = function(self)
                self.prompted = true
            end,
            clear_active_project = function(self)
                self.active_project_root = nil
            end,
            set_active_project = function(self, root)
                self.active_project_root = root
            end,
            has_visible_window = function()
                return false
            end,
        }
        local actions = ProjectActions.new({
            registry = {
                list = function()
                    return {
                        { name = "Alpha", root = "/tmp/alpha" },
                        { name = "Beta", root = "/tmp/beta" },
                    }
                end,
            },
            projects_for_queue_workspace = function(_, active_root)
                assert.are.same("/tmp/alpha", active_root)
                return {
                    { name = "Beta", root = "/tmp/beta" },
                    { name = "Alpha", root = "/tmp/alpha" },
                }
            end,
            project_details_store = {
                touch_activity = function(_, project)
                    touched_project = project
                end,
            },
            refresh_views = function()
                refresh_count = refresh_count + 1
            end,
        })

        actions:prompt_new_tab_active_project(state)

        assert.are.same("Active project for new tab", picked_opts.prompt)
        assert.is_true(picked_opts.include_none)
        assert.are.same("/tmp/alpha", picked_opts.active_root)
        assert.is_false(picked_opts.show_root)
        assert.is_false(picked_opts.with_preview)
        assert.are.same({
            { name = "Beta", root = "/tmp/beta" },
            { name = "Alpha", root = "/tmp/alpha" },
        }, picked_projects)
        assert.is_true(state.prompted)
        assert.are.same("/tmp/beta", state.active_project_root)
        assert.are.same("/tmp/beta", touched_project.root)
        assert.are.equal(1, refresh_count)
    end)

    it("opens the selected project README after choosing a new tab project", function()
        local root = vim.fn.tempname()
        local readme = root .. "/README.md"
        local opened_path
        vim.fn.mkdir(root, "p")
        vim.fn.writefile({ "# Beta" }, readme)
        vim.cmd.enew()
        vim.cmd.edit = function(path)
            opened_path = path
        end

        local state = {
            prompted = false,
            has_prompted_project = function(self)
                return self.prompted
            end,
            mark_prompted_project = function(self)
                self.prompted = true
            end,
            clear_active_project = function() end,
            set_active_project = function() end,
            has_visible_window = function()
                return false
            end,
        }
        local actions = ProjectActions.new({
            projects_for_queue_workspace = function()
                return {
                    { name = "Beta", root = root },
                }
            end,
            project_details_store = {
                touch_activity = function() end,
            },
            refresh_views = function() end,
        })

        actions:prompt_new_tab_active_project(state)

        assert.are.equal(readme, opened_path)
        vim.fn.delete(root, "rf")
    end)

    it("opens the selected project session in the new tab after project selection", function()
        local root = vim.fn.tempname()
        local ensured_project
        local shown_target
        local shown_state
        vim.fn.mkdir(root, "p")

        local state = {
            prompted = false,
            active_project_root = nil,
            has_prompted_project = function(self)
                return self.prompted
            end,
            mark_prompted_project = function(self)
                self.prompted = true
            end,
            clear_active_project = function() end,
            set_active_project = function(self, value)
                self.active_project_root = value
            end,
            has_visible_window = function()
                return false
            end,
        }
        local app = {
            projects_for_queue_workspace = function()
                return {
                    { name = "Beta", root = root },
                }
            end,
            project_details_store = {
                touch_activity = function() end,
            },
            terminals = {
                ensure_project_session = function(_, project)
                    ensured_project = project
                    return { key = project.root }
                end,
            },
            refresh_views = function() end,
        }
        local actions = ProjectActions.new(app)
        actions.show_target = function(_, received_state, target)
            shown_state = received_state
            shown_target = target
            return { key = target.project.root }
        end

        actions:prompt_new_tab_active_project(state)

        assert.are.equal(root, state.active_project_root)
        assert.are.same({ name = "Beta", root = root }, ensured_project)
        assert.are.same(state, shown_state)
        assert.are.same({
            kind = "project",
            project = { name = "Beta", root = root },
        }, shown_target)

        vim.fn.delete(root, "rf")
    end)

    it("does not jump to README when the new tab already shows a selected project file", function()
        local root = vim.fn.tempname()
        local readme = root .. "/README.md"
        local project_file = root .. "/lua/init.lua"
        local edit_calls = 0
        vim.fn.mkdir(root .. "/lua", "p")
        vim.fn.writefile({ "# Beta" }, readme)
        vim.fn.writefile({ "return {}" }, project_file)
        vim.cmd.edit(project_file)
        vim.cmd.edit = function()
            edit_calls = edit_calls + 1
        end

        local state = {
            prompted = false,
            has_prompted_project = function(self)
                return self.prompted
            end,
            mark_prompted_project = function(self)
                self.prompted = true
            end,
            clear_active_project = function() end,
            set_active_project = function() end,
            has_visible_window = function()
                return false
            end,
        }
        local actions = ProjectActions.new({
            projects_for_queue_workspace = function()
                return {
                    { name = "Beta", root = root },
                }
            end,
            project_details_store = {
                touch_activity = function() end,
            },
            refresh_views = function() end,
        })

        actions:prompt_new_tab_active_project(state)

        assert.are.equal(0, edit_calls)
        vim.cmd.enew()
        vim.fn.delete(root, "rf")
    end)

    it("jumps to the current chat target and enters terminal mode", function()
        local shown_state
        local shown_session
        local touched_project
        local refresh_count = 0
        local startinsert_calls = 0
        local original_startinsert = vim.cmd.startinsert
        vim.cmd.startinsert = function()
            startinsert_calls = startinsert_calls + 1
        end

        local state = {}
        local project = { name = "Demo", root = "/tmp/demo" }
        local actions = ProjectActions.new({
            current_tab = function()
                return state
            end,
            resolve_target = function()
                return {
                    kind = "project",
                    project = project,
                }
            end,
            terminals = {
                get_session = function()
                    return { key = "project::demo" }
                end,
                show_in_tab = function(_, received_state, session)
                    shown_state = received_state
                    shown_session = session
                end,
            },
            tabs = {
                list = function()
                    return {}
                end,
            },
            project_details_store = {
                touch_activity = function(_, value)
                    touched_project = value
                end,
            },
            refresh_views = function()
                refresh_count = refresh_count + 1
            end,
        })
        actions.prompt_set_active_project = function() end

        actions:jump_to_chat()
        vim.wait(100, function()
            return startinsert_calls > 0
        end)

        assert.are.same(state, shown_state)
        assert.are.same({ key = "project::demo" }, shown_session)
        assert.are.same(project, touched_project)
        assert.are.equal(1, refresh_count)

        vim.cmd.startinsert = original_startinsert
    end)


    it("keeps modified buffers open when opening a project workspace target", function()
        local root = vim.fn.tempname()
        local readme = root .. "/README.md"
        local edit_calls = 0
        local refreshed = 0
        local shown = 0
        local touched = 0
        local activated_root
        local state = {
            set_active_project = function(_, root_value)
                activated_root = root_value
            end,
        }
        vim.fn.mkdir(root, "p")
        vim.fn.writefile({ "# Demo" }, readme)
        vim.api.nvim_buf_set_lines(0, 0, -1, false, { "unsaved" })
        vim.bo[0].modified = true
        vim.cmd.edit = function()
            edit_calls = edit_calls + 1
        end

        local actions = ProjectActions.new({
            current_tab = function()
                return state
            end,
            terminals = {
                ensure_project_session = function()
                    return { key = "project::demo" }
                end,
                get_session = function()
                    return { key = "project::demo" }
                end,
                show_in_tab = function()
                    shown = shown + 1
                end,
            },
            tabs = {
                list = function()
                    return { state }
                end,
            },
            project_details_store = {
                touch_activity = function()
                    touched = touched + 1
                end,
            },
            refresh_views = function()
                refreshed = refreshed + 1
            end,
        })

        actions:open_project_workspace_target({ name = "Demo", root = root })

        assert.are.equal(root, activated_root)
        assert.are.equal(0, edit_calls)
        assert.are.equal(1, shown)
        assert.are.equal(1, touched)
        assert.are.equal(2, refreshed)
        assert.are.same({ "Current buffer has unsaved changes; keeping it open instead of replacing it." }, warned_messages)

        vim.bo[0].modified = false
        vim.fn.delete(root, "rf")
    end)

    it("warns instead of crashing when the project README hits a swapfile conflict", function()
        local root = vim.fn.tempname()
        local readme = root .. "/README.md"
        local edit_calls = 0
        local refreshed = 0
        local shown = 0
        local touched = 0
        local activated_root
        local state = {
            set_active_project = function(_, root_value)
                activated_root = root_value
            end,
        }
        vim.fn.mkdir(root, "p")
        vim.fn.writefile({ "# Demo" }, readme)
        vim.bo[0].modified = false
        vim.cmd.edit = function()
            edit_calls = edit_calls + 1
            error("vim/_editor.lua:0: nvim_exec2(), line 1: Vim(edit):E325: ATTENTION")
        end

        local actions = ProjectActions.new({
            current_tab = function()
                return state
            end,
            terminals = {
                ensure_project_session = function()
                    return { key = "project::demo" }
                end,
                get_session = function()
                    return { key = "project::demo" }
                end,
                show_in_tab = function()
                    shown = shown + 1
                end,
            },
            tabs = {
                list = function()
                    return { state }
                end,
            },
            project_details_store = {
                touch_activity = function()
                    touched = touched + 1
                end,
            },
            refresh_views = function()
                refreshed = refreshed + 1
            end,
        })

        actions:open_project_workspace_target({ name = "Demo", root = root })

        assert.are.equal(root, activated_root)
        assert.are.equal(1, edit_calls)
        assert.are.equal(1, shown)
        assert.are.equal(1, touched)
        assert.are.equal(2, refreshed)
        assert.are.same({
            ("Swap file already exists for %s; keeping the current buffer unchanged."):format(readme),
        }, warned_messages)
        assert.are.same({}, error_messages)

        vim.fn.delete(root, "rf")
    end)

    it("switches the backend at runtime without recreating the app", function()
        local notified_messages = {}
        local update_values
        local refresh_count = 0
        local values = {
            backend = "codex",
            prompt_execution = {
                skills_dir = "/tmp/codex-skills",
            },
        }

        package.loaded["clodex.util.notify"].notify = function(message)
            notified_messages[#notified_messages + 1] = message
        end

        local actions = ProjectActions.new({
            config = {
                get = function()
                    return values
                end,
            },
            terminals = {
                update_config = function(_, updated)
                    update_values = updated
                end,
            },
            state_preview = { update_config = function() end },
            execution = { update_config = function() end },
            exec_runner = { update_config = function() end },
            queue_workspace = { update_config = function() end },
            refresh_views = function()
                refresh_count = refresh_count + 1
            end,
        })

        actions:set_backend("opencode")

        assert.are.equal("opencode", values.backend)
        assert.are.equal("/tmp/codex-skills", values.prompt_execution.skills_dir)
        assert.are.same(values, update_values)
        assert.are.equal(1, refresh_count)
        assert.are.same({ "Switched Clodex backend to OpenCode" }, notified_messages)
    end)

    it("opens the icon picker and stores the selected project icon", function()
        local stored_icon
        local touched = 0
        local refreshed = 0
        local actions = ProjectActions.new({
            project_details_store = {
                get_icon = function()
                    return nil
                end,
                set_icon = function(_, _, icon)
                    stored_icon = icon
                end,
                touch_activity = function()
                    touched = touched + 1
                end,
            },
            refresh_views = function()
                refreshed = refreshed + 1
            end,
        })
        local project = { name = "Demo", root = "/tmp/demo" }

        actions:pick_project_icon(project)

        assert.are.equal("Set icon", picked_text_items[1].label)
        assert.are.equal("★", stored_icon)
        assert.is_not_nil(icon_picker_opts)
        assert.are.equal(1, touched)
        assert.are.equal(1, refreshed)
    end)

    it("removes the selected project icon from the same action menu", function()
        local stored_icon = "★"
        local touched = 0
        local refreshed = 0
        package.loaded["clodex.ui.select"].pick_text = function(items, _opts, on_choice)
            picked_text_items = items
            on_choice(items[2])
        end
        local actions = ProjectActions.new({
            project_details_store = {
                get_icon = function()
                    return stored_icon
                end,
                set_icon = function(_, _, icon)
                    stored_icon = icon
                end,
                touch_activity = function()
                    touched = touched + 1
                end,
            },
            refresh_views = function()
                refreshed = refreshed + 1
            end,
        })

        actions:pick_project_icon({ name = "Demo", root = "/tmp/demo" })

        assert.are.equal("Change icon", picked_text_items[1].label)
        assert.are.equal("Remove icon", picked_text_items[2].label)
        assert.is_nil(stored_icon)
        assert.are.equal(1, touched)
        assert.are.equal(1, refreshed)
    end)

    it("renames projects through the registry without changing project files", function()
        local registry_spec
        local terminal_project
        local refreshed = 0
        local actions = ProjectActions.new({
            registry = {
                add = function(_, spec)
                    registry_spec = spec
                    return {
                        name = spec.name,
                        root = spec.root,
                    }
                end,
            },
            terminals = {
                update_project_identity = function(_, project)
                    terminal_project = project
                end,
            },
            refresh_views = function()
                refreshed = refreshed + 1
            end,
        })

        local updated = actions:rename_project_to({ name = "Demo", root = "/tmp/demo" }, " Renamed Demo ")

        assert.are.same({ name = "Renamed Demo", root = "/tmp/demo" }, registry_spec)
        assert.are.same({ name = "Renamed Demo", root = "/tmp/demo" }, terminal_project)
        assert.are.same({ name = "Renamed Demo", root = "/tmp/demo" }, updated)
        assert.are.equal(1, refreshed)
    end)

end)
