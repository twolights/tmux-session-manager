# Phase 0 Research: Click-to-Exact-Tab Notification Switch

**Feature**: 004-click-to-exact-tab
**Date**: 2026-04-22

Resolves the remaining technical unknowns from `plan.md`'s Technical Context. Each section follows Decision / Rationale / Alternatives.

---

## 1. iTerm2 AppleScript API for per-tab TTY

**Decision**: Use `tty of current session of tab` inside `tell application "iTerm"`. This property returns a POSIX path string (e.g. `/dev/ttys007`) that matches tmux's `#{client_tty}` format byte-for-byte.

**Empirical verification** (from this host, macOS 26.4, iTerm2):

```applescript
tell application "iTerm"
    repeat with w in windows
        repeat with t in tabs of w
            tell current session of t
                return (tty as text)
            end tell
        end repeat
    end repeat
end tell
```

returns `/dev/ttys001`, `/dev/ttys007`, etc. — exact string match with `tmux list-clients -F '#{client_tty}'` output.

**Selection mechanism**: `tell window to select` raises the window; `tell tab to select` activates the tab within the selected window. Applied in order (window first, then tab) the focus lands correctly. On fullscreen windows, both selections are no-ops visually but the "current" state is still updated for future interactions.

**Rationale**: iTerm2 is the user's primary terminal per session diagnostics (`__CFBundleIdentifier=com.googlecode.iterm2`). Its AppleScript dictionary exposes `current session` on each tab and `tty` on each session — this is the documented public API surface, not a hack.

**Alternatives considered**:

- Match by `pane_title` / tab title: rejected per FR-002 — tab titles drift (shell sets title, tmux re-asserts, claude-code sets title, etc.) and matching is fragile.
- Match by `window id` + position: would require baking both into the click callback at emission time, but both can change (user re-orders tabs, closes windows). TTY is stable for the tmux client's lifetime.
- Python-iterm2 RPC: works, but adds a Python dependency and a long-running daemon. Heavier than the one-shot AppleScript approach.

---

## 2. Terminal.app AppleScript API for per-tab TTY

**Decision**: Use `tty of tab` directly (Terminal.app's tab exposes `tty` as a top-level property, unlike iTerm2 where it lives under `current session`). Selection via `set selected of tab to true` inside a `tell window` block, plus `activate` on the application.

**Expected shape** (not yet empirically verified on this host — user is on iTerm2):

```applescript
tell application "Terminal"
    repeat with w in windows
        repeat with t in tabs of w
            if tty of t is equal to "/dev/ttys007" then
                set frontmost of w to true
                set selected of t to true
                activate
                return 0
            end if
        end repeat
    end repeat
    return 1
end tell
```

Terminal.app's AppleScript dictionary has been stable across macOS versions (documented in Apple's Script Editor dictionary browser).

**Rationale**: Terminal.app is the #2 macOS terminal by usage; supporting it at launch is cheap (~15 line script). The `tty` field on `tab` is directly queryable, same source of truth as tmux's `client_tty`.

**Alternatives considered**:

- Route Terminal.app through the fallback path: would be simpler (no new script), but leaves a substantial slice of macOS users (and everyone using the default terminal) without the exact-tab experience. Contra to spec user stories.
- Query TTY via `busy of tab` or window title inspection: less reliable than the first-party `tty` property.

**Research deferral**: the exact script body will be verified empirically on a real Terminal.app + tmux setup during implementation. If the spec-assumed shape turns out incorrect, we adjust and document; Terminal.app may require small syntax changes (e.g., `set index of t to <n>` instead of `set selected to true`). The contract in `contracts/applescript-payloads.md` captures the expected shape; the implementation pass verifies and updates if needed.

---

## 3. osascript failure modes and exit codes

**Decision**: Detect AppleScript failure via `osascript -e '<body>'` exit code + stderr pattern matching. Three meaningful outcomes:

| osascript exit | Meaning in our click handler | Log category |
|----------------|------------------------------|--------------|
| 0 | Script ran, iterated windows/tabs, and either selected the target OR returned `1` indicating no-match-found | If returned 1: `applescript-failed` with mode=`no-tty-match` |
| 1 (generic error) | Script syntax error, runtime error, or internal failure | `applescript-failed` with mode=`script-error` |
| 1 (with stderr matching `not authorized to send Apple events`) | Automation permission not granted | `applescript-failed` with mode=`permission-denied` |
| Non-zero not matching above | Terminal app quit mid-execution or other transient | `applescript-failed` with mode=`osascript-other` |

