# clodex.nvim

Project-aware Codex and OpenCode workflows for Neovim.

`clodex.nvim` keeps one persistent terminal session per registered project root, one shared free session outside registered projects, MCP-managed queue data under Neovim's local data directory, and project-local `.clodex/` files for notes, bookmarks, skills, and other durable project context.

## What it does

- Reuses long-lived `codex` and `opencode` terminal sessions instead of disposable shells.
- Tracks an active project per tab while sharing the same session for the same project root.
- Reattaches to visible terminal buffers and recovered terminal jobs before opening a replacement CLI window, whose active prompt title matches the prompt kind accent, remains visible when unfocused, and truncates long text from the right with `[...]`.
- Keeps inactive terminal statusline visibility aligned with active windows, so the inactive line also disappears when that window is already at the latest terminal output.
- Prompts new tabs with the same project ordering used by the queue workspace, preselects the source tab's active project, opens the selected project's README when the new tab is otherwise empty, and immediately opens the selected project's chat/CLI session in that tab.
- Builds prompts from editor context such as the current file, selection, line, and diagnostics, and stores file/line/selection links as structured prompt context.
- Opens a queue workspace for planning, queuing, dispatching, and reviewing project work.
- Warns and shows a floating blocked-input window when hidden sessions are waiting for input or permission.
- Ships a local Rust MCP helper in `rust/clodex-mcp/` for queue-aware task loops.

## Requirements

- Neovim 0.10+
- `snacks.nvim`
- `codex` and/or `opencode`
- `cargo` if you want to build the bundled MCP helper

## Installation

With `lazy.nvim`:

```lua
{
    "AlexanderGolys/clodex.nvim",
    build = "cargo build --release --manifest-path rust/clodex-mcp/Cargo.toml",
    dependencies = {
        "folke/snacks.nvim,
    },
    opts = {},
}
```
\Minimal setup:

```lua
require("clodex").setup()
```

## Default config

```lua
require("clodex").setup({
    backend = "codex",
    codex_cmd = { "codex" },
    codex_args = {},
    opencode_cmd = { "opencode" },
    opencode_args = {},
    storage = {
        projects_file = vim.fn.stdpath("data") .. "/clodex/projects.json",
        workspaces_dir = vim.fn.stdpath("data") .. "/clodex/workspaces",
        session_state_dir = vim.fn.stdpath("data") .. "/clodex/session-state",
        history_file = vim.fn.stdpath("data") .. "/clodex/history.md",
    },
    terminal = {
        provider = "snacks",
        win = {
            position = "right",
            width = 0.4,
        },
        start_insert = true,
        prefer_native_statusline = true,
        blocked_input = {
            enabled = true,
            poll_ms = 1000,
            win = {
                position = "float",
                width = 0.72,
                height = 0.8,
                border = "rounded",
            },
        },
    },
    project_detection = {
        auto_suggest_git_root = false,
    },
    state_preview = {
        min_width = 36,
        max_width = 72,
        max_height = 0,
        row = 1,
        col = 2,
        winblend = 18,
        mini = {
            width = 42,
            height = 11,
            col = 2,
            winblend = 0,
        },
    },
    queue_workspace = {
        width = 1,
        height = 1,
        project_width = 0.3,
        footer_height = 3,
        preview_max_lines = 5,
        fold_preview = true,
        date_format = "ago",
    },
    bug_prompt = {
        screenshot_dir = nil,
    },
    prompt_execution = {
        receipts_dir = ".clodex/prompt-executions",
        poll_ms = 5000,
        skills_dir = ".codex/skills",
        skill_name = "prompt-nvim-clodex",
        git_workflow = "commit",
        review_after_completion = false,
    },
    mcp = {
        enabled = true,
        cmd = {},
        runtime_dir = vim.fn.stdpath("data") .. "/clodex/mcp",
    },
    session = {
        persist_current_project = true,
        free_root = vim.fn.expand("~"),
    },
    keymaps = {
        toggle = { lhs = "<leader>pt" },
        queue_workspace = { lhs = "<leader>pq" },
        state_preview = { lhs = "<leader>ps" },
        mini_state_preview = { lhs = "<leader>pS" },
        backend_toggle = { lhs = "<leader>pb" },
        chat_toggle = { lhs = "<leader>pc" },
        refresh = { lhs = "<leader>pR" },
        new_bug_prompt = { lhs = "<leader>pB" },
        new_improvement_prompt = { lhs = "<leader>pI" },
        go_to_readme = { lhs = "<leader>pM" },
    },
})
```

