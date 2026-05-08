local Config = require("clodex.config")
local Commands = require("clodex.commands")
local Preview = require("clodex.ui.state_preview")
local fs = require("clodex.util.fs")

local function disabled_keymaps()
    return {
        toggle = false,
        queue_workspace = false,
        state_preview = false,
        mini_state_preview = false,
        backend_toggle = false,
        chat_toggle = false,
        refresh = false,
        new_bug_prompt = false,
        new_improvement_prompt = false,
        go_to_readme = false,
    }
end

local function temp_dir()
    local dir = vim.fn.tempname()
    fs.ensure_dir(dir)
    return dir
end

local function action_by_lhs(actions, lhs)
    for _, action in ipairs(actions) do
        if action.lhs == lhs then
            return action
        end
    end
end

describe("clodex.ui.state_preview", function()
    after_each(function()
        Commands.register_keymaps({ keymaps = disabled_keymaps() })
        for _, name in ipairs({ "clodex-state-preview-state", "clodex-state-preview-commands" }) do
            local bufnr = vim.fn.bufnr(name)
            if bufnr > 0 and vim.api.nvim_buf_is_valid(bufnr) then
                pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
            end
        end
    end)

    it("shows prompt skill details in the state panel", function()
        local root = temp_dir()
        local skill_file = fs.join(root, "skills", "prompt-nvim-clodex", "SKILL.md")
        fs.write_file(skill_file, "---\nname: prompt-nvim-clodex\n---\nSkill body\n")

        local preview = Preview.new(Config.new():setup())
        Commands.register_keymaps(preview.config)
        preview:ensure_buffers()
        preview.app = {
            queue_summary = function()
                return {
                    counts = {
                        planned = 1,
                        queued = 2,
                        implemented = 3,
                        history = 4,
                    },
                    active_item_title = "Implement parser retry flow",
                    queue_loop_enabled = true,
                    last_updated_at = "2026-03-19T04:00:00Z",
                }
            end,
            terminals = {
                snapshot = function()
                    return {
                        {
                            key = "project:" .. root,
                            kind = "project",
                            cwd = root,
                            title = "Clodex: Demo",
                            project_root = root,
                            buf = 11,
                            buffer_valid = true,
                            job_id = 22,
                            running = true,
                            waiting_state = nil,
                            last_cli_line = "ready",
                            terminal_provider = "term",
                            env_keys = { "OPENCODE_CONFIG" },
                            active_queue_item_id = "item-1",
                            active_queue_item_title = "Implement parser retry flow",
                            queue_loop_enabled = true,
                        },
                    }
                end,
            },
            execution = {
                uses_prompt_skill = function()
                    return true
                end,
                skill_file = function()
                    return skill_file
                end,
            },
        }

        preview:render_state({
            backend = "opencode",
            current_tab = {
                tabpage = 1,
                has_visible_window = true,
                session_key = "project:" .. root,
                window_id = 1,
            },
            sessions = {
                {
                    key = "free:" .. root,
                    kind = "free",
                    cwd = root,
                    title = "OpenCode",
                    project_root = nil,
                    buf = 7,
                    buffer_valid = true,
                    job_id = 33,
                    running = true,
                    waiting_state = "question",
                    last_cli_line = "Which file should I open?",
                    terminal_provider = "snacks",
                    env_keys = {},
                    active_queue_item_id = nil,
                    active_queue_item_title = nil,
                    queue_loop_enabled = false,
                },
            },
            current_path = root,
            active_project = {
                name = "Demo",
                root = root,
            },
            detected_project = nil,
            resolved_target = {
                kind = "project",
                project = {
                    name = "Demo",
                    root = root,
                },
            },
            runtime_projects = {
                {
                    name = "Demo",
                    root = root,
                },
            },
            runtime_project_states = {
                {
                    project = {
                        name = "Demo",
                        root = root,
                    },
                    session_active = true,
                    window_open_in_active_tab = true,
                    usage_events = "not tracked yet",
                    working = "session alive",
                    runtime_sources = { "active", "target", "session" },
                    bookmark_count = 0,
                    notes_count = 0,
                    cheatsheet_count = 0,
                    cheatsheet_items = {},
                },
            },
            tabs = {},
        })

        local lines = vim.api.nvim_buf_get_lines(preview.state_buf, 0, -1, false)
        assert.is_true(vim.tbl_contains(lines, "backend:             OpenCode"))
        assert.is_true(vim.tbl_contains(lines, "runtime projects:    1"))
        assert.is_true(vim.tbl_contains(lines, "queues:              planned=1 queued=2 implemented=3 history=4"))
        assert.is_true(vim.tbl_contains(lines, "session:             session alive"))
        assert.is_true(vim.tbl_contains(lines, "  last line:         Which file should I open?"))
        assert.is_true(vim.tbl_contains(lines, "Keymaps"))
        assert.is_true(vim.tbl_contains(lines, "> Global"))
        assert.is_true(vim.tbl_contains(lines, "  [n] <leader>ps  Clodex: Toggle Codex state preview panel"))
        assert.is_true(vim.tbl_contains(lines, "Prompt Skill"))
        assert.is_true(vim.tbl_contains(lines, "status:              synced"))
        assert.is_true(vim.tbl_contains(lines, "  ---"))
        assert.is_true(vim.tbl_contains(lines, "  name: prompt-nvim-clodex"))
        assert.is_true(vim.tbl_contains(lines, "  Skill body"))

        fs.remove(root)
    end)

    it("formats last queue update using configured queue date format", function()
        local preview = Preview.new(Config.new():setup({
            queue_workspace = {
                date_format = "dd.MM.yyyy hh:mm",
            },
        }))
        preview:ensure_buffers()
        preview.app = {
            queue_summary = function()
                return {
                    counts = {
                        planned = 0,
                        queued = 0,
                        implemented = 0,
                        history = 0,
                    },
                    last_updated_at = "2026-05-08T05:53:33Z",
                }
            end,
            terminals = {
                snapshot = function()
                    return {}
                end,
            },
            execution = {
                uses_prompt_skill = function()
                    return false
                end,
            },
        }

        preview:render_state({
            backend = "codex",
            current_tab = {
                tabpage = 1,
                has_visible_window = false,
                session_key = nil,
            },
            sessions = {},
            current_path = "/tmp",
            active_project = {
                name = "Demo",
                root = "/tmp/demo",
            },
            detected_project = nil,
            resolved_target = {
                kind = "project",
                project = {
                    name = "Demo",
                    root = "/tmp/demo",
                },
            },
            runtime_projects = {
                {
                    name = "Demo",
                    root = "/tmp/demo",
                },
            },
            runtime_project_states = {},
            tabs = {},
        })

        local lines = vim.api.nvim_buf_get_lines(preview.state_buf, 0, -1, false)
        local value = nil
        for _, line in ipairs(lines) do
            if vim.startswith(line, "last queue update:") then
                value = vim.trim(line:sub(#("last queue update:") + 1))
                break
            end
        end

        assert.is_not_nil(value)
        assert.is_true(value ~= "2026-05-08T05:53:33Z")
        assert.is_truthy(value:match("^%d%d%.%d%d%.%d%d%d%d %d%d:%d%d$"))
    end)

    it("renders the command pane with bare command names only", function()
        local preview = Preview.new(Config.new():setup())
        preview:ensure_buffers()

        preview:render_commands()

        local lines = vim.api.nvim_buf_get_lines(preview.command_buf, 0, -1, false)

        assert.is_true(#lines > 0)
        assert.is_true(vim.startswith(lines[1], "Clodex"))
        assert.is_nil(lines[1]:find(":", 1, true))
        assert.is_nil(lines[1]:find("  ", 1, true))
    end)

    it("selects command and state panel items with the mouse", function()
        local preview = Preview.new(Config.new():setup())
        preview.commands = {
            { name = "Clodex" },
            { name = "ClodexProject" },
            { name = "ClodexDebug" },
        }
        preview.command_win = 101
        preview.state_win = 202
        preview.command_index = 1

        local original_getmousepos = vim.fn.getmousepos
        vim.fn.getmousepos = function()
            return {
                winid = preview.command_win,
                line = 3,
            }
        end
        local click = action_by_lhs(preview:common_actions(), "<LeftMouse>")
        assert.is_not_nil(click)
        click.callback()

        assert.are.equal("commands", preview.focus)
        assert.are.equal(3, preview.command_index)

        vim.fn.getmousepos = function()
            return {
                winid = preview.state_win,
                line = 1,
            }
        end
        click.callback()

        assert.are.equal("state", preview.focus)
        assert.are.equal(3, preview.command_index)

        vim.fn.getmousepos = original_getmousepos
    end)

    it("runs command panel items on double mouse click", function()
        local preview = Preview.new(Config.new():setup())
        preview.commands = {
            { name = "Clodex" },
            { name = "ClodexProject" },
        }
        preview.command_win = 303
        preview.command_index = 1

        local executed_index
        preview.execute_selected_command = function(self)
            executed_index = self.command_index
        end

        local original_getmousepos = vim.fn.getmousepos
        vim.fn.getmousepos = function()
            return {
                winid = preview.command_win,
                line = 2,
            }
        end
        local double_click = action_by_lhs(preview:command_actions(), "<2-LeftMouse>")
        assert.is_not_nil(double_click)
        double_click.callback()

        assert.are.equal(2, preview.command_index)
        assert.are.equal(2, executed_index)

        vim.fn.getmousepos = original_getmousepos
    end)
end)
