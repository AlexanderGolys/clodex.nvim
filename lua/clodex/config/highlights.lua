-- @@@clodex.hl

---@alias Clodex.Config.HighlightColorSource string|integer

--- Highlight color source definition that can map through existing highlight groups.
---@class Clodex.Config.HighlightColorRef
---@field from Clodex.Config.HighlightColorSource|Clodex.Config.HighlightColorSource[]
---@field attr? "fg"|"bg"|"sp"
---@field adjust? number

--- Accepted color type for a highlight field.
---@alias Clodex.Config.HighlightColor string|integer|Clodex.Config.HighlightColorRef|Clodex.Config.HighlightColor[]

--- Complete description of one Neovim highlight group.
---@class Clodex.Config.HighlightSpec
---@field link? string
---@field fg? Clodex.Config.HighlightColor
---@field bg? Clodex.Config.HighlightColor
---@field sp? Clodex.Config.HighlightColor
---@field blend? integer
---@field bold? boolean
---@field italic? boolean
---@field underline? boolean
---@field undercurl? boolean
---@field reverse? boolean
---@field strikethrough? boolean
---@field default? boolean
---@field force? boolean
---@field ctermfg? integer|string
---@field ctermbg? integer|string
---@field cterm? table|integer|string

--- Container for named highlight group specifications.
---@class Clodex.Config.Highlights
---@field groups table<string, Clodex.Config.HighlightSpec>

--- Default highlight definitions bundled with clodex.
---@type Clodex.Config.Highlights


local HLGroups = {
    bug = { "@float", "DiagnosticError"},
    float_win = { "NormalFloat", "Pmenu", "Normal" },
    not_working = { "@variable.builtin", "@error", "DiagnosticError" },
    improvement = { "@constructor", "Function", "Identifier" },
    fix = { "@symbol", "Function", "Identifier" },
    vision = { "#b366ff", "@keyword", "Keyword", "PreProc" },
}



local function float_win_bg(adjust)
    if adjust ~= nil then
        return {
            { from = HLGroups.float_win, attr = "bg", adjust = adjust },
            { from = "#101010", adjust = adjust },
        }
    end
    return {
        { from = HLGroups.float_win, attr = "bg" },
        "#101010",
    }
end


