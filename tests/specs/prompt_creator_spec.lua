local function wait_for(predicate)
    assert(vim.wait(1000, predicate, 10), "timed out waiting for prompt creator state")
end

local function extmark_groups(buf)
    local groups = {}
    for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(buf, -1, 0, -1, { details = true })) do
        groups[#groups + 1] = mark[4].hl_group
    end
    return groups
end

local function trigger_buffer_mapping(buf, lhs, mode)
    local map = vim.fn.maparg(lhs, mode or "n", false, true)
    assert.is_table(map)
    assert.is_function(map.callback)
    return map.callback()
end

describe("clodex.ui.prompt_creator", function()
    local Creator
    local creator
    local opened_windows
    local original_ui_win
    local original_notify
    local original_pumvisible
    local original_snacks

    before_each(function()
        package.loaded["clodex.ui.prompt_creator"] = nil
        package.loaded["clodex.ui.prompt_creator.layouts.composer"] = nil
        package.loaded["clodex.ui.prompt_creator.layouts.clipboard_preview"] = nil
        package.loaded["snacks.input"] = {
            input = function() end,
        }
        package.loaded["snacks.picker.select"] = {
            select = function(_items, _opts, on_choice)
                on_choice(nil)
            end,
        }

        original_ui_win = package.loaded["clodex.ui.win"]
        original_notify = package.loaded["clodex.util.notify"]
        original_snacks = package.loaded["snacks"]
        original_pumvisible = vim.fn.pumvisible
        opened_windows = {}

        package.loaded["clodex.ui.win"] = {
            create_buffer = function(opts)
                local buf = vim.api.nvim_create_buf(false, true)
                local preset = opts and opts.preset or "scratch"
                if preset == "markdown" then
                    vim.bo[buf].filetype = "markdown"
                    vim.bo[buf].modifiable = true
                elseif preset == "text" then
                    vim.bo[buf].modifiable = true
                else
                    vim.bo[buf].modifiable = false
                end
                vim.bo[buf].buftype = "nofile"
                vim.bo[buf].bufhidden = "wipe"
                vim.bo[buf].swapfile = false
                for key, value in pairs(opts and opts.bo or {}) do
                    vim.bo[buf][key] = value
                end
                return buf
            end,
            is_valid = function(win)
                return type(win) == "number" and win > 0 and vim.api.nvim_win_is_valid(win)
            end,
            close = function(win)
                if type(win) == "number" and win > 0 and vim.api.nvim_win_is_valid(win) then
                    vim.api.nvim_win_close(win, true)
                end
            end,
            apply_theme = function(win, theme)
                if type(win) ~= "number" or win <= 0 or not vim.api.nvim_win_is_valid(win) then
                    return
                end
                if theme == "prompt_editor" or theme == "prompt_footer" then
                    vim.wo[win].winhl = table.concat({
                        "FloatBorder:ClodexPromptEditorBorder",
                        "FloatTitle:ClodexPromptEditorTitle",
                    }, ",")
                end
            end,
            open = function(opts)
                local object = {
                    buf = opts.buf,
                    opts = opts,
                }
                object.win = vim.api.nvim_open_win(opts.buf, opts.enter or false, {
                    relative = "editor",
                    style = "minimal",
                    border = opts.border or "none",
                    title = opts.title,
                    title_pos = opts.title_pos,
                    row = type(opts.row) == "function" and opts.row() or opts.row or 0,
                    col = type(opts.col) == "function" and opts.col() or opts.col or 0,
                    width = type(opts.width) == "function" and opts.width() or opts.width or 1,
                    height = type(opts.height) == "function" and opts.height() or opts.height or 1,
                })

                for key, value in pairs(opts.bo or {}) do
                    vim.bo[opts.buf][key] = value
                end
                if opts.theme == "prompt_editor" or opts.theme == "prompt_footer" then
                    vim.wo[object.win].winhl = table.concat({
                        "FloatBorder:ClodexPromptEditorBorder",
                        "FloatTitle:ClodexPromptEditorTitle",
                    }, ",")
                end

                function object:valid()
                    return type(self.win) == "number" and self.win > 0 and vim.api.nvim_win_is_valid(self.win)
                end

                function object:update()
                    if not self:valid() then
                        return
                    end
                    vim.api.nvim_win_set_config(self.win, {
                        relative = "editor",
                        row = type(self.opts.row) == "function" and self.opts.row() or self.opts.row or 0,
                        col = type(self.opts.col) == "function" and self.opts.col() or self.opts.col or 0,
                        width = type(self.opts.width) == "function" and self.opts.width() or self.opts.width or 1,
                        height = type(self.opts.height) == "function" and self.opts.height() or self.opts.height or 1,
                    })
                    if self.opts.theme == "prompt_editor" or self.opts.theme == "prompt_footer" then
                        vim.wo[self.win].winhl = table.concat({
                            "FloatBorder:ClodexPromptEditorBorder",
                            "FloatTitle:ClodexPromptEditorTitle",
                        }, ",")
                    end
                end

                function object:close()
                    if self:valid() then
                        vim.api.nvim_win_close(self.win, true)
                        self.win = nil
                    end
                end

                opened_windows[#opened_windows + 1] = object
                return object
            end,
        }
        package.loaded["clodex.util.notify"] = {
            notify = function() end,
            warn = function() end,
        }

        Creator = require("clodex.ui.prompt_creator")
    end)

    after_each(function()
        if creator then
            pcall(function()
                creator:close()
            end)
        end
        for _, window in ipairs(opened_windows or {}) do
            if window:valid() then
                window:close()
            end
        end

        package.loaded["clodex.ui.prompt_creator"] = nil
        package.loaded["clodex.ui.prompt_creator.layouts.composer"] = nil
        package.loaded["clodex.ui.prompt_creator.layouts.clipboard_preview"] = nil
        package.loaded["snacks.input"] = nil
        package.loaded["snacks.picker.select"] = nil
        package.loaded["snacks"] = original_snacks
        package.loaded["clodex.ui.win"] = original_ui_win
        package.loaded["clodex.util.notify"] = original_notify
        vim.fn.pumvisible = original_pumvisible
    end)

    it("closes the footer when a prompt editor window is destroyed", function()
        creator = Creator.open({
            app = {
                config = {
                    get = function()
                        return {
                            storage = { workspaces_dir = "/tmp" },
                        }
                    end,
                },
            },
            project = {
                name = "Demo",
                root = "/tmp/demo",
            },
            initial_kind = "todo",
            on_submit = function() end,
        })

        local title_win = creator.layout.title_win
        local footer_win = creator.footer_win

        assert.is_true(title_win:valid())
        assert.is_true(footer_win:valid())

        vim.api.nvim_win_close(title_win.win, true)

        wait_for(function()
            return creator.footer_win == nil and creator.kind_win == nil and creator.layout.title_win == nil
        end)
    end)

    it("closes the footer when a destroyed prompt window handle becomes vim.NIL", function()
        creator = Creator.open({
            app = {
                config = {
                    get = function()
                        return {
                            storage = { workspaces_dir = "/tmp" },
                        }
                    end,
                },
            },
            project = {
                name = "Demo",
                root = "/tmp/demo",
            },
            initial_kind = "todo",
            on_submit = function() end,
        })

        local title_win = creator.layout.title_win

        assert.is_true(title_win:valid())

        vim.api.nvim_win_close(title_win.win, true)
        title_win.win = vim.NIL

        wait_for(function()
            return creator.footer_win == nil and creator.kind_win == nil and creator.layout.title_win == nil
        end)
    end)

    it("closes the footer even when wrapper close methods do nothing", function()
        creator = Creator.open({
            app = {
                config = {
                    get = function()
                        return {
                            storage = { workspaces_dir = "/tmp" },
                        }
                    end,
                },
            },
            project = {
                name = "Demo",
                root = "/tmp/demo",
            },
            initial_kind = "todo",
            on_submit = function() end,
        })

        creator.footer_win.close = function() end
        creator.kind_win.close = function() end
        creator.project_win.close = function() end

        vim.api.nvim_win_close(creator.layout.title_win.win, true)

        wait_for(function()
            return creator.footer_win == nil and creator.kind_win == nil and creator.project_win == nil
        end)
    end)

    it("renders active and inactive tab highlights", function()
        creator = Creator.open({
            app = {
                config = {
                    get = function()
                        return {
                            storage = { workspaces_dir = "/tmp" },
                        }
                    end,
                },
            },
            project = {
                name = "Demo",
                root = "/tmp/demo",
            },
            initial_kind = "todo",
            on_submit = function() end,
        })

        local groups = extmark_groups(creator.kind_buf)

        assert.is_true(vim.tbl_contains(groups, "ClodexPromptImprovementTitleActive"))
        assert.is_false(vim.tbl_contains(groups, "ClodexPromptImprovementKindName"))
        assert.is_true(vim.tbl_contains(groups, "ClodexPromptBugKindName"))
    end)

    it("centers tab rows and removes tab borders", function()
        creator = Creator.open({
            app = {
                config = {
                    get = function()
                        return {
                            storage = { workspaces_dir = "/tmp" },
                        }
                    end,
                },
            },
            project = {
                name = "Demo",
                root = "/tmp/demo",
            },
            initial_kind = "bug",
            on_submit = function() end,
        })

        local kind_line = vim.api.nvim_buf_get_lines(creator.kind_buf, 0, 1, false)[1]
        local kind_cfg = vim.api.nvim_win_get_config(creator.kind_win.win)
        local variant_cfg = vim.api.nvim_win_get_config(creator.variant_win.win)
        local title_cfg = vim.api.nvim_win_get_config(creator.layout.title_win.win)

        assert.are.equal("none", creator.kind_win.opts.border)
        assert.are.equal("none", creator.variant_win.opts.border)
        assert.are.equal(title_cfg.col - 1, kind_cfg.col)
        assert.are.equal(title_cfg.width + 2, kind_cfg.width)
        assert.are.equal(title_cfg.col - 1, variant_cfg.col)
        assert.are.equal(title_cfg.width + 2, variant_cfg.width)
        assert.is_truthy(kind_line:match("^%s+"))
        assert.is_truthy(kind_line:match("%s+$"))
    end)

    it("starts new prompts with a blank title field", function()
        creator = Creator.open({
            app = {
                config = {
                    get = function()
                        return {
                            storage = { workspaces_dir = "/tmp" },
                        }
                    end,
                },
            },
            project = {
                name = "Demo",
                root = "/tmp/demo",
            },
            initial_kind = "todo",
            on_submit = function() end,
        })

        local title = vim.api.nvim_buf_get_lines(creator.layout.title_buf, 0, 1, false)[1]

        assert.are.equal("", title)
    end)

    it("normalizes raw edit prompt drafts into title and details fields", function()
        creator = Creator.open({
            app = {
                config = {
                    get = function()
                        return {
                            storage = { workspaces_dir = "/tmp" },
                        }
                    end,
                },
            },
            project = {
                name = "Demo",
                root = "/tmp/demo",
            },
            initial_kind = "todo",
            mode = "edit",
            initial_draft = {
                title = "Wrong copied line",
                prompt = "Real title\n\nReal details\nSecond line",
            },
            on_submit = function() end,
        })

        assert.are.same({ "Real title" }, vim.api.nvim_buf_get_lines(creator.layout.title_buf, 0, -1, false))
        assert.are.same({ "Real details", "Second line" }, vim.api.nvim_buf_get_lines(creator.layout.body_buf, 0, -1, false))

        creator:close()
        creator = Creator.open({
            app = {
                config = {
                    get = function()
                        return {
                            storage = { workspaces_dir = "/tmp" },
                        }
                    end,
                },
            },
            project = {
                name = "Demo",
                root = "/tmp/demo",
            },
            initial_kind = "todo",
            mode = "edit",
            initial_draft = {
                title = "Real title\n\nReal details\nSecond line",
            },
            on_submit = function() end,
        })

        assert.are.same({ "Real title" }, vim.api.nvim_buf_get_lines(creator.layout.title_buf, 0, -1, false))
        assert.are.same({ "Real details", "Second line" }, vim.api.nvim_buf_get_lines(creator.layout.body_buf, 0, -1, false))
    end)

    it("opens with the title focused in normal mode", function()
        creator = Creator.open({
            app = {
                config = {
                    get = function()
                        return {
                            storage = { workspaces_dir = "/tmp" },
                        }
                    end,
                },
            },
            project = {
                name = "Demo",
                root = "/tmp/demo",
            },
            initial_kind = "todo",
            on_submit = function() end,
        })

        assert.are.equal(creator.layout.title_win.win, vim.api.nvim_get_current_win())
        assert.is_false(creator:in_insert_mode())
    end)

    it("keeps prompt panel highlights stable when focus moves", function()
        creator = Creator.open({
            app = {
                config = {
                    get = function()
                        return {
                            storage = { workspaces_dir = "/tmp" },
                        }
                    end,
                },
            },
            project = {
                name = "Demo",
                root = "/tmp/demo",
            },
            initial_kind = "todo",
            on_submit = function() end,
        })

        assert.is_truthy(
            vim.wo[creator.layout.title_win.win].winhl:find("NormalFloat:ClodexPromptEditorNormal", 1, true)
        )
        assert.is_truthy(
            vim.wo[creator.layout.title_win.win].winhl:find("FloatBorder:ClodexPromptImprovementTitleBorder", 1, true)
        )
        assert.is_truthy(
            vim.wo[creator.layout.title_win.win].winhl:find("FloatTitle:ClodexPromptImprovementTitleBorder", 1, true)
        )
        assert.is_truthy(
            vim.wo[creator.layout.body_win.win].winhl:find("NormalFloat:ClodexPromptEditorNormal", 1, true)
        )
        assert.is_truthy(
            vim.wo[creator.layout.body_win.win].winhl:find("FloatBorder:ClodexPromptImprovementTitleBorder", 1, true)
        )

        trigger_buffer_mapping(creator.layout.title_buf, "<Tab>")

        wait_for(function()
            return vim.api.nvim_get_current_win() == creator.layout.body_win.win
                and vim.wo[creator.layout.body_win.win].winhl:find(
                    "NormalFloat:ClodexPromptEditorNormal",
                    1,
                    true
                )
                and vim.wo[creator.layout.body_win.win].winhl:find(
                    "FloatBorder:ClodexPromptImprovementTitleBorder",
                    1,
                    true
                )
                and vim.wo[creator.layout.title_win.win].winhl:find(
                    "NormalFloat:ClodexPromptEditorNormal",
                    1,
                    true
                )
                and vim.wo[creator.layout.title_win.win].winhl:find(
                    "FloatBorder:ClodexPromptImprovementTitleBorder",
                    1,
                    true
                )
        end)
    end)

    it("keeps prompt creator buffers hidden instead of wiping them", function()
        creator = Creator.open({
            app = {
                config = {
                    get = function()
                        return {
                            storage = { workspaces_dir = "/tmp" },
                        }
                    end,
                },
            },
            project = {
                name = "Demo",
                root = "/tmp/demo",
            },
            initial_kind = "todo",
            on_submit = function() end,
        })

        assert.are.equal("hide", vim.bo[creator.project_buf].bufhidden)
        assert.are.equal("hide", vim.bo[creator.footer_buf].bufhidden)
        assert.are.equal("hide", vim.bo[creator.layout.title_buf].bufhidden)
        assert.are.equal("hide", vim.bo[creator.layout.body_buf].bufhidden)
    end)

    it("keeps bordered prompt windows vertically aligned without overlap", function()
        creator = Creator.open({
            app = {
                config = {
                    get = function()
                        return {
                            storage = { workspaces_dir = "/tmp" },
                        }
                    end,
                },
            },
            project = {
                name = "Demo",
                root = "/tmp/demo",
            },
            initial_kind = "todo",
            on_submit = function() end,
        })

        local title_cfg = vim.api.nvim_win_get_config(creator.layout.title_win.win)
        local body_cfg = vim.api.nvim_win_get_config(creator.layout.body_win.win)
        local footer_cfg = vim.api.nvim_win_get_config(creator.footer_win.win)

        local title_row = tonumber(title_cfg.row) or title_cfg.row[false]
        local body_row = tonumber(body_cfg.row) or body_cfg.row[false]
        local footer_row = tonumber(footer_cfg.row) or footer_cfg.row[false]
        local title_bottom = title_row + title_cfg.height + 1
        local body_bottom = body_row + body_cfg.height + 1

        assert.are.equal(title_bottom + 1, body_row)
        assert.are.equal(body_bottom + 1, footer_row)
    end)

    it("opens above the queue workspace panel layer", function()
        creator = Creator.open({
            app = {
                config = {
                    get = function()
                        return {
                            storage = { workspaces_dir = "/tmp" },
                        }
                    end,
                },
            },
            project = {
                name = "Demo",
                root = "/tmp/demo",
            },
            initial_kind = "todo",
            on_submit = function() end,
        })

        local background_cfg = vim.api.nvim_win_get_config(creator.project_bg_win.win)
        local title_cfg = vim.api.nvim_win_get_config(creator.layout.title_win.win)
        local footer_cfg = vim.api.nvim_win_get_config(creator.footer_win.win)

        assert.is_true((background_cfg.zindex or 0) > 56)
        assert.is_true((title_cfg.zindex or 0) > (background_cfg.zindex or 0))
        assert.are.equal(title_cfg.zindex, footer_cfg.zindex)
    end)

    it("restores the decorative background after tab focus returns", function()
        creator = Creator.open({
            app = {
                config = {
                    get = function()
                        return {
                            storage = { workspaces_dir = "/tmp" },
                        }
                    end,
                },
            },
            project = {
                name = "Demo",
                root = "/tmp/demo",
            },
            initial_kind = "todo",
            on_submit = function() end,
        })

        local background_win = creator.project_bg_win.win
        vim.api.nvim_win_close(background_win, true)

        wait_for(function()
            return creator.layout
                and creator.layout.title_win
                and creator.layout.title_win:valid()
                and creator.project_bg_win
                and not creator.project_bg_win:valid()
        end)

        vim.api.nvim_exec_autocmds("TabEnter", {})

        wait_for(function()
            return creator.project_bg_win
                and creator.project_bg_win:valid()
                and creator.project_bg_win.win ~= background_win
        end)
    end)

    it("places secondary tabs between the body and footer", function()
        creator = Creator.open({
            app = {
                config = {
                    get = function()
                        return {
                            storage = { workspaces_dir = "/tmp" },
                        }
                    end,
                },
            },
            project = {
                name = "Demo",
                root = "/tmp/demo",
            },
            initial_kind = "todo",
            on_submit = function() end,
        })

        assert.are.equal(creator:kind_row() + 2, creator:title_row())

        creator:switch_kind(1)

        wait_for(function()
            return creator.state.kind == "bug"
        end)

        assert.are.equal(creator:kind_row() + 2, creator:title_row())
        assert.is_true(creator:variant_row() > creator:body_row())
        assert.are.equal(creator:body_row() + creator:body_height() + 2, creator:variant_row())
        assert.is_true(creator:variant_row() < creator:footer_row())
    end)

    it("updates footer state from prompt editor mode events", function()
        creator = Creator.open({
            app = {
                config = {
                    get = function()
                        return {
                            storage = { workspaces_dir = "/tmp" },
                        }
                    end,
                },
            },
            project = {
                name = "Demo",
                root = "/tmp/demo",
            },
            initial_kind = "todo",
            on_submit = function() end,
        })

        local normal_lines = vim.api.nvim_buf_get_lines(creator.footer_buf, 0, -1, false)

        vim.api.nvim_exec_autocmds("InsertEnter", { buffer = creator.layout.title_buf })
        local insert_lines = vim.api.nvim_buf_get_lines(creator.footer_buf, 0, -1, false)

        vim.api.nvim_exec_autocmds("InsertLeave", { buffer = creator.layout.title_buf })
        local restored_lines = vim.api.nvim_buf_get_lines(creator.footer_buf, 0, -1, false)

        assert.is_false(vim.deep_equal(normal_lines, insert_lines))
        assert.are.same(normal_lines, restored_lines)
        assert.is_truthy(table.concat(normal_lines, "\n"):find("Tab", 1, true))
        assert.is_nil(table.concat(normal_lines, "\n"):find("S-Tab", 1, true))
        assert.is_truthy(table.concat(insert_lines, "\n"):find("S-Tab", 1, true))
        assert.is_nil(table.concat(insert_lines, "\n"):find("Tab/S-Tab", 1, true))
        assert.is_nil(table.concat(normal_lines, "\n"):find("move focus", 1, true))
        assert.is_nil(table.concat(insert_lines, "\n"):find("move focus", 1, true))
        assert.is_nil(table.concat(normal_lines, "\n"):find("kind (insert)", 1, true))
        assert.is_truthy(table.concat(insert_lines, "\n"):find("C-←/→", 1, true))
        assert.is_nil(table.concat(normal_lines, "\n"):find("plan+reset", 1, true))
        assert.is_nil(table.concat(normal_lines, "\n"):find("implement+reset", 1, true))
        assert.is_nil(table.concat(insert_lines, "\n"):find("implement+reset", 1, true))
        assert.is_truthy(table.concat(normal_lines, "\n"):find("S", 1, true))
        assert.is_truthy(table.concat(normal_lines, "\n"):find("S-.", 1, true))
        assert.is_truthy(table.concat(insert_lines, "\n"):find("C-S-.", 1, true))
    end)

    it("matches prompt border and footer keymap colors to the active kind", function()
        creator = Creator.open({
            app = {
                config = {
                    get = function()
                        return {
                            storage = { workspaces_dir = "/tmp" },
                        }
                    end,
                },
            },
            project = {
                name = "Demo",
                root = "/tmp/demo",
            },
            initial_kind = "todo",
            on_submit = function() end,
        })

        assert.is_truthy(
            vim.wo[creator.footer_win.win].winhl:find("FloatBorder:ClodexPromptImprovementTitleBorder", 1, true)
        )
        assert.is_truthy(vim.tbl_contains(extmark_groups(creator.footer_buf), "ClodexPromptImprovementTitle"))
        assert.is_truthy(
            vim.wo[creator.layout.title_win.win].winhl:find("FloatBorder:ClodexPromptImprovementTitleBorder", 1, true)
        )
        assert.is_truthy(
            vim.wo[creator.layout.body_win.win].winhl:find("FloatBorder:ClodexPromptImprovementTitleBorder", 1, true)
        )

        creator:switch_kind(1)

        wait_for(function()
            return creator.state.kind == "bug"
        end)

        assert.is_truthy(vim.wo[creator.footer_win.win].winhl:find("FloatBorder:ClodexPromptBugTitleBorder", 1, true))
        assert.is_truthy(vim.tbl_contains(extmark_groups(creator.footer_buf), "ClodexPromptBugTitle"))
        assert.is_truthy(
            vim.wo[creator.layout.title_win.win].winhl:find("FloatBorder:ClodexPromptBugTitleBorder", 1, true)
        )
        assert.is_truthy(vim.wo[creator.layout.body_win.win].winhl:find("FloatBorder:ClodexPromptBugTitleBorder", 1, true))
    end)

    it("supports context token highlighting, completion, and expansion in composer fields", function()
        local diagnostic_ns = vim.api.nvim_create_namespace("clodex-prompt-creator-context-test")
        local source_buf = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_buf_set_name(source_buf, "/tmp/demo/lua/demo.lua")
        vim.api.nvim_buf_set_lines(source_buf, 0, -1, false, {
            "local token = 1",
            "local second = token",
            "local third = token",
            "local fourth = token",
            "local fifth = token",
            "local sixth = token",
            "return token",
        })
        vim.diagnostic.set(diagnostic_ns, source_buf, {
            {
                lnum = 6,
                col = 0,
                message = "context failure",
                severity = vim.diagnostic.severity.ERROR,
            },
        })

        local submitted
        creator = Creator.open({
            app = {
                config = {
                    get = function()
                        return {
                            storage = { workspaces_dir = "/tmp" },
                        }
                    end,
                },
            },
            project = {
                name = "Demo",
                root = "/tmp/demo",
            },
            context = {
                buf = source_buf,
                file_path = "/tmp/demo/lua/demo.lua",
                project_root = "/tmp/demo",
                relative_path = "lua/demo.lua",
                cursor_row = 7,
                current_word = "token",
                visible_start = 1,
                visible_end = 7,
                selection_start_row = 1,
                selection_end_row = 2,
                selection_text = "local token = 1\nlocal second = token",
            },
            initial_kind = "todo",
            initial_draft = {
                title = "Explain &line",
                details = table.concat({
                    "&file",
                    "&selection",
                    "&visible_buff",
                    "&word",
                    "&diagnostic",
                    "&buff_diagnostics",
                    "&all_diagnostics",
                }, "\n"),
            },
            on_submit = function(spec)
                submitted = spec
                return { id = "queued-item" }
            end,
        })

        local title_buf = creator.layout.title_buf
        local body_buf = creator.layout.body_buf
        local title_groups = extmark_groups(title_buf)
        local body_groups = extmark_groups(body_buf)

        assert.is_false(vim.tbl_contains(title_groups, "ClodexPromptEditorContext"))
        assert.are.equal(7, vim.tbl_count(vim.tbl_filter(function(group)
            return group == "ClodexPromptEditorContext"
        end, body_groups)))

        vim.api.nvim_set_current_win(creator.layout.title_win.win)
        vim.api.nvim_win_set_cursor(creator.layout.title_win.win, { 1, 11 })

        local title_items = require("clodex.ui.select").prompt_context_complete(0, "&l")
        assert.are.equal(0, #title_items)

        vim.api.nvim_set_current_win(creator.layout.body_win.win)
        vim.api.nvim_win_set_cursor(creator.layout.body_win.win, { 7, 16 })

        local items = require("clodex.ui.select").prompt_context_complete(0, "&")
        local words = vim.tbl_map(function(item)
            return item.word
        end, items)

        for _, token in ipairs({
            "&file",
            "&line",
            "&selection",
            "&visible_buff",
            "&word",
            "&diagnostic",
            "&buff_diagnostics",
            "&all_diagnostics",
        }) do
            assert.is_true(vim.tbl_contains(words, token), token)
        end

        local body_ampersand
        for _, map in ipairs(vim.api.nvim_buf_get_keymap(body_buf, "i")) do
            if map.lhs == "&" then
                body_ampersand = map.callback
            end
        end
        assert.is_function(body_ampersand)
        assert.are.equal("&" .. vim.keycode("<C-x><C-u>"), body_ampersand())
        for _, map in ipairs(vim.api.nvim_buf_get_keymap(title_buf, "i")) do
            assert.are_not.equal("&", map.lhs)
        end

        creator:submit("queue")

        wait_for(function()
            return submitted ~= nil
        end)

        assert.are.equal("Explain &line", submitted.title)
        assert.matches("Inserted context from &file", submitted.details)
        assert.matches("Inserted context from &selection", submitted.details)
        assert.matches("Inserted context from &visible_buff", submitted.details)
        assert.matches("Inserted context from &word", submitted.details)
        assert.matches("Inserted context from &diagnostic", submitted.details)
        assert.matches("Inserted context from &buff_diagnostics", submitted.details)
        assert.matches("Inserted context from &all_diagnostics", submitted.details)
        assert.matches("context failure", submitted.details)

        vim.diagnostic.reset(diagnostic_ns, source_buf)
    end)

    it("changes kind tabs from the footer and keeps normal-mode focus in the editor", function()
        creator = Creator.open({
            app = {
                config = {
                    get = function()
                        return {
                            storage = { workspaces_dir = "/tmp" },
                        }
                    end,
                },
            },
            project = {
                name = "Demo",
                root = "/tmp/demo",
            },
            initial_kind = "todo",
            on_submit = function() end,
        })

        vim.api.nvim_set_current_win(creator.layout.body_win.win)
        vim.cmd.stopinsert()
        creator:switch_kind(1)

        wait_for(function()
            return creator.state.kind == "bug"
                and creator.layout.body_win
                and creator.layout.body_win:valid()
                and creator.project_bg_win
                and creator.project_bg_win:valid()
                and vim.api.nvim_get_current_win() == creator.layout.body_win.win
                and vim.api.nvim_get_mode().mode == "n"
        end)

        local background_config = vim.api.nvim_win_get_config(creator.project_bg_win.win)
        assert.are.equal(creator:project_background_width(), background_config.width)
        assert.are.equal(creator:project_background_height(), background_config.height)

        vim.api.nvim_set_current_win(creator.layout.title_win.win)
        vim.cmd.startinsert()
        vim.cmd.stopinsert()
        trigger_buffer_mapping(creator.layout.title_buf, "<Right>")

        wait_for(function()
            return creator.state.kind == "freeform"
                and vim.api.nvim_get_current_win() == creator.layout.title_win.win
                and vim.api.nvim_get_mode().mode == "n"
        end)

        trigger_buffer_mapping(creator.layout.title_buf, "<C-Left>")

        wait_for(function()
            return creator.state.kind == "bug"
                and vim.api.nvim_get_current_win() == creator.layout.title_win.win
                and vim.api.nvim_get_mode().mode == "n"
        end)

        trigger_buffer_mapping(creator.layout.title_buf, "<C-Right>")

        wait_for(function()
            return creator.state.kind == "freeform"
                and vim.api.nvim_get_current_win() == creator.layout.title_win.win
                and vim.api.nvim_get_mode().mode == "n"
        end)

        local footer_maps = vim.api.nvim_buf_get_keymap(creator.footer_buf, "n")
        local footer_insert_maps = vim.api.nvim_buf_get_keymap(creator.footer_buf, "i")
        local has_right_switch = false
        local has_left_switch = false
        local has_control_right_switch = false
        local has_control_left_switch = false
        local has_h_switch = false
        local has_l_switch = false
        local has_old_left_switch = false
        local has_implement_action = false
        local has_insert_left_switch = false
        local has_insert_right_switch = false

        for _, map in ipairs(footer_maps) do
            if map.lhs == "<Right>" then
                has_right_switch = true
            elseif map.lhs == "<Left>" then
                has_left_switch = true
            elseif map.lhs == "<C-Right>" then
                has_control_right_switch = true
            elseif map.lhs == "<C-Left>" then
                has_control_left_switch = true
            elseif map.lhs == "h" then
                has_h_switch = true
            elseif map.lhs == "l" then
                has_l_switch = true
            elseif map.lhs == "." then
                has_implement_action = true
            elseif map.lhs == "<" then
                has_old_left_switch = true
            end
        end
        for _, map in ipairs(footer_insert_maps) do
            if map.lhs == "<C-Left>" then
                has_insert_left_switch = true
            elseif map.lhs == "<C-Right>" then
                has_insert_right_switch = true
            end
        end

        assert.is_true(has_right_switch)
        assert.is_true(has_left_switch)
        assert.is_true(has_control_right_switch)
        assert.is_true(has_control_left_switch)
        assert.is_true(has_h_switch)
        assert.is_true(has_l_switch)
        assert.is_true(has_insert_left_switch)
        assert.is_true(has_insert_right_switch)
        assert.is_true(has_implement_action)
        assert.is_false(has_old_left_switch)

        vim.api.nvim_set_current_win(creator.footer_win.win)
        creator:switch_kind(1)

        wait_for(function()
            return creator.state.kind == "feature" and vim.api.nvim_get_current_win() == creator.footer_win.win
        end)
    end)

    it("preserves insert cursor position when switching to a tab with the same input field", function()
        creator = Creator.open({
            app = {
                config = {
                    get = function()
                        return {
                            storage = { workspaces_dir = "/tmp" },
                        }
                    end,
                },
            },
            project = {
                name = "Demo",
                root = "/tmp/demo",
            },
            initial_kind = "todo",
            initial_draft = {
                title = "Route prompt",
                details = "Keep cursor",
            },
            on_submit = function() end,
        })

        vim.api.nvim_set_current_win(creator.layout.title_win.win)
        vim.api.nvim_win_set_cursor(creator.layout.title_win.win, { 1, 5 })
        vim.cmd.startinsert()

        creator:switch_kind(1)

        wait_for(function()
            return creator.state.kind == "bug" and vim.api.nvim_get_current_win() == creator.layout.title_win.win
        end)

        assert.are.same({ 1, 5 }, vim.api.nvim_win_get_cursor(creator.layout.title_win.win))
    end)

    it("places the footer below the body area", function()
        creator = Creator.open({
            app = {
                config = {
                    get = function()
                        return {
                            storage = { workspaces_dir = "/tmp" },
                        }
                    end,
                },
            },
            project = {
                name = "Demo",
                root = "/tmp/demo",
            },
            initial_kind = "todo",
            on_submit = function() end,
        })

        assert.are.equal(creator:body_row() + creator:body_height() + 2, creator:footer_row())
        assert.is_true(
            creator.footer_win.opts.row() > creator.layout.body_win.opts.row() + creator.layout.body_win.opts.height()
        )
    end)

    it("keeps insert-mode left and right arrows available for text editing", function()
        creator = Creator.open({
            app = {
                config = {
                    get = function()
                        return {
                            storage = { workspaces_dir = "/tmp" },
                        }
                    end,
                },
            },
            project = {
                name = "Demo",
                root = "/tmp/demo",
            },
            initial_kind = "todo",
            on_submit = function() end,
        })

        local title_insert_maps = vim.api.nvim_buf_get_keymap(creator.layout.title_buf, "i")
        local body_insert_maps = vim.api.nvim_buf_get_keymap(creator.layout.body_buf, "i")

        for _, map in ipairs(title_insert_maps) do
            assert.are_not.equal("<Left>", map.lhs)
            assert.are_not.equal("<Right>", map.lhs)
            assert.are_not.equal("h", map.lhs)
        end
        for _, map in ipairs(body_insert_maps) do
            assert.are_not.equal("<Left>", map.lhs)
            assert.are_not.equal("<Right>", map.lhs)
        end
    end)

    it("uses mode-specific keys to move focus between title and details", function()
        creator = Creator.open({
            app = {
                config = {
                    get = function()
                        return {
                            storage = { workspaces_dir = "/tmp" },
                        }
                    end,
                },
            },
            project = {
                name = "Demo",
                root = "/tmp/demo",
            },
            initial_kind = "todo",
            initial_draft = {
                title = "Route prompt",
                details = "First line\nSecond line",
            },
            on_submit = function() end,
        })

        vim.api.nvim_set_current_win(creator.layout.title_win.win)
        vim.cmd.stopinsert()
        trigger_buffer_mapping(creator.layout.title_buf, "<Down>")
        assert.are.equal(creator.layout.title_win.win, vim.api.nvim_get_current_win())

        wait_for(function()
            return vim.api.nvim_get_current_win() == creator.layout.body_win.win
                and vim.api.nvim_get_mode().mode == "n"
        end)

        vim.api.nvim_set_current_win(creator.layout.title_win.win)
        trigger_buffer_mapping(creator.layout.title_buf, "<Tab>")

        wait_for(function()
            return vim.api.nvim_get_current_win() == creator.layout.body_win.win
                and vim.api.nvim_get_mode().mode == "n"
        end)

        trigger_buffer_mapping(creator.layout.body_buf, "<Up>")
        assert.are.equal(creator.layout.body_win.win, vim.api.nvim_get_current_win())

        wait_for(function()
            return vim.api.nvim_get_current_win() == creator.layout.title_win.win
                and vim.api.nvim_get_mode().mode == "n"
        end)

        local title_insert_maps = vim.api.nvim_buf_get_keymap(creator.layout.title_buf, "i")
        local title_down
        for _, map in ipairs(title_insert_maps) do
            assert.are_not.equal("<Tab>", map.lhs)
            if map.lhs == "<Down>" then
                title_down = map.callback
            end
        end
        assert.is_function(title_down)

        vim.api.nvim_set_current_win(creator.layout.title_win.win)
        assert.are.equal("", title_down())

        wait_for(function()
            return vim.api.nvim_get_current_win() == creator.layout.body_win.win
        end)

        local body_up
        for _, map in ipairs(vim.api.nvim_buf_get_keymap(creator.layout.body_buf, "i")) do
            if map.lhs == "<Up>" then
                body_up = map.callback
            end
        end
        assert.is_function(body_up)
        assert.are.equal("", body_up())

        wait_for(function()
            return vim.api.nvim_get_current_win() == creator.layout.title_win.win
        end)

        vim.api.nvim_set_current_win(creator.layout.body_win.win)
        vim.api.nvim_win_set_cursor(creator.layout.body_win.win, { 2, 0 })
        assert.are_not.equal("", body_up())
        assert.are.equal(creator.layout.body_win.win, vim.api.nvim_get_current_win())

        local body_down
        for _, map in ipairs(vim.api.nvim_buf_get_keymap(creator.layout.body_buf, "n")) do
            if map.lhs == "<Down>" then
                body_down = map.callback
            end
        end
        assert.is_function(body_down)
        assert.are_not.equal("", body_down())
        assert.are.equal(creator.layout.body_win.win, vim.api.nvim_get_current_win())

        assert.are.equal("", trigger_buffer_mapping(creator.layout.title_buf, "<S-Tab>", "i"))

        wait_for(function()
            return vim.api.nvim_get_current_win() == creator.layout.body_win.win
        end)
    end)

    it("splits title text into details from insert-mode enter", function()
        creator = Creator.open({
            app = {
                config = {
                    get = function()
                        return {
                            storage = { workspaces_dir = "/tmp" },
                        }
                    end,
                },
            },
            project = {
                name = "Demo",
                root = "/tmp/demo",
            },
            initial_kind = "todo",
            initial_draft = {
                title = "Fix parser details",
                details = "Existing detail",
            },
            on_submit = function() end,
        })

        vim.api.nvim_set_current_win(creator.layout.title_win.win)
        vim.api.nvim_win_set_cursor(creator.layout.title_win.win, { 1, #"Fix parser" })

        trigger_buffer_mapping(creator.layout.title_buf, "<CR>", "i")

        wait_for(function()
            return vim.api.nvim_get_current_win() == creator.layout.body_win.win
        end)

        assert.are.same({ "Fix parser" }, vim.api.nvim_buf_get_lines(creator.layout.title_buf, 0, -1, false))
        assert.are.same(
            { "details", "Existing detail" },
            vim.api.nvim_buf_get_lines(creator.layout.body_buf, 0, -1, false)
        )
        assert.are.same({ 1, 0 }, vim.api.nvim_win_get_cursor(creator.layout.body_win.win))
    end)

    it("moves title overflow into details at a word boundary", function()
        creator = Creator.open({
            app = {
                config = {
                    get = function()
                        return {
                            storage = { workspaces_dir = "/tmp" },
                        }
                    end,
                },
            },
            project = {
                name = "Demo",
                root = "/tmp/demo",
            },
            initial_kind = "todo",
            on_submit = function() end,
        })
        creator.content_width = function()
            return 10
        end

        vim.api.nvim_set_current_win(creator.layout.title_win.win)
        vim.api.nvim_buf_set_lines(creator.layout.title_buf, 0, -1, false, { "Alpha Beta Gamma Delta" })
        vim.api.nvim_win_set_cursor(creator.layout.title_win.win, { 1, #"Alpha Beta Gamma Delta" })
        vim.api.nvim_exec_autocmds("TextChangedI", { buffer = creator.layout.title_buf })

        wait_for(function()
            return vim.api.nvim_get_current_win() == creator.layout.body_win.win
        end)

        assert.are.same({ "Alpha Beta" }, vim.api.nvim_buf_get_lines(creator.layout.title_buf, 0, -1, false))
        assert.are.same({ "Gamma Delta" }, vim.api.nvim_buf_get_lines(creator.layout.body_buf, 0, -1, false))
    end)

    it("changes tabs by mouse hit testing", function()
        creator = Creator.open({
            app = {
                config = {
                    get = function()
                        return {
                            storage = { workspaces_dir = "/tmp" },
                        }
                    end,
                },
            },
            project = {
                name = "Demo",
                root = "/tmp/demo",
            },
            initial_kind = "bug",
            on_submit = function() end,
        })

        creator:activate_kind_tab_at(creator.kind_tab_spans[3].start_col + 1)

        wait_for(function()
            return creator.state.kind == "freeform"
        end)

        creator:switch_kind(-1)
        wait_for(function()
            return creator.state.kind == "bug"
        end)

        creator:activate_variant_tab_at(creator.variant_tab_spans[2].start_col + 1)

        wait_for(function()
            return creator.state.variant == "clipboard_error"
        end)

        assert.is_nil(creator.layout.note_win)
        assert.are.equal(" Comment ", creator.layout.title_win.opts.title)
        assert.are.same({ creator.layout.title_buf, creator.layout.preview_buf }, creator.layout:buffers())
    end)

    it("focuses and selects prompt creator panels from mouse clicks", function()
        creator = Creator.open({
            app = {
                config = {
                    get = function()
                        return {
                            storage = { workspaces_dir = "/tmp" },
                        }
                    end,
                },
            },
            project = { name = "Alpha", root = "/tmp/alpha" },
            projects = {
                { name = "Alpha", root = "/tmp/alpha" },
                { name = "Beta", root = "/tmp/beta" },
            },
            initial_kind = "bug",
            on_submit = function() end,
        })

        creator:handle_mouse({ winid = creator.project_win.win, line = 2, column = 1 })

        wait_for(function()
            return vim.api.nvim_get_current_win() == creator.layout.title_win.win
        end)
        assert.are.equal(1, creator.project_index)

        creator:handle_mouse({
            winid = creator.kind_win.win,
            line = 1,
            column = creator.kind_tab_spans[3].start_col + 1,
        })

        assert.are.equal("freeform", creator.state.kind)
        assert.are.equal(creator.kind_win.win, vim.api.nvim_get_current_win())

        creator:switch_kind(-1)
        creator:handle_mouse({
            winid = creator.variant_win.win,
            line = 1,
            column = creator.variant_tab_spans[2].start_col + 1,
        })

        assert.are.equal("clipboard_error", creator.state.variant)
        assert.are.equal(creator.variant_win.win, vim.api.nvim_get_current_win())
    end)

    it("leaves insert mode when mouse focuses a non-text prompt creator panel", function()
        creator = Creator.open({
            app = {
                config = {
                    get = function()
                        return {
                            storage = { workspaces_dir = "/tmp" },
                        }
                    end,
                },
            },
            project = { name = "Alpha", root = "/tmp/alpha" },
            initial_kind = "bug",
            on_submit = function() end,
        })

        vim.api.nvim_set_current_win(creator.layout.title_win.win)
        vim.cmd.startinsert()

        creator:handle_mouse({ winid = creator.kind_win.win, line = 1, column = 1 })

        wait_for(function()
            return vim.api.nvim_get_current_win() == creator.kind_win.win and not creator:in_insert_mode()
        end)
    end)

    it("preserves shared draft fields when switching kinds", function()
        creator = Creator.open({
            app = {
                config = {
                    get = function()
                        return {
                            storage = { workspaces_dir = "/tmp" },
                        }
                    end,
                },
            },
            project = {
                name = "Demo",
                root = "/tmp/demo",
            },
            initial_kind = "todo",
            on_submit = function() end,
        })

        vim.api.nvim_buf_set_lines(creator.layout.title_buf, 0, -1, false, { "Shared title" })
        vim.api.nvim_buf_set_lines(creator.layout.body_buf, 0, -1, false, { "Shared details" })

        creator:switch_kind(1)

        wait_for(function()
            return creator.state.kind == "bug"
        end)

        assert.are.equal("Shared title", vim.api.nvim_buf_get_lines(creator.layout.title_buf, 0, 1, false)[1])
        assert.are.equal("Shared details", vim.api.nvim_buf_get_lines(creator.layout.body_buf, 0, 1, false)[1])
        assert.are.same({ "Shared title" }, creator.field_history.title)
        assert.are.same({ "Shared details" }, creator.field_history.details)
    end)

    it("tracks a hidden default mode for single-layout categories", function()
        creator = Creator.open({
            app = {
                config = {
                    get = function()
                        return {
                            storage = { workspaces_dir = "/tmp" },
                        }
                    end,
                },
            },
            project = {
                name = "Demo",
                root = "/tmp/demo",
            },
            initial_kind = "todo",
            on_submit = function() end,
        })

        assert.are.equal("custom", creator.state.variant)
        assert.is_nil(creator.variant_win)
    end)

    it("caches hidden draft fields until a compatible tab is reopened", function()
        creator = Creator.open({
            app = {
                config = {
                    get = function()
                        return {
                            storage = { workspaces_dir = "/tmp" },
                        }
                    end,
                },
            },
            project = {
                name = "Demo",
                root = "/tmp/demo",
            },
            initial_kind = "bug",
            on_submit = function() end,
        })

        vim.api.nvim_buf_set_lines(creator.layout.title_buf, 0, -1, false, { "Sticky title" })
        vim.api.nvim_buf_set_lines(creator.layout.body_buf, 0, -1, false, { "Sticky details" })

        creator:switch_variant(1)

        wait_for(function()
            return creator.state.variant == "clipboard_error"
        end)

        assert.are.equal("Sticky title", vim.api.nvim_buf_get_lines(creator.layout.title_buf, 0, 1, false)[1])

        creator:switch_variant(1)

        wait_for(function()
            return creator.state.variant == "clipboard_screenshot"
        end)

        assert.are.equal("Sticky title", vim.api.nvim_buf_get_lines(creator.layout.title_buf, 0, 1, false)[1])
        assert.are.equal("Sticky details", vim.api.nvim_buf_get_lines(creator.layout.body_buf, 0, 1, false)[1])
    end)

    it("keeps completion popup navigation in the details field", function()
        creator = Creator.open({
            app = {
                config = {
                    get = function()
                        return {
                            storage = { workspaces_dir = "/tmp" },
                        }
                    end,
                },
            },
            project = {
                name = "Demo",
                root = "/tmp/demo",
            },
            initial_kind = "bug",
            on_submit = function() end,
        })

        local body_win = creator.layout.body_win

        vim.api.nvim_set_current_win(body_win.win)
        vim.api.nvim_win_set_cursor(body_win.win, { 1, 0 })
        vim.cmd.startinsert()
        vim.fn.pumvisible = function()
            return 1
        end

        vim.api.nvim_input(vim.keycode("<Up>"))

        wait_for(function()
            return vim.api.nvim_get_current_win() == body_win.win
        end)

        assert.are.equal(body_win.win, vim.api.nvim_get_current_win())
    end)

    it("removes the image preview when switching to a draft without an image", function()
        creator = Creator.open({
            app = {
                config = {
                    get = function()
                        return {
                            storage = { workspaces_dir = "/tmp" },
                        }
                    end,
                },
            },
            project = {
                name = "Demo",
                root = "/tmp/demo",
            },
            initial_kind = "todo",
            initial_draft = {
                title = "Todo with image",
                details = "Preview should disappear on another kind",
                image_path = "/tmp/demo.png",
            },
            on_submit = function() end,
        })

        assert.is_not_nil(creator.preview_win)
        assert.is_true(creator.preview_win:valid())

        creator:switch_kind(1)

        wait_for(function()
            return creator.preview_win == nil and creator.state.image_path == nil
        end)
    end)

    it("defaults the target project picker to the requested project", function()
        local alpha = { name = "Alpha", root = "/tmp/alpha" }
        local beta = { name = "Beta", root = "/tmp/beta" }

        creator = Creator.open({
            app = {
                config = {
                    get = function()
                        return {
                            storage = { workspaces_dir = "/tmp" },
                        }
                    end,
                },
            },
            project = alpha,
            projects = { alpha, beta },
            active_project_root = beta.root,
            context = {
                file_path = "/tmp/alpha/lua/demo.lua",
                relative_path = "lua/demo.lua",
            },
            initial_kind = "todo",
            on_submit = function() end,
        })

        assert.are.equal(alpha.root, creator.project.root)
        assert.are.equal(alpha.root, creator.state.project.root)
        assert.are.equal(alpha.root, creator.state.context.project_root)
        assert.are.equal(1, creator.project_index)
        assert.are.equal(creator.layout.title_win.win, vim.api.nvim_get_current_win())
    end)

    it("hides the cursor in non-text prompt creator windows", function()
        local alpha = { name = "Alpha", root = "/tmp/alpha" }
        local beta = { name = "Beta", root = "/tmp/beta" }

        creator = Creator.open({
            app = {
                config = {
                    get = function()
                        return {
                            storage = { workspaces_dir = "/tmp" },
                        }
                    end,
                },
            },
            project = alpha,
            projects = { alpha, beta },
            initial_kind = "bug",
            on_submit = function() end,
        })

        local project_winhl = vim.wo[creator.project_win.win].winhl
        local kind_winhl = vim.wo[creator.kind_win.win].winhl
        local variant_winhl = vim.wo[creator.variant_win.win].winhl
        local title_winhl = vim.wo[creator.layout.title_win.win].winhl

        assert.is_truthy(project_winhl:find("Cursor:ClodexPromptEditorNormal", 1, true))
        assert.is_truthy(project_winhl:find("lCursor:ClodexPromptEditorNormal", 1, true))
        assert.is_truthy(kind_winhl:find("Cursor:ClodexPromptEditorFooter", 1, true))
        assert.is_truthy(kind_winhl:find("lCursor:ClodexPromptEditorFooter", 1, true))
        assert.is_truthy(variant_winhl:find("Cursor:ClodexPromptEditorFooter", 1, true))
        assert.is_truthy(variant_winhl:find("lCursor:ClodexPromptEditorFooter", 1, true))
        assert.is_nil(title_winhl:find("Cursor:", 1, true))
    end)

    it("changes target projects with control arrows without focusing the project list", function()
        local submitted_project
        local alpha = { name = "Alpha", root = "/tmp/alpha" }
        local beta = { name = "Beta", root = "/tmp/beta" }

        creator = Creator.open({
            app = {
                config = {
                    get = function()
                        return {
                            storage = { workspaces_dir = "/tmp" },
                        }
                    end,
                },
            },
            project = alpha,
            projects = { alpha, beta },
            active_project_root = alpha.root,
            context = {
                file_path = "/tmp/alpha/lua/demo.lua",
                relative_path = "lua/demo.lua",
            },
            initial_kind = "todo",
            initial_draft = {
                title = "Route prompt",
                details = "Send it to another project",
            },
            on_submit = function(_, _, project)
                submitted_project = project
                return false
            end,
        })

        vim.api.nvim_set_current_win(creator.layout.title_win.win)
        vim.cmd.stopinsert()
        trigger_buffer_mapping(creator.layout.title_buf, "<C-Down>")

        wait_for(function()
            return creator.project.root == beta.root and creator.state.context.project_root == beta.root
        end)

        assert.are.equal(creator.layout.title_win.win, vim.api.nvim_get_current_win())

        vim.api.nvim_set_current_win(creator.layout.body_win.win)
        trigger_buffer_mapping(creator.layout.body_buf, "<C-Up>", "i")

        wait_for(function()
            return creator.project.root == alpha.root and creator.state.context.project_root == alpha.root
        end)

        assert.are.equal(creator.layout.body_win.win, vim.api.nvim_get_current_win())

        trigger_buffer_mapping(creator.layout.body_buf, "<C-Down>", "i")

        creator:submit("queue")

        wait_for(function()
            return submitted_project ~= nil
        end)

        assert.are.equal(beta.root, submitted_project.root)
    end)

    it("keeps the project list out of the normal-mode tab cycle", function()
        creator = Creator.open({
            app = {
                config = {
                    get = function()
                        return {
                            storage = { workspaces_dir = "/tmp" },
                        }
                    end,
                },
            },
            project = {
                name = "Demo",
                root = "/tmp/demo",
            },
            initial_kind = "todo",
            on_submit = function() end,
        })

        trigger_buffer_mapping(creator.layout.title_buf, "<Tab>")

        wait_for(function()
            return vim.api.nvim_get_current_win() == creator.layout.body_win.win
        end)

        trigger_buffer_mapping(creator.layout.body_buf, "<Tab>")

        wait_for(function()
            return vim.api.nvim_get_current_win() == creator.layout.title_win.win
        end)
    end)

    it("keeps the project list out of the insert-mode focus cycle", function()
        creator = Creator.open({
            app = {
                config = {
                    get = function()
                        return {
                            storage = { workspaces_dir = "/tmp" },
                        }
                    end,
                },
            },
            project = {
                name = "Demo",
                root = "/tmp/demo",
            },
            initial_kind = "todo",
            on_submit = function() end,
        })

        local title_insert_maps = vim.api.nvim_buf_get_keymap(creator.layout.title_buf, "i")
        local body_insert_maps = vim.api.nvim_buf_get_keymap(creator.layout.body_buf, "i")
        for _, map in ipairs(title_insert_maps) do
            assert.are_not.equal("<Tab>", map.lhs)
        end
        for _, map in ipairs(body_insert_maps) do
            assert.are_not.equal("<Tab>", map.lhs)
        end

        trigger_buffer_mapping(creator.layout.title_buf, "<S-Tab>", "i")

        wait_for(function()
            return vim.api.nvim_get_current_win() == creator.layout.body_win.win
        end)

        trigger_buffer_mapping(creator.layout.body_buf, "<S-Tab>", "i")

        wait_for(function()
            return vim.api.nvim_get_current_win() == creator.layout.title_win.win
        end)
    end)

    it("renders stored project icons in the project picker", function()
        creator = Creator.open({
            app = {
                config = {
                    get = function()
                        return {
                            storage = { workspaces_dir = "/tmp" },
                        }
                    end,
                },
                project_details_store = {
                    get_cached = function(_, project)
                        if project.root == "/tmp/alpha" then
                            return { project_icon = "★" }
                        end
                    end,
                },
            },
            project = { name = "Alpha", root = "/tmp/alpha" },
            projects = {
                { name = "Alpha", root = "/tmp/alpha" },
                { name = "Beta", root = "/tmp/beta" },
            },
            active_project_root = "/tmp/alpha",
            initial_kind = "todo",
            on_submit = function() end,
        })

        local lines = vim.api.nvim_buf_get_lines(creator.project_buf, 0, -1, false)

        assert.is_truthy(lines[1]:find("^ ★ Alpha%s+$"))
        assert.is_truthy(lines[2]:find("^ Beta%s+$"))
        assert.are.equal(vim.fn.strdisplaywidth(lines[1]), vim.fn.strdisplaywidth(lines[2]))
    end)

    it("highlights the selected target project in the project picker", function()
        local alpha = { name = "Alpha", root = "/tmp/alpha" }
        local beta = { name = "Beta", root = "/tmp/beta" }

        creator = Creator.open({
            app = {
                config = {
                    get = function()
                        return {
                            storage = { workspaces_dir = "/tmp" },
                        }
                    end,
                },
            },
            project = alpha,
            projects = { alpha, beta },
            active_project_root = alpha.root,
            initial_kind = "bug",
            on_submit = function() end,
        })

        local initial_groups = extmark_groups(creator.project_buf)
        assert.is_true(vim.tbl_contains(initial_groups, "ClodexPromptSourceTabActive"))
        assert.is_true(vim.tbl_contains(initial_groups, "ClodexPromptBugTitle"))

        trigger_buffer_mapping(creator.layout.title_buf, "<C-Down>")

        wait_for(function()
            return creator.project.root == beta.root
        end)

        local groups = extmark_groups(creator.project_buf)
        assert.is_true(vim.tbl_contains(groups, "ClodexPromptBugTitle"))
        assert.is_true(vim.tbl_contains(groups, "ClodexPromptSourceTabActive"))
    end)

    it("pads project picker rows to the same visual width", function()
        creator = Creator.open({
            app = {
                config = {
                    get = function()
                        return {
                            storage = { workspaces_dir = "/tmp" },
                        }
                    end,
                },
            },
            project = { name = "Short", root = "/tmp/short" },
            projects = {
                { name = "Short", root = "/tmp/short" },
                { name = "A much longer project", root = "/tmp/long" },
            },
            active_project_root = "/tmp/short",
            initial_kind = "todo",
            on_submit = function() end,
        })

        local lines = vim.api.nvim_buf_get_lines(creator.project_buf, 0, -1, false)
        local target_width = creator:project_list_width()

        assert.are.equal(target_width, vim.fn.strdisplaywidth(lines[1]))
        assert.are.equal(target_width, vim.fn.strdisplaywidth(lines[2]))
        assert.is_truthy(lines[1]:find("^ Short%s+$"))
    end)

    it("loads project icons when they are not already cached", function()
        creator = Creator.open({
            app = {
                config = {
                    get = function()
                        return {
                            storage = { workspaces_dir = "/tmp" },
                        }
                    end,
                },
                project_details_store = {
                    get_cached = function()
                        return nil
                    end,
                    get = function(_, project)
                        if project.root == "/tmp/alpha" then
                            return { project_icon = "★" }
                        end
                    end,
                },
            },
            project = { name = "Alpha", root = "/tmp/alpha" },
            projects = {
                { name = "Alpha", root = "/tmp/alpha" },
                { name = "Beta", root = "/tmp/beta" },
            },
            active_project_root = "/tmp/alpha",
            initial_kind = "todo",
            on_submit = function() end,
        })

        local lines = vim.api.nvim_buf_get_lines(creator.project_buf, 0, -1, false)

        assert.is_truthy(lines[1]:find("^ ★ Alpha%s+$"))
        assert.is_truthy(lines[2]:find("^ Beta%s+$"))
        assert.are.equal(vim.fn.strdisplaywidth(lines[1]), vim.fn.strdisplaywidth(lines[2]))
    end)

    it("adds panel background margin around the creator with extra right and bottom space", function()
        creator = Creator.open({
            app = {
                config = {
                    get = function()
                        return {
                            storage = { workspaces_dir = "/tmp" },
                        }
                    end,
                },
            },
            project = { name = "Alpha", root = "/tmp/alpha" },
            projects = {
                { name = "Alpha", root = "/tmp/alpha" },
                { name = "Beta", root = "/tmp/beta" },
            },
            initial_kind = "todo",
            on_submit = function() end,
        })

        local background_config = vim.api.nvim_win_get_config(creator.project_bg_win.win)
        local picker_config = vim.api.nvim_win_get_config(creator.project_win.win)
        local title_config = vim.api.nvim_win_get_config(creator.layout.title_win.win)
        local body_config = vim.api.nvim_win_get_config(creator.layout.body_win.win)
        local footer_config = vim.api.nvim_win_get_config(creator.footer_win.win)
        local left, top, right, bottom = creator:creator_frame_bounds()

        assert.are.equal("none", creator.project_bg_win.opts.border)
        assert.are.equal("ClodexPromptEditorFooter", creator.project_bg_win.opts.theme_overrides.normal)
        assert.are.equal("ClodexPromptEditorFooter", creator.project_bg_win.opts.theme_overrides.end_of_buffer)
        assert.are.equal(creator:project_background_width(), background_config.width)
        assert.are.equal(creator:project_background_height(), background_config.height)
        assert.are.equal(
            string.rep(" ", background_config.width),
            vim.api.nvim_buf_get_lines(creator.project_bg_buf, 0, 1, false)[1]
        )
        assert.are.equal(left - 1, background_config.col)
        assert.are.equal(top - 1, background_config.row)
        assert.are.equal((right - left) + 3, background_config.width)
        assert.are.equal((bottom - top) + 3, background_config.height)
        assert.are.equal(70, background_config.zindex)
        assert.are.equal(71, picker_config.zindex)
        assert.are.equal(71, footer_config.zindex)
        assert.are.equal(title_config.row, picker_config.row)
        assert.are.equal(footer_config.row + footer_config.height + 1, picker_config.row + picker_config.height + 1)
        assert.is_true(background_config.row < title_config.row)
        assert.is_true(background_config.col < picker_config.col)
        assert.is_true(background_config.col < title_config.col)
        assert.is_true(background_config.col + background_config.width > body_config.col + body_config.width)
        assert.is_true(footer_config.col + footer_config.width <= background_config.col + background_config.width)
    end)

    it("resizes the panel background after dynamic creator blocks are added", function()
        creator = Creator.open({
            app = {
                config = {
                    get = function()
                        return {
                            storage = { workspaces_dir = "/tmp" },
                        }
                    end,
                },
            },
            project = { name = "Alpha", root = "/tmp/alpha" },
            projects = {
                { name = "Alpha", root = "/tmp/alpha" },
                { name = "Beta", root = "/tmp/beta" },
            },
            initial_kind = "todo",
            on_submit = function() end,
        })

        creator:switch_kind(1)
        wait_for(function()
            return creator.state.kind == "bug"
                and creator.variant_win
                and creator.variant_win:valid()
        end)

        creator.state.image_path = "/tmp/clipboard.png"
        creator:refresh()
        wait_for(function()
            return creator.preview_win
                and creator.preview_win:valid()
                and creator.project_bg_win
                and creator.project_bg_win:valid()
        end)

        local background_config = vim.api.nvim_win_get_config(creator.project_bg_win.win)
        local preview_config = vim.api.nvim_win_get_config(creator.preview_win.win)
        local variant_config = vim.api.nvim_win_get_config(creator.variant_win.win)
        local left, top, right, bottom = creator:creator_frame_bounds()
        assert.are.equal(left - 1, background_config.col)
        assert.are.equal(top - 1, background_config.row)
        assert.are.equal((right - left) + 3, background_config.width)
        assert.are.equal((bottom - top) + 3, background_config.height)
        assert.is_true(background_config.col < preview_config.col)
        assert.is_true(background_config.row < variant_config.row)
        assert.is_true(background_config.col + background_config.width > preview_config.col + preview_config.width)
        assert.is_true(background_config.row + background_config.height > variant_config.row + variant_config.height)
        assert.are.equal(background_config.width, #vim.api.nvim_buf_get_lines(creator.project_bg_buf, 0, 1, false)[1])
    end)

    it("destroys the variant tab panel after toggling bug tabs off more than once", function()
        creator = Creator.open({
            app = {
                config = {
                    get = function()
                        return {
                            storage = { workspaces_dir = "/tmp" },
                        }
                    end,
                },
            },
            project = { name = "Alpha", root = "/tmp/alpha" },
            initial_kind = "bug",
            on_submit = function() end,
        })

        local first_variant_win = creator.variant_win.win
        assert.is_not_nil(creator.panel:block("variant_tabs"))

        creator:switch_kind(-1)
        assert.is_false(vim.api.nvim_win_is_valid(first_variant_win))
        assert.is_nil(creator.panel:block("variant_tabs"))

        creator:switch_kind(1)
        local second_variant_win = creator.variant_win.win
        assert.is_not_nil(creator.panel:block("variant_tabs"))

        creator:switch_kind(-1)
        assert.is_false(vim.api.nvim_win_is_valid(second_variant_win))
        assert.is_nil(creator.panel:block("variant_tabs"))
    end)

    it("limits clipboard image previews to the preview pane size", function()
        local attached_opts
        package.loaded["snacks"] = {
            input = { input = function() end },
            picker = {
                select = function(_items, _opts, on_choice)
                    on_choice(nil)
                end,
            },
            image = {
                terminal = {
                    env = function()
                        return { supported = true }
                    end,
                },
                supports = function()
                    return true
                end,
                placement = {
                    new = function(_buf, src, opts)
                        attached_opts = vim.tbl_extend("force", { src = src }, opts)
                        return {
                            ready = function()
                                return true
                            end,
                            close = function() end,
                        }
                    end,
                },
            },
        }

        creator = Creator.open({
            app = {
                config = {
                    get = function()
                        return {
                            storage = { workspaces_dir = "/tmp" },
                        }
                    end,
                },
            },
            project = {
                name = "Demo",
                root = "/tmp/demo",
            },
            initial_kind = "todo",
            initial_draft = {
                title = "Todo with image",
                image_path = "/tmp/demo.png",
            },
            on_submit = function() end,
        })

        assert.is_not_nil(attached_opts)
        assert.are.equal("/tmp/demo.png", attached_opts.src)
        assert.are.equal(creator:preview_width() - 2, attached_opts.max_width)
        assert.are.equal(creator:preview_height() - 2, attached_opts.max_height)

        package.loaded["snacks"] = nil
    end)

    it("uses the live preview window size when constraining image placement", function()
        local attached_opts
        package.loaded["snacks"] = {
            input = { input = function() end },
            picker = {
                select = function(_items, _opts, on_choice)
                    on_choice(nil)
                end,
            },
            image = {
                terminal = {
                    env = function()
                        return { supported = true }
                    end,
                },
                supports = function()
                    return true
                end,
                placement = {
                    new = function(_buf, src, opts)
                        attached_opts = vim.tbl_extend("force", { src = src }, opts)
                        return {
                            ready = function()
                                return true
                            end,
                            close = function() end,
                        }
                    end,
                },
            },
        }

        creator = Creator.open({
            app = {
                config = {
                    get = function()
                        return {
                            storage = { workspaces_dir = "/tmp" },
                        }
                    end,
                },
            },
            project = {
                name = "Demo",
                root = "/tmp/demo",
            },
            initial_kind = "todo",
            initial_draft = {
                title = "Todo with image",
                image_path = "/tmp/demo.png",
            },
            on_submit = function() end,
        })

        vim.api.nvim_win_set_width(creator.preview_win.win, 24)
        vim.api.nvim_win_set_height(creator.preview_win.win, 10)
        creator:render_preview()

        assert.is_not_nil(attached_opts)
        assert.are.equal("/tmp/demo.png", attached_opts.src)
        assert.are.equal(22, attached_opts.max_width)
        assert.are.equal(8, attached_opts.max_height)

        package.loaded["snacks"] = nil
    end)

    it("falls back when image preview rendering does not become ready", function()
        local closed = false
        local placement_buf
        package.loaded["snacks"] = {
            input = { input = function() end },
            picker = {
                select = function(_items, _opts, on_choice)
                    on_choice(nil)
                end,
            },
            image = {
                terminal = {
                    env = function()
                        return { supported = true }
                    end,
                },
                supports = function()
                    return true
                end,
                placement = {
                    new = function(buf)
                        placement_buf = buf
                        return {
                            ready = function()
                                return false
                            end,
                            close = function()
                                closed = true
                                vim.defer_fn(function()
                                    if vim.api.nvim_buf_is_valid(buf) then
                                        vim.bo[buf].modifiable = true
                                        vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "still loading" })
                                        vim.bo[buf].modifiable = false
                                    end
                                end, 20)
                            end,
                        }
                    end,
                },
            },
        }

        creator = Creator.open({
            app = {
                config = {
                    get = function()
                        return {
                            storage = { workspaces_dir = "/tmp" },
                        }
                    end,
                },
            },
            project = {
                name = "Demo",
                root = "/tmp/demo",
            },
            initial_kind = "todo",
            initial_draft = {
                title = "Todo with image",
                image_path = "/tmp/demo.png",
            },
            on_submit = function() end,
        })

        assert(
            vim.wait(2500, function()
                local lines = vim.api.nvim_buf_get_lines(creator.preview_buf, 0, -1, false)
                return closed and creator.preview_buf ~= placement_buf and lines[1] == "# Clipboard image"
            end, 20),
            "timed out waiting for image preview fallback"
        )
        assert.are.same({ "still loading" }, vim.api.nvim_buf_get_lines(placement_buf, 0, -1, false))

        package.loaded["snacks"] = nil
    end)

    it("uses fallback image preview text when the terminal cannot render images", function()
        local placement_created = false
        package.loaded["snacks"] = {
            input = { input = function() end },
            picker = {
                select = function(_items, _opts, on_choice)
                    on_choice(nil)
                end,
            },
            image = {
                terminal = {
                    env = function()
                        return { supported = false }
                    end,
                },
                supports = function()
                    return true
                end,
                placement = {
                    new = function()
                        placement_created = true
                    end,
                },
            },
        }

        creator = Creator.open({
            app = {
                config = {
                    get = function()
                        return {
                            storage = { workspaces_dir = "/tmp" },
                        }
                    end,
                },
            },
            project = {
                name = "Demo",
                root = "/tmp/demo",
            },
            initial_kind = "todo",
            initial_draft = {
                title = "Todo with image",
                image_path = "/tmp/demo.png",
            },
            on_submit = function() end,
        })

        local lines = vim.api.nvim_buf_get_lines(creator.preview_buf, 0, -1, false)
        assert.is_false(placement_created)
        assert.are.equal("# Clipboard image", lines[1])

        package.loaded["snacks"] = nil
    end)

    it("keeps the creator open when submit requests it", function()
        local submitted_spec
        local submitted_action

        creator = Creator.open({
            app = {
                config = {
                    get = function()
                        return {
                            storage = { workspaces_dir = "/tmp" },
                        }
                    end,
                },
            },
            project = {
                name = "Demo",
                root = "/tmp/demo",
            },
            initial_kind = "todo",
            initial_draft = {
                title = "Keep prompt",
                details = "Preserve footer",
            },
            on_submit = function(spec, action)
                submitted_spec = spec
                submitted_action = action
                return false
            end,
        })

        creator:submit("exec")

        wait_for(function()
            return submitted_action == "exec"
                and submitted_spec ~= nil
                and creator.footer_win ~= nil
                and creator.footer_win:valid()
                and creator.layout.title_win ~= nil
                and creator.layout.title_win:valid()
        end)

        assert.are.equal("Keep prompt", submitted_spec.title)
        assert.are.equal("Preserve footer", submitted_spec.details)
    end)

    it("closes the creator after a successful queued submit keymap", function()
        local submitted_action

        creator = Creator.open({
            app = {
                config = {
                    get = function()
                        return {
                            storage = { workspaces_dir = "/tmp" },
                        }
                    end,
                },
            },
            project = {
                name = "Demo",
                root = "/tmp/demo",
            },
            initial_kind = "todo",
            initial_draft = {
                title = "Queue prompt",
                details = "Close on queue",
            },
            on_submit = function(_, action)
                submitted_action = action
                return { id = "queued-item" }
            end,
        })

        trigger_buffer_mapping(creator.layout.title_buf, "<CR>", "n")

        wait_for(function()
            return submitted_action == "queue" and creator.footer_win == nil and creator.layout == nil
        end)
    end)

    it("closes the creator after successful normal-mode plan and implement submit keymaps", function()
        local submitted_actions = {}

        creator = Creator.open({
            app = {
                config = {
                    get = function()
                        return {
                            storage = { workspaces_dir = "/tmp" },
                        }
                    end,
                },
            },
            project = {
                name = "Demo",
                root = "/tmp/demo",
            },
            initial_kind = "todo",
            initial_draft = {
                title = "Run prompt",
                details = "Reset on submit",
            },
            on_submit = function(_, action)
                submitted_actions[#submitted_actions + 1] = action
                return { id = "queued-item" }
            end,
        })

        trigger_buffer_mapping(creator.layout.title_buf, "s", "n")

        wait_for(function()
            return submitted_actions[1] == "save" and creator.footer_win == nil and creator.layout == nil
        end)

        creator = Creator.open({
            app = {
                config = {
                    get = function()
                        return {
                            storage = { workspaces_dir = "/tmp" },
                        }
                    end,
                },
            },
            project = {
                name = "Demo",
                root = "/tmp/demo",
            },
            initial_kind = "todo",
            initial_draft = {
                title = "Run prompt again",
                details = "Close on implement",
            },
            on_submit = function(_, action)
                submitted_actions[#submitted_actions + 1] = action
                return { id = "queued-item" }
            end,
        })

        trigger_buffer_mapping(creator.layout.title_buf, ".", "n")

        wait_for(function()
            return submitted_actions[2] == "exec" and creator.footer_win == nil and creator.layout == nil
        end)
    end)

    it("uses control-key submit actions in insert mode", function()
        local submitted_actions = {}

        creator = Creator.open({
            app = {
                config = {
                    get = function()
                        return {
                            storage = { workspaces_dir = "/tmp" },
                        }
                    end,
                },
            },
            project = {
                name = "Demo",
                root = "/tmp/demo",
            },
            initial_kind = "todo",
            initial_draft = {
                title = "Insert actions",
                details = "Submit from insert mode",
            },
            on_submit = function(_, action)
                submitted_actions[#submitted_actions + 1] = action
                return { id = "queued-item" }
            end,
        })

        trigger_buffer_mapping(creator.layout.title_buf, "<C-s>", "i")

        wait_for(function()
            return submitted_actions[1] == "save" and creator.footer_win == nil and creator.layout == nil
        end)

        creator = Creator.open({
            app = {
                config = {
                    get = function()
                        return {
                            storage = { workspaces_dir = "/tmp" },
                        }
                    end,
                },
            },
            project = {
                name = "Demo",
                root = "/tmp/demo",
            },
            initial_kind = "todo",
            initial_draft = {
                title = "Insert actions again",
                details = "Submit from insert mode again",
            },
            on_submit = function(_, action)
                submitted_actions[#submitted_actions + 1] = action
                return { id = "queued-item" }
            end,
        })

        trigger_buffer_mapping(creator.layout.title_buf, "<C-.>", "i")

        wait_for(function()
            return submitted_actions[2] == "exec" and creator.footer_win == nil and creator.layout == nil
        end)
    end)

    it("resets the creator from shifted plan and implement submit keymaps", function()
        local submitted_actions = {}

        creator = Creator.open({
            app = {
                config = {
                    get = function()
                        return {
                            storage = { workspaces_dir = "/tmp" },
                        }
                    end,
                },
            },
            project = {
                name = "Demo",
                root = "/tmp/demo",
            },
            initial_kind = "todo",
            initial_draft = {
                title = "Reset prompt",
                details = "Keep creator open",
            },
            on_submit = function(_, action)
                submitted_actions[#submitted_actions + 1] = action
                return { id = "queued-item" }
            end,
        })

        trigger_buffer_mapping(creator.layout.title_buf, "S", "n")

        wait_for(function()
            return submitted_actions[1] == "save"
                and creator.layout.title_win ~= nil
                and creator.layout.title_win:valid()
                and vim.api.nvim_buf_get_lines(creator.layout.title_buf, 0, 1, false)[1] == ""
        end)

        vim.api.nvim_buf_set_lines(creator.layout.title_buf, 0, -1, false, { "Reset prompt again" })
        trigger_buffer_mapping(creator.layout.title_buf, "<S-.>", "n")

        wait_for(function()
            return submitted_actions[2] == "exec"
                and creator.layout.title_win ~= nil
                and creator.layout.title_win:valid()
                and vim.api.nvim_buf_get_lines(creator.layout.title_buf, 0, 1, false)[1] == ""
        end)
    end)

    it("still closes after submit mutates prompt windows before returning", function()
        local submitted_action

        creator = Creator.open({
            app = {
                config = {
                    get = function()
                        return {
                            storage = { workspaces_dir = "/tmp" },
                        }
                    end,
                },
            },
            project = {
                name = "Demo",
                root = "/tmp/demo",
            },
            initial_kind = "todo",
            initial_draft = {
                title = "Queue prompt",
                details = "Close after refresh",
            },
            on_submit = function(_, action)
                submitted_action = action
                creator:refresh()
                return { id = "queued-item" }
            end,
        })

        creator:submit("queue")

        assert.is_nil(creator.footer_win)

        wait_for(function()
            return submitted_action == "queue" and creator.footer_win == nil and creator.layout == nil
        end)
    end)
end)
