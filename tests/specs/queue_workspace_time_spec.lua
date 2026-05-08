describe("clodex.ui.queue_workspace time formatting", function()
    local Workspace
    local original_select
    local original_snacks_input
    local original_snacks_picker_select

    before_each(function()
        package.loaded["clodex.ui.queue_workspace"] = nil
        original_select = package.loaded["clodex.ui.select"]
        original_snacks_input = package.loaded["snacks.input"]
        original_snacks_picker_select = package.loaded["snacks.picker.select"]
        package.loaded["snacks.input"] = {
            input = function() end,
        }
        package.loaded["snacks.picker.select"] = {
            select = function(_items, _opts, on_choice)
                on_choice(nil)
            end,
        }
        package.loaded["clodex.ui.select"] = {
            close_active_input = function() end,
            has_active_input = function()
                return false
            end,
        }
        Workspace = require("clodex.ui.queue_workspace")
    end)

    after_each(function()
        package.loaded["clodex.ui.queue_workspace"] = nil
        package.loaded["snacks.input"] = original_snacks_input
        package.loaded["snacks.picker.select"] = original_snacks_picker_select
        package.loaded["clodex.ui.select"] = original_select
    end)

    it("renders configured token date formats in project details", function()
        local original_list_uis = vim.api.nvim_list_uis
        vim.api.nvim_list_uis = function()
            return {
                {
                    width = 160,
                    height = 40,
                },
            }
        end
        local project = {
            name = "Timed Project",
            root = "/tmp/timed-project",
        }
        local timestamp = os.time({
            year = 2026,
            month = 5,
            day = 7,
            hour = 14,
            min = 5,
            sec = 0,
        })
        local workspace = Workspace.new({
            current_tab = function()
                return {}
            end,
            queue_summary = function()
                return {
                    project = project,
                    session_running = false,
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
            project_details_store = {
                get_cached = function()
                    return {
                        file_count = 12,
                        remote_name = "origin",
                        languages = {
                            { name = "lua" },
                        },
                        last_file_modified_at = timestamp,
                    }
                end,
            },
        }, {
            queue_workspace = {
                preview_max_lines = 3,
                fold_preview = true,
                date_format = "dd.MM.yyyy hh:mm",
            },
        })
        workspace.projects = { project }
        workspace.project_index = 1
        workspace.project_buf = vim.api.nvim_create_buf(false, true)

        workspace:render_projects()

        local lines = table.concat(vim.api.nvim_buf_get_lines(workspace.project_buf, 0, -1, false), "\n")
        vim.api.nvim_list_uis = original_list_uis

        assert.is_truthy(lines:find(os.date("%d.%m.%Y %H:%M", timestamp), 1, true))
    end)

    it("keeps implemented prompts ordered when saved timestamps use older display formats", function()
        local project = {
            name = "History Project",
            root = "/tmp/history-project",
        }
        local workspace = Workspace.new({
            queue_summary = function()
                return {
                    project = project,
                    counts = {
                        planned = 0,
                        queued = 0,
                        implemented = 3,
                        history = 0,
                    },
                    queues = {
                        planned = {},
                        queued = {},
                        implemented = {
                            {
                                id = "iso",
                                kind = "todo",
                                title = "ISO prompt",
                                created_at = "2026-03-25T15:00:00Z",
                            },
                            {
                                id = "display",
                                kind = "todo",
                                title = "Display prompt",
                                created_at = "25.03.2026 16:00",
                            },
                            {
                                id = "legacy-default",
                                kind = "todo",
                                title = "Legacy default prompt",
                                created_at = "14:00 25.03.2026",
                            },
                        },
                        history = {},
                    },
                }
            end,
        }, {
            queue_workspace = {
                preview_max_lines = 3,
                fold_preview = true,
                date_format = "dd.MM.yyyy hh:mm",
            },
        })
        workspace.projects = { project }
        workspace.project_index = 1
        workspace.queue_buf = vim.api.nvim_create_buf(false, true)

        workspace:render_queue()

        local lines = table.concat(vim.api.nvim_buf_get_lines(workspace.queue_buf, 0, -1, false), "\n")
        local display_index = lines:find("Display prompt", 1, true)
        local iso_index = lines:find("ISO prompt", 1, true)
        local legacy_index = lines:find("Legacy default prompt", 1, true)

        assert.is_truthy(display_index)
        assert.is_truthy(iso_index)
        assert.is_truthy(legacy_index)
        assert.is_true(display_index < iso_index)
        assert.is_true(iso_index < legacy_index)
    end)
end)