local M = {
  groups = {
-- &&&ClodexQueueNormal&&&Lorem Ipsum&&&
    ClodexQueueNormal = {
      fg = { from = { "NormalFloat", "Normal" } },
      bg = float_win_bg(),
      blend = 0,
    },
-- &&&ClodexQueueFocusActive&&&Lorem Ipsum&&&
ClodexQueueFocusActive = {
      fg = { from = { "NormalFloat", "Normal" } },
      bg = float_win_bg(-0.28),
      blend = 0,
    },
-- &&&ClodexQueueFocusInactive&&&Lorem Ipsum&&&
ClodexQueueFocusInactive = {
      fg = { from = { "NormalFloat", "Normal" } },
      bg = { from = { "NormalFloat", "Normal" }, attr = "bg" },
      blend = 0,
    },
-- &&&ClodexPickerProject&&&Lorem Ipsum&&&
ClodexPickerProject = {
      fg = { from = { "DiagnosticError", "ErrorMsg" } },
      bold = true,
    },
-- &&&ClodexPickerRoot&&&Lorem Ipsum&&&
ClodexPickerRoot = {
      fg = { from = "Directory" },
      italic = true,
    },
-- &&&ClodexPromptImprovementTitle&&&Lorem Ipsum&&&
ClodexPromptImprovementTitle = {
      fg = { from = { "@constructor", "Function", "Identifier" } },
    },
-- &&&ClodexPromptImprovementKindName&&&Lorem Ipsum&&&
ClodexPromptImprovementKindName = {
      fg = { from = { "@constructor", "Function", "Identifier" } },
      bold = true,
    },
-- &&&ClodexPromptTodoTitle&&&Lorem Ipsum&&&
ClodexPromptTodoTitle = {
      link = "ClodexPromptImprovementTitle",
    },
-- &&&ClodexPromptTodoKindName&&&Lorem Ipsum&&&
ClodexPromptTodoKindName = {
      link = "ClodexPromptImprovementKindName",
    },
-- &&&ClodexPromptBugTitle&&&Lorem Ipsum&&&
ClodexPromptBugTitle = {
      fg = { from = HLGroups.bug },
    },
-- &&&ClodexPromptBugKindName&&&Lorem Ipsum&&&
ClodexPromptBugKindName = {
      fg = { from = HLGroups.bug },
      bold = true,
    },
-- &&&ClodexPromptNotWorkingTitle&&&Lorem Ipsum&&&
ClodexPromptNotWorkingTitle = {
      fg = { from = HLGroups.not_working },
    },
-- &&&ClodexPromptNotWorkingKindName&&&Lorem Ipsum&&&
ClodexPromptNotWorkingKindName = {
      fg = { from = HLGroups.not_working },
      bold = true,
    },
-- &&&ClodexPromptFixTitle&&&Lorem Ipsum&&&
ClodexPromptFixTitle = {
      fg = { from = HLGroups.fix },
    },
-- &&&ClodexPromptFixKindName&&&Lorem Ipsum&&&
ClodexPromptFixKindName = {
      fg = { from = HLGroups.fix },
      bold = true,
    },
-- &&&ClodexPromptFreeformTitle&&&Lorem Ipsum&&&
ClodexPromptFreeformTitle = {
      link = "ClodexPromptFixTitle",
    },
-- &&&ClodexPromptFreeformKindName&&&Lorem Ipsum&&&
ClodexPromptFreeformKindName = {
      link = "ClodexPromptFixKindName",
    },
-- &&&ClodexPromptAdjustmentTitle&&&Lorem Ipsum&&&
ClodexPromptAdjustmentTitle = {
      link = "ClodexPromptFixTitle",
    },
-- &&&ClodexPromptAdjustmentKindName&&&Lorem Ipsum&&&
ClodexPromptAdjustmentKindName = {
      link = "ClodexPromptFixKindName",
    },
-- &&&ClodexPromptFeatureTitle&&&Lorem Ipsum&&&
ClodexPromptFeatureTitle = {
      fg = { from = "Function" },
    },
-- &&&ClodexPromptFeatureKindName&&&Lorem Ipsum&&&
ClodexPromptFeatureKindName = {
      fg = { from = "Function" },
      bold = true,
    },
-- &&&ClodexPromptRestructureTitle&&&Lorem Ipsum&&&
ClodexPromptRestructureTitle = {
      fg = { from = "String" },
    },
-- &&&ClodexPromptRestructureKindName&&&Lorem Ipsum&&&
ClodexPromptRestructureKindName = {
      fg = { from = "String" },
      bold = true,
    },
-- &&&ClodexPromptRefactorTitle&&&Lorem Ipsum&&&
ClodexPromptRefactorTitle = {
      link = "ClodexPromptRestructureTitle",
    },
-- &&&ClodexPromptRefactorKindName&&&Lorem Ipsum&&&
ClodexPromptRefactorKindName = {
      link = "ClodexPromptRestructureKindName",
    },
-- &&&ClodexPromptVisionTitle&&&Lorem Ipsum&&&
ClodexPromptVisionTitle = {
      fg = { from = HLGroups.vision },
    },
-- &&&ClodexPromptVisionKindName&&&Lorem Ipsum&&&
ClodexPromptVisionKindName = {
      fg = { from = HLGroups.vision },
      bold = true,
    },
-- &&&ClodexPromptIdeaTitle&&&Lorem Ipsum&&&
ClodexPromptIdeaTitle = {
      link = "ClodexPromptVisionTitle",
    },
-- &&&ClodexPromptIdeaKindName&&&Lorem Ipsum&&&
ClodexPromptIdeaKindName = {
      link = "ClodexPromptVisionKindName",
    },
-- &&&ClodexPromptCleanupTitle&&&Lorem Ipsum&&&
ClodexPromptCleanupTitle = {
      fg = { from = "Comment" },
    },
-- &&&ClodexPromptCleanupKindName&&&Lorem Ipsum&&&
ClodexPromptCleanupKindName = {
      fg = { from = "Comment" },
      bold = true,
    },
-- &&&ClodexPromptDocsTitle&&&Lorem Ipsum&&&
ClodexPromptDocsTitle = {
      fg = { from = "Special" },
    },
-- &&&ClodexPromptDocsKindName&&&Lorem Ipsum&&&
ClodexPromptDocsKindName = {
      fg = { from = "Special" },
      bold = true,
    },
-- &&&ClodexPromptExplainTitle&&&Lorem Ipsum&&&
ClodexPromptExplainTitle = {
      fg = { from = "Type" },
    },
-- &&&ClodexPromptExplainKindName&&&Lorem Ipsum&&&
ClodexPromptExplainKindName = {
      fg = { from = "Type" },
      bold = true,
    },
-- &&&ClodexPromptImprovementTitleBorder&&&Lorem Ipsum&&&
ClodexPromptImprovementTitleBorder = {
      fg = { from = { "@constructor", "Function", "Identifier" } },
      bg = float_win_bg(),
      bold = true,
    },
-- &&&ClodexPromptBugTitleBorder&&&Lorem Ipsum&&&
ClodexPromptBugTitleBorder = {
      fg = { from = HLGroups.bug },
      bg = float_win_bg(),
      bold = true,
    },
-- &&&ClodexPromptNotWorkingTitleBorder&&&Lorem Ipsum&&&
ClodexPromptNotWorkingTitleBorder = {
      fg = { from = HLGroups.not_working },
      bg = float_win_bg(),
      bold = true,
    },
-- &&&ClodexPromptFixTitleBorder&&&Lorem Ipsum&&&
ClodexPromptFixTitleBorder = {
      fg = { from = HLGroups.fix },
      bg = float_win_bg(),
      bold = true,
    },
-- &&&ClodexPromptFeatureTitleBorder&&&Lorem Ipsum&&&
ClodexPromptFeatureTitleBorder = {
      fg = { from = "Function" },
      bg = float_win_bg(),
      bold = true,
    },
-- &&&ClodexPromptRestructureTitleBorder&&&Lorem Ipsum&&&
ClodexPromptRestructureTitleBorder = {
      fg = { from = "String" },
      bg = float_win_bg(),
      bold = true,
    },
-- &&&ClodexPromptVisionTitleBorder&&&Lorem Ipsum&&&
ClodexPromptVisionTitleBorder = {
      fg = { from = HLGroups.vision },
      bg = float_win_bg(),
      bold = true,
    },
-- &&&ClodexPromptCleanupTitleBorder&&&Lorem Ipsum&&&
ClodexPromptCleanupTitleBorder = {
      fg = { from = "Comment" },
      bg = float_win_bg(),
      bold = true,
    },
-- &&&ClodexPromptDocsTitleBorder&&&Lorem Ipsum&&&
ClodexPromptDocsTitleBorder = {
      fg = { from = "Special" },
      bg = float_win_bg(),
      bold = true,
    },
-- &&&ClodexPromptExplainTitleBorder&&&Lorem Ipsum&&&
ClodexPromptExplainTitleBorder = {
      fg = { from = "Type" },
      bg = float_win_bg(),
      bold = true,
    },
-- &&&ClodexPromptImprovementTitleActive&&&Lorem Ipsum&&&
ClodexPromptImprovementTitleActive = {
      fg = float_win_bg(),
      bg = { from = { "@constructor", "Function", "Identifier" }, attr = "fg" },
      bold = true,
    },
-- &&&ClodexPromptTodoTitleActive&&&Lorem Ipsum&&&
ClodexPromptTodoTitleActive = {
      link = "ClodexPromptImprovementTitleActive",
    },
-- &&&ClodexPromptBugTitleActive&&&Lorem Ipsum&&&
ClodexPromptBugTitleActive = {
      fg = float_win_bg(),
      bg = { from = HLGroups.bug, attr = "fg" },
      bold = true,
    },

-- &&&ClodexPromptNotWorkingTitleActive&&&Lorem Ipsum&&&
ClodexPromptNotWorkingTitleActive = {
      fg = float_win_bg(),
      bg = { from = HLGroups.not_working, attr = "fg" },
      bold = true,
    },

-- &&&ClodexPromptFixTitleActive&&&Lorem Ipsum&&&
ClodexPromptFixTitleActive = {
      fg = float_win_bg(),
      bg = { from = HLGroups.fix, attr = "fg" },
      bold = true,
    },
-- &&&ClodexPromptFreeformTitleActive&&&Lorem Ipsum&&&
ClodexPromptFreeformTitleActive = {
      link = "ClodexPromptFixTitleActive",
    },
-- &&&ClodexPromptFeatureTitleActive&&&Lorem Ipsum&&&
ClodexPromptFeatureTitleActive = {
      fg = float_win_bg(),
      bg = { from = "Function", attr = "fg" },
      bold = true,
    },
-- &&&ClodexPromptRestructureTitleActive&&&Lorem Ipsum&&&
ClodexPromptRestructureTitleActive = {
      fg = float_win_bg(),
      bg = { from = "String", attr = "fg" },
      bold = true,
    },
-- &&&ClodexPromptRefactorTitleActive&&&Lorem Ipsum&&&
ClodexPromptRefactorTitleActive = {
      link = "ClodexPromptRestructureTitleActive",
    },
-- &&&ClodexPromptVisionTitleActive&&&Lorem Ipsum&&&
ClodexPromptVisionTitleActive = {
      fg = float_win_bg(),
      bg = { from = HLGroups.vision, attr = "fg" },
      bold = true,
    },
-- &&&ClodexPromptIdeaTitleActive&&&Lorem Ipsum&&&
ClodexPromptIdeaTitleActive = {
      link = "ClodexPromptVisionTitleActive",
    },
-- &&&ClodexPromptCleanupTitleActive&&&Lorem Ipsum&&&
ClodexPromptCleanupTitleActive = {
      fg = float_win_bg(),
      bg = { from = "Comment", attr = "fg" },
      bold = true,
    },
-- &&&ClodexPromptDocsTitleActive&&&Lorem Ipsum&&&
ClodexPromptDocsTitleActive = {
      fg = float_win_bg(),
      bg = { from = "Special", attr = "fg" },
      bold = true,
    },
-- &&&ClodexPromptExplainTitleActive&&&Lorem Ipsum&&&
ClodexPromptExplainTitleActive = {
      fg = float_win_bg(),
      bg = { from = "Type", attr = "fg" },
      bold = true,
    },
-- &&&ClodexPromptSourceTab&&&Lorem Ipsum&&&
ClodexPromptSourceTab = {
      fg = { from = { "Comment", "Normal" } },
      bg = float_win_bg(),
      bold = true,
    },
-- &&&ClodexPromptSourceTabActive&&&Lorem Ipsum&&&
ClodexPromptSourceTabActive = {
      fg = float_win_bg(),
      bg = { from = { "Comment", "Normal" }, attr = "fg" },
      bold = true,
    },
-- &&&ClodexPromptPreviewText&&&Lorem Ipsum&&&
ClodexPromptPreviewText = {
      fg = { from = "Directory" },
    },
-- &&&ClodexPromptFixPreviewText&&&Lorem Ipsum&&&
ClodexPromptFixPreviewText = {
      fg = { from = HLGroups.fix },
    },
-- &&&ClodexPromptFreeformPreviewText&&&Lorem Ipsum&&&
ClodexPromptFreeformPreviewText = {
      link = "ClodexPromptFixPreviewText",
    },
-- &&&ClodexBookmarkLine&&&Lorem Ipsum&&&
ClodexBookmarkLine = {
      bg = { from = { "CursorLine", "Visual" }, attr = "bg" },
    },
-- &&&ClodexBookmarkVirtualText&&&Lorem Ipsum&&&
ClodexBookmarkVirtualText = {
      fg = { from = { "DiagnosticHint", "Comment" } },
      italic = true,
    },
-- &&&ClodexQueueProjectActive&&&Lorem Ipsum&&&
ClodexQueueProjectActive = {
      fg = { from = "Directory" },
      bold = true,
    },
-- &&&ClodexQueueProjectCurrent&&&Lorem Ipsum&&&
ClodexQueueProjectCurrent = {
      fg = { from = { "DiagnosticOk", "Directory" } },
      bold = true,
    },
-- &&&ClodexQueueProjectInactive&&&Lorem Ipsum&&&
ClodexQueueProjectInactive = {
      fg = { from = "Comment" },
      italic = true,
    },
-- &&&ClodexQueueCounts&&&Lorem Ipsum&&&
ClodexQueueCounts = {
      fg = { from = "Identifier" },
    },
-- &&&ClodexQueueHeader&&&Lorem Ipsum&&&
ClodexQueueHeader = {
      fg = { from = "Title" },
      bold = true,
    },
-- &&&ClodexQueueItem&&&Lorem Ipsum&&&
ClodexQueueItem = {
      fg = { from = "Normal" },
    },
-- &&&ClodexQueueItemMuted&&&Lorem Ipsum&&&
ClodexQueueItemMuted = {
      fg = { from = { "Comment", "Normal" } },
    },
-- &&&ClodexQueueFooter&&&Lorem Ipsum&&&
ClodexQueueFooter = {
      fg = { from = { "Comment", "Normal" } },
    },
-- &&&ClodexProjectRemoteAttached&&&Lorem Ipsum&&&
ClodexProjectRemoteAttached = {
      fg = { from = "GitSignsAdd" },
      bold = true,
    },
-- &&&ClodexProjectRemoteDetached&&&Lorem Ipsum&&&
ClodexProjectRemoteDetached = {
      fg = { from = { "Comment", "NonText" } },
      bold = true,
    },
-- &&&ClodexQueueSelectionActive&&&Lorem Ipsum&&&
ClodexQueueSelectionActive = {
      bg = float_win_bg(0.10),
      blend = 0,
    },
-- &&&ClodexQueueSelectionInactive&&&Lorem Ipsum&&&
ClodexQueueSelectionInactive = {
      bg = float_win_bg(0.04),
      blend = 0,
    },
-- &&&ClodexQueueCursorActive&&&Lorem Ipsum&&&
ClodexQueueCursorActive = {
      fg = float_win_bg(-0.28),
      bg = float_win_bg(-0.28),
      blend = 0,
    },
-- &&&ClodexQueueCursorInactive&&&Lorem Ipsum&&&
ClodexQueueCursorInactive = {
      fg = { from = { "NormalFloat", "Normal" }, attr = "bg" },
      bg = { from = { "NormalFloat", "Normal" }, attr = "bg" },
      blend = 0,
    },
-- &&&ClodexQueueActiveBorder&&&Lorem Ipsum&&&
ClodexQueueActiveBorder = {
      fg = { from = { "Identifier", "FloatBorder" } },
      bg = float_win_bg(-0.28),
      bold = true,
    },
-- &&&ClodexQueueInactiveBorder&&&Lorem Ipsum&&&
ClodexQueueInactiveBorder = {
      fg = { from = { "Comment", "FloatBorder" } },
      bg = { from = { "NormalFloat", "Normal" }, attr = "bg" },
    },
-- &&&ClodexPromptEditorNormal&&&Lorem Ipsum&&&
ClodexPromptEditorNormal = {
      fg = { from = { "NormalFloat", "Normal" } },
      bg = float_win_bg(),
      blend = 0,
    },
-- &&&ClodexPromptEditorBorder&&&Lorem Ipsum&&&
ClodexPromptEditorBorder = {
      fg = { from = { "Identifier", "FloatBorder" } },
      bg = float_win_bg(),
      bold = true,
    },
-- &&&ClodexPromptEditorTitle&&&Lorem Ipsum&&&
ClodexPromptEditorTitle = {
      fg = { from = { "Title", "Identifier" } },
    },
-- &&&ClodexPromptEditorSubtitle&&&Lorem Ipsum&&&
ClodexPromptEditorSubtitle = {
      fg = { from = { "Comment", "Normal" } },
      italic = true,
    },
-- &&&ClodexPromptEditorFooter&&&Lorem Ipsum&&&
ClodexPromptEditorFooter = {
      fg = { from = { "Comment", "LineNr" } },
      bg = float_win_bg(),
    },
-- &&&ClodexPromptBackgroundOverlay&&&Lorem Ipsum&&&
ClodexPromptBackgroundOverlay = {
      fg = { from = { "Comment", "LineNr" } },
      bg = {
        { from = { "ColorColumn", "CursorLine", "Visual", "Pmenu" }, attr = "bg", adjust = 0.18 },
        { from = HLGroups.float_win, attr = "bg", adjust = 0.18 },
        "#202830",
      },
    },
-- &&&ClodexPromptEditorHint&&&Lorem Ipsum&&&
ClodexPromptEditorHint = {
      fg = { from = { "Comment", "LineNr" } },
      bg = { from = { "ColorColumn", "Visual", "Pmenu" }, attr = "bg" },
    },
-- &&&ClodexPromptEditorKey&&&Lorem Ipsum&&&
ClodexPromptEditorKey = {
      fg = { from = { "Identifier", "Special" } },
      bold = true,
    },
-- &&&ClodexPromptEditorContext&&&Lorem Ipsum&&&
ClodexPromptEditorContext = {
      fg = "#4aa8d8",
      bold = true,
    },
-- &&&ClodexTerminalStatusline&&&Lorem Ipsum&&&
ClodexTerminalStatusline = {
      fg = { from = { "Comment", "Normal" } },
      bg = { from = { "StatusLine", "Normal", "NormalFloat" }, attr = "bg" },
    },
-- &&&ClodexTerminalStatuslineActive&&&Lorem Ipsum&&&
ClodexTerminalStatuslineActive = {
      fg = { from = { "Normal", "Title" } },
      bg = { from = { "StatusLine", "Normal", "NormalFloat" }, attr = "bg" },
    },
-- &&&ClodexConfirmButton&&&Lorem Ipsum&&&
ClodexConfirmButton = {
      fg = { from = { "Comment", "Normal" } },
      bg = float_win_bg(),
      bold = true,
    },
-- &&&ClodexConfirmButtonActive&&&Lorem Ipsum&&&
ClodexConfirmButtonActive = {
      fg = { from = { "Title", "Identifier" } },
      bg = { from = { "CursorLine", "PmenuSel", "Visual" }, attr = "bg" },
      bold = true,
    },
-- &&&ClodexQueueTodoName&&&Lorem Ipsum&&&
ClodexQueueTodoName = {
      fg = "#d8873a",
      bold = true,
    },
-- &&&ClodexQueueTodoBracket&&&Lorem Ipsum&&&
ClodexQueueTodoBracket = {
      fg = "#eab36f",
      bold = true,
    },
-- &&&ClodexQueueTodoCount&&&Lorem Ipsum&&&
ClodexQueueTodoCount = {
      fg = "#f5c78a",
      bold = true,
    },
-- &&&ClodexQueueQueuedName&&&Lorem Ipsum&&&
ClodexQueueQueuedName = {
      fg = "#4aa8d8",
      bold = true,
    },
-- &&&ClodexQueueQueuedBracket&&&Lorem Ipsum&&&
ClodexQueueQueuedBracket = {
      fg = "#74c2e8",
    },
-- &&&ClodexQueueQueuedCount&&&Lorem Ipsum&&&
ClodexQueueQueuedCount = {
      fg = "#9ad8f2",
      bold = true,
    },
-- &&&ClodexQueueImplementedName&&&Lorem Ipsum&&&
ClodexQueueImplementedName = {
      fg = "#f5a0d0",
      bold = true,
    },
-- &&&ClodexQueueImplementedBracket&&&Lorem Ipsum&&&
ClodexQueueImplementedBracket = {
      fg = "#f8b8dc",
    },
-- &&&ClodexQueueImplementedCount&&&Lorem Ipsum&&&
ClodexQueueImplementedCount = {
      fg = "#fcd0e8",
      bold = true,
    },
-- &&&ClodexQueueHistoryName&&&Lorem Ipsum&&&
ClodexQueueHistoryName = {
      fg = "#79b98f",
      bold = true,
    },
-- &&&ClodexQueueHistoryBracket&&&Lorem Ipsum&&&
ClodexQueueHistoryBracket = {
      fg = "#9ad0ac",
    },
-- &&&ClodexQueueHistoryCount&&&Lorem Ipsum&&&
ClodexQueueHistoryCount = {
      fg = "#b7e1c4",
      bold = true,
    },
-- &&&ClodexStateSection&&&Lorem Ipsum&&&
ClodexStateSection = {
      fg = { from = "Directory" },
    },
-- &&&ClodexStateFieldLabel&&&Lorem Ipsum&&&
ClodexStateFieldLabel = {
      fg = { from = "@constructor" },
    },
-- &&&ClodexStateStatusActive&&&Lorem Ipsum&&&
ClodexStateStatusActive = {
      fg = { from = "@diff.plus" },
    },
-- &&&ClodexStateStatusStopped&&&Lorem Ipsum&&&
ClodexStateStatusStopped = {
      fg = { from = "ErrorMsg" },
    },
-- &&&ClodexStateStatusOffline&&&Lorem Ipsum&&&
ClodexStateStatusOffline = {
      fg = { from = "@error" },
    },
-- &&&ClodexStateBoolean&&&Lorem Ipsum&&&
ClodexStateBoolean = {
      fg = { from = "@boolean" },
    },
-- &&&ClodexStateNil&&&Lorem Ipsum&&&
ClodexStateNil = {
      fg = { from = "@constant" },
    },
-- &&&ClodexStateMarker&&&Lorem Ipsum&&&
ClodexStateMarker = {
      fg = { from = "SpecialChar" },
    },
-- &&&ClodexStateEntryTitle&&&Lorem Ipsum&&&
ClodexStateEntryTitle = {
      fg = { from = "Identifier" },
    },
-- &&&ClodexStateCommandName&&&Lorem Ipsum&&&
ClodexStateCommandName = {
      fg = { from = "Identifier" },
    },
-- &&&ClodexStateCommandHint&&&Lorem Ipsum&&&
ClodexStateCommandHint = {
      fg = { from = "Comment" },
    },
-- &&&ClodexCommitId&&&Lorem Ipsum&&&
ClodexCommitId = {
      fg = { from = { "DiagnosticError", "ErrorMsg" } },
      bold = true,
    },
  },
}

return M
