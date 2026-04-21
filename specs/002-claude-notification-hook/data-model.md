# Phase 1 Data Model: Claude Code Notification Hook with Click-to-Switch

**Feature**: 002-claude-notification-hook
**Date**: 2026-04-21

This document maps the spec's Key Entities onto concrete data shapes (YAML config extension, JSON hook payload, log line format, click-callback payload). Contracts in `contracts/` reference these shapes; do not duplicate structure there.

---

## Entity: Project (extended)

The existing `projects[]` entry in `~/.config/tmux-session-manager/projects.yml` gains one optional nested setting. No required fields are changed; existing configs remain valid.

### YAML schema (additions in **bold**)

```yaml
projects:
  - name: my-webapp              # string, required, existing
    dir: ~/Projects/my-webapp    # string, required, existing
    servers: [...]               # list, optional, existing
    # --- new, all optional ---
    notifications:
      enabled: true              # bool, optional, default true (opt-out is enabled: false)
```

### Validation rules (enforced in `lib/config.sh:_config_validate`)

- `notifications` MUST be a map (or absent). Any other type → `die`.
- `notifications.enabled` MUST be a bool (or absent). Any other type → `die`.
- Absent `notifications` block is equivalent to `notifications.enabled: true` (global-on default per FR-011).
- `notifications: {}` (empty map) is also valid and equivalent to `enabled: true`.

### Accessor contract

`config_get_notifications_enabled <project-name>` → prints `"true"` or `"false"` to stdout; returns 0 on success, non-zero only if the project itself is not in config. Absent field defaults to `"true"`.

### State transitions

None — this is a static config flag. Changes take effect on the next `Notification` hook fire; no tms-side hot-reload needed because `tms-notify-hook` reads the config file on every invocation (acceptable given human-scale notification frequency).

---

## Entity: Notification Event

A single invocation of `bin/tms-notify-hook` driven by Claude Code's `Notification` hook. Exists only for the lifetime of one hook invocation.

### Input contract (JSON on stdin)

Fields consumed by the hook (see research.md §2 for authoritative list):

| Field | Type | Required | Hook behavior if missing |
|-------|------|----------|--------------------------|
| `hook_event_name` | string | yes | Log `invalid-payload` entry, exit 0. MUST equal `"Notification"`. |
| `cwd` | string | yes | Emit plain notification with no click-to-switch; log `no-cwd` entry, exit 0. |
| `message` | string | yes | Use empty string as body; log `empty-message` warning but still emit. |
| `session_id` | string | no | Log if present; omit if missing. |
| `transcript_path` | string | no | Log if present on failure only. |
| `notification_type` | string | no | Log if present. No filtering in v1. |
| `title` | string | no | Ignored for notification title (overridden with tms project name per FR-003). |

### Parse strategy (jq-optional)

The hook prefers `jq` when available (cleanest). When `jq` is absent (e.g., fresh macOS without Homebrew-jq), fall back to a narrow POSIX shell extractor that scans for `"field":"..."` using `sed`/`awk`. The fallback does **not** attempt full JSON parsing — it only extracts the flat string fields listed above, which the Claude Code hook payload guarantees. If extraction fails on a required field, the hook logs `parse-error` with the raw payload (truncated to 512 bytes) and exits 0. Claude Code's process is never blocked (FR-007).

### Derived fields (computed at emission time, baked into click callback)

| Derived field | Source | Used for |
|---------------|--------|----------|
| `project_name` | Resolved from `cwd` via §5a of research.md | Notification title, click callback argument, log entry |
| `term_bundle_id` | `$__CFBundleIdentifier` → `$TERM_PROGRAM` lookup → `com.apple.Terminal` fallback | Click callback `open -b` argument |
| `click_cmd` | `open -b <term_bundle_id> ; exec <tms-path> switch <project_name>` | `-execute` arg to `terminal-notifier` |

**Critical invariant (FR-005, and Per-Project Notification Setting entity)**: `project_name` is resolved **at emission time**, not lazily at click time. This matters because the tms config file may change between emission and click; the user's click should land on the project that emitted the event, not on whatever project happens to map to the same `cwd` now.

---

## Entity: Click Action Payload

The literal shell command passed to `terminal-notifier -execute`. Escaping matters because tms project names are already validated to disallow `.` and `:` (see `lib/config.sh:_config_validate`), but arbitrary shell metacharacters are NOT currently banned, so the command must be quoted defensively.

### Shape

```sh
open -b 'com.googlecode.iterm2' ; \
'/Users/ykchen/Projects/ykchen/tmux-session-manager/bin/tms' switch 'my-webapp' \
    2>&1 | tee -a '/Users/ykchen/.local/state/tmux-session-manager/notifications.log' ; \
[ "${PIPESTATUS[0]:-0}" -ne 0 ] && \
    terminal-notifier \
        -title 'Claude Code — my-webapp' \
        -message "Session not running. Run 'tms start my-webapp' to restart it."
```

### Construction rules

