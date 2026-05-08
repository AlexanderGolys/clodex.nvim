local Queue = require("clodex.workspace.queue")
local QueueActions = require("clodex.app.queue_actions")
local fs = require("clodex.util.fs")

local function temp_dir()
    local dir = vim.fn.tempname()
    fs.ensure_dir(dir)
    return dir
end

local function new_project(root, name)
    return {
        name = name or "Test Project",
        root = fs.join(root, name or "project"),
    }
end

describe("clodex.app.queue_actions", function()
    local workspace_root
    local project
    local target_project
    local queue
    local actions
    local refresh_count

    before_each(function()
        workspace_root = temp_dir()
        project = new_project(workspace_root, "project-a")
        target_project = new_project(workspace_root, "project-b")
        fs.ensure_dir(project.root)
        fs.ensure_dir(target_project.root)
        queue = Queue.new(".clodex-test")
        refresh_count = 0
        actions = QueueActions.new({
            queue = queue,
            is_project_working = function()
                return false
            end,
            execution = {
                queue_item_instructions = function(_, item)
                    return ("Current queue item id: `%s`\n$prompt-nvim-clodex"):format(item.id)
                end,
            },
            project_details_store = {
                touch_activity = function() end,
            },
            refresh_views = function()
                refresh_count = refresh_count + 1
            end,
        })
    end)

    after_each(function()
        actions = nil
        queue = nil
        if target_project then
            fs.remove(target_project.root)
        end
        if project then
            fs.remove(project.root)
        end
        if workspace_root then
            fs.remove(workspace_root)
        end
    end)

    it("sets the active terminal prompt title while dispatching an interactive queued item", function()
        local seen_title
        local seen_kind
        local dispatched_prompt
        local session = {
            set_active_prompt_title = function(_, title, kind)
                seen_title = title
                seen_kind = kind
            end,
            dispatch_prompt = function(_, prompt)
                dispatched_prompt = prompt
                return true
            end,
        }
        actions.app.terminals = {
            ensure_project_session = function()
                return session
            end,
        }
        actions.app.execution = {
            dispatch_prompt = function(_, _, item)
                return ("dispatch %s"):format(item.id)
            end,
        }

        local item = queue:add_todo(project, {
            title = "Show prompt title",
            details = "surface in winbar",
            queue = "queued",
            kind = "todo",
        })

        assert.is_true(actions:dispatch_item(project, item))
        assert.are.equal("Show prompt title", seen_title)
        assert.are.equal("todo", seen_kind)
        assert.are.equal(("dispatch %s"):format(item.id), dispatched_prompt)
    end)

    it("sends the Plan mode command before dispatching a Plan-mode queued item", function()
        local sent = {}
        local dispatched_prompt
        local session = {
            send = function(_, text)
                sent[#sent + 1] = text
                return true
            end,
            set_active_prompt_title = function() end,
            dispatch_prompt = function(_, prompt)
                dispatched_prompt = prompt
                return true
            end,
        }
        actions.app.terminals = {
            ensure_project_session = function()
                return session
            end,
        }
        actions.app.execution = {
            dispatch_prompt = function(_, _, item)
                return ("dispatch %s"):format(item.id)
            end,
        }

        local item = queue:add_todo(project, {
            title = "Plan first",
            queue = "queued",
            kind = "todo",
            start_mode = "plan",
        })

        assert.is_true(actions:dispatch_item(project, item))
        assert.are.same({ "/plan" }, sent)
        assert.are.equal(("dispatch %s"):format(item.id), dispatched_prompt)
    end)

    it("resumes the saved session when dispatching a not-working queued item", function()
        local seen_opts
        local dispatched_prompt
        local session = {
            set_active_prompt_title = function() end,
            dispatch_prompt = function(_, prompt)
                dispatched_prompt = prompt
                return true
            end,
        }
        actions.app.config = {
            get = function()
                return { backend = "codex" }
            end,
        }
        actions.app.terminals = {
            ensure_project_session = function(_, _, opts)
                seen_opts = opts
                return session
            end,
        }
        actions.app.execution = {
            dispatch_prompt = function(_, _, item)
                return ("dispatch %s"):format(item.id)
            end,
        }

        local item = queue:add_todo(project, {
            title = "Fix previous implementation",
            queue = "queued",
            kind = "notworking",
        })
        queue:update_item(project, item.id, {
            history_session = {
                backend = "codex",
                id = "session-123",
            },
        })

        assert.is_true(actions:start_queued_item(project, item.id, "interactive"))
        assert.are.equal("session-123", seen_opts.resume_session_id)
        assert.are.equal(("dispatch %s"):format(item.id), dispatched_prompt)
    end)

    it("clears the active terminal prompt title when interactive dispatch fails", function()
        local titles = {}
        local session = {
            set_active_prompt_title = function(_, title)
                titles[#titles + 1] = title or "<nil>"
            end,
            dispatch_prompt = function()
                return false
            end,
        }
        actions.app.terminals = {
            ensure_project_session = function()
                return session
            end,
        }
        actions.app.execution = {
            dispatch_prompt = function()
                return "$prompt-nvim-clodex"
            end,
        }

        local item = queue:add_todo(project, {
            title = "Show prompt title",
            details = "surface in winbar",
            queue = "queued",
            kind = "todo",
        })

        assert.is_false(actions:dispatch_item(project, item))
        assert.are.same({ "Show prompt title", "<nil>" }, titles)
    end)

    it("syncs active MCP prompt titles into project terminal sessions", function()
        local active_path = require("clodex.mcp").active_state_path({
            storage = {
                workspaces_dir = workspace_root,
            },
        }, project.root)
        fs.write_json(active_path, {
            item_id = "item-1",
            source_queue = "queued",
            claimed_at = "2026-01-01T00:00:00Z",
            title = "Authoritative prompt title",
            kind = "bug",
        })

        local original_terminal_ui = package.loaded["clodex.terminal.ui"]
        local chrome_refresh_count = 0
        package.loaded["clodex.terminal.ui"] = {
            refresh_all_chrome = function()
                chrome_refresh_count = chrome_refresh_count + 1
            end,
        }

        local authoritative
        local session = {
            set_active_prompt_title = function(self, title, kind, opts)
                self.active_prompt_title = title
                self.active_prompt_kind = kind
                self.active_prompt_authoritative = title and opts and opts.authoritative == true or nil
                authoritative = self.active_prompt_authoritative
            end,
        }
        actions.app.config = {
            get = function()
                return {
                    storage = {
                        workspaces_dir = workspace_root,
                    },
                }
            end,
        }
        actions.app.registry = {
            list = function()
                return { project }
            end,
        }
        actions.app.terminals = {
            project_session = function(_, root)
                if root == project.root then
                    return session
                end
            end,
        }

        assert.is_true(actions:poll_active_prompt_titles())
        assert.are.equal("Authoritative prompt title", session.active_prompt_title)
        assert.are.equal("bug", session.active_prompt_kind)
        assert.is_true(authoritative)
        assert.are.equal(1, chrome_refresh_count)

        fs.remove(active_path)

        assert.is_true(actions:poll_active_prompt_titles())
        assert.is_nil(session.active_prompt_title)
        assert.is_nil(session.active_prompt_kind)
        assert.is_nil(authoritative)
        assert.are.equal(2, chrome_refresh_count)

        package.loaded["clodex.terminal.ui"] = original_terminal_ui
    end)

    it("keeps the submitted prompt title before MCP has claimed the task", function()
        local send_count = 0
        local session = {
            active_prompt_title = "Submitted prompt",
            active_prompt_kind = "todo",
            active_prompt_authoritative = nil,
            set_active_prompt_title = function(self, title, kind, opts)
                self.active_prompt_title = title
                self.active_prompt_kind = kind
                self.active_prompt_authoritative = title and opts and opts.authoritative == true or nil
            end,
            send = function()
                send_count = send_count + 1
            end,
        }
        actions.app.config = {
            get = function()
                return {
                    storage = {
                        workspaces_dir = workspace_root,
                    },
                }
            end,
        }
        actions.app.registry = {
            list = function()
                return { project }
            end,
        }
        actions.app.terminals = {
            project_session = function(_, root)
                if root == project.root then
                    return session
                end
            end,
        }

        assert.is_false(actions:poll_active_prompt_titles())
        assert.are.equal("Submitted prompt", session.active_prompt_title)
        assert.are.equal("todo", session.active_prompt_kind)
        assert.is_nil(session.active_prompt_authoritative)
        assert.are.equal(0, send_count)
    end)

    it("queues a review request before continuing after a completed prompt when enabled", function()
        local original_defer_fn = vim.defer_fn
        vim.defer_fn = function(fn)
            fn()
            return 0
        end

        local started_item_id
        local sent = {}
        local session = {
            active_prompt_title = "Completed prompt",
            active_prompt_kind = "todo",
            active_prompt_authoritative = true,
            set_active_prompt_title = function(self, title, kind, opts)
                self.active_prompt_title = title
                self.active_prompt_kind = kind
                self.active_prompt_authoritative = title and opts and opts.authoritative == true or nil
            end,
            send = function(_, text)
                sent[#sent + 1] = text
                return true
            end,
        }
        actions.app.config = {
            get = function()
                return {
                    storage = {
                        workspaces_dir = workspace_root,
                    },
                    prompt_execution = {
                        review_after_completion = true,
                    },
                }
            end,
        }
        actions.app.registry = {
            list = function()
                return { project }
            end,
        }
        actions.app.terminals = {
            project_session = function(_, root)
                if root == project.root then
                    return session
                end
            end,
        }
        actions.start_queued_item = function(_, _, item_id)
            started_item_id = item_id
            return true
        end

        local completed = queue:add_todo(project, {
            title = "Implement feature",
            details = "Make the app better",
            queue = "queued",
            kind = "todo",
        })
        queue:advance(project, completed.id)
        queue:update_implemented_item(project, completed.id, {
            summary = "Implemented the feature",
            commit = "abc123",
            completed_at = "2026-01-01T00:00:00Z",
        })
        queue:add_todo(project, {
            title = "Existing queued work",
            queue = "queued",
            kind = "todo",
        })

        assert.is_true(actions:poll_active_prompt_titles())
        vim.defer_fn = original_defer_fn

        local implemented = queue:queue(project, "implemented")[1]
        local queued = queue:queue(project, "queued")

        assert.is_not_nil(implemented.review_requested_at)
        assert.are.equal("Review changes for Implement feature", queued[1].title)
        assert.are.equal("ask", queued[1].kind)
        assert.are.equal("history", queued[1].completion_target)
        assert.is_truthy(queued[1].details:find("abc123", 1, true))
        assert.are.equal(queued[1].id, started_item_id)
        assert.are.same({ "/new" }, sent)
    end)

    it("waits for the backend to become idle before continuing after a completed prompt", function()
        local original_defer_fn = vim.defer_fn
        local deferred = {}
        vim.defer_fn = function(fn)
            deferred[#deferred + 1] = fn
            return #deferred
        end

        local started_item_id
        local sent = {}
        local working = true
        local session = {
            active_prompt_title = "Completed prompt",
            active_prompt_kind = "todo",
            active_prompt_authoritative = true,
            is_working = function()
                return working
            end,
            set_active_prompt_title = function(self, title, kind, opts)
                self.active_prompt_title = title
                self.active_prompt_kind = kind
                self.active_prompt_authoritative = title and opts and opts.authoritative == true or nil
            end,
            send = function(_, text)
                sent[#sent + 1] = text
                return true
            end,
        }
        actions.app.config = {
            get = function()
                return {
                    storage = {
                        workspaces_dir = workspace_root,
                    },
                }
            end,
        }
        actions.app.registry = {
            list = function()
                return { project }
            end,
        }
        actions.app.terminals = {
            project_session = function(_, root)
                if root == project.root then
                    return session
                end
            end,
        }
        actions.start_queued_item = function(_, _, item_id)
            started_item_id = item_id
            return true
        end

        local item = queue:add_todo(project, {
            title = "Next queued work",
            queue = "queued",
            kind = "todo",
        })

        assert.is_true(actions:poll_active_prompt_titles())
        assert.are.same({ "/new" }, sent)
        assert.are.equal(1, #deferred)
        assert.is_nil(started_item_id)

        deferred[1]()
        assert.are.equal(2, #deferred)
        assert.is_nil(started_item_id)

        working = false
        deferred[2]()
        vim.defer_fn = original_defer_fn

        assert.are.equal(item.id, started_item_id)
    end)

    it("continues to the next queued item when a pending title closes before becoming authoritative", function()
        local original_defer_fn = vim.defer_fn
        vim.defer_fn = function(fn)
            fn()
            return 0
        end

        local started_item_id
        local sent = {}
        local session = {
            active_prompt_title = "Submitted prompt",
            active_prompt_kind = "todo",
            active_prompt_authoritative = nil,
            is_working = function()
                return false
            end,
            set_active_prompt_title = function(self, title, kind, opts)
                self.active_prompt_title = title
                self.active_prompt_kind = kind
                self.active_prompt_authoritative = title and opts and opts.authoritative == true or nil
            end,
            send = function(_, text)
                sent[#sent + 1] = text
                return true
            end,
        }
        actions.app.config = {
            get = function()
                return {
                    storage = {
                        workspaces_dir = workspace_root,
                    },
                }
            end,
        }
        actions.app.registry = {
            list = function()
                return { project }
            end,
        }
        actions.app.terminals = {
            project_session = function(_, root)
                if root == project.root then
                    return session
                end
            end,
        }
        actions.start_queued_item = function(_, _, item_id)
            started_item_id = item_id
            return true
        end

        local item = queue:add_todo(project, {
            title = "Next queued work",
            queue = "queued",
            kind = "todo",
        })

        assert.is_true(actions:poll_active_prompt_titles())
        vim.defer_fn = original_defer_fn

        assert.are.same({ "/new" }, sent)
        assert.are.equal(item.id, started_item_id)
        assert.is_nil(session.active_prompt_title)
    end)

    it("moves an implemented item back to queued when the source queue is specified", function()
        local item = queue:add_todo(project, {
            title = "fix prompt flow",
            details = "return to queued",
            queue = "queued",
            kind = "todo",
        })
        queue:advance(project, item.id)
        queue:update_implemented_item(project, item.id, {
            summary = "implemented",
            completed_at = "2026-01-01T00:00:00Z",
        })

        actions:rewind_queue_item(project, item.id, { queue = "implemented" })

        local queue_name, _, moved = queue:find_item(project, item.id)
        assert.are.equal("queued", queue_name)
        assert.are.equal(nil, moved.history_summary)
        assert.are.equal(nil, moved.history_completed_at)
        assert.are.equal(1, refresh_count)
    end)

    it("moves an implemented item back to queued marked as not working", function()
        local item = queue:add_todo(project, {
            title = "fix prompt flow",
            details = "return to queued",
            queue = "queued",
            kind = "todo",
        })
        queue:advance(project, item.id)
        queue:update_implemented_item(project, item.id, {
            summary = "implemented",
            completed_at = "2026-01-01T00:00:00Z",
        })

        actions:rewind_queue_item(project, item.id, {
            queue = "implemented",
            mark_not_working = true,
        })

        local queue_name, _, moved = queue:find_item(project, item.id)
        assert.are.equal("queued", queue_name)
        assert.are.equal("notworking", moved.kind)
        assert.are.equal(nil, moved.history_summary)
        assert.are.equal(nil, moved.history_completed_at)
        assert.are.equal(1, refresh_count)
    end)

    it("preserves saved session metadata when marking an item as not working", function()
        local item = queue:add_todo(project, {
            title = "fix prompt flow",
            details = "return to queued",
            queue = "queued",
            kind = "todo",
        })
        queue:advance(project, item.id)
        queue:update_implemented_item(project, item.id, {
            summary = "implemented",
            completed_at = "2026-01-01T00:00:00Z",
            session = {
                backend = "codex",
                id = "session-123",
            },
        })

        actions:rewind_queue_item(project, item.id, {
            queue = "implemented",
            mark_not_working = true,
        })

        local _, _, moved = queue:find_item(project, item.id)
        assert.are.same({
            backend = "codex",
            id = "session-123",
        }, moved.history_session)
    end)

    it("saves session metadata on implemented items", function()
        local item = queue:add_todo(project, {
            title = "fix prompt flow",
            queue = "queued",
            kind = "todo",
        })
        queue:advance(project, item.id)

        local saved = actions:save_queue_item_session(project, item.id, "session-123", "opencode")

        assert.is_not_false(saved)
        assert.are.same({
            backend = "opencode",
            id = "session-123",
        }, saved.history_session)
    end)

    it("moves a history item back to queued when marked as not working", function()
        local item = queue:add_todo(project, {
            title = "fix prompt flow",
            details = "return to queued",
            queue = "queued",
            kind = "todo",
        })
        queue:advance(project, item.id)
        queue:update_implemented_item(project, item.id, {
            summary = "implemented",
            commit = "abcdef1234567890",
            completed_at = "2026-01-01T00:00:00Z",
        })
        queue:advance(project, item.id)

        actions:rewind_queue_item(project, item.id, {
            queue = "history",
            mark_not_working = true,
            note = "Still fails after review.",
        })

        local queue_name, _, moved = queue:find_item(project, item.id)
        assert.are.equal("queued", queue_name)
        assert.are.equal("notworking", moved.kind)
        assert.is_true(moved.details:find("Still fails after review%.") ~= nil)
        assert.is_true(moved.details:find("abcdef12") ~= nil)
        assert.are.equal(nil, moved.history_summary)
        assert.are.same({}, moved.history_commits)
        assert.are.equal(nil, moved.history_completed_at)
        assert.are.equal(1, refresh_count)
    end)

    it("adds an optional user note when moving an implemented item back to queued", function()
        local item = queue:add_todo(project, {
            title = "fix prompt flow",
            details = "return to queued",
            queue = "queued",
            kind = "todo",
        })
        queue:advance(project, item.id)
        queue:update_implemented_item(project, item.id, {
            summary = "implementation complete",
            completed_at = "2026-01-01T00:00:00Z",
        })

        actions:rewind_queue_item(project, item.id, {
            queue = "implemented",
            mark_not_working = true,
            note = "Fails when the cache is cold.",
        })

        local queue_name, _, moved = queue:find_item(project, item.id)
        assert.are.equal("queued", queue_name)
        assert.are.equal("notworking", moved.kind)
        assert.is_true(moved.details:find("## User Note") ~= nil)
        assert.is_true(moved.details:find("Fails when the cache is cold%.") ~= nil)
        assert.is_true(moved.details:find("## Implementation Details") ~= nil)
        assert.is_true(moved.details:find("implementation complete") ~= nil)
        assert.are.equal(nil, moved.history_summary)
        assert.are.same({}, moved.history_commits)
    end)

    it("coerces non-string rewind fields before trimming them", function()
        local item = queue:add_todo(project, {
            title = "fix prompt flow",
            details = "return to queued",
            queue = "queued",
            kind = "todo",
        })
        queue:advance(project, item.id)
        local timer = vim.uv.new_timer()
        queue:update_implemented_item(project, item.id, {
            summary = timer,
            completed_at = "2026-01-01T00:00:00Z",
        })

        actions:rewind_queue_item(project, item.id, {
            queue = "implemented",
            mark_not_working = true,
            note = timer,
        })

        local queue_name, _, moved = queue:find_item(project, item.id)
        timer:close()

        assert.are.equal("queued", queue_name)
        assert.are.equal("notworking", moved.kind)
        assert.is_true(moved.details:find("## User Note") ~= nil)
        assert.is_true(moved.details:find("uv_timer") ~= nil)
    end)

    it("does not leak vim.NIL into not-working prompt details", function()
        local item = queue:add_todo(project, {
            title = "fix prompt flow",
            details = "",
            queue = "queued",
            kind = "todo",
        })
        queue:advance(project, item.id)
        queue:update_implemented_item(project, item.id, {
            summary = "implemented",
            completed_at = "2026-01-01T00:00:00Z",
        })
        local _, _, implemented = queue:find_item(project, item.id)
        implemented.details = vim.NIL

        actions:rewind_queue_item(project, item.id, {
            queue = "implemented",
            mark_not_working = true,
        })

        local queue_name, _, moved = queue:find_item(project, item.id)

        assert.are.equal("queued", queue_name)
        assert.are.equal("notworking", moved.kind)
        assert.is_nil(moved.details:match("vim%.NIL"))
    end)

    it("moves a history item to another project when the source queue is specified", function()
        local item = queue:add_todo(project, {
            title = "share prompt",
            queue = "queued",
            kind = "todo",
        })
        local created_at = item.created_at
        queue:advance(project, item.id)
        queue:update_implemented_item(project, item.id, {
            summary = "done",
        })
        queue:advance(project, item.id)

        actions:move_queue_item_to_project(project, item.id, target_project, {
            source_queue = "history",
            target_queue = "queued",
        })

        local source_queue_name = queue:find_item(project, item.id)
        local target_queues = queue:queues(target_project)

        assert.are.equal(nil, source_queue_name)
        assert.are.equal(1, #target_queues.queued)
        assert.are.equal(item.id, target_queues.queued[1].id)
        assert.are.equal(created_at, target_queues.queued[1].created_at)
        assert.are.equal("share prompt", target_queues.queued[1].title)
        assert.are.equal(nil, target_queues.queued[1].history_summary)
        assert.are.equal(0, #target_queues.history)
        assert.are.equal(1, refresh_count)
    end)

    it("keeps a queued item in queued when dispatching interactively", function()
        local item = queue:add_todo(project, {
            title = "stay queued",
            queue = "queued",
            kind = "todo",
        })
        local dispatched_project
        local dispatched_item
        local remembered_project

        actions.dispatch_item = function(_, queued_project, queued_item)
            dispatched_project = queued_project
            dispatched_item = queued_item
            return true
        end
        actions.remember_workspace_revision = function(_, queued_project)
            remembered_project = queued_project
        end

        local ok = actions:implement_queue_item(project, item.id)
        local queue_name, _, current_item = queue:find_item(project, item.id)

        assert.is_true(ok)
        assert.are.same(project, dispatched_project)
        assert.are.same(item.id, dispatched_item.id)
        assert.are.equal("queued", queue_name)
        assert.are.equal(item.id, current_item.id)
        assert.are.same(project, remembered_project)
        assert.are.equal(1, refresh_count)
    end)

    it("moves a planned item to queued before dispatching interactively", function()
        local item = queue:add_todo(project, {
            title = "planned first",
            queue = "planned",
            kind = "todo",
        })
        local dispatched_project
        local dispatched_item
        local remembered_project

        actions.dispatch_item = function(_, queued_project, queued_item)
            dispatched_project = queued_project
            dispatched_item = queued_item
            return true
        end
        actions.remember_workspace_revision = function(_, queued_project)
            remembered_project = queued_project
        end

        local ok = actions:implement_queue_item(project, item.id)
        local queue_name, _, current_item = queue:find_item(project, item.id)

        assert.is_true(ok)
        assert.are.same(project, dispatched_project)
        assert.are.same(item.id, dispatched_item.id)
        assert.are.equal("queued", queue_name)
        assert.are.equal(item.id, current_item.id)
        assert.are.equal(nil, current_item.execution_instructions)
        assert.are.same(project, remembered_project)
        assert.are.equal(1, refresh_count)
    end)

    it("prioritizes the selected queued item before dispatching it", function()
        local first = queue:add_todo(project, {
            title = "first queued",
            queue = "queued",
            kind = "todo",
        })
        local second = queue:add_todo(project, {
            title = "second queued",
            queue = "queued",
            kind = "todo",
        })
        local dispatched_item

        actions.dispatch_item = function(_, _, queued_item)
            dispatched_item = queued_item
            return true
        end

        local ok = actions:implement_queue_item(project, second.id)
        local queued = queue:queue(project, "queued")

        assert.is_true(ok)
        assert.are.equal(second.id, dispatched_item.id)
        assert.are.equal(second.id, queued[1].id)
        assert.are.equal(first.id, queued[2].id)
    end)

    it("queues creator implement submissions at the front before starting them", function()
        local existing = queue:add_todo(project, {
            title = "existing queued work",
            queue = "queued",
            kind = "todo",
        })
        local started_item_id

        actions.start_queued_item = function(_, _, item_id)
            started_item_id = item_id
            return true
        end
        actions.app.prompt_actions = {
            normalize_spec = function(_, _, spec)
                return spec
            end,
        }

        local item = actions:add_project_todo(project, {
            title = "new implement item",
            kind = "todo",
        }, {
            queue = "queued",
            implement = true,
            run_mode = "interactive",
        })
        local queued = queue:queue(project, "queued")

        assert.are.equal(item.id, started_item_id)
        assert.are.equal(item.id, queued[1].id)
        assert.are.equal(existing.id, queued[2].id)
    end)

    it("still dispatches a queued item while the project is already working", function()
        local item = queue:add_todo(project, {
            title = "queued while busy",
            queue = "queued",
            kind = "todo",
        })
        local dispatched_project
        local dispatched_item

        actions.app.is_project_working = function()
            return true
        end
        actions.dispatch_item = function(_, queued_project, queued_item)
            dispatched_project = queued_project
            dispatched_item = queued_item
            return true
        end

        local ok, status = actions:implement_queue_item(project, item.id)

        assert.is_true(ok)
        assert.are.equal("started", status)
        assert.are.same(project, dispatched_project)
        assert.are.same(item.id, dispatched_item.id)
        assert.are.equal("queued", queue:find_item(project, item.id))
        assert.are.equal(1, refresh_count)
    end)

    it("still dispatches a planned item while the project is already working", function()
        local item = queue:add_todo(project, {
            title = "planned while busy",
            queue = "planned",
            kind = "todo",
        })
        local dispatched_project
        local dispatched_item

        actions.app.is_project_working = function()
            return true
        end
        actions.dispatch_item = function(_, queued_project, queued_item)
            dispatched_project = queued_project
            dispatched_item = queued_item
            return true
        end

        local ok, status = actions:implement_queue_item(project, item.id)
        local queue_name, _, current_item = queue:find_item(project, item.id)

        assert.is_true(ok)
        assert.are.equal("started", status)
        assert.are.same(project, dispatched_project)
        assert.are.same(item.id, dispatched_item.id)
        assert.are.equal("queued", queue_name)
        assert.are.equal(item.id, current_item.id)
        assert.are.equal(nil, current_item.execution_instructions)
        assert.are.equal(1, refresh_count)
    end)

    it("moves all queued items to dispatched but keeps them in queued for interactive mode", function()
        local first = queue:add_todo(project, {
            title = "first",
            queue = "queued",
            kind = "todo",
        })
        local second = queue:add_todo(project, {
            title = "second",
            queue = "queued",
            kind = "todo",
        })
        local dispatched_ids = {}
        local remembered_project

        actions.dispatch_item = function(_, queued_project, queued_item)
            assert.are.same(project, queued_project)
            dispatched_ids[#dispatched_ids + 1] = queued_item.id
            return true
        end
        actions.remember_workspace_revision = function(_, queued_project)
            remembered_project = queued_project
        end

        actions:implement_queued_items(project)

        assert.are.same({ first.id, second.id }, dispatched_ids)
        assert.are.equal("queued", queue:find_item(project, first.id))
        assert.are.equal("queued", queue:find_item(project, second.id))
        assert.are.same(project, remembered_project)
        assert.are.equal(1, refresh_count)
    end)

    it("keeps a queued item queued before dispatching in exec mode", function()
        local item = queue:add_todo(project, {
            title = "exec mode",
            queue = "queued",
            kind = "todo",
        })
        local started_project
        local started_item
        local remembered_project

        actions.app.exec_runner = {
            start = function(_, project, item)
                started_project = project
                started_item = item
                return true
            end,
        }
        actions.app.project_details_store = {
            touch_activity = function() end,
        }
        actions.remember_workspace_revision = function(_, queued_project)
            remembered_project = queued_project
        end

        local ok = actions:start_queued_item(project, item.id, "exec")
        local queue_name, _, current_item = queue:find_item(project, item.id)

        assert.is_true(ok)
        assert.are.same(project, started_project)
        assert.are.same(item.id, started_item.id)
        assert.are.equal("queued", queue_name)
        assert.are.equal(item.id, current_item.id)
        assert.are.same(project, remembered_project)
    end)

    it("keeps a queued item queued when exec dispatch fails", function()
        local item = queue:add_todo(project, {
            title = "retry later",
            queue = "queued",
            kind = "todo",
        })

        actions.app.exec_runner = {
            start = function()
                return false
            end,
        }
        actions.dispatch_item = function()
            return false
        end

        local ok = actions:start_queued_item(project, item.id, "exec")
        local queue_name, _, current_item = queue:find_item(project, item.id)

        assert.is_false(ok)
        assert.are.equal("queued", queue_name)
        assert.are.equal(item.id, current_item.id)
        assert.are.equal(nil, current_item.history_summary)
        assert.are.equal(nil, current_item.execution_instructions)
        assert.are.equal(0, refresh_count)
    end)

    it("falls back to interactive dispatch when exec dispatch fails", function()
        local item = queue:add_todo(project, {
            title = "fallback to chat",
            queue = "queued",
            kind = "todo",
        })
        local dispatched_project
        local dispatched_item

        actions.app.exec_runner = {
            start = function()
                return false
            end,
        }
        actions.dispatch_item = function(_, queued_project, queued_item)
            dispatched_project = queued_project
            dispatched_item = queued_item
            return true
        end

        local ok = actions:start_queued_item(project, item.id, "exec")
        local queue_name, _, current_item = queue:find_item(project, item.id)

        assert.is_true(ok)
        assert.are.same(project, dispatched_project)
        assert.are.same(item.id, dispatched_item.id)
        assert.are.equal("queued", queue_name)
        assert.are.equal(item.id, current_item.id)
    end)

    it("keeps a queued item in queued when interactive dispatch fails", function()
        local item = queue:add_todo(project, {
            title = "stay queued on fail",
            queue = "queued",
            kind = "todo",
        })

        actions.dispatch_item = function()
            return false
        end

        local ok = actions:implement_queue_item(project, item.id)
        local queue_name, _, current_item = queue:find_item(project, item.id)

        assert.is_false(ok)
        assert.are.equal("queued", queue_name)
        assert.are.equal(item.id, current_item.id)
        assert.are.equal(nil, current_item.history_summary)
        assert.are.equal(nil, current_item.execution_instructions)
        assert.are.equal(0, refresh_count)
    end)

    it("keeps a planned item queued when interactive dispatch fails after promotion", function()
        local item = queue:add_todo(project, {
            title = "planned fail",
            queue = "planned",
            kind = "todo",
        })

        actions.dispatch_item = function()
            return false
        end

        local ok = actions:implement_queue_item(project, item.id)
        local queue_name, _, current_item = queue:find_item(project, item.id)

        assert.is_false(ok)
        assert.are.equal("queued", queue_name)
        assert.are.equal(item.id, current_item.id)
        assert.are.equal(nil, current_item.execution_instructions)
        assert.are.equal(1, refresh_count)
    end)
end)
