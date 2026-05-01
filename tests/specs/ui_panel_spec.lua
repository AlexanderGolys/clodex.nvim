describe("clodex.ui.panel", function()
    local original_ui_win
    local Panel
    local opened_windows

    before_each(function()
        package.loaded["clodex.ui.panel"] = nil
        package.loaded["clodex.ui.panel.block"] = nil
        package.loaded["clodex.ui.panel.panel"] = nil
        package.loaded["clodex.ui.panel.action"] = nil

        original_ui_win = package.loaded["clodex.ui.win"]
        opened_windows = {}

        package.loaded["clodex.ui.win"] = {
            create_buffer = function(opts)
                local buf = vim.api.nvim_create_buf(false, true)
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
            configure = function() end,
            open = function(opts)
                local object = {
                    buf = opts.buf,
                    opts = opts,
                }
                object.win = vim.api.nvim_open_win(opts.buf, opts.enter or false, {
                    relative = "editor",
                    style = "minimal",
                    border = opts.border or "none",
                    row = type(opts.row) == "function" and opts.row() or opts.row or 0,
                    col = type(opts.col) == "function" and opts.col() or opts.col or 0,
                    width = type(opts.width) == "function" and opts.width() or opts.width or 1,
                    height = type(opts.height) == "function" and opts.height() or opts.height or 1,
                })

                function object:valid()
                    return type(self.win) == "number" and self.win > 0 and vim.api.nvim_win_is_valid(self.win)
                end

                function object:update()
                    if self:valid() then
                        vim.api.nvim_win_set_config(self.win, {
                            relative = "editor",
                            row = type(self.opts.row) == "function" and self.opts.row() or self.opts.row or 0,
                            col = type(self.opts.col) == "function" and self.opts.col() or self.opts.col or 0,
                            width = type(self.opts.width) == "function" and self.opts.width() or self.opts.width or 1,
                            height = type(self.opts.height) == "function" and self.opts.height() or self.opts.height or 1,
                        })
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

        Panel = require("clodex.ui.panel").Panel
    end)

    after_each(function()
        for _, window in ipairs(opened_windows) do
            if window:valid() then
                window:close()
            end
        end
        package.loaded["clodex.ui.win"] = original_ui_win
        package.loaded["clodex.ui.panel"] = nil
        package.loaded["clodex.ui.panel.block"] = nil
        package.loaded["clodex.ui.panel.panel"] = nil
        package.loaded["clodex.ui.panel.action"] = nil
    end)

    it("destroys owned blocks and closes their windows", function()
        local panel = Panel.new({
            id = "demo",
            blocks = {
                {
                    id = "body",
                    win = { width = 10, height = 1, row = 1, col = 1, border = "rounded" },
                },
            },
        })

        panel:open()
        local block = panel:block("body")
        local winid = block:winid()

        assert.is_true(vim.api.nvim_win_is_valid(winid))

        panel:destroy()

        assert.is_false(vim.api.nvim_win_is_valid(winid))
        assert.is_nil(panel:block("body"))
    end)

    it("updates every block accent as a panel-level operation", function()
        local panel = Panel.new({
            id = "demo",
            blocks = {
                {
                    id = "title",
                    win = { width = 10, height = 1, row = 1, col = 1, border = "rounded" },
                },
                {
                    id = "body",
                    win = { width = 10, height = 1, row = 3, col = 1, border = "rounded" },
                },
            },
        })

        panel:open()
        panel:set_accent("ClodexPromptBugTitle")

        assert.is_truthy(vim.wo[panel:block("title"):winid()].winhl:find("FloatBorder:ClodexPromptBugTitle", 1, true))
        assert.is_truthy(vim.wo[panel:block("body"):winid()].winhl:find("FloatTitle:ClodexPromptBugTitle", 1, true))
    end)
end)
