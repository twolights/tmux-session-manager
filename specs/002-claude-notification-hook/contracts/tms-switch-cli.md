# Contract: `tms switch <project>` subcommand

**Surface**: `bin/tms` subcommand dispatch → `lib/session.sh:cmd_switch`
**Callers**: Notification click callback (primary), manual CLI use (secondary).

## Signature

```text
tms switch <project-name>
```

- `<project-name>`: required; must match a `projects[].name` in `projects.yml`.
- No flags in v1.

## Preconditions

- tms config file exists and is valid (`config_load` succeeds).
- `<project-name>` is registered in config.
- A tmux session named `<project-name>` already exists. `cmd_switch` does **not** auto-start stopped sessions — the user starts sessions with `tms start`, which is a distinct user intent. This is spec-mandated per FR-006 and Edge Case 4: "fail loudly" means surfacing an error, not silently spinning up a fresh session that the user didn't ask for.

## Postconditions (success path)

After the command returns with exit 0, the following MUST all be true:

1. A tmux session named `<project-name>` is still running (the command did not kill or recreate it).
2. Some tmux client is attached to that session (retargeted if one existed, newly attached otherwise).
3. The active window of that session is `workspace` (window 1 per project convention; the window named `workspace` per `lib/session.sh:session_create`, regardless of its numeric index).

## Behavior matrix

| State before call | Action |
|-------------------|--------|
| Session exists, client attached | `tmux switch-client -t <project>` to retarget the client; then `tmux select-window -t <project>:workspace`. |
| Session exists, no client attached, called from a TTY | `tmux attach-session -t <project>` (replacing the current terminal session); tmux selects `workspace` on attach per `select-window` below. |
| Session exists, no client attached, non-TTY (notification click callback) | `tmux switch-client -t <project>` on any existing client; if no client exists at all, `tmux attach-session -t <project>` in a detached client is not possible, so print the "no attachable client" error below and exit 1. After a successful switch, `tmux select-window -t <project>:workspace`. |
| Session does not exist | **Error**. Print to stderr: `Error: session '<project>' is not running. Run 'tms start <project>' to restart it.` Exit 1. Do NOT call `cmd_start` or otherwise create a session. |

## Error handling

| Condition | Behavior |
|-----------|----------|
| `<project>` missing from config | Print to stderr `Error: project '<project>' not found in configuration`; exit 1 (matches existing `die` convention). |
| `<project>` registered but session not running | Print to stderr `Error: session '<project>' is not running. Run 'tms start <project>' to restart it.`; exit 1. This is the FR-006 / Edge Case 4 loud-error path. |
| No tmux client available for a non-TTY switch | Print to stderr `Error: no tmux client to retarget; cannot switch from this context.`; exit 1. In practice this is rare because the click callback's `open -b <bundle>` foregrounds the user's terminal, which generally has at least one attached client somewhere. |
| `tmux` command fails non-zero | Propagate exit status; stderr output from tmux is preserved. |

## Non-goals

- No interactive prompting. `tms-switch` (the existing fzf picker) remains separate.
- No automatic creation of missing config entries; project must already be registered.
- **No auto-start of stopped sessions.** This is intentional per FR-006 and Edge Case 4 — `tms start <project>` is a distinct user intent. Callers who want the "auto-start if stopped" behavior (e.g., a future keybinding) should invoke `tms start` explicitly rather than asking `tms switch` to be clever.
- No server-side windowing choices (which pane to focus within `workspace`). `workspace.0` (editor) selection stays the responsibility of `session_create` on initial session creation.

## Manual test mapping

Covered by quickstart.md scenarios QS-3, QS-4, QS-5.
