describe("clodex.ui.project_dashboard", function()
    local Dashboard

    before_each(function()
        package.loaded["clodex.ui.project_dashboard"] = nil
        Dashboard = require("clodex.ui.project_dashboard")
    end)

    after_each(function()
        package.loaded["clodex.ui.project_dashboard"] = nil
    end)

    local function app_with_projects(projects, queues_by_root)
        return {
            projects_for_queue_workspace = function()
                return vim.deepcopy(projects)
            end,
            current_tab = function()
                return {
                    active_project_root = projects[1] and projects[1].root or nil,
                }
            end,
            queue_summary = function(_, project)
                local queues = queues_by_root[project.root] or {
                    planned = {},
                    queued = {},
                    implemented = {},
                    history = {},
                }
                return {
                    project = project,
                    session_running = false,
                    counts = {
                        planned = #queues.planned,
                        queued = #queues.queued,
                        implemented = #queues.implemented,
                        history = #queues.history,
                    },
                    queues = queues,
                }
            end,
        }
    end

    it("keeps the dashboard project navigation cyclic and separate from the queue workspace", function()
        local projects = {
            { name = "Alpha", root = "/tmp/alpha" },
            { name = "Beta", root = "/tmp/beta" },
            { name = "Gamma", root = "/tmp/gamma" },
        }
        local dashboard = Dashboard.new(app_with_projects(projects, {}), {
            queue_workspace = {},
        })

        dashboard:refresh_state(true)
        assert.are.equal(1, dashboard.project_index)

        dashboard:move_project(-1)
        assert.are.equal(3, dashboard.project_index)

        dashboard:move_project(1)
        assert.are.equal(1, dashboard.project_index)
    end)

    it("selects the first queued item when project selection changes", function()
        local alpha = { name = "Alpha", root = "/tmp/alpha" }
        local beta = { name = "Beta", root = "/tmp/beta" }
        local dashboard = Dashboard.new(app_with_projects({ alpha, beta }, {
            [alpha.root] = {
                planned = {
                    { id = "plan-1", title = "Plan first", kind = "todo" },
                },
                queued = {
                    { id = "queue-1", title = "Queue first", kind = "bug" },
                },
                implemented = {},
                history = {},
            },
            [beta.root] = {
                planned = {},
                queued = {
                    { id = "queue-2", title = "Queue second", kind = "todo" },
                },
                implemented = {},
                history = {},
            },
        }), {
            queue_workspace = {},
        })

        dashboard:refresh_state(true)
        assert.are.equal(2, dashboard.queue_index)
        assert.are.equal("queue-1", ({ dashboard:selected_queue_item() })[1].id)

        dashboard:move_project(1)
        assert.are.equal(1, dashboard.queue_index)
        assert.are.equal("queue-2", ({ dashboard:selected_queue_item() })[1].id)
    end)
end)
