local Prompt = require("clodex.prompt")
local PromptContext = require("clodex.prompt.context")

local M = {}
local BUG_VARIANT_CLIPBOARD_ERROR = "clipboard_error"
local BUG_VARIANT_CLIPBOARD_SCREENSHOT = "clipboard_screenshot"
local BUG_DEFAULT_TITLE = "Investigate runtime error"
local BUG_SCREENSHOT_MESSAGE =
    "Explain the cause, implement a fix if needed, and mention any follow-up validation that should be run."

---@param path string
---@param primary boolean
---@return string
local function image_reference(path, primary)
    return (primary and "Use the attached clipboard image at `%s` as the primary context."
        or "Use the attached clipboard image at `%s` as additional context."):format(path)
end

---@param text string?
---@param context Clodex.PromptContext.Capture?
---@return string?
local function expand_field(text, context)
    text = text and vim.trim(text) or ""
    if text == "" then
        return nil
    end
    return PromptContext.expand_text(text, context)
end

---@param state table
---@return Clodex.PromptContext.Linked[]
local function linked_context(state)
    local referenced_text = table.concat({
        state.title or "",
        state.details or "",
    }, "\n")
    local context = PromptContext.linked_context(state.context, {
        text = referenced_text,
        include_current = true,
    })
    if #context > 0 then
        return context
    end
    return state.linked_context or {}
end

---@param text string?
---@return string?
local function trim_field(text)
    text = text and vim.trim(text) or ""
    return text ~= "" and text or nil
end

---@param state table
---@return boolean
local function bug_clipboard_error(state)
    return state.kind == "bug" and state.variant == BUG_VARIANT_CLIPBOARD_ERROR
end

---@param state table
---@return boolean
local function bug_clipboard_screenshot(state)
    return state.kind == "bug" and state.variant == BUG_VARIANT_CLIPBOARD_SCREENSHOT
end

---@param state table
---@return Clodex.AppPromptActions.AddTodoSpec?
function M.build_spec(state)
    local title = trim_field(state.title)
    local details = expand_field(state.details, state.context)
    local image_path = state.image_path
    local context = linked_context(state)

    if bug_clipboard_error(state) then
        local parts = {}
        local preview = state.preview_text and vim.trim(state.preview_text) or ""
        if preview ~= "" then
            parts[#parts + 1] = ("Bug message:\n```\n%s\n```"):format(preview)
        end
        parts[#parts + 1] = BUG_SCREENSHOT_MESSAGE
        return {
            title = title or BUG_DEFAULT_TITLE,
            details = table.concat(parts, "\n\n"),
            kind = "bug",
            completion_target = "history",
            context = context,
        }
    end

    local detail_parts = {} ---@type string[]
    if image_path then
        detail_parts[#detail_parts + 1] = image_reference(image_path, bug_clipboard_screenshot(state))
    end
    if details then
        detail_parts[#detail_parts + 1] = details
    end

    if not title then
        return nil
    end
    return {
        title = title,
        details = #detail_parts > 0 and table.concat(detail_parts, "\n\n") or nil,
        kind = state.kind,
        image_path = image_path,
        context = context,
        completion_target = bug_clipboard_screenshot(state) and "history" or nil,
    }
end

return M
