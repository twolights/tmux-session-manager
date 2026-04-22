# Phase 1 Data Model: Click-to-Exact-Tab Notification Switch

**Feature**: 004-click-to-exact-tab
**Date**: 2026-04-22

Maps the spec's Key Entities to concrete shapes (bash variables, command-line args to osascript, log-line format). Contracts in `contracts/` reference these shapes.

---

## Entity: Target TTY

The TTY path of the tmux client attached to the originating tmux session at **click time**. The unambiguous identifier used for window/tab matching.

### Shape

A string like `/dev/ttys007`. Exact match between:

- `tmux list-clients -t <project> -F '#{client_tty}'` (bash side — query at click time)
- `tty of current session of tab` (iTerm2 AppleScript) or `tty of tab` (Terminal.app AppleScript)

### Lifecycle

Queried fresh on every click via:

```bash
target_tty=$(tmux list-clients -t "$project_name" -F '#{client_tty}' 2>/dev/null | head -1)
```

- `head -1` picks the first attached client when multiple clients share the session (FR-009 first-client-wins).
- Empty result → session has no attached client (detached). Handler falls through to `tms switch`'s attach path.

### Validation

- Non-empty → pass to osascript as `--args "$target_tty"`.
- Empty → skip osascript entirely; proceed directly to `open -b` + `tms switch` fallback (which will attach the session somewhere and the user ends up on that window). No `applescript-failed` log entry in this case — expected behavior for detached sessions.

---

## Entity: Terminal Automation Script

The per-terminal AppleScript payload that iterates windows/tabs, finds the one whose current tty matches Target TTY, and selects it.

### iTerm2 script (expected shape)

```applescript
on run argv
    set target_tty to item 1 of argv
    tell application "iTerm"
        activate
        repeat with w in windows
            repeat with t in tabs of w
                tell current session of t
                    if (tty as text) is equal to target_tty then
                        tell w to select
                        tell t to select
                        return 0
                    end if
                end tell
            end repeat
        end repeat
        return 1  -- no tab matched target_tty
    end tell
end run
```

Invoked as:

```bash
osascript -e '<body>' -- "$target_tty"
```

### Terminal.app script (expected shape)

```applescript
on run argv
    set target_tty to item 1 of argv
    tell application "Terminal"
        activate
        repeat with w in windows
            repeat with t in tabs of w
                if (tty of t as text) is equal to target_tty then
                    set frontmost of w to true
                    set selected of t to true
                    return 0
                end if
            end repeat
        end repeat
        return 1
    end tell
end run
```

Terminal.app's AppleScript dictionary exposes `tty` directly on tabs (not nested under `current session` like iTerm2), and selection uses `set selected of tab to true` rather than a `select` message. Minor syntactic drift from iTerm2; semantics match.

### Exit codes

- `0` — match found, window+tab selected successfully.
- `1` — iterated all windows/tabs, no match. (Maps to `applescript-failed` with mode=`no-tty-match`.)
- non-zero (other) — osascript runtime error, AppleScript syntax error, TCC permission denied. Stderr may contain `not authorized to send Apple events` or `(-1743)` for TCC denial — used to discriminate the log mode.

### Output

stdout: always empty on success, empty or script-error text on failure.
stderr: osascript's own error diagnostics — consumed by the bash wrapper for mode discrimination.

---

## Entity: Click Action Payload (extended)

Feature 002's payload shape (`open -b <bundle> ; <tms-abs> switch <project> …`) is extended conditionally. The click callback logic at emission time inspects `term_bundle_id` and embeds different command shapes depending on which terminal.

### Shape for iTerm2 (com.googlecode.iterm2)

```sh
target_tty=$('<tmux-abs>' list-clients -t '<project>' -F '#{client_tty}' 2>/dev/null | head -1) ;
if [ -n "$target_tty" ] ; then
    if osascript -e '<iterm-script-body>' -- "$target_tty" 2>/tmp/tms-osa-err.$$ ; then
        :  # success, script activated iTerm2 and selected the tab
    else
        # log applescript-failed with discriminated mode, then fall through
        mode=$(cat /tmp/tms-osa-err.$$ | '<tms-abs>' __classify-osascript-err)  # or inline case
        '<tms-abs>' __log-applescript-failed '<project>' "$mode"
        open -b '<bundle>'
    fi
    rm -f /tmp/tms-osa-err.$$
else
    # detached session — no target_tty to match. Skip AppleScript, use fallback.
    open -b '<bundle>'
fi ;
'<tms-abs>' switch '<project>' 2>&1 | tee -a '<log>' ;
[ "${PIPESTATUS[0]:-0}" -ne 0 ] && alerter … # existing follow-up
```