`codex_cmd` and `opencode_cmd` set the executable used for each backend. `codex_args` and `opencode_args` add backend-specific CLI flags whenever Clodex starts that backend, including project/free chat sessions, resumed sessions, and direct Codex execution. Codex MCP config arguments are appended after `codex_args` so the bundled queue helper remains wired to the configured workspace directory.

`queue_workspace.date_format` accepts `"ago"` for relative timestamps, existing `os.date` formats such as `"%H:%M %d.%m.%Y"`, and token formats such as `"dd.MM.yyyy hh:mm"`. Queue data keeps its saved timestamps unchanged, so older ISO queue files remain readable when the display format changes.

Set `terminal.prefer_native_statusline = false` to leave Codex terminal statusline and winbar handling to your global UI configuration. The default keeps Clodex's native terminal chrome enabled and disables lualine for `clodex_terminal` buffers when lualine is loaded.

## Prompt kinds

- `improvement` (`todo`)
- `bug`
- `fix` (`freeform`) 
- `feature`
- `restructure` (`refactor`)
- `vision` (`idea`)
- `clean-up` (`cleanup`)
- `missing-docs` (`docs`)
- `ask`
- `notworking`

Legacy queue items and command aliases using `todo`, `freeform`, `adjustment`, `refactor`, `idea`, `cleanup`, `docs`, and `explain` are still accepted and mapped to the current prompt kinds.

Bug prompt accents and queue commit ids prefer Neovim's `DiagnosticError` color, while `notworking` prompts prefer a separate variable/error fallback so follow-up failures stay visually distinct from new bug prompts.

`vision` prompts are planning-only and should produce plans or follow-up prompts instead of repository changes.

## Commands

- `:Clodex[ panel|dashboard|cli|term|chat|history|backend [codex|opencode]|header]`
- `:ClodexDebug[ panel|mini|reload]` (`reload` captures Clodex runtime state, stops old timers/autocmds, runs `:Lazy reload clodex.nvim` when Lazy is available, reloads Clodex modules, and restores tab/session state)
- `:ClodexProject add [name]`
- `:ClodexProject readme`
- `:ClodexProject todo`
- `:ClodexProject dictionary`
- `:ClodexProject cheatsheet`
- `:ClodexProject cheatsheet-panel`
- `:ClodexProject cheatsheet-add`
- `:ClodexProject notes`
- `:ClodexProject note-add`
- `:ClodexProject bookmarks`
- `:ClodexProject bookmark-add`
- `:ClodexSession new`
- `:ClodexSession compact`
- `:ClodexSession save <session-id>`
- `:ClodexPrompt [kind]`

Use `:'<,'>ClodexPrompt ...` from visual mode to seed prompt context from the selected range.

Clodex terminal buffers map `<localleader>s` in normal and terminal mode to insert `$<prompt_execution.skill_name>` into the CLI and submit it. From normal mode inside the CLI window, the mapping returns to terminal input after sending the skill trigger.

The main queue workspace panel uses the shared Clodex UI panel shell, with project, queue, and footer panes owned as one panel. Opening the panel from insert mode returns Neovim to normal mode automatically, selects the current tab's active project, and selects that project's first queued prompt when one exists. When implementing from the workspace with no existing project session, Clodex closes the workspace and opens the project terminal before dispatching the prompt so the new CLI receives the prompt in the project session. Project file counts use tracked Git files when available, so checked-in files are counted even if they also match local ignore patterns. Project detail rows use cached metadata while moving the project selection, so selecting a project does not refresh its displayed last-edit time by itself. Language summaries count Rust projects through `Cargo.toml` and `.rs` files, and skip HTML and CSS files as project language signals. Queue filtering matches prompt titles, body text, details, full prompt text, and queue labels. Clicking either main panel pane moves focus to that pane, even when the click lands on empty panel space. Its panel cursor highlights match the pane backgrounds so the text cursor stays hidden while selection highlights show the active row. Project rows color the current tab's active project with the current-project accent, and color projects with any open background or other-tab session with the active-session accent even when that session is not the current tab target.

The experimental project dashboard is available separately through `:Clodex dashboard` or `require("clodex").open_project_dashboard()`. It does not replace the stable queue workspace yet. The dashboard shows a cyclic project carousel on top, bordered queue prompt cards on the left, project panels on the right, and a compact one-line footer. Use `Ctrl-Left` and `Ctrl-Right` to cycle projects, `j`/`k` to move the selected prompt, `[`/`]` to cycle right-side project panels, and `c` to replace the right panels with the selected project's embedded chat session. The Roadmap panel reads root `TODO.md`, and the README panel previews the project README.

