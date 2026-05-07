local fs = require("clodex.util.fs")
local Project = require("clodex.project.project")

---@class Clodex.ProjectRegistry
---@field path string
---@field projects Clodex.Project[]
---@field by_root table<string, Clodex.Project>
local Registry = {}
Registry.__index = Registry

---@param root string
---@return string
local function normalize_root(root)
    return fs.normalize(root)
end

---@param spec Clodex.Project|Clodex.Project.Record
---@return Clodex.Project
local function normalize_project(spec)
    if getmetatable(spec) == Project then
        return spec
    end
    return Project.new(spec)
end

---@param projects Clodex.Project[]
local function sort_projects(projects)
    table.sort(projects, function(left, right)
        return left.name:lower() < right.name:lower()
    end)
end

---@param projects Clodex.Project[]
---@return table<string, Clodex.Project>
local function build_lookup(projects)
    local by_root = {} ---@type table<string, Clodex.Project>
    for _, project in ipairs(projects) do
        by_root[project.root] = project
    end
    return by_root
end

---@param path string
---@param projects Clodex.Project[]
local function save_projects(path, projects)
    local records = {} ---@type Clodex.Project.Record[]
    for _, project in ipairs(projects) do
        records[#records + 1] = project:to_record()
    end
    fs.write_json(path, { projects = records })
end

---@param data any
---@return Clodex.Project[]
local function parse_projects(data)
    local projects = {} ---@type Clodex.Project[]
    if type(data) ~= "table" then
        return projects
    end

    for _, record in ipairs(data.projects or {}) do
        local ok, project = pcall(Project.new, record)
        if ok and project then
            projects[#projects + 1] = project
        end
    end

    sort_projects(projects)
    return projects
end

---@param opts { path: string }
---@return Clodex.ProjectRegistry
function Registry.new(opts)
    local self = setmetatable({}, Registry)
    self.path = normalize_root(opts.path)
    self.projects = {}
    self.by_root = {}
    self:load()
    return self
end

function Registry:load()
    self.projects = parse_projects(fs.read_json(self.path, { projects = {} }))
    self.by_root = build_lookup(self.projects)
end

function Registry:save()
    save_projects(self.path, self.projects)
end

---@return Clodex.Project[]
function Registry:list()
    return vim.deepcopy(self.projects)
end

---@param root string
---@return Clodex.Project?
function Registry:get(root)
    return self.by_root[normalize_root(root)]
end

---@param name string
---@return Clodex.Project?
function Registry:find_by_name(name)
    for _, project in ipairs(self.projects) do
        if project.name == name then
            return project
        end
    end
end

---@param root string
---@return boolean
function Registry:has_root(root)
    return self:get(root) ~= nil
end

---@param root string
---@return string
function Registry:suggest_name(root)
    return fs.basename(root)
end

---@param spec Clodex.Project|Clodex.Project.Record
---@return Clodex.Project
function Registry:add(spec)
    local project = normalize_project(spec)
    local existing = self.by_root[project.root]

    if existing then
        existing.name = project.name
    else
        self.projects[#self.projects + 1] = project
    end

    sort_projects(self.projects)
    self.by_root = build_lookup(self.projects)
    self:save()
    return existing or project
end

---@param root string
---@return Clodex.Project?
function Registry:remove(root)
    root = normalize_root(root)
    local project = self.by_root[root]
    if not project then
        return
    end

    self.by_root[root] = nil
    for index, item in ipairs(self.projects) do
        if item.root == root then
            table.remove(self.projects, index)
            break
        end
    end

    self:save()
    return project
end

---@param path string
---@return Clodex.Project?
function Registry:find_for_path(path)
    path = normalize_root(path)
    local best ---@type Clodex.Project?

    for _, project in ipairs(self.projects) do
        if fs.is_relative_to(path, project.root) and (not best or #project.root > #best.root) then
            best = project
        end
    end

    return best
end

---@param value string
---@return Clodex.Project?
function Registry:find_by_name_or_root(value)
    local normalized = normalize_root(value)
    if self.by_root[normalized] then
        return self.by_root[normalized]
    end

    return self:find_by_name(value)
end

return Registry
