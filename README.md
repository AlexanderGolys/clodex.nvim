# clodex.nvim

Project-aware Codex and OpenCode workflows for Neovim.

`clodex.nvim` keeps one persistent terminal session per registered project root, one shared free session outside registered projects, MCP-managed queue data under Neovim's local data directory, and project-local `.clodex/` files for notes, bookmarks, skills, and other durable project context.

## What it does

- Reuses long-lived `codex` and `opencode` terminal sessions instead of disposable shells.
- Tracks an active project per tab while sharing the same session for the same project root.
- Reattaches to visible terminal buffers and recovered terminal jobs before opening a replacement CLI window, whose active prompt title matches the prompt kind accent, remains visible when unfocused, and truncates long text from the right with `[...]`.
- Prompts new tabs with the same project ordering used by the queue workspace, preselects the source tab's active project, and opens the selected project's README when the new tab is otherwise empty.
- Builds prompts from editor context such as the current file, selection, line, and diagnostics.
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
        "folke/snacks.nvim",
    },
    opts = {},
}
```

Minimal setup:

```lua
require("clodex").setup()
```

## Default config

```lua
require("clodex").setup({
    backend = "codex",
    codex_cmd = { "codex" },
    opencode_cmd = { "opencode" },
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

`vision` prompts are planning-only and should produce plans or follow-up prompts instead of repository changes.

## Commands

- `:Clodex[ panel|cli|term|chat|history|backend [codex|opencode]|header]`
- `:ClodexDebug[ panel|mini|reload]`
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
- `:ClodexPrompt [kind]`

Use `:'<,'>ClodexPrompt ...` from visual mode to seed prompt context from the selected range.

The main queue workspace panel uses the shared Clodex UI panel shell, with project, queue, and footer panes owned as one panel. Opening the panel from insert mode returns Neovim to normal mode automatically, selects the current tab's active project, and selects that project's first queued prompt when one exists. When implementing from the workspace with no existing project session, Clodex closes the workspace and opens the project terminal before dispatching the prompt so the new CLI receives the prompt in the project session. Project file counts use tracked Git files when available, so checked-in files are counted even if they also match local ignore patterns. Language summaries count Rust projects through `Cargo.toml` and `.rs` files, and skip HTML and CSS files as project language signals. Its panel cursor highlights match the pane backgrounds so the text cursor stays hidden while selection highlights show the active row. Project rows color the current tab's active project with the current-project accent, and color projects with any open background or other-tab session with the active-session accent even when that session is not the current tab target.

The debug state panel uses the same shared Clodex UI panel API as the prompt creator, with panel-owned command and state blocks. The state pane includes backend, focus, session, project, tab, queued workflow, prompt skill, and the global keymaps currently registered by Clodex. Before rendering, Clodex re-adopts existing `clodex_terminal` buffers that still carry Clodex buffer metadata, so restored or already-open terminal sessions are included in the session list and runtime project status instead of appearing offline.

## Queue workflow

- `planned`: captured work not ready to run yet
- `queued`: ready to dispatch or currently claimed by the MCP loop, but not finished yet
- `implemented`: successfully closed by the MCP loop, waiting for review unless completion goes straight to history
- `history`: verified or directly completed work with summary and commit metadata

Queued execution uses project-local skills under `.codex/skills/` together with the checked-in `prompt-nvim-clodex` workflow in `.codex/skills/prompt-nvim-clodex/SKILL.md` and the checked-in `clodex-debug` repair workflow in `.codex/skills/clodex-debug/SKILL.md`. Clodex syncs those bundled skills into every registered project during setup and again before creating a project session, so existing and newly opened roots have the local workflow files agents need. Queue JSON lives under `storage.workspaces_dir` by default, and the MCP helper receives that path through its runtime config so agents use `get_task`, `close_task`, and `create_prompt` instead of editing queue files directly. `storage.workspaces_dir` stays authoritative even when `mcp.cmd` is customized; Clodex replaces any embedded `--workspace-dir` helper argument with the configured storage path. The task returned by `get_task` is authoritative; when a prompt is queued while another item is already active, the returned task can intentionally differ from the item that launched the agent. A claimed task remains in `queued` until `close_task(success = true, ...)` moves it to `implemented` or `history`; failed closes keep it in `queued` with a failure note. Queued agents show the original returned `work_prompt` in chat before interpreting or implementing it so the active task is visible immediately.

### MCP tools

- `get_task`: high-level queued-work entrypoint; claims or resumes the active item and returns the next `work_prompt`
- `close_task`: high-level queued-work closer; records success or failure and advances the loop when another queued item exists
- `create_prompt`: creates a follow-up prompt item, usually when an `ask` or planning task turns into actionable work
- `queue_status`: read-only queue inspection for UI/debug surfaces that need queue counts or active-state visibility, not for normal prompt-by-prompt task execution
- `local_data_dir`: debug/repair helper that reports the MCP server's current project queue directory, runtime directory, and per-queue file paths so legacy project-local queue files can be moved without guessing

Typical patterns:

- normal queued loop: `get_task` -> implement -> commit -> `close_task(success = true, comment, commit_id)`
- blocked queued loop: `get_task` -> investigate -> `close_task(success = false, comment)`
- MCP-driven delegation loop: `get_task` -> implement -> `close_task` -> MCP either returns the next task or reports that no queued work remains
- planning follow-up: finish an `ask`/discussion item, then use `create_prompt` to queue the next concrete task

The prompt creator keeps footer actions visible, docks the target-project picker on the left without putting focus in it, aligns the project picker top border with the title field top border, opens above the queue workspace panel, visually highlights the focused prompt pane and its border background, preserves compatible drafts, mode, and cursor position across kind switches when the same input field exists, and can preview attached clipboard images in a separate pane. Image preview falls back to a stable attached-image text block when the terminal cannot render images or Snacks image placement does not become ready. The selected target project keeps the inverted picker highlight, the explicitly requested project remains selected when the creator opens, the current project stays colored with the active prompt accent when the target project moves elsewhere, and project picker rows follow the same project ordering as the queue workspace while padding rows to a shared visual width so selection highlights fill the row. The creator background keeps the normal one-cell margin on the top and left and adds one extra cell on the right and bottom. Borderless kind tabs use the same outer frame width as the bordered text fields below them, secondary variant tabs sit between the details editor and footer, and selected prompt kind names use an inverted highlight based on their kind color. In composer prompts, the title behaves as the first line of the details editor: insert-mode Enter splits the title into details, title overflow moves into details at a word boundary, and edit-mode raw prompt drafts are parsed back into a single title line plus details before rendering. Queue prompt rows display the prompt kind as a right-aligned bold colored prefix without extra item-left padding before prompt title text in the matching non-bold kind color, keep selected row kind labels bold, indent preview/body lines one tab beyond the title start, and keep the selection background behind the full kind prefix; implemented and history rows keep the original prompt title as the main text, move completion comments into muted prompt text below it, and keep red commit ids to the right of the title row. `!` can mark implemented or history items as not working and moves the generated follow-up back to queued. `C-Up` and `C-Down` change the target project from normal or insert mode. Normal mode uses `Tab` and vertical arrows to move focus inside the creator, and `Left`, `Right`, `C-Left`, and `C-Right` switch prompt kinds; insert mode uses `S-Tab`, plus `Down` from title to details, `Up` from details to title, and `C-Left`/`C-Right` for prompt kinds. In normal mode, `s`, `<CR>`, `.`, and `c` plan, queue, implement immediately, or send straight to the live chat; insert mode uses `C-s`, `C-q`, `C-.`, and `C-c` for the same actions. Plan, queue, implement, and chat submissions close the creator after success. Shifted plan and implement keys (`S`, `S-.`, and `C-S-.`) keep the reset-and-stay-open workflow. Implement submissions first place the prompt in the queued lane; Codex uses direct `codex exec` when available and falls back to interactive terminal dispatch if direct start fails, while OpenCode keeps the interactive terminal flow. Interactive queued dispatch now sends only `$prompt-nvim-clodex`; the MCP task response supplies the actual prompt text and queue contract. While an interactive queued prompt is working, the project chat winbar shows that prompt title in the active prompt kind accent for focused and unfocused terminal windows, truncates long titles from the right with `[...]`, and clears it when the session returns to idle. Codex terminal dispatch uses bracketed paste followed by a deferred submit keystroke, and OpenCode keeps its delayed submit path.

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
- `require("clodex").open_history()`
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
