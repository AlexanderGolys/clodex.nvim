local Config = require("clodex.config")

describe("clodex.config", function()
    describe("Config.merge", function()
        it("merges nested dictionary values", function()
            local merged = Config.merge({
                terminal = {
                    win = {
                        position = "right",
                        width = 0.4,
                    },
                    start_insert = true,
                },
                project_detection = {
                    auto_suggest_git_root = false,
                },
            }, {
                terminal = {
                    start_insert = false,
                },
                project_detection = {
                    auto_suggest_git_root = true,
                },
            })

            assert.are.equal("right", merged.terminal.win.position)
            assert.are.equal(0.4, merged.terminal.win.width)
            assert.are.equal(false, merged.terminal.start_insert)
            assert.are.equal(true, merged.project_detection.auto_suggest_git_root)
        end)

        it("replaces list values instead of attempting deep merge", function()
            local merged = Config.merge({
                hooks = { "start", "stop" },
            }, {
                hooks = { "override" },
            })

            assert.are.same({ "override" }, merged.hooks)
        end)
    end)

    describe("setup", function()
        it("keeps defaults and applies option overrides", function()
            local cfg = Config.new()
            local values = cfg:setup({
                terminal = {
                    start_insert = false,
                },
                project_detection = {
                    auto_suggest_git_root = true,
                },
            })

            assert.are.equal(false, values.terminal.start_insert)
            assert.are.equal("snacks", values.terminal.provider)
            assert.are.equal("right", values.terminal.win.position)
            assert.are.equal(true, values.project_detection.auto_suggest_git_root)
            assert.are.equal("codex", values.backend)
            assert.are.equal("codex", values.codex_cmd[1])
            assert.are.equal("opencode", values.opencode_cmd[1])
            assert.are.equal(".codex/skills", values.prompt_execution.skills_dir)
            assert.are.equal("commit", values.prompt_execution.git_workflow)
            assert.are.equal(true, values.mcp.enabled)
            assert.are.same({}, values.mcp.cmd)
            assert.are.equal("<leader>pt", values.keymaps.toggle.lhs)
            assert.are.equal("<leader>pq", values.keymaps.queue_workspace.lhs)
            assert.are.equal("<leader>ps", values.keymaps.state_preview.lhs)
            assert.are.equal("<leader>pS", values.keymaps.mini_state_preview.lhs)
            assert.are.equal("<leader>pb", values.keymaps.backend_toggle.lhs)
            assert.are.equal("<leader>pc", values.keymaps.chat_toggle.lhs)
            assert.are.equal("<leader>pR", values.keymaps.refresh.lhs)
            assert.are.equal("<leader>pB", values.keymaps.new_bug_prompt.lhs)
            assert.are.equal("<leader>pI", values.keymaps.new_improvement_prompt.lhs)
            assert.are.equal("<leader>pM", values.keymaps.go_to_readme.lhs)
        end)

        it("keeps the project-local skill root when opencode backend is selected", function()
            local cfg = Config.new()
            local values = cfg:setup({
                backend = "opencode",
            })

            assert.are.equal("opencode", values.backend)
            assert.are.same({ "opencode" }, values.opencode_cmd)
            assert.are.equal(".codex/skills", values.prompt_execution.skills_dir)
        end)

        it("keeps an explicit git workflow override", function()
            local cfg = Config.new()
            local values = cfg:setup({
                prompt_execution = {
                    git_workflow = "branch_pr",
                },
            })

            assert.are.equal("branch_pr", values.prompt_execution.git_workflow)
        end)


        it("normalizes the terminal provider and allows the native terminal option", function()
            local cfg = Config.new()

            local term_values = cfg:setup({
                terminal = {
                    provider = "term",
                },
            })
            local default_values = cfg:setup({
                terminal = {
                    provider = "invalid",
                },
            })

            assert.are.equal("term", term_values.terminal.provider)
            assert.are.equal("snacks", default_values.terminal.provider)
        end)

        it("darkens adjusted highlight colors relative to their source background", function()
            vim.api.nvim_set_hl(0, "ConfigSpecBase", { bg = "#808080" })

            Config.apply_highlights({
                highlights = {
                    groups = {
                        ConfigSpecAdjusted = {
                            bg = {
                                from = "ConfigSpecBase",
                                attr = "bg",
                                adjust = -0.25,
                            },
                        },
                    },
                },
            })

            local adjusted = vim.api.nvim_get_hl(0, { name = "ConfigSpecAdjusted", link = false })
            assert.are.equal(0x606060, adjusted.bg)
        end)

        it("gives notworking prompt titles a distinct red from bug titles", function()
            vim.api.nvim_set_hl(0, "DiagnosticError", { fg = "#aa2222" })

            Config.apply_highlights({
                highlights = require("clodex.config.highlights"),
            })

            local bug = vim.api.nvim_get_hl(0, { name = "ClodexPromptBugTitle", link = false })
            local notworking = vim.api.nvim_get_hl(0, { name = "ClodexPromptNotWorkingTitle", link = false })

            assert.are.equal(0xaa2222, bug.fg)
            assert.are_not.equal(bug.fg, notworking.fg)
        end)

        it("keeps prompt titles plain and inverts active kind tabs", function()
            vim.api.nvim_set_hl(0, "DiagnosticError", { fg = "#aa2222", bg = "#331111" })
            vim.api.nvim_set_hl(0, "NormalFloat", { fg = "#dddddd", bg = "#101010" })
            vim.api.nvim_set_hl(0, "Function", { fg = "#22aa44" })
            vim.api.nvim_set_hl(0, "Comment", { fg = "#777777" })

            Config.apply_highlights({
                highlights = require("clodex.config.highlights"),
            })

            local title = vim.api.nvim_get_hl(0, { name = "ClodexPromptBugTitle", link = false })
            local kind = vim.api.nvim_get_hl(0, { name = "ClodexPromptBugKindName", link = false })
            local active = vim.api.nvim_get_hl(0, { name = "ClodexPromptBugTitleActive", link = false })

            assert.is_nil(title.bold)
            assert.are.equal(0xaa2222, kind.fg)
            assert.is_true(kind.bold)
            assert.is_nil(kind.bg)
            assert.are.equal(0x101010, active.fg)
            assert.are.equal(kind.fg, active.bg)
            assert.is_true(active.bold)

            for _, pair in ipairs({
                { inactive = "ClodexPromptFeatureKindName", active = "ClodexPromptFeatureTitleActive" },
                { inactive = "ClodexPromptCleanupKindName", active = "ClodexPromptCleanupTitleActive" },
            }) do
                local inactive_hl = vim.api.nvim_get_hl(0, { name = pair.inactive, link = false })
                local active_hl = vim.api.nvim_get_hl(0, { name = pair.active, link = false })
                assert.are.equal(inactive_hl.fg, active_hl.bg)
                assert.are.equal(0x101010, active_hl.fg)
            end
        end)

        it("keeps the active improvement tab visible without constructor highlights", function()
            vim.api.nvim_set_hl(0, "@constructor", {})
            vim.api.nvim_set_hl(0, "NormalFloat", { fg = "#dddddd", bg = "#101010" })
            vim.api.nvim_set_hl(0, "Function", { fg = "#22aa44" })

            Config.apply_highlights({
                highlights = require("clodex.config.highlights"),
            })

            local inactive = vim.api.nvim_get_hl(0, { name = "ClodexPromptImprovementKindName", link = false })
            local active = vim.api.nvim_get_hl(0, { name = "ClodexPromptImprovementTitleActive", link = false })

            assert.are.equal(0x22aa44, inactive.fg)
            assert.are.equal(inactive.fg, active.bg)
            assert.are.equal(0x101010, active.fg)
            assert.is_true(active.bold)
        end)

        it("keeps prompt border backgrounds aligned with editor backgrounds", function()
            vim.api.nvim_set_hl(0, "DiagnosticError", { fg = "#aa2222" })
            vim.api.nvim_set_hl(0, "NormalFloat", { fg = "#dddddd", bg = "#101010" })

            Config.apply_highlights({
                highlights = require("clodex.config.highlights"),
            })

            local editor = vim.api.nvim_get_hl(0, { name = "ClodexPromptEditorNormal", link = false })
            local default_border = vim.api.nvim_get_hl(0, { name = "ClodexPromptEditorBorder", link = false })
            local kind_border = vim.api.nvim_get_hl(0, { name = "ClodexPromptBugTitleBorder", link = false })

            assert.are.equal(editor.bg, default_border.bg)
            assert.are.equal(editor.bg, kind_border.bg)
            assert.are.equal(0xaa2222, kind_border.fg)
            assert.is_true(kind_border.bold)
        end)

        it("maps commit ids to the diagnostic error color", function()
            vim.api.nvim_set_hl(0, "DiagnosticError", { fg = "#aa2222" })

            Config.apply_highlights({
                highlights = require("clodex.config.highlights"),
            })

            local commit = vim.api.nvim_get_hl(0, { name = "ClodexCommitId", link = false })
            assert.are.equal(0xaa2222, commit.fg)
            assert.is_true(commit.bold)
        end)

        it("maps terminal statusline highlights to the StatusLine background", function()
            vim.api.nvim_set_hl(0, "Normal", { fg = "#dddddd", bg = "#1a1b26" })
            vim.api.nvim_set_hl(0, "StatusLine", { fg = "#eeeeee", bg = "#445566" })

            Config.apply_highlights({
                highlights = require("clodex.config.highlights"),
            })

            local active = vim.api.nvim_get_hl(0, { name = "ClodexTerminalStatuslineActive", link = false })
            local inactive = vim.api.nvim_get_hl(0, { name = "ClodexTerminalStatusline", link = false })

            assert.are.equal(0x445566, active.bg)
            assert.are.equal(0x445566, inactive.bg)
        end)

        it("hides queue panel cursor highlights against their panel backgrounds", function()
            vim.api.nvim_set_hl(0, "Normal", { fg = "#dddddd", bg = "#20242c" })
            vim.api.nvim_set_hl(0, "NormalFloat", { fg = "#dddddd", bg = "#30343c" })

            Config.apply_highlights({
                highlights = require("clodex.config.highlights"),
            })

            local active = vim.api.nvim_get_hl(0, { name = "ClodexQueueCursorActive", link = false })
            local inactive = vim.api.nvim_get_hl(0, { name = "ClodexQueueCursorInactive", link = false })

            assert.are.equal(active.bg, active.fg)
            assert.are.equal(inactive.bg, inactive.fg)
        end)

    end)
end)
