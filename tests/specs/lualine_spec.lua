describe("clodex.lualine", function()
    local original_app_preload
    local original_app_loaded

    before_each(function()
        original_app_preload = package.preload["clodex.app"]
        original_app_loaded = package.loaded["clodex.app"]
    end)

    after_each(function()
        package.preload["clodex.app"] = original_app_preload
        package.loaded["clodex.app"] = original_app_loaded
        package.loaded["clodex.lualine"] = nil
    end)

    it("renders one label per tab and highlights the active tab", function()
        local tab1 = vim.api.nvim_get_current_tabpage()
        vim.cmd.tabnew()
        local tab2 = vim.api.nvim_get_current_tabpage()
        vim.cmd.tabprevious()

        vim.api.nvim_tabpage_set_var(tab1, "clodex_active_project_root", "/tmp/project-one")
        vim.api.nvim_tabpage_set_var(tab2, "clodex_active_project_root", "/tmp/project-two")

        local registry = {
            get = function(_, root)
                if root == "/tmp/project-one" then
                    return { name = "Project One" }
                end
                if root == "/tmp/project-two" then
                    return { name = "Project Two" }
                end
            end,
            find_for_path = function()
                return nil
            end,
        }
        local tabs = {
            get = function()
                return { active_project_root = nil }
            end,
        }
        package.preload["clodex.app"] = function()
            return {
                instance = function()
                    return {
                        registry = registry,
                        tabs = tabs,
                    }
                end,
            }
        end

        local lualine = require("clodex.lualine")
        local output = lualine.tab_project_names({
            tabpages = { tab1, tab2 },
            separator = " | ",
            active_hl = "ClodexActive",
            inactive_hl = "ClodexInactive",
        })

        assert.are.equal(
            "%#ClodexActive#Project One%* | %#ClodexInactive#Project Two%*",
            output
        )

        if vim.api.nvim_tabpage_is_valid(tab2) then
            pcall(vim.api.nvim_tabpage_del_var, tab2, "clodex_active_project_root")
            vim.api.nvim_set_current_tabpage(tab2)
            vim.cmd.tabclose()
        end
    end)
end)
