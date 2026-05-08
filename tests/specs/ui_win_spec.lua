describe("clodex.ui.win", function()
    local original_snacks
    local ui_win
    local captured

    before_each(function()
        package.loaded["clodex.ui.win"] = nil
        original_snacks = package.loaded["snacks"]
        captured = nil
        package.loaded["snacks"] = {
            win = setmetatable({
                resolve = function(defaults, style, opts)
                    captured = {
                        defaults = vim.deepcopy(defaults),
                        style = style,
                        opts = vim.deepcopy(opts),
                    }
                    return vim.tbl_extend("force", defaults, opts or {})
                end,
            }, {
                __call = function(_, resolved)
                    return {
                        win = 0,
                        buf = resolved.buf,
                        opts = resolved,
                    }
                end,
            }),
        }
        ui_win = require("clodex.ui.win")
    end)

    after_each(function()
        package.loaded["clodex.ui.win"] = nil
        package.loaded["snacks"] = original_snacks
    end)

    it("disables Snacks fixbuf for dedicated float views by default", function()
        local win = ui_win.open({
            buf = 23,
            enter = true,
            style = "minimal",
        })

        assert.are.same({
            position = "float",
            relative = "editor",
            show = true,
            noautocmd = true,
            fixbuf = false,
        }, captured.defaults)
        assert.are.equal("minimal", captured.style)
        assert.are.equal(23, win.buf)
        assert.is_false(win.opts.fixbuf)
        assert.is_true(win.opts.noautocmd)
    end)

    it("bumps low zindex values to avoid invalid backdrop zindex", function()
        local win = ui_win.open({
            buf = 23,
            zindex = 1,
        })

        assert.are.equal(2, win.opts.zindex)
    end)

    it("keeps zindex at 1 when backdrop is disabled", function()
        local win = ui_win.open({
            buf = 23,
            zindex = 1,
            backdrop = false,
        })

        assert.are.equal(1, win.opts.zindex)
    end)

    it("reuses an existing named buffer instead of failing on duplicate names", function()
        local first = ui_win.create_buffer({
            preset = "workspace",
            name = "clodex-test-duplicate-name",
        })
        local second = ui_win.create_buffer({
            preset = "workspace",
            name = "clodex-test-duplicate-name",
        })

        assert.are.equal(first, second)
        assert.is_true(vim.api.nvim_buf_is_valid(first))
    end)
end)
