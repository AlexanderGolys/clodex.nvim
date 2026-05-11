local Extmark = require("clodex.ui.extmark")
local Prompt = require("clodex.prompt")
local PromptContext = require("clodex.prompt.context")
local ui_win = require("clodex.ui.win")
local fs = require("clodex.util.fs")
local notify = require("clodex.util.notify")
local util = require("clodex.util")

---@class Clodex.ProjectDashboard.QueueEntry
---@field queue Clodex.QueueName
---@field item Clodex.QueueItem

---@class Clodex.ProjectDashboard.PanelSpec
---@field id string
---@field title string
---@field lines string[]
---@field file boolean

---@class Clodex.ProjectDashboard
---@field app Clodex.App
---@field config Clodex.Config.Values
---@field project_buf? integer
---@field footer_buf? integer
---@field project_win? integer
---@field footer_win? integer
---@field card_blocks table<string, { buf: integer, win: snacks.win }>
---@field right_blocks table<string, { buf: integer, win: snacks.win }>
---@field chat_win? snacks.win
---@field projects Clodex.Project[]
---@field project_index integer
---@field queue_index integer
---@field queue_entries Clodex.ProjectDashboard.QueueEntry[]
---@field right_panel_offset integer
---@field chat_open boolean
---@field focus "queue"|"right"|"chat"
local Dashboard = {}
Dashboard.__index = Dashboard

local PROJECT_NS = vim.api.nvim_create_namespace("clodex-dashboard-projects")
local FOOTER_NS = vim.api.nvim_create_namespace("clodex-dashboard-footer")
local CARD_NS = vim.api.nvim_create_namespace("clodex-dashboard-cards")
local RIGHT_NS = vim.api.nvim_create_namespace("clodex-dashboard-right")
local MAIN_ZINDEX = 58
local CHAT_ZINDEX = 59
local BORDER_COLS = 2
local TOP_HEIGHT = 3
local FOOTER_HEIGHT = 3
local MIN_WIDTH = 84
local MIN_HEIGHT = 24
local QUEUE_MIN_WIDTH = 36
local RIGHT_MIN_WIDTH = 30
local QUEUE_ORDER = { "planned", "queued", "implemented", "history" }
local QUEUE_LABELS = {
    planned = "Planned",
    queued = "Queued",
    implemented = "Implemented",
    history = "History",
}
local EMPTY_LINES = { "No content yet" }

local function win_valid(win)
    return type(win) == "number" and vim.api.nvim_win_is_valid(win)
end

local function buf_valid(buf)
    return type(buf) == "number" and vim.api.nvim_buf_is_valid(buf)
end

local function floating_win_valid(win)
    return win and win.valid and win:valid()
end

local function close_floating(win)
    if not win then
        return
    end
    if win.close then
        pcall(function()
            win:close()
        end)
    elseif win.win then
        ui_win.close(win.win)
    end
end

local function make_buffer(name)
    return ui_win.create_buffer({
        preset = "workspace",
        name = name,
    })
end

local function set_lines(buf, lines, ns, extmarks)
    if not buf_valid(buf) then
        return
    end
    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, #lines > 0 and lines or { "" })
    vim.bo[buf].modifiable = false
    vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
    for _, mark in ipairs(extmarks or {}) do
        mark:place(buf, ns)
    end
end

---@param win integer
---@param changes vim.api.keyset.win_config
local function update_win(win, changes)
    if not win_valid(win) then
        return
    end
    local config = vim.api.nvim_win_get_config(win)
    for key, value in pairs(changes) do
        config[key] = value
    end
    vim.api.nvim_win_set_config(win, config)
end

---@param total integer
---@param value number
---@param minimum integer
---@return integer
local function resolve_size(total, value, minimum)
    if value <= 1 then
        return math.max(math.floor(total * value), minimum)
    end
    return math.max(math.floor(value), minimum)
end