The debug state panel uses the same shared Clodex UI panel API as the prompt creator, with panel-owned command and state blocks. The state pane includes backend, focus, session, project, tab, queued workflow, prompt skill, and the global keymaps currently registered by Clodex. Mouse clicks select command-list rows or focus the state pane, and double-clicking a command-list row runs that command. Before rendering, and when terminal chrome looks up a session by buffer, Clodex re-adopts existing `clodex_terminal` buffers that still carry Clodex buffer metadata, so restored or already-open terminal sessions are included in the session list and runtime project status instead of appearing offline.

## Queue workflow

- `planned`: captured work not ready to run yet
- `queued`: ready to dispatch or currently claimed by the MCP loop, but not finished yet
- `implemented`: successfully closed by the MCP loop, waiting for review unless completion goes straight to history
- `history`: verified or directly completed work with summary and commit metadata

Queued execution uses project-local skills under `.codex/skills/` together with the checked-in `prompt-nvim-clodex` workflow in `.codex/skills/prompt-nvim-clodex/SKILL.md` and the checked-in `clodex-debug` repair workflow in `.codex/skills/clodex-debug/SKILL.md`. Clodex syncs those bundled skills into every registered project during setup and checks them again whenever a project session is opened. Bundled skills carry a `version` frontmatter field; missing, unversioned, or older project-local skill files are refreshed from the checked-in copy, while newer local skill files are left intact. Queue JSON lives under `storage.workspaces_dir` by default, and the MCP helper receives that path through its runtime config so agents use `get_task`, `close_task`, and `create_prompt` instead of editing queue files directly. `storage.workspaces_dir` stays authoritative even when `mcp.cmd` is customized; Clodex replaces any embedded `--workspace-dir` helper argument with the configured storage path. Queue items may carry a backward-compatible `context` array with linked file, line, and selection metadata separate from prompt text; old items without that field continue to load normally. The task returned by `get_task` is authoritative; when a prompt is queued while another item is already active, the returned task can intentionally differ from the item that launched the agent. The MCP helper includes linked prompt context in the task payload and appends a compact linked-context section to `work_prompt` so agents receive both the normal prompt text and the durable context references. The MCP helper stores the active task id, title, and kind in its local runtime `active.json`, refreshes those fields from the current queue item whenever `get_task` resumes active work, and Neovim polls that file with the queue sync timer so open project terminal winbars and `b:term_title` show the authoritative prompt title until the active task closes and the file is removed. Before MCP claims a just-dispatched interactive prompt, Clodex keeps the provisional queued title visible instead of clearing the terminal title during the pre-claim poll window. When a polled active title changes, Clodex reapplies terminal chrome to visible terminal windows before redrawing so adopted or restored windows receive the winbar expression. Interactive queued agents close one task at a time with `close_task`, which defaults to close-only behavior unless `continue_next = true` is explicitly supplied; when queued work remains, Clodex sends `/new` to the backend, waits for the reset to finish or the backend to become idle, and then starts the next `$prompt-nvim-clodex` turn so each task gets a fresh conversation while the next `get_task` response remains authoritative. When `prompt_execution.review_after_completion` is enabled, a successfully implemented item with commits gets one generated Ask review prompt placed before other queued work, and that implemented item is marked so the review request is not duplicated. A claimed task remains in `queued` until `close_task(success = true, ...)` moves it to `implemented` or `history`; failed closes keep it in `queued` with a failure note. When resuming active state left by an older helper that already moved the item to `implemented`, `get_task` restores that item to `queued` before returning it. Queued agents show the original returned `work_prompt` in chat before interpreting or implementing it so the active task is visible immediately. `:ClodexSession save <session-id>` stores an explicit backend session id on the focused implemented or history item; when that item is later marked not working, Clodex preserves the session metadata and dispatches the fix through the saved Codex or OpenCode session when the matching backend is active.

### MCP tools

- `get_task`: high-level queued-work entrypoint; claims or resumes the active item and returns the next `work_prompt`
- `close_task`: high-level queued-work closer; records success or failure, closes without claiming the next task by default, and only advances the loop when `continue_next = true`
- `create_prompt`: creates a follow-up prompt item, usually when an `ask` or planning task turns into actionable work
- `queue_status`: read-only queue inspection for UI/debug surfaces that need queue counts or active-state visibility, not for normal prompt-by-prompt task execution
- `local_data_dir`: debug/repair helper that reports the MCP server's current project queue directory, runtime directory, and per-queue file paths so legacy project-local queue files can be moved without guessing