### Shape for Terminal.app (com.apple.Terminal)

Identical structure to iTerm2 shape, but with the Terminal.app script body and `com.apple.Terminal` bundle id.

### Shape for other terminals

Unchanged from feature 002 — the existing `open -b <bundle> ; tms switch ...` chain. No osascript invocation.

### Construction rules

- `<tms-abs>` is the result of `$TMS_DIR/bin/tms` at hook-emission time (same as feature 002).
- `<project>` is baked at emission time (feature 002 critical invariant).
- `<bundle>` is the real terminal bundle (`notify_resolve_term_bundle`, unchanged from feature 002).
- The osascript body is baked at emission time — embedding as a literal string into the click_cmd. The body is idempotent and stateless; baking is safe.
- `<target_tty>` is **queried at click time**, not emission — a `$(tmux list-clients ...)` inline subshell in the click_cmd itself. Critical per research.md §5.

### Classification helper

The failure-mode discriminator is a small pure-bash case statement, no subprocess. Likely extracted as a helper function in `lib/notify.sh`:

```bash
_notify_classify_osascript_err() {
    local stderr_text="$1"
    case "$stderr_text" in
        *"not authorized to send Apple events"* | *"(-1743)"*) printf 'permission-denied' ;;
        *"execution error"* | *"syntax error"*)               printf 'script-error' ;;
        *"Can’t get"* | *"doesn't understand"*)                printf 'terminal-quit' ;;
        *)                                                      printf 'osascript-other' ;;
    esac
}
```

For the `no-tty-match` case (osascript exit 1, empty stderr), the classifier isn't invoked — the caller distinguishes exit 0 from exit 1 and passes `no-tty-match` explicitly.

---

## Entity: AppleScript Failure Log Entry

Extends feature 002's `notifications.log` with one new category.

### Shape (matches existing log format)

```text
<iso8601-timestamp>\t<category>\t<project>\t<notification_type>\t<session_id>\t<message>
```

Same 6 tab-separated fields. Only the values differ:

| Field | Value |
|-------|-------|
| category | `applescript-failed` |
| project | The resolved `project_name` (same as emission) |
| notification_type | Same as emission (`permission_prompt`, `idle_prompt`, etc.) |
| session_id | Same as emission |
| message | One of: `permission-denied`, `no-tty-match`, `script-error`, `terminal-quit`, `osascript-other` |

### Defined failure modes

| Mode | Trigger |
|------|---------|
| `permission-denied` | osascript exit ≠ 0 AND stderr contains `not authorized to send Apple events` or `-1743`. User can fix in System Settings → Privacy & Security → Automation. |
| `no-tty-match` | osascript exit == 1 (AppleScript-returned; iterated all windows/tabs, no match). Expected when session's attached client is in a window the script can't see (rare) or when the TTY we queried is stale (shouldn't happen given click-time query). |
| `script-error` | osascript stderr contains `execution error` or `syntax error`. Indicates a bug in our AppleScript body; should be zero in production. Log so it surfaces in the first user report. |
| `terminal-quit` | stderr contains `Can't get` or `doesn't understand` — usually means the terminal app was killed between the user reading the banner and clicking. |
| `osascript-other` | Catchall for unexpected non-zero exit + unexpected stderr. |

### Logging call

Via the existing `notify_log_failure` helper:

```bash
notify_log_failure "applescript-failed" "$project_name" "$notification_type" "$session_id" "$mode"
```

No new helper needed; the log format handles new categories transparently (per feature 002's `contracts/notifications-log-format.md` extensibility clause).

---

## Relationships summary

```text
hook emission (feature 002 + 003 flow, unchanged)
  │
  ├─ resolve project_name (bake at emission)
  ├─ resolve term_bundle_id (bake at emission)
  ├─ compose click_cmd:
  │    if bundle in {com.googlecode.iterm2, com.apple.Terminal}:
  │        embed osascript-extended shape with bundle-specific AppleScript body
  │    else:
  │        embed existing feature-002 shape
  └─ alerter … -execute "<click_cmd>" (unchanged)

click-time (inside alerter's subshell, which runs under `sh -c <click_cmd>`)
  │
  ├─ target_tty = tmux list-clients -t <project> -F '#{client_tty}' | head -1
  │
  ├─ if target_tty non-empty AND bundle is AppleScript-capable:
  │     osascript --args "$target_tty"
  │     ├─ exit 0 → window/tab selected. Skip `open -b`. Continue to tms switch.
  │     └─ non-zero → log applescript-failed, then fall through to existing path.
  │
  └─ existing path: open -b <bundle> ; tms switch <project> ; conditional follow-up alerter
```

No new persistent state. No new subcommands. One new log category. Two new embedded AppleScript bodies.
