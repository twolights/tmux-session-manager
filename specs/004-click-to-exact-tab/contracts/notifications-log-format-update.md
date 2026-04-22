# Contract Update: notifications.log format — add `applescript-failed` category

**Surface**: `${TMS_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/tmux-session-manager}/notifications.log`
**Parent contract**: `specs/002-claude-notification-hook/contracts/notifications-log-format.md`

Delta document. Feature 002's log format and all existing categories are unchanged. This feature adds exactly one new category.

## New category: `applescript-failed`

### When written

When the notification click callback attempts to select a terminal window/tab via AppleScript (iTerm2 or Terminal.app only) and the AppleScript phase fails for any reason. The callback then falls back to feature 002's existing `open -b` + `tms switch` path so the user still ends up on the correct session somewhere.

### Message field: failure mode

The message field (column 6 of the tab-separated log line) carries a short mode discriminator. Exactly one of:

| Mode | Trigger | User action |
|------|---------|-------------|
| `permission-denied` | osascript exit non-zero AND stderr matches `not authorized to send Apple events` or `-1743` | Open System Settings → Privacy & Security → Automation. Enable the shell's permission to control iTerm2/Terminal. |
| `no-tty-match` | osascript exit 1 (iterated all tabs, no TTY match) | Expected when the session's attached client is in a hidden window, stale, or just-closed. Self-heal on next click if state changes. |
| `script-error` | osascript stderr matches `execution error` or `syntax error` | Report as a tms bug. Indicates our script body is malformed for the user's macOS/terminal-app version. |
| `terminal-quit` | stderr matches `Can't get` / `doesn't understand` | Terminal app quit between banner emission and click; cosmetic. |
| `osascript-other` | non-zero exit with stderr not matching any of the above | Catchall. Report with log excerpt if reproducible. |

### Line shape (unchanged from feature 002)

```text
2026-04-22T18:37:02+0800	applescript-failed	my-webapp	permission_prompt	abc-123	permission-denied
```

6 tab-separated columns: timestamp, category, project, notification_type, session_id, message. No format change; just a new valid value for the category field.

## Reader contract (unchanged)

Readers (humans + future `tms log` / `tms doctor` subcommands) MUST continue to tolerate unknown categories per feature 002's extensibility clause. This feature just exercises that clause.

## Interaction with `tms install-hooks --uninstall`

No change. `install-hooks --uninstall` removes the Claude Code Notification hook entry from settings.json; notifications.log is separately user-owned state that tms never touches on uninstall (feature 002 contract).

## Manual test mapping

- `permission-denied` entry appears: quickstart.md QS-4.
- `no-tty-match` entry appears: quickstart.md QS-3 (detached session trigger).
- Entry format is parseable by existing readers: visual inspection during any QS run.