Typical patterns:

- normal queued loop: `get_task` -> implement -> commit -> `close_task(success = true, comment, commit_id)`
- blocked queued loop: `get_task` -> investigate -> `close_task(success = false, comment)`
- MCP-driven delegation loop: `get_task` -> implement -> `close_task` -> MCP either returns the next task or reports that no queued work remains
- planning follow-up: finish an `ask`/discussion item, then use `create_prompt` to queue the next concrete task

The prompt creator opens with the title field focused in insert mode, keeps footer actions visible, docks the target-project picker on the left without putting focus in it, aligns the project picker top border with the title field top border, opens above the queue workspace panel, and keeps the queue workspace in modal-overlay mode while it is open so workspace refreshes do not steal focus back from prompt editing. It visually highlights the focused prompt pane and its border background, preserves compatible drafts, mode, and cursor position across kind switches when the same input field exists, and can preview attached clipboard images in a separate pane. When captured file, line, or selection context is linked without an image, the same right-side pane lists the linked context before submission. Image preview falls back to a stable attached-image text block when the terminal cannot render images or Snacks image placement does not become ready. The selected target project keeps the inverted picker highlight, the explicitly requested project remains selected when the creator opens, the current project keeps the active prompt accent when selected or when the target project moves elsewhere, and project picker rows follow the same project ordering as the queue workspace while padding rows to a shared visual width so selection highlights fill the row. Opening a project through Clodex or adding a prompt resets that project's displayed activity timestamp while preserving cached project details. The creator background keeps the normal one-cell margin on the top and left, adds one extra cell on the right and bottom, is reopened and remeasured during creator tab changes, reapplies its panel theme after geometry updates, and is restored when Neovim tab focus returns if the decorative background window disappeared while the creator stayed open. Borderless kind tabs use the same outer frame width as the bordered text fields below them, secondary variant tabs sit between the details editor and footer, and selected prompt kind names use an inverted highlight based on their kind color. In composer prompts, the title behaves as the first line of the details editor: insert-mode Enter splits the title into details, title overflow moves into details at a word boundary, and edit-mode raw prompt drafts are parsed back into a single title line plus details before rendering. Context macros are details-only: creators opened from commands, keymaps, or workspace actions capture the current editor context by default, typing `&` in details inserts the trigger and opens context completion immediately, valid tokens are highlighted in blue, and tokens expand into captured editor context when the prompt is submitted. File, line, and selection links are also stored separately on the queue item, including when those links came from typed context macros or from the captured editor context alone. Queue prompt rows display the prompt kind as a right-aligned bold colored prefix without extra item-left padding before prompt title text in the matching non-bold kind color, keep selected row kind labels bold, show a muted `+ctx` suffix and context preview rows when linked context is present, indent preview/body lines one tab beyond the title start, and keep the selection background behind the full kind prefix; implemented and history rows keep the original prompt title as the main text, move completion comments into muted prompt text below it, and keep unbracketed red commit ids to the right of the title row when valid commit ids exist, and omit commit metadata when none are recorded. `!` can mark implemented or history items as not working and moves the generated follow-up back to queued. `C-Up` and `C-Down` change the target project from normal or insert mode. Normal mode uses `Tab` to move focus inside the creator, and `Left`, `Right`, `C-Left`, and `C-Right` switch prompt kinds; composer field arrows keep their normal text movement until the cursor is at a title/details boundary, then defer the focus transfer until Neovim has finished the arrow mapping. Insert mode uses `Tab`/`S-Tab` to move between prompt panes, plus boundary-only `Down` from title to details and `Up` from the first details line to title, and `C-Left`/`C-Right` for prompt kinds, with handled insert-mode navigation keys consumed without inserting terminal escape text. In normal mode, `s`, `<CR>`, `.`, `p`, and `c` plan, queue, implement immediately, implement in Plan mode, or send straight to the live chat; insert mode uses `C-s`, `C-q`, `C-.`, `C-p`, and `C-c` for the same actions. Plan, queue, implement, Plan-mode implement, and chat submissions close the creator after success. Shifted plan and implement keys (`S`, `S-.`, and `C-S-.`) keep the reset-and-stay-open workflow, the prompt footer groups implement with its shifted reset alternative, and the footer keeps move-focus shortcuts plus the standalone shifted plan reset shortcut without action descriptions. Implement submissions first place the prompt in the queued lane; Codex uses direct `codex exec` when available and falls back to interactive terminal dispatch if direct start fails, while Plan-mode implement always uses the interactive terminal flow and sends `/plan` before the queued prompt. Feature prompts carry the same Plan-mode start metadata by default, including when they are queued first and implemented later. Interactive queued dispatch now sends only `$prompt-nvim-clodex`; the MCP task response supplies the actual prompt text and queue contract. While an interactive queued prompt is active, the project chat winbar shows the queued title immediately, adopts the MCP-polled prompt title in the active prompt kind accent for focused and unfocused terminal windows once claimed, truncates long titles from the right with `[...]`, and clears it when MCP removes the active task state. Codex terminal dispatch uses bracketed paste followed by a deferred submit keystroke, and OpenCode keeps its delayed submit path.

