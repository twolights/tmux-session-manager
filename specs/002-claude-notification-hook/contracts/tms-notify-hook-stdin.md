# Contract: `tms-notify-hook` stdin payload

**Surface**: `bin/tms-notify-hook` (reads JSON on stdin)
**Callers**: Claude Code's `Notification` hook dispatcher (only).

## Input contract

Exactly one JSON object on stdin per invocation. See data-model.md §Notification Event for the full field list. Authoritative source: <https://code.claude.com/docs/en/hooks-guide>.

Example payload:

```json
{
  "hook_event_name": "Notification",
  "session_id": "abc-123",
  "transcript_path": "/path/to/transcript.jsonl",
  "cwd": "/Users/alice/Projects/my-webapp",
  "message": "Claude needs your permission to run: git push",
  "notification_type": "permission_prompt"
}
```

## Execution contract

| Property | Value |
|----------|-------|
| Exit code | MUST be 0 on all paths, success or failure (FR-007: never block Claude Code). |
| Stdout | Silent on success; empty on failure. Any content printed will appear in Claude Code's internal hook log but MUST NOT block. |
| Stderr | Reserved for critical-only messages (e.g., the bash script itself crashed before the trap). Typical failures go to the notifications.log file, NOT stderr. |
| Timeout | Registered with `timeout: 10` in settings.json; the hook is architected to return in well under 1 second (terminal-notifier is invoked in a detached background subshell). |
| Parallelism | Safe — two concurrent invocations may produce two banners, which is the intended behavior when two projects notify simultaneously (spec acceptance scenario US1-2). |
| Environment | Inherits Claude Code's env. MUST NOT assume `$TMUX`, `$TERM`, or any interactive-session variable. MAY read `$TERM_PROGRAM`, `$__CFBundleIdentifier`, `$CLAUDE_PROJECT_DIR`. |

## Behavior tree

```text
read stdin into $payload
├─ if payload empty or invalid → log parse-error, exit 0
│
├─ extract cwd
│   └─ if missing → emit plain notification (no click-to-switch), log no-cwd, exit 0
│
├─ resolve cwd → project_name (via config lookup)
│   └─ if no match → emit plain notification (no click-to-switch), log no-project-match, exit 0
│
├─ check notifications.enabled for project_name
│   └─ if "false" → exit 0 silently (no notification, no log)
│
├─ resolve term_bundle_id from env
│
├─ build click_cmd (see data-model.md §Click Action Payload) —
│     this includes both the primary switch attempt AND a follow-up
│     terminal-notifier invocation that fires on tms-switch failure, so
│     the user sees a visible "session not running" banner instead of a
│     silent stderr message that the Notification Center subshell hides.
│
├─ invoke (in detached background subshell):
│     terminal-notifier -title <project_name> -message <payload.message> -execute <click_cmd>
│
├─ if terminal-notifier was not found → log notifier-missing, exit 0
│
└─ exit 0 (immediately; do not wait for subshell)
```

## Notification body construction (FR-003)

- Title: `project_name` verbatim (already validated by tms config rules — no dots/colons/control chars).
- Body: `payload.message` verbatim, with one transformation only: replace embedded newlines with space to keep the banner single-line. No truncation at the application level (macOS Notification Center handles display truncation).

## Detached subshell pattern

```bash
( terminal-notifier ... >/dev/null 2>&1 || \
    notify_log_failure "notifier-failed" "$project_name" "$notification_type" "$session_id" "$message" \
) &
disown 2>/dev/null || true
```

This pattern is non-negotiable: it ensures the hook returns before the notification round-trip, preserving SC-005 (< 100 ms p95 overhead on Claude Code's interaction loop).

## Manual test mapping

Every behavior-tree branch maps to a quickstart.md scenario: parse error (QS-10), no-cwd (QS-11), no-project-match (QS-7), opt-out (QS-6), happy path (QS-2), notifier-missing (QS-12).