- `$TMS_DIR` is resolved to an **absolute path** at emission time (same `TMS_DIR` logic as `bin/tms:6`) so the callback works regardless of `$PATH` at click time.
- Single-quote each substituted value; inside a single-quoted value, escape embedded `'` as `'\''`.
- The `open -b` and `tms switch` parts are separated by `;` (not `&&`) so a `tms switch` failure still foregrounds the terminal before the follow-up notifier fires.
- `tee -a <log>` captures raw stderr for debugging; it is NOT the tab-structured log format. The structured log is populated only by `lib/notify.sh:notify_log_failure` from inside `tms-notify-hook`.
- `[ "${PIPESTATUS[0]:-0}" -ne 0 ]` detects a non-zero exit from `tms switch` specifically (not from `tee`). This is bash-specific; terminal-notifier's `-execute` runs the callback via `/bin/sh -c`, and on macOS `/bin/sh` is bash-in-sh-compat, so `PIPESTATUS` is available. (If this ever breaks on a future macOS, wrap the callback in `bash -c '...'` explicitly.)
- The follow-up `terminal-notifier` invocation is what makes the error **user-visible** per FR-006. Without it, the Notification Center subshell swallows stderr and the user sees no feedback about why the click didn't land them on a working session.
- Do **not** use `exec` on the `tms switch` call (previous design) — we need to keep the shell alive to run the conditional follow-up notifier.

**Known limitation — multi-window terminal users**: `open -b '<bundle>'` brings the terminal application to the foreground, but macOS promotes whichever window of that application was most recently active. If the user has two windows of the same emulator open (e.g., iTerm2 window A running a plain shell, window B attached to some tmux session), the `open -b` step may foreground window A while `tmux switch-client` retargets the client running in window B. The tmux session switch **does** happen; the user just may need to cycle to window B (⌘\` on macOS) to see it. This is accepted as a design tradeoff: detecting which specific window owns the retargeted tmux client would require per-emulator AppleScript (Terminal.app, iTerm2, Ghostty, Alacritty, etc. all have different scripting surfaces), and the target audience for `tms` typically runs a single terminal window per development context. Documented in README and quickstart.md per FR-008.

---

## Entity: Per-Project Notification Setting

See "Project (extended)" above — this is the YAML-level representation. The in-memory representation during a hook invocation is the output of `config_get_notifications_enabled "<project>"`:

| Value | Hook behavior |
|-------|---------------|
| `"true"` (or field absent) | Proceed with emission (global-on default). |
| `"false"` | Suppress macOS notification emission. Do NOT write to the log. Exit 0 silently (not a failure; user intentionally opted out). The tmux visual bell is unaffected (FR-009, FR-011). |

---

## Entity: Notification Failure Log Entry

Appended to `${TMS_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/tmux-session-manager}/notifications.log` by `lib/notify.sh:notify_log_failure` on each emission failure. Also appended by the click callback's `tee` on `tms switch` failures (see research.md §5b).

### Line format (newline-delimited, one event per line)

```text
<iso8601-timestamp>\t<category>\t<project-or-"-">\t<notification_type-or-"-">\t<session_id-or-"-">\t<message-summary>
```

Fields are tab-separated, no embedded tabs in any field (replace `\t` in payload with a single space at write time). `<message-summary>` is at most 200 characters, truncated with a trailing `…` if longer.

### Defined categories

| Category | Trigger |
|----------|---------|
| `notifier-missing` | `terminal-notifier` not found on `$PATH`. One entry per hook invocation. |
| `notifier-failed` | `terminal-notifier` exited non-zero. Note: on recent macOS, a notification suppressed by denied permission does **not** produce a non-zero exit; that case surfaces as a silent emission and is caught at install time by the probe banner (see `contracts/tms-install-hooks-cli.md` §Post-install probe), not at runtime. If a user sees no banners at runtime and the log is clean, the diagnostic is always "check System Settings → Notifications → terminal-notifier". |
| `no-cwd` | Payload missing `cwd`. |
| `no-project-match` | `cwd` didn't match any configured project (graceful — spec FR-010). |
| `parse-error` | Stdin payload malformed. |
| `empty-message` | Payload `message` field empty. |
| `switch-failed` | Click callback's `tms switch` step failed (captured by the `tee` in the callback shell; the user-visible signal is the follow-up `terminal-notifier` banner per data-model.md §Click Action Payload). |

All categories log on every occurrence (they are rare by construction). There is no application-level deduplication — runtime `notifier-failed` spam is bounded by Claude Code's notification cadence, and the common "permissions never granted" case is caught once at install time rather than every event.

---

## Relationships summary

```text
projects.yml                      (Entity: Project, extended)
  └─ notifications.enabled        (Entity: Per-Project Notification Setting)
          │
          ▼
Claude Code Notification hook stdin   (Entity: Notification Event — input)
          │
          ▼
tms-notify-hook                       (resolves project_name, term_bundle_id)
          │
          ├─► terminal-notifier ... -execute <click_cmd>   (Entity: Click Action Payload)
          │
          └─► notifications.log        (Entity: Notification Failure Log Entry)
                (on failure paths only; silent opt-out does NOT log)

click → open -b <bundle> ; tms switch <project>
                                      (Entity: Click Action Payload — executed)
                                      │
                                      ├─► tmux switch-client / attach
                                      └─► tmux select-window workspace
```

All entities are either transient (lifetime of one hook invocation), static config (YAML), or append-only state (log). No persistent in-memory data is introduced.
