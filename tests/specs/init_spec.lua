describe("clodex.init", function()
    local original_preload
    local original_app_preload
    local original_loaded
    local original_notify

    before_each(function()
        original_preload = package.preload.clodex
        original_app_preload = package.preload["clodex.app"]
        original_loaded = package.loaded["clodex.app"]
        original_notify = vim.notify
    end)

    after_each(function()
        pcall(vim.api.nvim_del_user_command, "Lazy")
        package.preload.clodex = original_preload
        package.preload["clodex.app"] = original_app_preload
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

    it("captures and restores app state around debug reload", function()
        local setup_opts
        local restored_state
        local calls = {}
        local config = {
            backend = "codex",
        }
        local reload_state = {
            tabs = {
                {
                    active_project_root = "/tmp/project",
                },
            },
            terminal_specs = {
                {
                    key = "project:/tmp/project",
                    kind = "project",
                    cwd = "/tmp/project",
                    title = "Clodex: project",
                    cmd = { "codex" },
                },
            },
        }
        local old_app = {
            config = {
                get = function()
                    return config
                end,
            },
            capture_reload_state = function()
                calls[#calls + 1] = "capture"
                return reload_state
            end,
            teardown_for_reload = function()
                calls[#calls + 1] = "teardown"
            end,
        }
        local new_app = {
            restore_reload_state = function(_, state)
                calls[#calls + 1] = "restore"
                restored_state = state
            end,
        }

        vim.notify = function() end
        package.loaded.clodex = nil
        package.loaded["clodex.app"] = {
            instance = function()
                return old_app
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
        package.preload["clodex.app"] = function()
            return {
                instance = function()
                    return new_app
                end,
            }
        end

        clodex.debug_reload()

        assert.are.same({ "capture", "teardown", "restore" }, calls)
        assert.are.same(config, setup_opts)
        assert.are.same(reload_state, restored_state)
    end)
end)
