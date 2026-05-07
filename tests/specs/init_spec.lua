describe("clodex.init", function()
    local original_preload
    local original_loaded
    local original_notify

    before_each(function()
        original_preload = package.preload.clodex
        original_loaded = package.loaded["clodex.app"]
        original_notify = vim.notify
    end)

    after_each(function()
        pcall(vim.api.nvim_del_user_command, "Lazy")
        package.preload.clodex = original_preload
        package.loaded["clodex.app"] = original_loaded
        package.loaded.clodex = nil
        vim.notify = original_notify
    end)

    it("asks Lazy to reload clodex.nvim during debug reload when available", function()
        local lazy_args
        local setup_opts
        local config = {
            backend = "opencode",
        }

        vim.api.nvim_create_user_command("Lazy", function(command)
            lazy_args = command.args
        end, { nargs = "*" })
        vim.notify = function() end
        package.loaded.clodex = nil
        package.loaded["clodex.app"] = {
            instance = function()
                return {
                    config = {
                        get = function()
                            return config
                        end,
                    },
                }
            end,
        }

        local clodex = require("clodex")
        package.preload.clodex = function()
            return {
                setup = function(opts)
                    setup_opts = opts
                end,
            }
        end

        clodex.debug_reload()

        assert.are.equal("reload clodex.nvim", lazy_args)
        assert.are.same(config, setup_opts)
    end)
end)
