# Phase 0 Research: Claude Code Notification Hook with Click-to-Switch

**Feature**: 002-claude-notification-hook
**Date**: 2026-04-21

This document resolves the remaining technical unknowns surfaced by the Technical Context in `plan.md`. Each section follows the Decision / Rationale / Alternatives format. No `NEEDS CLARIFICATION` markers remain after this phase.

---

## 1. macOS notifier tool

**Decision**: Use `terminal-notifier` (Homebrew) invoked with the `-execute <shell-command>` flag to make the banner clickable and run a callback.

**Rationale**: `terminal-notifier` 2.0.0 is in Homebrew with current bottles for Sonoma, Sequoia, and Tahoe (<https://formulae.brew.sh/formula/terminal-notifier>). Its `-execute COMMAND` flag is documented to "run the shell command COMMAND when the user clicks the notification" — this is banner-click, which is exactly the FR-004 behavior, not an action-button press. `osascript -e 'display notification ...'` has no click action at all (clicks only open Script Editor), so it is a hard block. `alerter` exists and is more recently maintained, but it emits click results to stdout for the caller to dispatch, which is the wrong shape for a fire-and-forget Claude Code hook that must return immediately (FR-007). First run will trigger macOS Notification Center permission prompting under the `fr.julienxx.oss.terminal-notifier` bundle; we document this in the `tms install-hooks` output (quickstart.md will cover the user-visible steps). Sources: <https://github.com/julienXX/terminal-notifier>, <https://formulae.brew.sh/formula/terminal-notifier>.

**Alternatives considered**:

- `osascript 'display notification ...'` — built-in, zero install, but no click-action support. Rejected.
- `alerter` (<https://github.com/vjeantet/alerter>) — more active fork, but requires a parent process to wait on stdout and dispatch clicks; fundamentally incompatible with the fire-and-forget hook shape we need. Held as a future fallback only if terminal-notifier breaks on a future macOS.
- Custom Swift binary using `UNUserNotificationCenter` — the principled modern path, but adds a build toolchain dependency and maintenance surface that a bash-based tool should avoid. Rejected on simplicity grounds.

---

## 2. Claude Code `Notification` hook payload schema

**Decision**: Treat the `Notification` hook stdin payload as JSON with these fields, consumed by `bin/tms-notify-hook`:

| Field | Type | Use |
|-------|------|-----|
| `hook_event_name` | string — always `"Notification"` | sanity-check; hard-fail otherwise |
| `session_id` | string | include in log entries for correlation |
| `transcript_path` | string | include in log entries on failure |
| `cwd` | string | **authoritative** source for project detection |
| `message` | string | notification body (verbatim, per FR-003) |
| `title` | string, optional | ignored for the notification title (we override with tms project name per FR-003); may be logged for debugging |
| `notification_type` | string — one of `permission_prompt`, `idle_prompt`, `auth_success`, `elicitation_dialog` | include in the log entry; no filtering in v1 (all types fire a banner) |

**Rationale**: Confirmed by the Claude Code Hooks reference and guide (<https://code.claude.com/docs/en/hooks>, <https://code.claude.com/docs/en/hooks-guide>). The hook command receives the payload on stdin and inherits the Claude Code process environment. Claude Code also exports `$CLAUDE_PROJECT_DIR` and may set `$CLAUDE_ENV_FILE`, but critically **does not guarantee `$TMUX` is set** — Claude Code may have been started outside tmux, and even when inside tmux the hook runs as a child of the Claude Code process, not of a tmux client. This is why `cwd` from the JSON payload (not `$PWD` or `$TMUX`) is the canonical key for project detection (see §5 below).

**Alternatives considered**: N/A — schema is canonical.

---

## 3. Claude Code hook configuration location & format

**Decision**: `tms install-hooks` writes to `~/.claude/settings.json` (user-global scope) and registers one entry under `hooks.Notification`:

```json
{
  "hooks": {
    "Notification": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "/absolute/path/to/bin/tms-notify-hook",
            "timeout": 10
          }
        ]
      }
    ]
  }
}
```

`tms install-hooks` MUST be idempotent: if an identical `tms-notify-hook` entry already exists, it is a no-op with a friendly message; if a conflicting entry exists under `hooks.Notification`, the command refuses to overwrite silently and instructs the user to edit manually. Existing unrelated keys in `settings.json` MUST be preserved — write via `jq` round-trip, never a naive overwrite.

**Rationale**: The 3-level structure (`hooks` → event name → array of `{matcher, hooks:[{type, command}]}`) is mandated by the Hooks guide. `matcher: ""` matches every `Notification` event (we want all four `notification_type` values in v1). User-global is correct because tms is a user-global tool: the hook must fire regardless of which project directory Claude Code is running in, so project-local `.claude/settings.json` would make the hook silent whenever the user works outside tms-registered projects. Default timeout for command hooks is 600 s; we set `timeout: 10` to fail fast if terminal-notifier ever hangs. Matching hooks run in parallel with identical handlers deduplicated automatically per the guide, so duplicate registration is non-catastrophic but still worth preventing. Source: <https://code.claude.com/docs/en/hooks-guide>.

**Alternatives considered**:

- Project-scoped `.claude/settings.json` per tms project — rejected: forces per-project install, silent for unregistered dirs, contradicts FR-011's global-on default.
- Plugin `hooks/hooks.json` format — overkill for a single hook.
- Writing via `sed`/`cat` text manipulation — rejected: guaranteed to corrupt nested JSON with user edits. Requires `jq`.

**New runtime dependency**: `jq` is needed for safe JSON round-tripping in `tms install-hooks`. Check via `require_cmd jq` at install time; do not require it for the hook itself (the hook reads JSON via bash + a small `jq` parse only when `jq` is already present, otherwise falls back to a narrow-regex extractor — see data-model.md §Notification Event for the parse contract).

---

## 4. Log directory

**Decision**: Write to `${TMS_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/tmux-session-manager}/notifications.log`. Create the directory on first write with `mkdir -p`. The file is append-only text; no rotation in v1 (log volume is bounded by human notification frequency, typically < 100 entries/day).

**Rationale**: The XDG Base Directory spec reserves `$XDG_STATE_HOME` (default `~/.local/state/`) for "logs, history, recently used files" — exactly this use case (<https://specifications.freedesktop.org/basedir-spec/latest/>). The existing codebase uses `${TMS_CONFIG_DIR:-${HOME}/.config/tmux-session-manager}` for config (see `lib/utils.sh:config_dir`), so pairing with `XDG_STATE_HOME` keeps config (user-versioned, read-only at runtime) cleanly separated from state (append-only, mutable). Mirroring the `TMS_CONFIG_DIR` override pattern with `TMS_STATE_DIR` keeps the convention consistent and makes the path testable in isolation.

**Alternatives considered**:

- `~/Library/Logs/tmux-session-manager/` — macOS-native and discoverable in Console.app, but mismatches this project's existing `~/.config/...` convention and surprises users already familiar with the tool's config layout. Rejected for consistency.
- `$(config_dir)/notifications.log` (same dir as projects.yml) — simplest but conflates config with mutable state and risks confusion (users may accidentally version or git-ignore the wrong thing). Rejected on principle.

---

## 5. Project detection and terminal activation

### 5a. Detecting the originating project from inside the hook

**Decision**: In `tms-notify-hook`, read `cwd` from the stdin JSON payload and resolve to a tms project name by matching `cwd` (with realpath normalization and prefix-match semantics) against each configured `projects[].dir` in `~/.config/tmux-session-manager/projects.yml`. First-match wins; if no match, the hook emits a plain notification with no click-to-switch (FR-010) and logs a `no-project-match` entry.

**Rationale**: `cwd` is guaranteed by the hook payload schema (§2). `$TMUX` / tmux-session-name detection (`tmux display-message -p '#S'`) is unreliable because the hook is not guaranteed to run inside a tmux client (§2). Prefix-match rather than exact match is necessary because `cwd` may be a subdirectory of the registered project root (e.g., `cd src/` before running Claude Code). Realpath normalization handles symlinks (`~/Projects/foo` vs `/Users/.../Projects/foo`).

### 5b. Bringing the terminal to the foreground when the banner is clicked

**Decision**: At emission time, read `$TERM_PROGRAM` (and `$__CFBundleIdentifier` if present) from the hook's inherited environment to capture the terminal bundle id. Bake it literally into the click callback command along with the tmux switch invocation:

```bash
open -b "$TERM_BUNDLE_ID" ; tms switch "$PROJECT_NAME" 2>&1 | \
    tee -a "$TMS_STATE_DIR/notifications.log"
```

Fallback order for resolving `$TERM_BUNDLE_ID`: `$__CFBundleIdentifier` → `$TERM_PROGRAM` mapped through a small lookup table (iTerm2 → `com.googlecode.iterm2`, Apple_Terminal → `com.apple.Terminal`, ghostty → `com.mitchellh.ghostty`, alacritty → `org.alacritty`, kitty → `net.kovidgoyal.kitty`, WezTerm → `com.github.wez.wezterm`) → if nothing resolves, fall back to `open -a Terminal`.

**Rationale**: When Notification Center invokes the click callback, the shell that runs it has **no controlling terminal and no tmux client**; `tmux switch-client` alone fails in this context because it needs an existing attached client to retarget (<https://man.openbsd.org/tmux.1#switch-client>). We must:

1. Capture the terminal bundle id at emission time (the env var is gone by click time, and the click shell inherits none of the user's terminal env).
2. Use `open -b <bundle-id>` at click time, which activates the running instance and brings it to the foreground (<https://www.jviotti.com/2022/11/28/launching-macos-applications-from-the-command-line.html>).
3. Then delegate the actual session+window switch to `tms switch <project>` (see Phase 1 contract `contracts/tms-switch-cli.md`), which handles "retarget existing client if any, else attach" so the result is correct whether or not a tmux client already exists.

**Alternatives considered**:

- `terminal-notifier -activate <bundle-id>` alone — brings terminal forward but does no tmux work. We still need `-execute` for the tmux switch, and `-execute` is the composable choice because it runs a full shell command (including the `open` + `tms switch` pair above).
- `open -a Terminal` hardcoded — wrong for any user not on Terminal.app, which is most tms users (iTerm2, Ghostty, etc.).
- Detecting terminal at click time — impossible; the click callback inherits no user-terminal env.
- Running `tmux switch-client` without `open` — fails whenever no tmux client is currently attached (the normal case when clicking a notification from another app).

---

## 6. macOS 26+ compatibility: `-sender` bundle override

**Decision**: All `terminal-notifier` invocations MUST pass `-sender com.apple.Terminal` as a hardcoded safe sender, regardless of which terminal emulator is actually hosting Claude Code. The real terminal bundle (resolved per §5b) is still used for the click callback's `open -b <bundle>` target, but it is NOT used as `-sender`. This is implemented in `lib/notify.sh` as `notify_resolve_sender_bundle()` (returns `com.apple.Terminal`), kept distinct from `notify_resolve_term_bundle()` (returns the real terminal for click activation).

**Rationale**: Discovered during bring-up on macOS 26.4 (Tahoe). Two independent failure modes:

1. Without `-sender` at all, `terminal-notifier` 2.0.0 (2018) returns exit 0 but Notification Center silently drops the banner. Apple has tightened delivery requirements for unsigned/unnotarized tools, so the default sender (terminal-notifier's own bundle `fr.julienxx.oss.terminal-notifier`) is no longer reliably delivered. Verified empirically: identical invocations with and without `-sender` produce exit 0 both times, but only the `-sender` variant actually shows a banner.
2. With `-sender com.googlecode.iterm2` (iTerm2 is the actual host terminal on the bring-up machine), `terminal-notifier` **hangs indefinitely** — the subprocess never returns. Apparently iTerm2's bundle doesn't advertise the notification capability in its Info.plist in whatever form terminal-notifier expects, and the call blocks waiting for a response. Verified empirically: `timeout 10 terminal-notifier -sender com.googlecode.iterm2 ...` exits 124; same invocation with `-sender com.apple.Terminal` exits 0 and delivers the banner. This likely affects other third-party terminal bundles (Ghostty, Alacritty, kitty, WezTerm) to varying degrees — they were not tested but are assumed broken-by-default.

`com.apple.Terminal` is the universally safe sender because it is a system-shipped app with guaranteed notification registration in its Info.plist. The cost is cosmetic: the banner icon shows Terminal.app rather than the user's actual terminal. The click callback still foregrounds the correct terminal via `open -b <real-bundle>`, so functional correctness is preserved.

**Alternatives considered**:

- Per-terminal allow/deny lists — tried conceptually; rejected because we cannot statically know which terminals advertise notification capability on which macOS versions, so this would require a probe step at install time that is fragile and adds complexity.
- Swap to `alerter` — still rejected for the same reason as §1 (wrong shape for fire-and-forget hooks); and the sender-bundle issue likely affects alerter too since it uses the same underlying macOS notification APIs.
- Custom Swift binary — now slightly more attractive as a fallback if `terminal-notifier` ever fully breaks on a future macOS, but still rejected today on simplicity grounds.

**Scope note**: This workaround is invisible to the user except that the banner shows Terminal.app's icon instead of iTerm2's / Ghostty's / etc. If a future terminal-notifier release (or an official alternative) restores proper sender-bundle handling, `notify_resolve_sender_bundle` can be removed and `notify_resolve_term_bundle` used directly for both roles.

## 7. macOS 26+ click callbacks broken (OPEN — blocks FR-004/FR-005)

**Observation**: On macOS 26.4 (Tahoe), `terminal-notifier` 2.0.0 click callbacks do not dispatch, regardless of flag used. Both `-execute '<shell-cmd>'` (our primary mechanism for FR-004 click-to-switch) and `-activate '<bundle-id>'` (foreground-only fallback) silently do nothing when the user clicks the banner body. Verified empirically with two canary banners:

| Canary | Flag | Expected | Observed |
|--------|------|----------|----------|
| A | `-execute 'touch /tmp/tms-click-canary'` | file created on click | file never created |
| B | `-activate com.googlecode.iterm2` | iTerm2 foregrounds on click | iTerm2 stays in background |

This is separate from the delivery issue documented in §6. Banners *deliver* correctly with the `-sender com.apple.Terminal` workaround, but the click-dispatch mechanism on the back end is also broken. The most likely cause is Apple's tightening of notification-callback entitlements in recent macOS: `terminal-notifier` is not codesigned/notarized in a way that lets macOS route banner-click events back to it, so the stored callback is dropped.

**Status**: OPEN. The macOS 26 `-sender` delivery fix (§6) was necessary but not sufficient for the full feature. User Story 1 (banner fires with project name) works end-to-end. User Story 2 (click-to-switch) is blocked until we choose a remediation.

**Remediation options** (none chosen yet; left to Phase 2 decision):

1. **Accept the limitation on macOS 26** — banner still identifies the project, but strip `-execute` from the hook and document that users must manually switch via `prefix+P` (existing fzf picker) or `tms switch <name>`. Delivers ~70% of the feature value with zero additional dependencies. Lowest effort (~5 min to implement the macOS-version guard).

2. **Swap to `alerter`** (<https://github.com/vjeantet/alerter>) — uses a different click mechanism (blocks the process until the user interacts, then prints the click result to stdout; no reliance on macOS's notification-callback delivery path). Previously rejected in §1 as "wrong shape for a fire-and-forget hook," but the shape can be accommodated: run `alerter` inside the existing detached subshell and dispatch the switch from there. Risk: `alerter`'s last release is 2015, so it may have its own macOS 26 issues we haven't found yet. Moderate effort (~15-20 min implementation + test cycle).

3. **Minimal Swift notification helper** — ship a tiny Swift binary (~100 lines) using `UNUserNotificationCenter` with an explicit click handler, ad-hoc signed for personal use. Correct long-term fix; adds a compiled binary and a build step to the repo. Moderate-to-large effort (~1-2 hours + test cycle).

4. **URL scheme handler** — register a custom `tms://` URL scheme via a small LSHandler app; put the URL in the banner body so clicks activate the handler. Same codesigning requirements as Option 3. Rejected as more complex without being more correct.

**Pending decision**: Document-only update 2026-04-21; implementation remediation deferred pending user decision between Options 1–3.

---

## Summary of decisions feeding Phase 1

- **New runtime dependencies**: `terminal-notifier` (required for emission), `jq` (required for `tms install-hooks` only; optional for the hook if a jq-free fallback JSON extractor is provided).
- **Files added**: `bin/tms-notify-hook`, `lib/notify.sh`.
- **Files modified**: `bin/tms`, `lib/session.sh` (new `cmd_switch`), `lib/config.sh` (opt-out flag accessor + validation), `config/projects.example.yml` (document `notifications.enabled: false`), `README.md`.
- **New subcommands**: `tms switch <project>` (direct, non-interactive), `tms install-hooks` (idempotent settings.json writer).
- **State location**: `${TMS_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/tmux-session-manager}/notifications.log`.
- **Click callback shape**: `open -b <BUNDLE> ; tms switch <PROJECT>` — both parts necessary for correct activation regardless of prior tmux-client state.

All five Technical Context unknowns resolved; no `NEEDS CLARIFICATION` markers remaining.