---@param text string
---@param max_width integer
---@return string
local function truncate(text, max_width)
    text = tostring(text or "")
    if max_width <= 0 then
        return ""
    end
    if vim.fn.strdisplaywidth(text) <= max_width then
        return text
    end
    if max_width <= 3 then
        return string.rep(".", max_width)
    end
    local out = {}
    local width = 0
    local target = max_width - 3
    for index = 0, vim.fn.strchars(text) - 1 do
        local char = vim.fn.strcharpart(text, index, 1)
        local char_width = vim.fn.strdisplaywidth(char)
        if width + char_width > target then
            break
        end
        out[#out + 1] = char
        width = width + char_width
    end
    return table.concat(out) .. "..."
end

local function read_file_lines(path, max_lines)
    if not path or not fs.is_file(path) then
        return vim.deepcopy(EMPTY_LINES)
    end
    local lines = vim.fn.readfile(path)
    local limit = math.max(tonumber(max_lines) or #lines, 1)
    local out = {}
    for index = 1, math.min(#lines, limit) do
        out[#out + 1] = lines[index]
    end
    if #lines > limit then
        out[#out + 1] = ("... +%d more lines"):format(#lines - limit)
    end
    return #out > 0 and out or vim.deepcopy(EMPTY_LINES)
end

local function queue_label(queue)
    return QUEUE_LABELS[queue] or queue
end

---@param item Clodex.QueueItem
---@return string[]
local function queue_preview_lines(item)
    local lines = { item.title or "(untitled)" }
    for _, context_line in ipairs(PromptContext.linked_context_lines(item.context)) do
        lines[#lines + 1] = "  " .. context_line
        if #lines >= 4 then
            return lines
        end
    end
    for _, raw in ipairs(vim.split(item.prompt or "", "\n", { plain = true })) do
        local line = vim.trim(raw)
        if line ~= "" and line ~= vim.trim(item.title or "") then
            lines[#lines + 1] = "  " .. line
        end
        if #lines >= 5 then
            break
        end
    end
    return lines
end

---@param app Clodex.App
---@param project Clodex.Project
---@return Clodex.ProjectDetails.Snapshot?
local function project_details(app, project)
    local store = app.project_details_store
    if not store then
        return nil
    end
    local cached = type(store.get_cached) == "function" and store:get_cached(project) or nil
    return cached or (type(store.get) == "function" and store:get(project)) or nil
end

---@param project Clodex.Project
---@return string
local function todo_path(project)
    return fs.join(project.root, "TODO.md")
end

---@param app Clodex.App
---@param project Clodex.Project
---@return Clodex.ProjectDashboard.PanelSpec[]
local function project_panels(app, project)
    local summary = app:queue_summary(project)
    local details = project_details(app, project)
    local info = {
        ("Name: %s"):format(project.name),
        ("Root: %s"):format(project.root),
        ("Queues: %d planned / %d queued / %d implemented / %d history"):format(
            summary.counts.planned,
            summary.counts.queued,
            summary.counts.implemented,
            summary.counts.history
        ),
        ("Session: %s"):format(summary.session_running and "running" or "stopped"),
    }
    if details then
        info[#info + 1] = ("Files: %d"):format(details.file_count or 0)
        if details.remote_name and details.remote_name ~= "" then
            info[#info + 1] = ("Remote: %s"):format(details.remote_name)
        end
    end

    local bookmarks = {}
    if app.project_bookmarks and type(app.project_bookmarks.list) == "function" then
        for _, bookmark in ipairs(app.project_bookmarks:list(project)) do
            bookmarks[#bookmarks + 1] = ("%s  %s:%d"):format(bookmark.title, bookmark.path, bookmark.line)
        end
    end

    local notes = {}
    if app.project_notes and type(app.project_notes.list) == "function" then
        for _, note in ipairs(app.project_notes:list(project)) do
            notes[#notes + 1] = note.title
            for _, line in ipairs(note.summary or {}) do
                notes[#notes + 1] = "  " .. line
            end
        end
    end

    local readme = fs.find_readme(project.root)
    return {
        { id = "info", title = " Project Info ", lines = info, file = false },
        { id = "bookmarks", title = " Bookmarks ", lines = #bookmarks > 0 and bookmarks or vim.deepcopy(EMPTY_LINES), file = false },
        { id = "notes", title = " Notes ", lines = #notes > 0 and notes or vim.deepcopy(EMPTY_LINES), file = false },
        { id = "roadmap", title = " Roadmap ", lines = read_file_lines(todo_path(project), 80), file = true },
        { id = "readme", title = " README ", lines = read_file_lines(readme, 100), file = true },
    }
end

---@param app Clodex.App
---@param config Clodex.Config.Values
---@return Clodex.ProjectDashboard
function Dashboard.new(app, config)
    return setmetatable({
        app = app,
        config = config,
        card_blocks = {},
        right_blocks = {},
        projects = {},
        project_index = 1,
        queue_index = 1,
        queue_entries = {},
        right_panel_offset = 1,
        chat_open = false,
        focus = "queue",
    }, Dashboard)
end

---@param config Clodex.Config.Values
function Dashboard:update_config(config)
    self.config = config
end

function Dashboard:ensure_buffers()
    self.project_buf = buf_valid(self.project_buf) and self.project_buf or make_buffer("clodex-project-dashboard-projects")
    self.footer_buf = buf_valid(self.footer_buf) and self.footer_buf or make_buffer("clodex-project-dashboard-footer")
end

---@return integer, integer, integer, integer, integer, integer, integer, integer
function Dashboard:layout()
    local ui_state = vim.api.nvim_list_uis()[1]
    local columns = ui_state and ui_state.width or vim.o.columns
    local lines = ui_state and ui_state.height or vim.o.lines
    local cfg = self.config.queue_workspace or {}
    local width = math.min(resolve_size(columns, tonumber(cfg.width) or 1, MIN_WIDTH), columns)
    local height = math.min(resolve_size(lines - 2, tonumber(cfg.height) or 1, MIN_HEIGHT), lines - 2)
    local row = math.max(math.floor((lines - height) / 2), 0)
    local col = math.max(math.floor((columns - width) / 2), 0)
    local body_row = row + TOP_HEIGHT + 1
    local body_height = math.max(height - TOP_HEIGHT - FOOTER_HEIGHT - 2, 1)
    local content_width = math.max(width - BORDER_COLS, QUEUE_MIN_WIDTH + RIGHT_MIN_WIDTH)
    local queue_width = math.max(math.floor(content_width * 0.46), QUEUE_MIN_WIDTH)
    local right_width = math.max(content_width - queue_width - 1, RIGHT_MIN_WIDTH)
    local footer_row = body_row + body_height + 1
    return row, col, width, body_row, body_height, queue_width, right_width, footer_row
end

---@return boolean
function Dashboard:is_open()
    return win_valid(self.project_win) and win_valid(self.footer_win)
end

function Dashboard:open()
    if self:is_open() then
        self:refresh()
        return
    end
    self:ensure_buffers()
    local row, col, width, _, _, _, _, footer_row = self:layout()
    local project = ui_win.open({
        buf = self.project_buf,
        enter = true,
        fixbuf = false,
        row = row,
        col = col,
        width = width,
        height = 1,
        style = "minimal",
        border = "rounded",
        title = " Projects ",
        zindex = MAIN_ZINDEX,
        view = "panel",
    })
    local footer = ui_win.open({
        buf = self.footer_buf,
        enter = false,
        fixbuf = false,
        row = footer_row,
        col = col,
        width = width,
        height = 1,
        style = "minimal",
        border = "rounded",
        title = " Dashboard Actions ",
        zindex = MAIN_ZINDEX,
        view = "footer",
    })
    self.project_win = project and project.win or nil
    self.footer_win = footer and footer.win or nil
    self:attach_keymaps()
    self:refresh(true)
end

function Dashboard:close_cards()
    for _, block in pairs(self.card_blocks) do
        close_floating(block.win)
    end
    self.card_blocks = {}
end

function Dashboard:close_right_blocks()
    for _, block in pairs(self.right_blocks) do
        close_floating(block.win)
    end
    self.right_blocks = {}
end

function Dashboard:close_chat()
    close_floating(self.chat_win)
    self.chat_win = nil
end

function Dashboard:close()
    self:close_cards()
    self:close_right_blocks()
    self:close_chat()
    ui_win.close(self.project_win)
    ui_win.close(self.footer_win)
    self.project_win = nil
    self.footer_win = nil
end

function Dashboard:selected_project()
    return self.projects[self.project_index]
end

function Dashboard:build_queue_entries(project)
    self.queue_entries = {}
    if not project then
        self.queue_index = 1
        return
    end
    local summary = self.app:queue_summary(project)
    for _, queue in ipairs(QUEUE_ORDER) do
        for _, item in ipairs(summary.queues[queue] or {}) do
            self.queue_entries[#self.queue_entries + 1] = {
                queue = queue,
                item = item,
            }
        end
    end
    if #self.queue_entries == 0 then
        self.queue_index = 1
    else
        self.queue_index = util.clamp(self.queue_index, 1, #self.queue_entries)
    end
end

function Dashboard:select_first_queued()
    local selected = 1
    for index, entry in ipairs(self.queue_entries) do
        if entry.queue == "queued" then
            selected = index
            break
        end
    end
    self.queue_index = selected
end

function Dashboard:refresh_state(initial)
    local selected = self:selected_project()
    local selected_root = selected and selected.root
    self.projects = self.app:projects_for_queue_workspace()
    if #self.projects == 0 then
        self.project_index = 1
        self.queue_index = 1
        self.queue_entries = {}
        return
    end
    if initial then
        local active_root = self.app:current_tab().active_project_root
        selected_root = active_root
    end
    self.project_index = 1
    for index, project in ipairs(self.projects) do
        if selected_root and project.root == selected_root then
            self.project_index = index
            break
        end
    end
    self:build_queue_entries(self:selected_project())
    if initial then
        self:select_first_queued()
    end
end

function Dashboard:refresh(initial)
    if not self:is_open() then
        return
    end
    self:refresh_state(initial)
    local row, col, width, _, _, _, _, footer_row = self:layout()
    update_win(self.project_win, { row = row, col = col, width = width, height = 1 })
    update_win(self.footer_win, { row = footer_row, col = col, width = width, height = 1 })
    self:render_projects()
    self:render_queue_cards()
    self:render_right_side()
    self:render_footer()
end

function Dashboard:render_projects()
    local _, _, width = self:layout()
    if #self.projects == 0 then
        set_lines(self.project_buf, { "No projects configured" }, PROJECT_NS, {
            Extmark.inline(0, 0, #"No projects configured", "ClodexQueueItemMuted"),
        })
        return
    end
    local visible = math.min(#self.projects, math.max(math.floor(width / 18), 1))
    if visible % 2 == 0 and visible > 1 then
        visible = visible - 1
    end
    local center = math.floor(visible / 2)
    local parts = {}
    local spans = {}
    local col = 0
    local selected_start = 0
    local selected_end = 0
    for offset = -center, center do
        local index = ((self.project_index - 1 + offset) % #self.projects) + 1
        local project = self.projects[index]
        local summary = self.app:queue_summary(project)
        local label = ("%s %d/%d"):format(project.name, summary.counts.queued, summary.counts.planned)
        local text = offset == 0 and ("[%s]"):format(label) or label
        if #parts > 0 then
            parts[#parts + 1] = "   "
            col = col + 3
        end
        local start_col = col
        parts[#parts + 1] = text
        col = col + #text
        spans[#spans + 1] = {
            start_col = start_col,
            end_col = col,
            hl_group = offset == 0 and "ClodexQueueProjectCurrent" or "ClodexQueueProjectInactive",
        }
        if offset == 0 then
            selected_start = start_col
            selected_end = col
        end
    end
    local raw_line = table.concat(parts)
    local target_center = math.floor(math.max(width - 2, 1) / 2)
    local selected_center = math.floor((selected_start + selected_end) / 2)
    local padding = math.max(target_center - selected_center, 0)
    local line = truncate(string.rep(" ", padding) .. raw_line, math.max(width - 2, 1))
    local marks = {}
    for _, span in ipairs(spans) do
        if span.start_col + padding < #line then
            marks[#marks + 1] = Extmark.inline(
                0,
                span.start_col + padding,
                math.min(span.end_col + padding, #line),
                span.hl_group
            )
        end
    end
    set_lines(self.project_buf, { line }, PROJECT_NS, marks)
end

---@param key string
---@param opts snacks.win.Config
---@param lines string[]
---@param ns integer
---@param marks Clodex.Extmark[]
---@param accent? string
---@return { buf: integer, win: snacks.win }?
function Dashboard:open_or_update_block(key, opts, lines, ns, marks, accent)
    local block = self.card_blocks[key] or self.right_blocks[key]
    if not block then
        block = {
            buf = make_buffer("clodex-dashboard-" .. key),
            win = nil,
        }
        self:attach_buffer_keymaps(block.buf)
    end
    if not floating_win_valid(block.win) then
        opts.buf = block.buf
        block.win = ui_win.open(opts)
    elseif block.win.update then
        block.win.opts = vim.tbl_deep_extend("force", block.win.opts or {}, opts)
        block.win:update()
    elseif block.win.win then
        update_win(block.win.win, opts)
    end
    if accent and block.win and block.win.win then
        ui_win.apply_theme(block.win.win, "queue_inactive", {
            float_border = accent,
            float_title = accent,
        })
    end
    set_lines(block.buf, lines, ns, marks)
    return block
end

function Dashboard:render_queue_cards()
    self:close_cards()
    local _, col, _, body_row, body_height, queue_width = self:layout()
    if #self.queue_entries == 0 then
        local block = self:open_or_update_block("queue-empty", {
            row = body_row,
            col = col,
            width = queue_width,
            height = math.min(body_height, 3),
            style = "minimal",
            border = "rounded",
            title = " Queue ",
            zindex = MAIN_ZINDEX,
            view = "panel",
        }, { "No prompts queued for this project" }, CARD_NS, {
            Extmark.inline(0, 0, #"No prompts queued for this project", "ClodexQueueItemMuted"),
        })
        if block then
            self.card_blocks["queue-empty"] = block
        end
        return
    end

    local card_height = 5
    local gap = 1
    local visible = math.max(math.floor((body_height + gap) / (card_height + gap)), 1)
    visible = math.min(visible, #self.queue_entries)
    local start = util.clamp(self.queue_index - math.floor(visible / 2), 1, math.max(#self.queue_entries - visible + 1, 1))
    local y = body_row
    for index = start, start + visible - 1 do
        local entry = self.queue_entries[index]
        local item = entry.item
        local kind = Prompt.categories.get(item.kind)
        local selected = index == self.queue_index
        local title = ("%s  %s"):format(queue_label(entry.queue), kind.label or item.kind or "Prompt")
        local lines = queue_preview_lines(item)
        local marks = {
            Extmark.inline(0, 0, #lines[1], Prompt.title_group(kind.id)),
        }
        local block = self:open_or_update_block(("card-%d"):format(index), {
            row = y,
            col = col,
            width = queue_width,
            height = math.min(card_height, body_row + body_height - y),
            style = "minimal",
            border = "rounded",
            title = selected and ("* " .. title .. " ") or (" " .. title .. " "),
            zindex = MAIN_ZINDEX,
            view = "panel",
        }, lines, CARD_NS, marks, Prompt.title_border_group(kind.id))
        if block then
            self.card_blocks[("card-%d"):format(index)] = block
        end
        y = y + card_height + gap
        if y > body_row + body_height then
            break
        end
    end
end

function Dashboard:render_right_side()
    self:close_right_blocks()
    self:close_chat()
    local project = self:selected_project()
    if not project then
        return
    end
    local _, col, _, body_row, body_height, queue_width, right_width = self:layout()
    local right_col = col + queue_width + 3
    if self.chat_open then
        local session = self.app.terminals:ensure_project_session(project)
        if not session then
            notify.warn(("Could not open chat for %s"):format(project.name))
            self.chat_open = false
            return
        end
        self.chat_win = self.app.terminals:open_window(session, nil, {
            row = body_row,
            col = right_col,
            width = right_width,
            height = body_height,
            position = "float",
            relative = "editor",
            border = "rounded",
            title = (" Chat: %s "):format(project.name),
            zindex = CHAT_ZINDEX,
        })
        return
    end

    local panels = project_panels(self.app, project)
    if #panels == 0 then
        return
    end
    self.right_panel_offset = util.clamp(self.right_panel_offset, 1, #panels)
    local max_file_height = math.max(math.floor(body_height / 2), 4)
    local y = body_row
    for offset = 0, #panels - 1 do
        local panel_index = ((self.right_panel_offset - 1 + offset) % #panels) + 1
        local panel = panels[panel_index]
        local desired = panel.file and math.min(max_file_height, #panel.lines + 1) or math.min(7, #panel.lines + 1)
        local remaining = body_row + body_height - y
        local height = math.min(math.max(desired, 3), remaining)
        if height < 3 then
            break
        end
        local marks = {}
        for line_index, line in ipairs(panel.lines) do
            marks[#marks + 1] = Extmark.inline(line_index - 1, 0, #line, "ClodexQueueItem")
        end
        local block = self:open_or_update_block("right-" .. panel.id, {
            row = y,
            col = right_col,
            width = right_width,
            height = height,
            style = "minimal",
            border = "rounded",
            title = panel.title,
            zindex = MAIN_ZINDEX,
            view = panel.file and "wrapped_text" or "panel",
        }, panel.lines, RIGHT_NS, marks)
        if block then
            self.right_blocks["right-" .. panel.id] = block
        end
        y = y + height + 1
        if y >= body_row + body_height then
            break
        end
    end
end

function Dashboard:render_footer()
    local chat = self.chat_open and "chat: on" or "chat: off"
    local line = table.concat({
        "q/Esc close",
        "C-Left/C-Right project",
        "j/k queue",
        "i implement",
        "e edit",
        "m/M move",
        "a add",
        "d delete",
        "[/] panels",
        "c " .. chat,
    }, "   ")
    set_lines(self.footer_buf, { line }, FOOTER_NS, {
        Extmark.inline(0, 0, #line, "ClodexQueueFooter"),
    })
end

function Dashboard:move_project(delta)
    if #self.projects == 0 then
        return
    end
    self.project_index = ((self.project_index - 1 + delta) % #self.projects) + 1
    self:build_queue_entries(self:selected_project())
    self:select_first_queued()
    self:refresh()
end

function Dashboard:move_queue(delta)
    if #self.queue_entries == 0 then
        return
    end
    self.queue_index = util.clamp(self.queue_index + delta, 1, #self.queue_entries)
    self:refresh()
end

function Dashboard:move_right_panels(delta)
    local project = self:selected_project()
    if not project then
        return
    end
    local panels = project_panels(self.app, project)
    if #panels == 0 then
        return
    end
    self.right_panel_offset = ((self.right_panel_offset - 1 + delta) % #panels) + 1
    self.chat_open = false
    self:refresh()
end

---@return Clodex.QueueItem?, Clodex.QueueName?
function Dashboard:selected_queue_item()
    local entry = self.queue_entries[self.queue_index]
    if not entry then
        return nil, nil
    end
    return entry.item, entry.queue
end

function Dashboard:add_prompt()
    local project = self:selected_project()
    if not project then
        self.app:add_project()
        return
    end
    self.app.prompt_actions:open_creator(project, {
        category = "todo",
        context = PromptContext.capture({ project = project }),
        active_project_root = project.root,
        on_submit = function(spec, action, selected_project)
            self.app.prompt_actions:submit_prompt(selected_project or project, spec, action)
            self:build_queue_entries(project)
            self:select_first_queued()
            self:refresh()
        end,
    })
end

function Dashboard:edit_queue_item()
    local project = self:selected_project()
    local item = self:selected_queue_item()
    if not project or not item then
        notify.warn("No queue item selected")
        return
    end
    self.app.prompt_actions:open_creator(project, {
        category = Prompt.categories.is_valid(item.kind) and Prompt.categories.get(item.kind).id or "todo",
        context = PromptContext.capture({ project = project }),
        active_project_root = project.root,
        mode = "edit",
        lock_kind = true,
        submit_actions = {
            { value = "save", label = "save", keymap = { normal = "s", insert = "<C-s>" } },
        },
        initial_draft = {
            title = item.title,
            details = item.details,
            prompt = item.prompt,
            image_path = item.image_path,
            context = item.context,
        },
        on_submit = function(spec)
            self.app.queue_actions:edit_queue_item(project, item.id, {
                title = spec.title,
                details = spec.details,
                image_path = spec.image_path,
                context = spec.context,
            })
            self:refresh()
        end,
    })
end

function Dashboard:implement_queue_item()
    local project = self:selected_project()
    local item, queue = self:selected_queue_item()
    if not project or not item then
        notify.warn("No queue item selected")
        return
    end
    if queue ~= "queued" and queue ~= "planned" then
        notify.warn("Select an item from the planned or queued section")
        return
    end
    self.app.queue_actions:implement_queue_item(project, item.id)
    self:refresh()
end

function Dashboard:move_queue_item(delta)
    local project = self:selected_project()
    local item = self:selected_queue_item()
    if not project or not item then
        notify.warn("No queue item selected")
        return
    end
    if delta > 0 then
        self.app.queue_actions:advance_queue_item(project, item.id)
    else
        local _, queue = self:selected_queue_item()
        self.app.queue_actions:rewind_queue_item(project, item.id, { queue = queue })
    end
    self:refresh()
end

function Dashboard:delete_queue_item()
    local project = self:selected_project()
    local item = self:selected_queue_item()
    if not project or not item then
        notify.warn("No queue item selected")
        return
    end
    self.app.queue_actions:delete_queue_item(project, item.id)
    self.queue_index = 1
    self:refresh()
end

function Dashboard:toggle_chat()
    self.chat_open = not self.chat_open
    self.focus = self.chat_open and "chat" or "right"
    self:refresh()
end

function Dashboard:attach_keymaps()
    local function map(buf, lhs, rhs)
        if buf_valid(buf) then
            vim.keymap.set("n", lhs, rhs, { buffer = buf, nowait = true, silent = true })
        end
    end

    local function map_all(lhs, rhs)
        map(self.project_buf, lhs, rhs)
        map(self.footer_buf, lhs, rhs)
    end

    map_all("q", function() self:close() end)
    map_all("<Esc>", function() self:close() end)
    map_all("<C-Left>", function() self:move_project(-1) end)
    map_all("<C-Right>", function() self:move_project(1) end)
    map_all("j", function() self:move_queue(1) end)
    map_all("<Down>", function() self:move_queue(1) end)
    map_all("k", function() self:move_queue(-1) end)
    map_all("<Up>", function() self:move_queue(-1) end)
    map_all("[", function() self:move_right_panels(-1) end)
    map_all("]", function() self:move_right_panels(1) end)
    map_all("c", function() self:toggle_chat() end)
    map_all("a", function() self:add_prompt() end)
    map_all("e", function() self:edit_queue_item() end)
    map_all("i", function() self:implement_queue_item() end)
    map_all("m", function() self:move_queue_item(1) end)
    map_all("M", function() self:move_queue_item(-1) end)
    map_all("d", function() self:delete_queue_item() end)
end

---@param buf integer
function Dashboard:attach_buffer_keymaps(buf)
    local function map(lhs, rhs)
        if buf_valid(buf) then
            vim.keymap.set("n", lhs, rhs, { buffer = buf, nowait = true, silent = true })
        end
    end

    map("q", function() self:close() end)
    map("<Esc>", function() self:close() end)
    map("<C-Left>", function() self:move_project(-1) end)
    map("<C-Right>", function() self:move_project(1) end)
    map("j", function() self:move_queue(1) end)
    map("<Down>", function() self:move_queue(1) end)
    map("k", function() self:move_queue(-1) end)
    map("<Up>", function() self:move_queue(-1) end)
    map("[", function() self:move_right_panels(-1) end)
    map("]", function() self:move_right_panels(1) end)
    map("c", function() self:toggle_chat() end)
    map("a", function() self:add_prompt() end)
    map("e", function() self:edit_queue_item() end)
    map("i", function() self:implement_queue_item() end)
    map("m", function() self:move_queue_item(1) end)
    map("M", function() self:move_queue_item(-1) end)
    map("d", function() self:delete_queue_item() end)
end

return Dashboard
