local Helpers = require("clodex.ui.prompt_creator.helpers")

local Frame = {}

---@param win snacks.win?
---@return boolean
function Frame.is_valid_win(win)
    return win ~= nil and win.valid ~= nil and win:valid() == true
end

---@param creator Clodex.PromptCreator
---@return snacks.win?[]
function Frame.windows(creator)
    local layout = creator.layout
    return {
        creator.project_win,
        creator.kind_win,
        creator.variant_win,
        creator.footer_win,
        creator.preview_win,
        layout and layout.title_win or nil,
        layout and layout.body_win or nil,
        layout and layout.preview_win or nil,
    }
end

---@param creator Clodex.PromptCreator
---@return snacks.win[]
function Frame.valid_windows(creator)
    local windows = {}
    for _, win in ipairs(Frame.windows(creator)) do
        if Frame.is_valid_win(win) then
            windows[#windows + 1] = win
        end
    end
    return windows
end

---@param creator Clodex.PromptCreator
---@return integer?, integer?, integer?, integer?
function Frame.bounds(creator)
    local left, top, right, bottom
    for _, win in ipairs(Frame.valid_windows(creator)) do
        local ok, config = pcall(vim.api.nvim_win_get_config, win.win)
        if ok then
            local border = Helpers.window_border_padding(win)
            local frame_left = config.col - border
            local frame_top = config.row - border
            local frame_right = config.col + config.width + border
            local frame_bottom = config.row + config.height + border
            left = left and math.min(left, frame_left) or frame_left
            top = top and math.min(top, frame_top) or frame_top
            right = right and math.max(right, frame_right) or frame_right
            bottom = bottom and math.max(bottom, frame_bottom) or frame_bottom
        end
    end
    return left, top, right, bottom
end

---@param creator Clodex.PromptCreator
---@return boolean
function Frame.has_window_in_current_tab(creator)
    local current_tab = vim.api.nvim_get_current_tabpage()
    for _, win in ipairs(Frame.valid_windows(creator)) do
        local ok, tabpage = pcall(vim.api.nvim_win_get_tabpage, win.win)
        if ok and tabpage == current_tab then
            return true
        end
    end
    return false
end

---@param creator Clodex.PromptCreator
---@param callback fun(win: snacks.win)
function Frame.each_valid_window(creator, callback)
    for _, win in ipairs(Frame.valid_windows(creator)) do
        callback(win)
    end
end

return Frame
