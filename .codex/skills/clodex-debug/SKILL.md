---
name: clodex-debug
description: Diagnose and repair known clodex.nvim legacy state issues, especially local queue data left in older project-local locations.
version: 1
---

Use this skill when a user reports that clodex.nvim queue, MCP, project state, prompt execution, or shipped skill behavior looks stale, missing, or inconsistent.

Start with the least invasive checks and only apply a fix when the matching cause is present. Do not edit MCP-managed queue JSON by hand unless the fix below explicitly says to move whole files. Prefer the Clodex MCP tools for queue inspection and for discovering the authoritative local data directory.

# Checks

1. Confirm the current project root.
   - Use the repository root or the user-provided project root.
   - Do not assume that the shell cwd and the registered Clodex project root are the same.

2. Ask the MCP helper where it stores this project's queue data.
   - Call `local_data_dir` with `project_root`.
   - Treat `queue_data_dir` and `queue_files` from the response as authoritative.
   - Do not reconstruct the hash directory manually unless the tool is unavailable and the user explicitly asks for a manual diagnosis.

3. Check for legacy project-local queue files.
   - Look for these files directly under `<project_root>/.clodex/`:
     `planned.json`, `queued.json`, `implemented.json`, `history.json`.
   - If any are present, create the `queue_data_dir` from `local_data_dir`, move those files to the matching paths reported in `queue_files`, and leave non-queue project context files in `.clodex/` in place.
   - If a destination queue file already exists and is non-empty, stop and ask the user before merging or overwriting. Do not guess.
   - After moving files, call `queue_status` or `get_task` to confirm the queue is visible through MCP.

4. Check for legacy MCP runtime state.
   - Look for `<project_root>/.clodex/mcp/active.json` and `<project_root>/.clodex/mcp/events.jsonl`.
   - If the queue files were moved and these runtime files refer to the same active queue item, move them to `runtime_dir` from `local_data_dir`.
   - If the destination runtime files already exist, stop and ask before merging or overwriting.

5. Check that bundled skills are installed locally.
   - Verify that `<project_root>/.codex/skills/prompt-nvim-clodex/SKILL.md` exists.
   - Verify that `<project_root>/.codex/skills/clodex-debug/SKILL.md` exists.
   - Check each local bundled skill's `version` frontmatter against the checked-in `.codex/skills/<name>/SKILL.md` version.
   - If either is missing, unversioned, or older in a clodex.nvim repository, run the plugin's normal skill sync path by restarting setup or opening the project session, or copy the checked-in `.codex/skills/<name>/SKILL.md` file into the project-local skills directory.

6. Check MCP runtime configuration when agents cannot see the expected tools.
   - Confirm that Codex/OpenCode runtime config points to the current clodex MCP helper.
   - Confirm that any configured `--workspace-dir` and `CLODEX_WORKSPACES_DIR` values match the plugin's current `storage.workspaces_dir`.
   - If they still say `.clodex/workspaces`, treat that as stale runtime config. Rebuild or restart the helper after updating config so `local_data_dir` reports the local data workspace, not the project-local legacy path.
   - Restart the affected backend session after changing runtime config.

7. Check for stale queue-work assumptions in prompts or docs.
   - Agents should use `get_task`, `close_task`, `create_prompt`, `queue_status`, and `local_data_dir`.
   - Do not use removed internal queue mutators or edit queue storage directly.

8. Use safe reload for stale live Neovim state.
   - Prefer `:ClodexDebug reload` over manually running `:Lazy reload clodex.nvim`.
   - The reload command captures Clodex tab/session state, stops old timers and autocmds, runs Lazy reload when available, reloads Clodex modules, and restores the captured state into the fresh app instance.
   - The debug state panel supports mouse selection: click command rows to select them, double-click command rows to run them, and click the state pane to focus it.

# Legacy Queue Migration Fix

When `<project_root>/.clodex/` contains legacy queue JSON and `local_data_dir` reports a different `queue_data_dir`:

1. Create `queue_data_dir` if it does not exist.
2. Move each present legacy queue file to the exact path reported in `queue_files`.
3. Create `runtime_dir` if moving legacy MCP runtime files.
4. Move legacy runtime files only when they are needed to preserve an active claim and the destination does not already exist.
5. Confirm with `queue_status`.
6. Report exactly what moved and any files intentionally left in `.clodex/`.

# Stale Runtime Config Fix

When `local_data_dir` reports `<project_root>/.clodex/workspaces` but the real queue files exist under `stdpath("data")/clodex/workspaces/<workspace_id>`:

1. Confirm that `<project_root>/.clodex/workspaces` does not contain queue JSON.
2. Confirm that the local-data workspace contains queue JSON for the same project.
3. Update the MCP runtime config so `--workspace-dir` and `CLODEX_WORKSPACES_DIR` point to the configured local-data `storage.workspaces_dir`.
4. Rebuild or restart the MCP helper if the running agent session already launched it with stale args.
5. After restart, call `local_data_dir` and `queue_status` again.

The current helper also includes a compatibility fallback for the known stale `.clodex/workspaces` runtime config: if the legacy location has no queue files and the migrated default local-data workspace does have queue files, it uses the migrated local-data workspace.
