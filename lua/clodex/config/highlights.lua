--- Highlight color source definition that can map through existing highlight groups.
---@class Clodex.Config.HighlightColorRef
---@field from string|string[]
---@field attr? "fg"|"bg"|"sp"
---@field adjust? number

--- Accepted color type for a highlight field.
---@alias Clodex.Config.HighlightColor string|integer|Clodex.Config.HighlightColorRef

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
local M = {
  groups = {
-- &&&ClodexQueueNormal&&&Lorem Ipsum&&&
    ClodexQueueNormal = {
      fg = { from = { "NormalFloat", "Normal" } },
      bg = { from = { "NormalFloat", "Pmenu", "Normal" }, attr = "bg" },
      blend = 0,
    },
-- &&&ClodexQueueFocusActive&&&Lorem Ipsum&&&
ClodexQueueFocusActive = {
      fg = { from = { "NormalFloat", "Normal" } },
      bg = { from = { "NormalFloat", "Pmenu", "Normal" }, attr = "bg", adjust = -0.28 },
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
      fg = { from = "@constructor" },
      bold =true,
    },
-- &&&ClodexPromptImprovementKindName&&&Lorem Ipsum&&&
ClodexPromptImprovementKindName = {
      fg = { from = "@constructor" },
      bold = true,
    },
-- &&&ClodexPromptTodoTitle&&&Lorem Ipsum&&&
ClodexPromptTodoTitle = {
      link = "ClodexPromptImprovementTitle",
      bold = true,
    },
-- &&&ClodexPromptTodoKindName&&&Lorem Ipsum&&&
ClodexPromptTodoKindName = {
      link = "ClodexPromptImprovementKindName",
      bold = true,
    },
-- &&&ClodexPromptBugTitle&&&Lorem Ipsum&&&
ClodexPromptBugTitle = {
      fg = { from = "DiagnosticError" },
      bold = true,
    },
-- &&&ClodexPromptNotWorkingTitle&&&Lorem Ipsum&&&
ClodexPromptNotWorkingTitle = {
      fg = { from = "DiagnosticError", adjust = 0.18 },
      bold = true,
    },
-- &&&ClodexPromptFixTitle&&&Lorem Ipsum&&&
ClodexPromptFixTitle = {
      fg = { from = { "Normal", "NormalFloat" } },
      bold = true,
    },
-- &&&ClodexPromptFreeformTitle&&&Lorem Ipsum&&&
ClodexPromptFreeformTitle = {
      link = "ClodexPromptFixTitle",
    },
-- &&&ClodexPromptAdjustmentTitle&&&Lorem Ipsum&&&
ClodexPromptAdjustmentTitle = {
      link = "ClodexPromptFixTitle",
    },
-- &&&ClodexPromptFeatureTitle&&&Lorem Ipsum&&&
ClodexPromptFeatureTitle = {
      fg = { from = "Function" },
      bold = true,
    },
-- &&&ClodexPromptRestructureTitle&&&Lorem Ipsum&&&
ClodexPromptRestructureTitle = {
      fg = { from = "String" },
      bold = true,
    },
-- &&&ClodexPromptRefactorTitle&&&Lorem Ipsum&&&
ClodexPromptRefactorTitle = {
      link = "ClodexPromptRestructureTitle",
    },
-- &&&ClodexPromptVisionTitle&&&Lorem Ipsum&&&
ClodexPromptVisionTitle = {
      fg = { from = "PreProc" },
      bold = true,
    },
-- &&&ClodexPromptIdeaTitle&&&Lorem Ipsum&&&
ClodexPromptIdeaTitle = {
      link = "ClodexPromptVisionTitle",
    },
-- &&&ClodexPromptCleanupTitle&&&Lorem Ipsum&&&
ClodexPromptCleanupTitle = {
      fg = { from = "Comment" },
      bold = true,
    },
-- &&&ClodexPromptDocsTitle&&&Lorem Ipsum&&&
ClodexPromptDocsTitle = {
      fg = { from = "Special" },
      bold = true,
    },
-- &&&ClodexPromptExplainTitle&&&Lorem Ipsum&&&
ClodexPromptExplainTitle = {
      fg = { from = "Type" },
      bold = true,
    },
-- &&&ClodexPromptImprovementTitleActive&&&Lorem Ipsum&&&
ClodexPromptImprovementTitleActive = {
      fg = { from = { "NormalFloat", "Pmenu", "Normal" }, attr = "bg" },
      bg = { from = "ClodexPromptImprovementTitle", attr = "fg" },
      bold = true,
    },
-- &&&ClodexPromptTodoTitleActive&&&Lorem Ipsum&&&
ClodexPromptTodoTitleActive = {
      link = "ClodexPromptImprovementTitleActive",
    },
-- &&&ClodexPromptBugTitleActive&&&Lorem Ipsum&&&
ClodexPromptBugTitleActive = {
      fg = { from = { "NormalFloat", "Pmenu", "Normal" }, attr = "bg" },
      bg = { from = "ClodexPromptBugTitle", attr = "fg" },
      bold = true,
    },
-- &&&ClodexPromptNotWorkingTitleActive&&&Lorem Ipsum&&&
ClodexPromptNotWorkingTitleActive = {
      fg = { from = { "NormalFloat", "Pmenu", "Normal" }, attr = "bg" },
      bg = { from = "ClodexPromptNotWorkingTitle", attr = "fg" },
      bold = true,
    },
-- &&&ClodexPromptFixTitleActive&&&Lorem Ipsum&&&
ClodexPromptFixTitleActive = {
      fg = { from = { "NormalFloat", "Pmenu", "Normal" }, attr = "bg" },
      bg = { from = "ClodexPromptFixTitle", attr = "fg" },
      bold = true,
    },
-- &&&ClodexPromptFreeformTitleActive&&&Lorem Ipsum&&&
ClodexPromptFreeformTitleActive = {
      link = "ClodexPromptFixTitleActive",
    },
-- &&&ClodexPromptFeatureTitleActive&&&Lorem Ipsum&&&
ClodexPromptFeatureTitleActive = {
      fg = { from = { "NormalFloat", "Pmenu", "Normal" }, attr = "bg" },
      bg = { from = "ClodexPromptFeatureTitle", attr = "fg" },
      bold = true,
    },
-- &&&ClodexPromptRestructureTitleActive&&&Lorem Ipsum&&&
ClodexPromptRestructureTitleActive = {
      fg = { from = { "NormalFloat", "Pmenu", "Normal" }, attr = "bg" },
      bg = { from = "ClodexPromptRestructureTitle", attr = "fg" },
      bold = true,
    },
-- &&&ClodexPromptRefactorTitleActive&&&Lorem Ipsum&&&
ClodexPromptRefactorTitleActive = {
      link = "ClodexPromptRestructureTitleActive",
    },
-- &&&ClodexPromptVisionTitleActive&&&Lorem Ipsum&&&
ClodexPromptVisionTitleActive = {
      fg = { from = { "NormalFloat", "Pmenu", "Normal" }, attr = "bg" },
      bg = { from = "ClodexPromptVisionTitle", attr = "fg" },
      bold = true,
    },
-- &&&ClodexPromptIdeaTitleActive&&&Lorem Ipsum&&&
ClodexPromptIdeaTitleActive = {
      link = "ClodexPromptVisionTitleActive",
    },
-- &&&ClodexPromptCleanupTitleActive&&&Lorem Ipsum&&&
ClodexPromptCleanupTitleActive = {
      fg = { from = { "NormalFloat", "Pmenu", "Normal" }, attr = "bg" },
      bg = { from = "ClodexPromptCleanupTitle", attr = "fg" },
      bold = true,
    },
-- &&&ClodexPromptDocsTitleActive&&&Lorem Ipsum&&&
ClodexPromptDocsTitleActive = {
      fg = { from = { "NormalFloat", "Pmenu", "Normal" }, attr = "bg" },
      bg = { from = "ClodexPromptDocsTitle", attr = "fg" },
      bold = true,
    },
-- &&&ClodexPromptExplainTitleActive&&&Lorem Ipsum&&&
ClodexPromptExplainTitleActive = {
      fg = { from = { "NormalFloat", "Pmenu", "Normal" }, attr = "bg" },
      bg = { from = "ClodexPromptExplainTitle", attr = "fg" },
      bold = true,
    },
-- &&&ClodexPromptSourceTab&&&Lorem Ipsum&&&
ClodexPromptSourceTab = {
      fg = { from = { "Comment", "Normal" } },
      bg = { from = { "NormalFloat", "Pmenu", "Normal" }, attr = "bg" },
      bold = true,
    },
-- &&&ClodexPromptSourceTabActive&&&Lorem Ipsum&&&
ClodexPromptSourceTabActive = {
      fg = { from = { "NormalFloat", "Pmenu", "Normal" }, attr = "bg" },
      bg = { from = { "Comment", "Normal" }, attr = "fg" },
      bold = true,
    },
-- &&&ClodexPromptPreviewText&&&Lorem Ipsum&&&
ClodexPromptPreviewText = {
      fg = { from = "Directory" },
    },
-- &&&ClodexPromptFixPreviewText&&&Lorem Ipsum&&&
ClodexPromptFixPreviewText = {
      fg = { from = { "Comment", "LineNr", "Normal" } },
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
      bg = { from = { "NormalFloat", "Pmenu", "Normal" }, attr = "bg", adjust = 0.10 },
      blend = 0,
    },
-- &&&ClodexQueueSelectionInactive&&&Lorem Ipsum&&&
ClodexQueueSelectionInactive = {
      bg = { from = { "NormalFloat", "Pmenu", "Normal" }, attr = "bg", adjust = 0.04 },
      blend = 0,
    },
-- &&&ClodexQueueCursorActive&&&Lorem Ipsum&&&
ClodexQueueCursorActive = {
      fg = { from = { "NormalFloat", "Pmenu", "Normal" }, attr = "bg", adjust = -0.28 },
      bg = { from = { "NormalFloat", "Pmenu", "Normal" }, attr = "bg", adjust = -0.28 },
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
      bg = { from = { "NormalFloat", "Pmenu", "Normal" }, attr = "bg", adjust = -0.28 },
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
      bg = { from = { "NormalFloat", "Pmenu", "Normal" }, attr = "bg" },
      blend = 0,
    },
-- &&&ClodexPromptEditorBorder&&&Lorem Ipsum&&&
ClodexPromptEditorBorder = {
      fg = { from = { "Identifier", "FloatBorder" } },
      bold = true,
    },
-- &&&ClodexPromptEditorTitle&&&Lorem Ipsum&&&
ClodexPromptEditorTitle = {
      fg = { from = { "Title", "Identifier" } },
      bold = true,
    },
-- &&&ClodexPromptEditorSubtitle&&&Lorem Ipsum&&&
ClodexPromptEditorSubtitle = {
      fg = { from = { "Comment", "Normal" } },
      italic = true,
    },
-- &&&ClodexPromptEditorFooter&&&Lorem Ipsum&&&
ClodexPromptEditorFooter = {
      fg = { from = { "Comment", "LineNr" } },
      bg = { from = { "NormalFloat", "Pmenu", "Normal" }, attr = "bg" },
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
      bold = true,
    },
-- &&&ClodexConfirmButton&&&Lorem Ipsum&&&
ClodexConfirmButton = {
      fg = { from = { "Comment", "Normal" } },
      bg = { from = { "NormalFloat", "Pmenu", "Normal" }, attr = "bg" },
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
      fg = "#e0af68",
      bold = true,
    },
  },
}

return M
