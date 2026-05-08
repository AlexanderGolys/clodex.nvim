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
            assert.are.same({}, values.codex_args)
            assert.are.equal("opencode", values.opencode_cmd[1])
            assert.are.same({}, values.opencode_args)
            assert.are.equal(".codex/skills", values.prompt_execution.skills_dir)
            assert.are.equal("commit", values.prompt_execution.git_workflow)
            assert.are.equal(false, values.prompt_execution.review_after_completion)
            assert.are.equal(true, values.mcp.enabled)
            assert.are.same({}, values.mcp.cmd)
            assert.are.equal("<leader>pp", values.keymaps.main_panel[1].lhs)
            assert.are.equal("<leader>p<home>", values.keymaps.queue_workspace[1].lhs)
            assert.are.equal("<leader>ps", values.keymaps.state_preview[1].lhs)
            assert.are.equal("<leader>pS", values.keymaps.mini_state_preview[1].lhs)
            assert.are.equal("<leader>pB", values.keymaps.backend_toggle[1].lhs)
            assert.are.equal("<leader>p<leader>", values.keymaps.chat_toggle[1].lhs)
            assert.are.equal("<leader>pj", values.keymaps.chat_jump[1].lhs)
            assert.are.equal("<leader>pw", values.keymaps.chat_skill[1].lhs)
            assert.are.equal("<leader>pR", values.keymaps.refresh[1].lhs)
            assert.are.equal("<leader>pb", values.keymaps.new_prompt.bug[1].lhs)
            assert.are.equal("<leader>pa", values.keymaps.new_prompt.improvement[1].lhs)
            assert.are.same({
                { lhs = "<leader>pl", mode = "n" },
                { lhs = "<Home>l", mode = { "n", "i", "v" } },
            }, values.keymaps.new_prompt.line_linked)
            assert.are.equal("<leader>pr", values.keymaps.go_to_readme[1].lhs)
        end)

        it("keeps the project-local skill root when opencode backend is selected", function()
            local cfg = Config.new()
            local values = cfg:setup({
                backend = "opencode",
            })

            assert.are.equal("opencode", values.backend)
            assert.are.same({ "opencode" }, values.opencode_cmd)
            assert.are.same({}, values.opencode_args)
            assert.are.equal(".codex/skills", values.prompt_execution.skills_dir)
        end)

        it("keeps backend CLI args separate from the executable commands", function()
            local cfg = Config.new()
            local values = cfg:setup({
                codex_args = { "--profile", "work" },
                opencode_args = { "--model", "qwen3-coder" },
            })

            assert.are.same({ "codex" }, values.codex_cmd)
            assert.are.same({ "--profile", "work" }, values.codex_args)
            assert.are.same({ "opencode" }, values.opencode_cmd)
            assert.are.same({ "--model", "qwen3-coder" }, values.opencode_args)
        end)

        it("supports legacy prompt-panel and refresh keymap option names", function()
            local cfg = Config.new()
            local values = cfg:setup({
                keymaps = {
                    prompt_panel = { lhs = "<leader>pP" },
                    prompt_refresh = { lhs = "<leader>pF" },
                },
            })
            local queue_workspace = values.keymaps.queue_workspace
            local queue_workspace_lhs = (queue_workspace[1] and queue_workspace[1].lhs) or queue_workspace.lhs
            local refresh = values.keymaps.refresh
            local refresh_lhs = (refresh[1] and refresh[1].lhs) or refresh.lhs

            assert.are.equal("<leader>pP", queue_workspace_lhs)
            assert.are.equal("<leader>pF", refresh_lhs)
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

        it("uses literal colors as final highlight fallbacks", function()
            vim.api.nvim_set_hl(0, "ConfigSpecNoColor", {})

            Config.apply_highlights({
                highlights = {
                    groups = {
                        ConfigSpecLiteralFallback = {
                            bg = {
                                {
                                    from = "ConfigSpecNoColor",
                                    attr = "bg",
                                },
                                {
                                    from = "#20242c",
                                    adjust = 0.25,
                                },
                            },
                        },
                    },
                },
            })

            local fallback = vim.api.nvim_get_hl(0, { name = "ConfigSpecLiteralFallback", link = false })
            assert.are.equal(0x585b61, fallback.bg)
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

        it("keeps vision prompt accents on the bundled purple accent", function()
            vim.api.nvim_set_hl(0, "@keyword", { fg = "#ff99cc" })
            vim.api.nvim_set_hl(0, "NormalFloat", { fg = "#dddddd", bg = "#101010" })

            Config.apply_highlights({
                highlights = require("clodex.config.highlights"),
            })

            local title = vim.api.nvim_get_hl(0, { name = "ClodexPromptVisionTitle", link = false })
            local kind = vim.api.nvim_get_hl(0, { name = "ClodexPromptVisionKindName", link = false })
            local active = vim.api.nvim_get_hl(0, { name = "ClodexPromptVisionTitleActive", link = false })

            assert.are.equal(0xb366ff, title.fg)
            assert.are.equal(title.fg, kind.fg)
            assert.are.equal(title.fg, active.bg)
            assert.are.equal(0x101010, active.fg)
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
