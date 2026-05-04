local Details = require("clodex.project.details")
local Config = require("clodex.config")
local fs = require("clodex.util.fs")

describe("clodex.project.details", function()
    it("counts tracked git files even when they match ignore patterns", function()
        local root = vim.fn.tempname()
        fs.ensure_dir(root)
        fs.write_file(fs.join(root, ".gitignore"), "ignored.log\n")
        fs.write_file(fs.join(root, "tracked.lua"), "print('tracked')\n")
        fs.write_file(fs.join(root, "ignored.log"), "tracked anyway\n")

        assert.are.equal(0, vim.system({ "git", "-C", root, "init" }):wait().code)
        assert.are.equal(0, vim.system({ "git", "-C", root, "add", "tracked.lua" }):wait().code)
        assert.are.equal(0, vim.system({ "git", "-C", root, "add", "-f", "ignored.log" }):wait().code)

        local details = Details.new(Config.new():setup({}))
        local snapshot = details:compute({
            name = "Demo",
            root = root,
        })

        assert.are.equal(2, snapshot.file_count)

        fs.remove(root)
    end)

    it("persists custom project icons across refreshes", function()
        local root = vim.fn.tempname()
        fs.ensure_dir(root)
        local details = Details.new(Config.new():setup({}))
        local project = {
            name = "Demo",
            root = root,
        }

        details:set_icon(project, "★")

        assert.are.equal("★", details:get_icon(project))
        assert.are.equal("★", details:get(project).project_icon)

        details:set_icon(project, nil)

        assert.is_nil(details:get_icon(project))
        assert.is_nil(details:get(project).project_icon)

        fs.remove(root)
    end)
end)
