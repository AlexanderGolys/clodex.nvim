local fs = require("clodex.util.fs")

---@class Clodex.Mcp
local M = {}

local SOURCE_PATH = fs.normalize(debug.getinfo(1, "S").source:sub(2))
local REPO_ROOT = fs.dirname(fs.dirname(fs.dirname(SOURCE_PATH)))
local BIN_NAME = vim.fn.has("win32") == 1 and "clodex-mcp.exe" or "clodex-mcp"
local SERVER_NAME = "clodex"
local RUNTIME_SIGNATURE_SEPARATOR = "\0"
local U32_MOD = 4294967296

---@param values Clodex.Config.Values
---@return string
local function runtime_root(values)
    return fs.normalize(values.mcp.runtime_dir)
end

---@param value string
---@return string
local function toml_string(value)
    return ('"%s"'):format(value:gsub('\\', '\\\\'):gsub('"', '\\"'))
end

---@param values? Clodex.Config.Values
---@return string[]
local function raw_server_args(values)
    local configured = values and values.mcp and values.mcp.cmd or nil
    local args = {}
    local has_configured_command = type(configured) == "table" and #configured > 0
    if has_configured_command and #configured > 1 then
        local index = 2
        while index <= #configured do
            if configured[index] == "--workspace-dir" then
                index = index + 1
            else
                args[#args + 1] = configured[index]
            end
            index = index + 1
        end
    end

    local workspace_dir = values and values.storage and values.storage.workspaces_dir or nil
    if
        type(workspace_dir) == "string"
        and vim.trim(workspace_dir) ~= ""
    then
        args[#args + 1] = "--workspace-dir"
        args[#args + 1] = fs.normalize(vim.fn.expand(workspace_dir))
    end

    return args
end

---@param values Clodex.Config.Values
---@return string?
local function queue_workspace_dir(values)
    local workspace_dir = values and values.storage and values.storage.workspaces_dir or nil
    if type(workspace_dir) ~= "string" or vim.trim(workspace_dir) == "" then
        return nil
    end
    return fs.normalize(vim.fn.expand(workspace_dir))
end

---@param project_root string
---@return string
local function canonical_project_root(project_root)
    local uv = vim.uv or vim.loop
    local realpath = uv and uv.fs_realpath(project_root) or nil
    return fs.normalize(realpath or project_root)
end

---@param project_root string
---@return string
function M.workspace_id(project_root)
    project_root = canonical_project_root(project_root)
    local hash = 5381
    for index = 1, #project_root do
        hash = (hash * 33 + project_root:byte(index)) % U32_MOD
    end
    return ("%08x"):format(hash)
end

---@param values Clodex.Config.Values
---@param project_root string
---@return string
function M.queue_data_dir(values, project_root)
    local workspace_dir = queue_workspace_dir(values)
    project_root = canonical_project_root(project_root)
    if type(workspace_dir) == "string" and workspace_dir ~= "" then
        if vim.startswith(workspace_dir, "/") or workspace_dir:match("^%a:[/\\]") ~= nil then
            return fs.join(workspace_dir, M.workspace_id(project_root))
        end
        return fs.join(project_root, workspace_dir)
    end
    return fs.join(project_root, ".clodex")
end

---@param values Clodex.Config.Values
---@param project_root string
---@return string
function M.active_state_path(values, project_root)
    return fs.join(M.queue_data_dir(values, project_root), "mcp", "active.json")
end

---@param values? Clodex.Config.Values
---@return string[]
local function server_args(values)
    return vim.tbl_map(toml_string, raw_server_args(values))
end

---@param values Clodex.Config.Values
---@return string
function M.codex_home(values)
    return fs.join(runtime_root(values), "codex")
end

---@param values Clodex.Config.Values
---@return string
function M.codex_config_path(values)
    return fs.join(M.codex_home(values), "config.toml")
end

---@param values Clodex.Config.Values
---@return string
function M.opencode_config_path(values)
    return fs.join(runtime_root(values), "opencode.json")
end

---@return string
local function release_binary_path()
    return fs.join(REPO_ROOT, "rust", "clodex-mcp", "target", "release", BIN_NAME)
end

---@return string
local function debug_binary_path()
    return fs.join(REPO_ROOT, "rust", "clodex-mcp", "target", "debug", BIN_NAME)
end

---@param values? Clodex.Config.Values
---@return string[]?
function M.server_cmd(values)
    local configured = values and values.mcp and values.mcp.cmd or nil
    if type(configured) == "table" and #configured > 0 then
        return vim.deepcopy(configured)
    end

    local release = release_binary_path()
    if fs.is_file(release) then
        return { release }
    end

    local debug = debug_binary_path()
    if fs.is_file(debug) then
        return { debug }
    end

    return nil
end

---@param values? Clodex.Config.Values
---@return boolean
function M.is_available(values)
    return M.server_cmd(values) ~= nil
end

---@param values? Clodex.Config.Values
---@return boolean
function M.is_enabled(values)
    return values ~= nil and values.mcp ~= nil and values.mcp.enabled == true and M.is_available(values)
end

---@param values? Clodex.Config.Values
---@return string?
function M.runtime_signature(values)
    if not M.is_enabled(values) then
        return nil
    end

    local cmd = M.server_cmd(values)
    if not cmd then
        return nil
    end

    local parts = { runtime_root(values), values.storage and values.storage.workspaces_dir or "" }
    vim.list_extend(parts, cmd)
    vim.list_extend(parts, raw_server_args(values))
    return table.concat(parts, RUNTIME_SIGNATURE_SEPARATOR)
end

---@param values? Clodex.Config.Values
---@return string[]
function M.codex_config_args(values)
    if not M.is_enabled(values) then
        return {}
    end

    local cmd = assert(M.server_cmd(values))
    local args = {
        "-c",
        ("mcp_servers.%s.command=%s"):format(SERVER_NAME, toml_string(cmd[1])),
    }

    local server_cmd_args = server_args(values)
    if #server_cmd_args > 0 then
        args[#args + 1] = "-c"
        args[#args + 1] = ("mcp_servers.%s.args=[%s]"):format(SERVER_NAME, table.concat(server_cmd_args, ", "))
    end

    return args
end

---@param values Clodex.Config.Values
local function write_codex_runtime(values)
    local cmd = assert(M.server_cmd(values))
    local lines = {
        ("[mcp_servers.%s]"):format(SERVER_NAME),
        ("command = %s"):format(toml_string(cmd[1])),
    }

    local server_cmd_args = server_args(values)
    if #server_cmd_args > 0 then
        lines[#lines + 1] = ("args = [%s]"):format(table.concat(server_cmd_args, ", "))
    end
    local workspace_dir = queue_workspace_dir(values)
    if workspace_dir then
        lines[#lines + 1] = ("env = { CLODEX_WORKSPACES_DIR = %s }"):format(toml_string(workspace_dir))
    end

    fs.write_file(M.codex_config_path(values), table.concat(lines, "\n") .. "\n")
end

---@param values Clodex.Config.Values
local function write_opencode_runtime(values)
    local cmd = assert(M.server_cmd(values))
    local command = { cmd[1] }
    vim.list_extend(command, raw_server_args(values))
    fs.write_json(M.opencode_config_path(values), {
        mcp = {
            [SERVER_NAME] = {
                type = "local",
                command = command,
                environment = queue_workspace_dir(values) and {
                    CLODEX_WORKSPACES_DIR = queue_workspace_dir(values),
                } or nil,
                enabled = true,
            },
        },
    })
end

---@param values Clodex.Config.Values
function M.sync_runtime(values)
    if not M.is_enabled(values) then
        return
    end

    write_codex_runtime(values)
    write_opencode_runtime(values)
end

return M
