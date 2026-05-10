local PromptContext = require("clodex.prompt.context")

describe("clodex.prompt.context", function()
    it("expands file and line tokens using captured metadata", function()
        local context = {
            file_path = "/Users/dev/project/src/main.lua",
            project_root = "/Users/dev/project",
            relative_path = "src/main.lua",
            cursor_row = 12,
            cursor_col = 5,
            current_word = "function",
        }

        assert.are.equal("@src/main.lua", PromptContext.expand_token("&file", context))
        assert.are.equal("@src/main.lua: line 12", PromptContext.expand_token("&line", context))
        assert.are.equal(("\"%s\" under the cursor in @%s: line %d"):format("function", "src/main.lua", 12), PromptContext.expand_token("&word", context))
    end)

    it("replaces supported tokens in prompt templates", function()
        local context = {
            relative_path = "src/main.lua",
            file_path = "/Users/dev/project/src/main.lua",
            project_root = "/Users/dev/project",
            cursor_row = 3,
            current_word = "token",
        }

        local text = "Check line: &line\nAlso: &file\nWord: &word"
        local expanded = PromptContext.expand_text(text, context)

        assert.matches("Check line: @src/main.lua: line 3 %(%[Inserted context from &line%]%)", expanded)
        assert.matches("Also: @src/main.lua %(%[Inserted context from &file%]%)", expanded)
        assert.matches("Word: \"token\" under the cursor in @src/main.lua: line 3 %(%[Inserted context from &word%]%)", expanded)
    end)

    it("keeps invalid or unavailable tokens unchanged during expansion", function()
        local context = {
            relative_path = "src/main.lua",
            file_path = "/Users/dev/project/src/main.lua",
            project_root = "/Users/dev/project",
            cursor_row = 3,
            current_word = "token",
        }

        local text = "Keep &selection and &filex as written"
        local expanded = PromptContext.expand_text(text, context)

        assert.are.equal("Keep &selection and &filex as written", expanded)
    end)

    it("flattens multiline diagnostic messages during expansion", function()
        local buf = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_buf_set_name(buf, "/Users/dev/project/src/main.lua")
        local diagnostic_ns = vim.api.nvim_create_namespace("clodex-prompt-context-diag-test")
        vim.diagnostic.set(diagnostic_ns, buf, {
            {
                lnum = 2,
                col = 4,
                message = "context failure\nwith extra detail",
                severity = vim.diagnostic.severity.ERROR,
            },
        })

        local expanded = PromptContext.expand_text("&diagnostic", {
            buf = buf,
            file_path = "/Users/dev/project/src/main.lua",
            project_root = "/Users/dev/project",
            relative_path = "src/main.lua",
            cursor_row = 3,
        })

        assert.are.equal(
            '"context failure with extra detail" [ERROR]: file @src/main.lua : line 3 ([Inserted context from &diagnostic])',
            expanded
        )

        vim.diagnostic.reset(diagnostic_ns, buf)
        vim.api.nvim_buf_delete(buf, { force = true })
    end)

    it("filters completion tokens to only currently available context", function()
        local context = {
            buf = vim.api.nvim_create_buf(false, true),
            relative_path = "src/main.lua",
            file_path = "/Users/dev/project/src/main.lua",
            project_root = "/Users/dev/project",
            cursor_row = 3,
            current_word = "token",
        }

        local tokens = PromptContext.tokens(context)
        local labels = vim.tbl_map(function(item)
            return item.token
        end, tokens)

        assert.is_true(vim.tbl_contains(labels, "&file"))
        assert.is_true(vim.tbl_contains(labels, "&line"))
        assert.is_true(vim.tbl_contains(labels, "&word"))
        assert.is_false(vim.tbl_contains(labels, "&selection"))
        assert.is_false(vim.tbl_contains(labels, "&diagnostic"))
        assert.is_false(vim.tbl_contains(labels, "&buff_diagnostics"))
        assert.is_false(vim.tbl_contains(labels, "&all_diagnostics"))
    end)

    it("keeps quick prompts tokenized until prompt submission", function()
        local prompts = PromptContext.quick_prompts({
            relative_path = "src/main.lua",
            file_path = "/Users/dev/project/src/main.lua",
            project_root = "/Users/dev/project",
            cursor_row = 3,
            current_word = "token",
        })

        assert.are.equal(
            "Explain how the current file fits into the project and walk through the important control flow.\n\n&file",
            prompts[2].text
        )
    end)

    it("builds durable linked context for file, line, and selection references", function()
        local context = {
            relative_path = "src/main.lua",
            file_path = "/Users/dev/project/src/main.lua",
            project_root = "/Users/dev/project",
            cursor_row = 9,
            selection_start_row = 7,
            selection_end_row = 9,
            selection_text = "local value = call()",
        }

        local linked = PromptContext.linked_context(context, {
            text = "Use &file and &selection",
        })

        assert.are.equal(2, #linked)
        assert.are.same({
            kind = "file",
            token = "&file",
            file_path = "/Users/dev/project/src/main.lua",
            project_root = "/Users/dev/project",
            relative_path = "src/main.lua",
            summary = "File @src/main.lua",
        }, linked[1])
        assert.are.equal("selection", linked[2].kind)
        assert.are.equal("&selection", linked[2].token)
        assert.are.equal(7, linked[2].start_line)
        assert.are.equal(9, linked[2].end_line)
        assert.are.equal("Selection @src/main.lua:7-9", PromptContext.linked_context_summary(linked[2]))
    end)

    it("builds durable linked context for diagnostic references", function()
        local context = {
            relative_path = "src/main.lua",
            file_path = "/Users/dev/project/src/main.lua",
            project_root = "/Users/dev/project",
            cursor_row = 9,
        }

        local line_linked = PromptContext.linked_context(context, {
            text = "Fix this diagnostic\n\n&diagnostic",
        })
        local file_linked = PromptContext.linked_context(context, {
            text = "Fix buffer diagnostics\n\n&buff_diagnostics",
        })

        assert.are.equal(1, #line_linked)
        assert.are.equal("line", line_linked[1].kind)
        assert.are.equal("&diagnostic", line_linked[1].token)
        assert.are.equal(9, line_linked[1].line)

        assert.are.equal(1, #file_linked)
        assert.are.equal("file", file_linked[1].kind)
        assert.are.equal("&buff_diagnostics", file_linked[1].token)
        assert.are.equal("src/main.lua", file_linked[1].relative_path)
    end)

    it("can attach the captured file, line, and selection without explicit tokens", function()
        local linked = PromptContext.linked_context({
            relative_path = "src/main.lua",
            file_path = "/Users/dev/project/src/main.lua",
            project_root = "/Users/dev/project",
            cursor_row = 9,
            selection_start_row = 9,
            selection_end_row = 9,
            selection_text = "return value",
        }, { include_current = true })

        assert.are.equal(3, #linked)
        assert.are.equal("file", linked[1].kind)
        assert.are.equal("line", linked[2].kind)
        assert.are.equal("selection", linked[3].kind)
    end)
end)
