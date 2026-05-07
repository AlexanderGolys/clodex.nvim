local fs = require("clodex.util.fs")

--- Defines the Clodex.Project.Record type for this module.
--- This annotation documents structured state so modules can pass data with consistent expectations.
---@class Clodex.Project.Record
---@field name string
---@field root string

--- Defines the Clodex.Project type for this module.
--- This annotation documents structured state so modules can pass data with consistent expectations.
---@class Clodex.Project
---@field name string
---@field root string
local Project = {}
Project.__index = Project

---@param record Clodex.Project.Record
---@return string, string
local function normalize_record(record)
    assert(type(record.name) == "string" and record.name ~= "", "project name is required")
    assert(type(record.root) == "string" and record.root ~= "", "project root is required")
    return vim.trim(record.name), fs.normalize(record.root)
end

---@param record Clodex.Project.Record
---@return Clodex.Project
function Project.new(record)
    local name, root = normalize_record(record)
    return setmetatable({
        name = name,
        root = root,
    }, Project)
end

---@return Clodex.Project.Record
function Project:to_record()
    return {
        name = self.name,
        root = self.root,
    }
end

---@return string
function Project:display_name()
    return self.name
end

return Project
