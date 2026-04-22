# Quickstart: Click-to-Exact-Tab Notification Switch

**Feature**: 004-click-to-exact-tab
**Date**: 2026-04-22

Manual verification recipe for the exact-tab banner-click behavior. Runs against a real multi-window, multi-tab setup of iTerm2 or Terminal.app.

---

## Prerequisites

- feature 002 (notification hook) and feature 003 (install bootstrap) already merged and installed.
- `alerter`, `jq`, and `osascript` (built-in) on PATH. No new install steps.
- Two or more tms projects configured and running. Recommendation: 3 projects on 2 terminal windows, 2 tabs each.
- Claude Code Notification hook registered (`tms install-hooks`).

---

## Verification scenarios

### QS-1: Click lands on exact iTerm2 tab (P1 happy path)

**Covers**: US1 AS-1; FR-001, FR-002, FR-003; SC-001.

1. In iTerm2, open 2 windows. In each window, open 2 tabs (4 tabs total).
2. Attach a different tms session in each tab:
   - Window 1 Tab 1 → `tms start project-a`
   - Window 1 Tab 2 → `tms start project-b`
   - Window 2 Tab 1 → `tms start project-c`
   - Window 2 Tab 2 → any non-tms shell (control: we should NOT land here).
3. Bring Window 2 Tab 2 to the front (focus a non-tms tab).
4. Trigger a Claude Code Notification in `project-a` (e.g., ask Claude in that session to run a command needing approval).

**Expect** within 2 seconds of clicking the banner:
1. iTerm2 remains the active application.
2. Window 1 is now the frontmost window (Window 2 drops to the back).
3. Tab 1 in Window 1 is selected (shows Claude prompt waiting).
4. `tmux display-message -p '#S:#W.#P'` in that tab prints `project-a:workspace.<claude-pane>` (feature 003's pane routing still applies).

Also check:
- `~/.local/state/tmux-session-manager/notifications.log` has NO new entries from this click (success path is silent).

---

### QS-2: Click lands on exact Terminal.app tab (P1 alternate terminal)

**Covers**: US1 AS-2; FR-003.

Run the same setup as QS-1 but using Terminal.app instead of iTerm2. Note that `notify_resolve_term_bundle` should produce `com.apple.Terminal` when Claude Code is running in Terminal.app (via `$TERM_PROGRAM=Apple_Terminal`).

**Expect**: identical behavior to QS-1. Terminal.app activates; the correct window is frontmost; the correct tab is selected.

**Note on first-run permission prompt**: on the very first click, macOS may show a TCC dialog asking Terminal.app's controller (the shell running the click callback) for permission to control Terminal.app. Click Allow. Subsequent clicks are silent.

---

### QS-3: Detached session — graceful no-tty-match fallback

**Covers**: US3 AS-1, AS-2; FR-008; log category `no-tty-match`.

1. Start a tms project: `tms start project-a`.
2. Detach from it: `tmux detach-client` (or `prefix + d`).
3. From another terminal, trigger a Claude Code Notification for `project-a` — use `tms test-hooks --project project-a` since Claude Code isn't running there.
4. Click the banner.

**Expect**:
1. AppleScript runs, iterates iTerm2 tabs, finds no match (no tab has the target TTY because the session is detached), returns 1.
2. Click callback logs `applescript-failed / no-tty-match` to `notifications.log`.
3. Falls back to the existing `open -b` + `tms switch` path. iTerm2 activates, current tab retargets to `project-a`.

Verify log line:

```bash
tail -1 ~/.local/state/tmux-session-manager/notifications.log
# → 2026-04-22T…+0800  applescript-failed  project-a  idle_prompt  tms-test  no-tty-match
```

---

### QS-4: Permission denied — first-click TCC flow

**Covers**: FR-010; log category `permission-denied`.

1. Fresh install OR revoke existing automation permission: **System Settings → Privacy & Security → Automation → [shell or osascript entry] → uncheck iTerm**.
2. Click a notification banner.

**Expect**:
1. macOS shows a TCC prompt: "sh would like to control iTerm.app. Allow?" (or similar).
2. The first click's osascript fails before the user can grant permission. Log line `applescript-failed / permission-denied` appears.
3. Fallback runs; tmux session switches; iTerm2 activates via `open -b`.
4. Click Allow on the dialog.
5. Trigger another notification and click. Second click should work — osascript succeeds, exact-tab selected, no new log line (success is silent).

---

### QS-5: Fallback on non-AppleScript terminal

**Covers**: US2 AS-1, AS-2; FR-004; SC-004.

1. Launch `ghostty` (or alacritty / kitty / wezterm — any terminal without a macOS AppleScript API).
2. Attach a tms session inside: `tms start project-a`.
3. Run Claude Code inside; trigger a Notification.
4. Click the banner.

**Expect**:
1. Click callback does NOT invoke osascript (term_bundle_id is not in the AppleScript-capable set).
2. Behavior matches feature 002 exactly: ghostty foregrounds via `open -b`; `tms switch project-a` runs; user lands on the session.
3. No `applescript-failed` log entry (feature is simply a no-op here).
4. No permission prompts.

---

### QS-6: Single-tab regression check

**Covers**: US1 AS-3; FR-007; SC-003.

1. In iTerm2, close all but one window with one tab. Run a single tms session.
2. Trigger and click a banner.

**Expect**:
1. Click lands on the (only) tab, as before.
2. No perceptible slowdown vs. pre-feature behavior.
3. No log entries.

Optionally measure:

```bash
for i in $(seq 1 20); do
  time (printf '<click payload>' | simulate-click-callback)
done
```

p95 click-to-landed time should be <250ms (versus pre-feature ~200ms).

---

### QS-7: Multiple clients attached to same session — first-client-wins

**Covers**: Edge case from spec; FR-009.

1. In one iTerm2 tab: `tms start project-a`.
2. In another iTerm2 tab (different window or same): `tmux attach -t project-a` (now 2 clients attached).
3. Trigger a notification for `project-a`.
4. Click.

**Expect**:
1. Exact-tab resolution picks one of the two attached tabs — specifically the first one returned by `tmux list-clients -t project-a` (sort-stable).
2. That tab is selected. No log entry.
3. The other attached tab remains attached but un-selected — user can manually cmd-shift-] to cycle tabs if they want the other one.

