# Contract: AppleScript Payloads for Click-to-Exact-Tab

**Surface**: `osascript -e '<body>' -- <target_tty>` called from the click callback inside `lib/notify.sh:cmd_notify_hook`.
**Callers**: Only the notification click callback (not user-typed commands).

## Payload 1: iTerm2 (`com.googlecode.iterm2`)

### Body

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
        return 1
    end tell
end run
```

### Input contract

- `argv` must have length 1.
- `argv[0]` is a POSIX path string (e.g., `/dev/ttys007`). Must exactly match a `tty` field on some `current session of tab` in iTerm2's running instance.

### Output contract

| osascript exit | AppleScript return | Stdout | Meaning |
|----------------|--------------------|--------|---------|
| 0 | 0 | empty | Match found. iTerm2 activated; window raised; tab selected. |
| 1 | 1 | empty | No tab in any iTerm2 window has the given TTY. |
| ≠0,1 | — | error text on stderr | osascript runtime error, TCC denied, or AppleScript syntax error. |

### Side effects

- **Activates iTerm2** (brings to foreground, equivalent to `open -b com.googlecode.iterm2`).
- **Raises the matching window** if iconified.
- **Selects the matching tab** within that window.
- **Does NOT** switch macOS Spaces if the target window is on a different Space.
- **Does NOT** exit fullscreen or rearrange windows.

### Preconditions

- iTerm2 is running. If not running, iTerm2 launches via `activate`, which means no tabs exist and the loop returns 1 (no-tty-match). The AppleScript does NOT attempt to create a new window/tab.
- TCC: the osascript's owning process (the shell that runs the click callback) has been granted automation permission to control iTerm2. On first click this triggers a TCC prompt; the script exits non-zero until the user grants it.

### Error handling

Caller (bash click callback) must:
- Inspect osascript exit code.
- On exit 1 with empty stderr: log `applescript-failed / no-tty-match`, fall through to existing path.
- On other non-zero + stderr matching `not authorized to send Apple events`: log `applescript-failed / permission-denied`, fall through.
- On other non-zero + stderr matching `execution error` / `syntax error`: log `applescript-failed / script-error`, fall through.
- Otherwise: log `applescript-failed / osascript-other`, fall through.

---

## Payload 2: Terminal.app (`com.apple.Terminal`)

### Body (expected shape — verify during implementation)

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

### Input contract

Identical to Payload 1.

### Output contract

Identical to Payload 1 (0 on match, 1 on no-match, non-zero,1 on error).

### Side effects

- Activates Terminal.app.
- `set frontmost of window to true` raises the owning window.
- `set selected of tab to true` selects the tab within its window.
- Does NOT switch macOS Spaces or exit fullscreen.

### Preconditions

- Terminal.app is running. If not, `activate` launches it with a new empty window → no tty match → return 1.
- TCC: same model as iTerm2 — automation permission required, first click prompts.

### Error handling

Identical to Payload 1.

### Differences from Payload 1

- iTerm2: `tty` is a property of `current session` (sessions are nested under tabs). Terminal.app: `tty` is a property of `tab` directly.
- iTerm2: selection via `tell window to select` / `tell tab to select`. Terminal.app: `set frontmost of window to true` / `set selected of tab to true`.
- Otherwise structurally identical.

---

## Non-goals / excluded terminals

The following terminal bundles are NOT handled by any AppleScript payload and retain feature 002's click behavior (`open -b <bundle>` + `tms switch`) without modification:

- `com.mitchellh.ghostty` (Ghostty) — no AppleScript API at time of writing.
- `org.alacritty` (Alacritty) — GPU-accelerated, no AppleScript.
- `net.kovidgoyal.kitty` (kitty) — no AppleScript.
- `com.github.wez.wezterm` (WezTerm) — has its own CLI but not AppleScript.
- Unknown / future bundles — default fallback.

If one of these emulators gains AppleScript support in a future version, a new payload can be added here without touching the existing ones.

## Invocation pattern (reference)

```bash
# From the click callback, already inside the detached alerter subshell:

target_tty=$(tmux list-clients -t "$project" -F '#{client_tty}' 2>/dev/null | head -1)

if [[ -z "$target_tty" ]]; then
    # No attached client — skip AppleScript, use existing fallback.
    open -b "$term_bundle_id" >/dev/null 2>&1
else
    # Try AppleScript first.
    if osascript -e "$applescript_body" -- "$target_tty" 2>"$stderr_tmp"; then
        :  # success — iTerm2/Terminal activated and selected the tab. Skip `open -b`.
    else
        # Classify failure mode + log.
        mode=$(_notify_classify_osascript_err "$(cat "$stderr_tmp")")
        notify_log_failure "applescript-failed" "$project" "$notification_type" "$session_id" "$mode"
        # Fall back to existing behavior.
        open -b "$term_bundle_id" >/dev/null 2>&1
    fi
fi

# Continue to tms switch (unchanged).
"$tms_abs_path" switch "$project" 2>&1 | tee -a "$log_path"
# ... existing follow-up alerter on PIPESTATUS[0] != 0 ...
```

## Manual test mapping

- Happy path (target tab selected): quickstart.md QS-1 (iTerm2), QS-2 (Terminal.app).
- `no-tty-match`: quickstart.md QS-3 (detached session).
- `permission-denied`: quickstart.md QS-4 (first click after fresh install OR after revoking permission).
- Fallback on non-AppleScript terminal: quickstart.md QS-5 (Ghostty/etc.).
- Single-tab regression check: quickstart.md QS-6.
