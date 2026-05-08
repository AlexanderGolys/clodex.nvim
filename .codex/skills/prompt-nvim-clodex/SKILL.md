---
name: prompt-nvim-clodex
description: Handle clodex.nvim-managed queued work through the local Clodex MCP task loop.
---

Treat obvious typos in the user-written title and prompt text as mistakes to silently normalize before you interpret the task.
Keep the original intent, but do not preserve clearly accidental misspellings, duplicated words, or broken punctuation in your understanding of the request.

Use this skill when a prompt includes `$prompt-nvim-clodex`, or when you are doing normal project work inside a repository managed by clodex.nvim and need to record the outcome in that project's Clodex queue history.

When the prompt provides a queue item id or tells you to use the Clodex queued-work MCP loop:

1. Use the `clodex` MCP server as the primary queue interface.
2. Call `get_task` for the current repository root to claim or resume the active queued task.
   - Treat the returned task id and `work_prompt` as authoritative. They may differ from a queued item id shown in the prompt text when another item was already active.
   - A prompt creator implement action may arrive through direct `codex exec` or through the interactive terminal fallback; the MCP task response is authoritative in both cases.
   - The MCP helper writes the active task id, title, and kind to its local runtime `active.json`; clodex.nvim polls that file to keep open project terminal winbars and Neovim terminal title metadata aligned with the authoritative active prompt until MCP clears the active state.
   - Before MCP claims a just-dispatched interactive prompt, clodex.nvim keeps the provisional queued title visible in terminal chrome instead of clearing it during the pre-claim poll window.
   - When `get_task` resumes an existing active item, it refreshes the active file title and kind from the current queue item so older or stale active metadata still updates the terminal winbar.
   - Neovim refreshes visible terminal chrome after MCP-polled active titles change, so adopted or restored terminal windows receive the Clodex winbar expression before redraw.
   - After a task closes and queued work remains, clodex.nvim sends `/new`, waits for the backend reset to finish or become idle, and then starts the next `$prompt-nvim-clodex` turn.
   - Claimed tasks stay in the queued lane until `close_task(success = true, ...)` records completion; unsuccessful closes keep the task queued with the blocker note.
   - If an older helper left the active item in `implemented` before completion, `get_task` restores that item to `queued` before returning it.
   - Prompt creator Plan-mode implementation runs are still normal interactive queued tasks; clodex.nvim switches the terminal with `/plan` before sending `$prompt-nvim-clodex`, and this MCP task response remains the authoritative source of the actual work prompt.
   - Queue items may include a structured `context` array for linked file, line, and selection metadata; `get_task` exposes it in the task payload and appends a compact linked-context section to `work_prompt`.
   - When `prompt_execution.review_after_completion` is enabled, clodex.nvim may generate an Ask review task immediately after an implemented item closes; treat it as a normal queued review, and if no code changes are needed, close it with the reviewed commit id.
3. If `get_task` returns `status = done`, stop; the queue is exhausted.
4. Before interpreting, planning, or implementing the task, send a user-visible chat message that shows the original returned `work_prompt` text as-is so the user can see exactly what the agent is working on.
5. Otherwise, implement the returned `work_prompt`.
6. Before any successful close, update relevant `README.md` content and agent/context files so they describe the current behavior, workflow, and user-facing changes introduced by the work.
7. For the current commit-based workflow, a successful close usually requires a focused git commit and a closure payload with `success`, `comment`, and `commit_id`.
   - Exception: `idea` prompts are planning-only. They should generate follow-up prompts or plans without changing code and should close with an empty `commit_id`.
8. Call `close_task` after the work is finished:
   - on success, use `success = true`, a short completion comment, and the new `commit_id`; omit `continue_next` or set it to `false`
   - on failure or blocker, use `success = false` and provide the blocker note in `comment`; omit `continue_next` or set it to `false`
9. Stop after the close-only response. Clodex.nvim will reset the interactive backend session with `/new` and launch the next `$prompt-nvim-clodex` turn when queued work remains.
10. Compatibility note: callers that explicitly set `continue_next = true` may receive another task from `close_task`; only continue in the same loop when the tool response explicitly returns `status = task`.
11. When a conversation in planning mode should produce a new follow-up prompt instead of immediate code changes, prefer the `create_prompt` MCP tool to add the new prompt directly to the project queue.
12. Do not rely on internal queue-mutating helpers as part of the public workflow; the MCP loop itself owns task claiming, requeueing, completion, and exhaustion.
13. Do not edit queue JSON files directly. Queue storage is MCP-managed local data and may live outside the project root.
14. If queue state appears missing or stale, switch to the separate `clodex-debug` skill and use `local_data_dir` to inspect the MCP helper's current queue destination before moving or repairing any legacy files.

# Manual History

For normal project work outside queued prompt execution:

1. If queue history needs to be recorded, use the `clodex` MCP server instead of editing queue JSON files directly.
2. Before any commit, update relevant `README.md` content and agent/context files so they describe the current behavior, workflow, and user-facing changes introduced by the work.
3. Prefer `create_prompt` for follow-up work that should be queued after a discussion or planning task.
4. Do not modify queue storage files directly, including planned, queued, implemented, history, active-task, or event files.
5. Normalize obvious typos in the user request before you turn it into a title, prompt, or summary.
6. Keep the original intent, but do not preserve clearly accidental misspellings, duplicated words, or broken punctuation.
7. Use a concise `title` that describes the completed task.
8. Set `kind` to `bug` for bug fixes or regressions, otherwise use the closest existing queue category such as `todo`, `refactor`, `freeform`, `idea`, or `ask`.
9. Set `details` when extra context from the user request matters later; otherwise leave it unset.
10. Set `prompt` to a clean plain-text version of the request that could have been queued manually.
11. Set `history_summary` to a short summary of what changed or what blocker remains.
12. If the project is in git and you changed code, create a focused commit for that completed task and set `history_commits` to an array containing that new commit id; otherwise leave it unset.
13. Set `history_completed_at` and `updated_at` to a UTC timestamp like `2026-03-13T16:40:17Z`.
14. If you create a new history item, also set `created_at` and include a non-empty `id`; a generated unique string is fine.
15. Preserve existing items instead of rewriting the whole file unnecessarily.

Only create or update queue history through MCP when the conversation actually resulted in project work worth remembering. Do not create history items for pure discussion, exploration, or no-op answers.