---

### QS-8: iTerm2 not running at emission time

**Covers**: Edge case — terminal app quit between emission and click.

1. Trigger a notification (banner appears).
2. Before clicking, quit iTerm2 entirely (cmd-Q).
3. Click the banner.

**Expect**:
1. osascript attempts to `tell application "iTerm"` which relaunches iTerm2 (macOS behavior) but with no windows/tabs.
2. AppleScript iterates (empty windows), returns 1.
3. Log entry `applescript-failed / no-tty-match`.
4. Fallback `open -b` launches iTerm2 properly; `tms switch` attaches the tmux session in a new/fresh window.

User ends up with the session visible in a freshly-opened iTerm2 window. Acceptable graceful degradation.

---

### QS-9: Performance measurement

**Covers**: SC-002, SC-003; FR-006.

Measure 20 clicks across the multi-window matrix. Record:
- p50, p95 click-to-landed time
- Pre-feature (feature 002) baseline: should be <1.5s p95 (the tms-switch perf PR brought it down dramatically)
- Post-feature: should be <2s p95 per SC-002

Acceptable: the AppleScript phase adds <500ms to the happy path. Total click → landed < 2s p95.

---

## Acceptance traceability matrix

| Spec element | Quickstart scenario |
|--------------|---------------------|
| US1 AS-1 (iTerm2 exact tab) | QS-1 |
| US1 AS-2 (Terminal.app exact tab) | QS-2 |
| US1 AS-3 (single-tab regression) | QS-6 |
| US2 AS-1 (non-AppleScript fallback) | QS-5 |
| US2 AS-2 (unknown terminal) | QS-5 (covers both) |
| US3 AS-1, AS-2 (detached session) | QS-3 |
| FR-001 (window + tab selected) | QS-1, QS-2 |
| FR-002 (TTY matching) | QS-1 (verified via `tmux list-clients` vs selected tab) |
| FR-003 (iTerm2 + Terminal.app) | QS-1, QS-2 |
| FR-004 (fallback path) | QS-5 |
| FR-005 (log on AppleScript failure) | QS-3, QS-4 |
| FR-006 (<2s end-to-end) | QS-9 |
| FR-007 (no regression single-tab) | QS-6 |
| FR-008 (detached session fallback) | QS-3 |
| FR-009 (first-client-wins) | QS-7 |
| FR-010 (graceful permission denial) | QS-4 |
| SC-001 (95% correct tab) | QS-1 (multi-week real use) |
| SC-002 (<2s p95) | QS-9 |
| SC-003 (no single-tab regression) | QS-6, QS-9 |
| SC-004 (fallback correctness) | QS-5 |
| SC-005 (AppleScript failure → fallback safe) | QS-3, QS-4, QS-8 |

All spec requirements and acceptance scenarios have at least one corresponding manual verification step.