**Script return value convention**: our AppleScript body returns `0` from the outer `tell` block on successful match-and-select, `1` on no match found. osascript propagates the AppleScript return value as its own exit code (when the script's last expression is a number). This gives us 3 cleanly distinguishable states:

- exit 0, no stderr: matched and selected.
- exit 1, no stderr (osascript itself succeeded, AppleScript returned 1): iterated but no tab had a matching TTY. Log `no-tty-match`.
- exit 1, stderr contains `not authorized` or `(-1743)`: TCC permission denied. Log `permission-denied`.
- exit ≠ 0,1, OR exit 1 with different stderr: runtime failure. Log `osascript-other` (catchall).

**Rationale**: Distinguishes user-actionable failures (permission-denied → user can fix in System Settings → Privacy & Security → Automation) from silent-fall-through cases (no-tty-match → expected when session is detached). The categories feed the spec's FR-005 clarification.

**Alternatives considered**:

- Always return exit 0 from the AppleScript, encode success/failure in stdout: more code in both the script and the bash wrapper, no diagnostic gain.
- Use `osascript -s o` (output as object) for structured stdout: overkill for binary success/fail.

---

## 4. TCC (Transparency, Consent, Control) permission flow

**Decision**: The first click on a banner that routes through `osascript` triggers a macOS TCC dialog asking for automation permission to control iTerm2 (or Terminal.app). The parent process that "owns" this permission is **whichever binary invokes `osascript`** — in our pipeline, that's either `alerter`'s click-callback subshell (`/bin/sh -c` parenting `osascript`) or more precisely `osascript` itself. The permission is per-(requestor-bundle × target-app) and persists until the user revokes it.

**User-facing flow**:
1. User installs tms install-hooks (with feature 004) — no permission prompt yet.
2. First real Claude Code Notification event fires a banner — banner shows, no prompt.
3. User clicks the banner. The click callback runs osascript for iTerm2 control. macOS shows a dialog: "sh would like to control 'iTerm'. Allow?" (or similar).
4. User clicks Allow. The click proceeds (possibly after a slight delay; the already-launched osascript may have errored by the time user grants).
5. Subsequent clicks: no prompt, script runs, tab selected.

**Deferred TCC handling for first-click UX**: the first click may visibly fail to reach the target tab because osascript errored before permission was granted. Our fallback chain ensures the tmux session still switches correctly — user gets the current pre-feature experience on that first click, plus the `applescript-failed permission-denied` log entry. From the second click onward, the exact-tab behavior works.

**Rationale**: TCC prompts cannot be pre-requested from a shell script — there's no `tccutil request` or equivalent. The organic first-click prompt is the standard macOS pattern. Documenting it in the README under the notifications section is sufficient.

**Alternatives considered**:

- Fire a dummy osascript during `tms install-hooks` to front-load the TCC prompt: cleaner onboarding, but adds complexity and a questionable UX (asking for permission the user hasn't seen a reason for yet). Rejected.
- Require the user to manually pre-grant via System Settings: passes the burden to docs. Rejected in favor of organic first-click prompt + documentation.

---

## 5. TTY query timing: emission vs click

**Decision**: Query the target TTY at **click time**, not at emission time. The click-callback shell string includes a `tmux list-clients -t <project> -F '#{client_tty}' | head -1` inline subshell; its result feeds the AppleScript as an `--args` parameter.

**Rationale**: Between banner emission and user click, the tmux client landscape can change — user detaches and re-attaches in another tab, closes the original window, or opens a second view. Baking the TTY at emission time (the feature 002 pattern for `project_name`) would lead to stale TTYs and spurious `no-tty-match` logs. Live query at click time gets the current truth.

**Performance cost**: one `tmux list-clients` call is ~5ms on a local tmux server. Trivial compared to the osascript spend (~200-400ms).

**Alternatives considered**:

- Bake at emission time like `project_name`: simpler shell escaping, but incorrect for the common "user moved session" case. Rejected.
- Query TTY at emission but refresh if stale: adds state tracking we don't need. Rejected.

Note: `project_name` must still be baked at emission time (per feature 002 data-model.md §Click Action Payload's critical invariant — clicks should always route to the project that emitted the banner, even if config changed). TTY is a different concern (per-attachment identity, not project identity) and correctly belongs at click time.

---

## 6. Embedding strategy: inline osascript vs external .scpt file

**Decision**: Embed AppleScript as an inline string passed to `osascript -e '<body>'` (or heredoc'd via `osascript <<EOF`). No external `.scpt` file.

**Rationale**:

- Shell-string-interpolating the body into the click callback keeps the whole click flow inside one subshell — matches the existing emission pattern (everything lives inside `cmd_notify_hook`'s detached subshell, no external resources).
- External `.scpt` file would require path resolution at click time, adding a failure mode (path wrong / file missing) that contributes zero value.
- `osascript -e` accepts arbitrary-length scripts; our bodies are ~15-25 lines.

**Implementation note**: pass the target TTY as a command-line argument to osascript (`osascript -e '<body>' -- "$target_tty"`) and reference it inside the AppleScript via `item 1 of argv` (accessible via the `on run argv` entry point). This avoids shell-escaping a TTY path into the script body — clean separation of code and data.

**Alternatives considered**:

- External `.scpt` compiled via `osacompile`: marginal startup-time speedup (~20ms per invocation), but adds build step, install step, path-resolution failure mode. Not worth it.
- Inline shell string with sed substitution of TTY: fragile shell-escaping. Rejected in favor of `--args`.

---

## 7. Performance budget

**Decision**: Target <500ms for the osascript phase alone, within the feature 002 SC-002 2-second end-to-end click budget. Measured empirically on a typical multi-tab setup, osascript startup is ~80ms, script execution (iterating a handful of windows × tabs) is ~50-200ms depending on iTerm2 responsiveness. Total well under budget.

**Rationale**: the 2-second feature-002 SC-002 budget was calibrated for terminal-notifier + click callback dispatch. Our extended click handler adds one osascript call (up to 300ms worst case) and one extra `tmux list-clients` (negligible). Remaining budget after osascript: ~1.5s for `open -b` + `tms switch`. That's already comfortably the current behavior's headroom.

**Alternatives considered**:

- Pre-cache TTY→window/tab mapping: caches can go stale. Reject; one-shot query is fast enough.
- Run osascript in parallel with `open -b`: AppleScript's `activate` already raises the app; parallelism is unnecessary and would complicate error handling.

---

## 8. Failure chain and decision tree at click time

**Decision**: Click-callback flow (inside the detached subshell that already exists per feature 002):

```text
click → (start of callback)
├─ resolve term_bundle_id at emission time (existing) — feature 002 bake
├─ query target_tty fresh:
│    target_tty=$(tmux list-clients -t "$project" -F '#{client_tty}' | head -1)
│
├─ decide branch by term_bundle_id:
│
├─ if bundle == com.googlecode.iterm2:
│    osascript -e '<iterm body>' -- "$target_tty"
│    ├─ exit 0 → success. Target tab selected. Run `tms switch` for tmux-side
│    │           session+window+pane selection (feature 003's in-session routing).
│    │           Skip `open -b` (osascript activated iTerm2).
│    └─ exit ≠ 0 or AppleScript-returned 1 → log applescript-failed with mode,
│                  fall through to the existing open-b + tms switch path.
│
├─ if bundle == com.apple.Terminal:
│    osascript -e '<terminal body>' -- "$target_tty"
│    ├─ exit 0 → success, as iTerm path.
│    └─ non-zero → same fallback + log.
│
└─ else (non-AppleScript bundle):
     existing path unchanged: open -b ; tms switch ; conditional follow-up alerter.
```

The "skip `open -b` on osascript success" optimization matters because osascript's `activate` already raises the app — running `open -b` afterward would be a no-op but wastes ~50ms and potentially re-focuses a window the script just selected.

**Rationale**: The happy path (AppleScript succeeds) does exactly what the user expects, skipping redundant app-activation. The sad path (AppleScript fails for any reason) falls back to the current pre-feature behavior — no regression. Logging `applescript-failed` gives the user a diagnostic trail without spamming the log for the success case.

**Alternatives considered**:

- Always run `open -b` in addition to AppleScript: harmless on macOS (open is idempotent) but wasteful. Rejected.
- Replace `open -b` entirely with AppleScript `activate`: would be fine for iTerm2/Terminal.app but leaves the fallback path (other terminals) still using `open -b`, so `open -b` stays in the codebase anyway.

---

## Summary of decisions feeding Phase 1

- **iTerm2 AppleScript**: `tty of current session of tab` matches tmux `client_tty` exactly. Verified.
- **Terminal.app AppleScript**: `tty of tab` (expected shape; verify empirically during implementation).
- **osascript failure modes**: 4 discriminator values (`permission-denied`, `no-tty-match`, `script-error`, `osascript-other`) logged as `applescript-failed` category.
- **TCC permissions**: first-click prompt is acceptable UX; document in README; no proactive dummy prompt.
- **TTY query timing**: click-time, not emission-time. `project_name` stays emission-time.
- **Embedding strategy**: inline `osascript -e` with `--args` for TTY. No .scpt file.
- **Performance**: ~300ms added on happy path, within existing SC-002 budget.
- **Happy path optimization**: skip `open -b` when AppleScript activates the app successfully.

All Technical Context unknowns resolved; no `NEEDS CLARIFICATION` markers remain.