In the queue workspace project panel, press `r` to rename the project inside Clodex's registry without changing project files. Press `I` to set, change, or remove a custom project icon through `snacks.picker.icons()`.

## Project files

Clodex keeps durable project data inside each repository:

- `README.md`
- `TODO.md`
- `.codex/skills/`
- `.clodex/PROJECT_DICTIONARY.md`
- `.clodex/cheatsheet.md`
- `.clodex/notes/`
- `.clodex/bookmarks.json`

Queue state stays under `storage.workspaces_dir`, which defaults to `stdpath("data")/clodex/workspaces`, with legacy project-local queue files migrated there on first access. Agents can use the `clodex-debug` skill and `local_data_dir` MCP tool to repair older roots that still contain queue JSON directly under `.clodex/` or sessions launched from stale `.clodex/workspaces` MCP args. The MCP helper falls forward from that stale relative workspace setting to the migrated default local-data workspace when the project-local legacy location has no queue files. Global plugin state stays under `stdpath("data")/clodex/`, including the project registry, session snapshots, MCP runtime config, and the optional history markdown log.

## Public API

Main entrypoints live in `lua/clodex/init.lua`:

- `require("clodex").setup(opts)`
- `require("clodex").toggle()`
- `require("clodex").toggle_state_preview()`
- `require("clodex").toggle_mini_state_preview()`
- `require("clodex").toggle_backend()`
- `require("clodex").toggle_terminal_header()`
- `require("clodex").add_project(opts)`
- `require("clodex").rename_project(name)`
- `require("clodex").remove_project(value)`
- `require("clodex").clear_active_project()`
- `require("clodex").open_queue_workspace()`
- `require("clodex").open_project_dashboard()`
- `require("clodex").open_history()`
- `require("clodex").new_session()`
- `require("clodex").compact_session()`
- `require("clodex").save_session(session_id)`
- `require("clodex").open_project_readme_file(project)`
- `require("clodex").open_project_todo_file(project)`
- `require("clodex").open_project_dictionary_file(project)`
- `require("clodex").open_project_cheatsheet_file(project)`
- `require("clodex").toggle_project_cheatsheet_preview(project)`
- `require("clodex").add_project_cheatsheet_item(project)`
- `require("clodex").open_project_notes_picker(project)`
- `require("clodex").create_project_note(project)`
- `require("clodex").add_project_bookmark(project)`
- `require("clodex").open_project_bookmarks_picker(project)`
- `require("clodex").add_todo(opts)`
- `require("clodex").add_bug_todo(opts)`
- `require("clodex").add_prompt(opts)`
- `require("clodex").implement_next_queued_item(opts)`
- `require("clodex").implement_all_queued_items(opts)`

Statusline helpers:

- `require("clodex").lualine.project(opts)`
- `require("clodex").lualine.project_name(opts)`

## Development

Useful checks:

```bash
nvim --headless "+lua require('clodex').setup()" +qa
nvim --headless "+lua print(vim.inspect(require('clodex')))" +qa
nvim --headless -u tests/minimal_init.lua -c "PlenaryBustedFile tests/specs/config_spec.lua" +qa
bash bin/clodex-nvim-test
cargo build --release --manifest-path rust/clodex-mcp/Cargo.toml
```

Core runtime code lives under `lua/clodex/` and `plugin/clodex.lua`. The bundled MCP helper lives under `rust/clodex-mcp/`. Checked-in workflow instructions live under `.codex/skills/`. Tests live under `tests/specs/`.

## License

MIT. See `LICENSE`.
