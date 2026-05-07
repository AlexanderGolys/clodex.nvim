local Config = require("clodex.config")
local Execution = require("clodex.workspace.execution")
local fs = require("clodex.util.fs")

local function temp_dir()
    local dir = vim.fn.tempname()
    fs.ensure_dir(dir)
    return dir
end

local function new_execution(skills_dir, prompt_execution)
    prompt_execution = vim.tbl_extend("force", {
        skills_dir = skills_dir,
        skill_name = "prompt-nvim-clodex",
    }, prompt_execution or {})
    return Execution.new(Config.new():setup({
        prompt_execution = prompt_execution,
    }))
end

local function new_opencode_execution()
    return Execution.new(Config.new():setup({
        backend = "opencode",
    }))
end

describe("clodex.workspace.execution", function()
    it("syncs the global prompt skill from the repo template", function()
        local root = temp_dir()
        local execution = new_execution(fs.join(root, "skills"))

        execution:sync_prompt_skill()

        local file = assert(io.open(execution:skill_file(), "rb"))
        local content = file:read("*a")
        file:close()

        assert.matches("Use the `clodex` MCP server as the primary queue interface", content)
        assert.matches("Call `get_task`", content)
        assert.matches("Call `close_task`", content)
        assert.matches("Do not edit queue JSON files directly", content)
        assert.matches("%$prompt%-nvim%-clodex", content)

        local debug_file = assert(io.open(
            fs.join(root, "skills", "clodex-debug", "SKILL.md"),
            "rb"
        ))
        local debug_content = debug_file:read("*a")
        debug_file:close()
        assert.matches("local_data_dir", debug_content)
        assert.matches("Legacy Queue Migration Fix", debug_content)

        fs.remove(root)
    end)

    it("overwrites stale global skill content during sync", function()
        local root = temp_dir()
        local execution = new_execution(fs.join(root, "skills"))

        fs.write_file(execution:skill_file(), "stale")
        execution:sync_prompt_skill()

        local file = assert(io.open(execution:skill_file(), "rb"))
        local content = file:read("*a")
        file:close()

        assert.are_not.equal("stale", content)
        assert.matches("continue_next = false", content)

        fs.remove(root)
    end)

    it("renders queued dispatches as skill-only prompts", function()
        local root = temp_dir()
        local project = {
            name = "Demo",
            root = fs.join(root, "project"),
        }
        fs.ensure_dir(project.root)
        local execution = new_execution(fs.join(root, "skills"))

        local todo_prompt = execution:dispatch_prompt(project, {
            id = "todo-1",
            kind = "todo",
            prompt = "Implement the fix",
        })
        local bug_prompt = execution:dispatch_prompt(project, {
            id = "bug-1",
            kind = "bug",
            prompt = "Fix the traceback",
            completion_target = "history",
        })
        local vision_prompt = execution:dispatch_prompt(project, {
            id = "idea-1",
            kind = "vision",
            prompt = "Plan the feature",
        })

        assert.are.equal("$prompt-nvim-clodex\r", todo_prompt)
        assert.are.equal("$prompt-nvim-clodex\r", bug_prompt)
        assert.are.equal("$prompt-nvim-clodex\r", vision_prompt)

        fs.remove(root)
    end)

    it("syncs the checked-in skill into the configured project-local skills dir", function()
        local root = temp_dir()
        local project = {
            name = "Demo",
            root = fs.join(root, "project"),
        }
        fs.ensure_dir(project.root)

        local execution = new_opencode_execution()
        execution:sync_prompt_skill(project)

        local skill_file = execution:skill_file(project)
        local file = assert(io.open(skill_file, "rb"))
        local content = file:read("*a")
        file:close()

        assert.are.equal(
            fs.join(project.root, ".codex/skills/prompt-nvim-clodex/SKILL.md"),
            skill_file
        )
        assert.matches("Manual History", content)
        assert.matches("%$prompt%-nvim%-clodex", content)

        local debug_file = assert(io.open(
            fs.join(project.root, ".codex/skills/clodex-debug/SKILL.md"),
            "rb"
        ))
        local debug_content = debug_file:read("*a")
        debug_file:close()
        assert.matches("known clodex.nvim legacy state issues", debug_content)

        fs.remove(root)
    end)
end)
