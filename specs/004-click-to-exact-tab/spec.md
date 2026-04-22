# Feature Specification: Click-to-Exact-Tab Notification Switch

**Feature Branch**: `feat/click-to-exact-tab`
**Created**: 2026-04-22
**Status**: Draft
**Input**: User description: "is it possible that clicking on banner also switch to the window and tab of the terminal? I have multiple tabs and windows"

## Clarifications

### Session 2026-04-22

- Q: Should AppleScript-specific failures be logged to notifications.log when the click falls back to the existing `tms switch` path? → A: Yes — log a new `applescript-failed` category with the failure mode (e.g., `permission-denied`, `no-tty-match`, `script-error`, `terminal-quit`). Rationale: users notice the "exact tab" regression but need a breadcrumb to diagnose; silent fallback leaves them blind. Cost is one log write on a rare path; doesn't affect hot-path latency.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Click lands on the exact terminal tab hosting the session (Priority: P1) 🎯 MVP

A developer has multiple terminal windows open, each with several tabs, across different projects. A Claude Code Notification fires in one specific tab (attached to a specific tms session). When the developer clicks the macOS banner, the correct terminal application is foregrounded, the correct window is raised, and the correct tab within that window is selected — landing the developer directly on the pane where Claude is awaiting attention, without having to hunt through tabs.

**Why this priority**: This is the core UX improvement. Today, clicking the banner foregrounds the terminal application but lands the user on whichever window/tab macOS most recently focused — which is often NOT the session Claude Code was running in. The user then has to cycle tabs manually to find the right one, defeating the point of click-to-switch.

**Independent Test**: Open two terminal windows, each with two tabs. Attach a different tms session to each tab. Trigger Claude Code Notifications in each. Click the banner for a specific session and verify the click lands on that session's exact tab — not just the terminal app, not just the right tmux session, but the specific window+tab that's actually displaying it.

**Acceptance Scenarios**:

1. **Given** iTerm2 is open with 2 windows, each with 2 tabs, and a different tms session attached per tab, **When** the user clicks a notification banner for one specific session, **Then** iTerm2 comes to the foreground AND the window containing that session is raised AND the tab within that window is selected, in under 2 seconds.
2. **Given** the user is running Terminal.app with multiple tabs and tms sessions attached to different tabs, **When** a banner is clicked, **Then** Terminal.app foregrounds, the owning window activates, and the target tab is selected.
3. **Given** the user has exactly one terminal window open with one tab (a single-tab setup), **When** a banner is clicked, **Then** behavior is identical to the current implementation — no regression.

---

### User Story 2 - Graceful fallback on terminals without AppleScript (Priority: P2)

A developer uses a terminal emulator that doesn't expose a scripting API for programmatic window/tab selection (Ghostty, Alacritty, kitty, WezTerm, etc.). When they click a notification banner, the existing behavior is preserved: the terminal application foregrounds, the tmux client is retargeted to the correct session, and the developer may need to cycle windows/tabs manually to find the one now showing the session.

**Why this priority**: This feature should not regress behavior for users on terminals we can't programmatically script. Current behavior already works (session switches, user cycles if needed); P2 just means we're explicit about preserving it rather than silently breaking.

**Independent Test**: On a terminal without AppleScript support (e.g., Ghostty), click a notification banner. Verify the terminal foregrounds and the tmux session switches — same behavior as before this feature — without errors.

**Acceptance Scenarios**:

1. **Given** the user is running Ghostty (no AppleScript API), **When** a banner is clicked, **Then** the click callback proceeds through the current `open -b` path without attempting AppleScript, logs no unnecessary error, and tmux session switching works as before.
2. **Given** an unknown or future terminal emulator, **When** a banner is clicked, **Then** the fallback path runs without the feature crashing the click callback.

---

### User Story 3 - Session not currently attached in any window (Priority: P3)

A developer has a tms session running (the tmux server has it) but no terminal window is currently attached to it (e.g., they detached earlier). When they click a notification banner for that session, the click still lands them on the session — using the existing `cmd_switch` attach logic — rather than failing silently or spawning new windows.

**Why this priority**: This is a graceful-degradation case. The correct window+tab matching can't find a window because none owns the target session's TTY. The feature must not break this case.

**Independent Test**: Detach from a tms session. Trigger a notification for it (either leave Claude Code running in that session without an attached client, or fire via `tms test-hooks --project <name>`). Click the banner and verify the existing attach-to-session fallback kicks in — no attempt to open a new window, no silent failure.

**Acceptance Scenarios**:

1. **Given** a tms session is running but has no attached tmux client, **When** the user clicks a banner for that session, **Then** the click handler falls through to `cmd_switch`'s existing attach logic and the user ends up viewing the session in some terminal window (existing behavior — not a regression).
2. **Given** the click handler's AppleScript tab-matching finds no window owning the target TTY, **When** the handler falls back to the existing path, **Then** no error banner fires and no log entry of "switch-failed" is written (because the switch ultimately succeeds via the fallback).

---

### Edge Cases

- **Session attached in multiple clients simultaneously**: Two tabs may both be attached to the same tmux session (uncommon but possible — e.g., the user opened a second view). Pick the first client returned by `tmux list-clients -t <session>` and select that tab; deterministic and consistent, and the user can cycle tabs manually if they want the other one.
- **Terminal is in fullscreen mode**: AppleScript `tell window to select` and `tell tab to select` should still work in fullscreen. If the target window is on a different macOS Space, macOS activates but does NOT auto-switch spaces — user may need to cmd-tab or switch Space manually. Explicitly out of scope.
- **Target window was closed** since the notification fired: `tmux list-clients` still returns the stale TTY; AppleScript iteration finds no tab with that TTY; falls back to the existing attach-in-any-window path.
- **Terminal.app doesn't support per-tab session.tty access**: Terminal.app exposes tab TTYs via a different AppleScript path (`tty of selected tab`) — implement per-terminal dialects.
- **Non-AppleScript terminal emulator**: feature is a no-op improvement; existing `open -b <bundle>` + `tms switch` path runs unchanged.
- **AppleScript execution denied** (user revoked automation permissions): the first click fails with a macOS permission prompt; user grants and future clicks work. Handler must NOT treat a denied AppleScript as a hard failure — fall through to the existing `open -b` path.
- **Stage Manager or Mission Control interference**: out of scope; macOS window-management features may interpose visually, but our click handler doesn't try to override them.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: On notification click, when the resolved tmux session has at least one attached client, the feature MUST bring the exact terminal window AND tab owning that client's TTY to the front — not just the terminal application. "Exact" means the window is raised (not iconified, not behind other windows) AND the tab is selected (not merely the window's last-active tab).
- **FR-002**: Window/tab identification MUST use tmux's `client_tty` matched against the terminal's reported per-tab TTY via AppleScript. Title-based matching MUST NOT be used (tab titles change as commands run; tmux auto-titles drift; fragile).
- **FR-003**: On iTerm2 (`com.googlecode.iterm2`) and Terminal.app (`com.apple.Terminal`), the feature MUST use terminal-specific AppleScript to perform the window+tab selection.
- **FR-004**: On terminal bundles other than iTerm2 and Terminal.app (Ghostty, Alacritty, kitty, WezTerm, any unknown), the feature MUST fall back to the current behavior (`open -b <bundle>` + `tms switch <project>`) without attempting AppleScript. No new errors logged on fallback.
- **FR-005**: If AppleScript window/tab selection fails for any reason (permission denied, syntax error, no matching TTY found, terminal quit since emission), the feature MUST fall back to the existing `tms switch <project>` behavior so the user still ends up on the correct session in *some* window. Additionally, the feature MUST write a diagnostic entry to `notifications.log` under a new category `applescript-failed`, with a failure-mode discriminator in the message field (e.g., `permission-denied`, `no-tty-match`, `script-error`, `terminal-quit`) so users can diagnose why the exact-tab behavior regressed to fallback (clarified 2026-04-22).
- **FR-006**: Total click-to-landed time (from user click to active tab = target tab) MUST remain under 2 seconds at p95, preserving SC-002 from feature 002.
- **FR-007**: Single-window, single-tab setups (the simplest case) MUST behave identically to the pre-feature implementation — no regression, no additional AppleScript overhead that adds perceptible latency.
- **FR-008**: When the target tmux session has no currently-attached client (detached session), the feature MUST NOT spawn a new window or tab. It MUST fall through to the existing `cmd_switch` attach logic which handles the no-attached-client case.
- **FR-009**: When the target tmux session has multiple attached clients (e.g., one tab has it attached, another also has it attached), the feature MUST select the first client returned by `tmux list-clients -t <session>` (sort-stable ordering). The user can manually cycle to the other attached tab if desired. This MUST NOT be surfaced as an error.
- **FR-010**: If the user has revoked AppleScript automation permissions for the click callback's parent process (alerter or `osascript`), the first click MUST degrade gracefully — no silent hang. The behavior is whatever the OS surfaces (permission prompt) plus our fallback to the `open -b` path when osascript returns a denied exit.

### Key Entities *(include if feature involves data)*

- **Target TTY**: The TTY path of the client attached to the originating tmux session at click time. Retrieved via `tmux list-clients -t <session> -F '#{client_tty}'`. Used as the unambiguous identifier for window/tab selection.
- **Terminal Automation Script**: The per-terminal AppleScript (or equivalent) that iterates windows/tabs, finds the one whose current session TTY matches the Target TTY, and selects it. iTerm2 and Terminal.app have different AppleScript shapes; each is a separate script payload.
- **Click Action Payload (extended from feature 002)**: The command embedded in the notification banner's click callback. Feature 002's shape (`open -b <bundle> ; tms switch <project>`) is extended to first attempt the terminal automation script when the bundle is iTerm2/Terminal.app, falling back to the existing shape if it fails or isn't applicable.
- **AppleScript Failure Log Entry (new log category)**: Extends the notifications.log categories defined in feature 002's `contracts/notifications-log-format.md`. New category `applescript-failed` logs when the terminal automation script fails (permission denied, no matching TTY, script error, terminal quit). Same 6-column tab-separated shape as existing categories; the message field carries the failure-mode discriminator.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: On a multi-window, multi-tab iTerm2 or Terminal.app setup (2+ windows × 2+ tabs), clicking a banner lands the user on the exact tab hosting the target session on the first click, with correct tab selection in at least 95% of clicks over a week of real use.
- **SC-002**: The p95 click-to-landed time (click → tab is active) remains under 2 seconds (unchanged from feature 002's SC-002, preserved under the extended behavior).
- **SC-003**: Zero regression in single-window, single-tab setups — click-to-switch time is no slower than the pre-feature implementation when measured across 20 synthetic clicks.
- **SC-004**: Graceful degradation on unsupported terminals — clicking a banner in Ghostty/Alacritty/kitty/WezTerm produces identical behavior to the pre-feature implementation, with no new errors surfaced to the user or log.
- **SC-005**: AppleScript failure (permission denied, missing TTY match, etc.) never leaves the user on the wrong session. The fallback path ensures the tmux session switch still lands them on SOME window showing that session.

## Assumptions

- The user's terminal emulator is one of iTerm2, Terminal.app, or an emulator without AppleScript support. Other emulators (unknown bundles) default to the non-AppleScript fallback path.
- The `tmux list-clients -t <session> -F '#{client_tty}'` command returns the TTY in a format that matches the TTY string exposed by iTerm2's and Terminal.app's AppleScript APIs (both report POSIX paths like `/dev/ttys001`). This has been verified empirically for iTerm2; Terminal.app behavior is expected but needs confirmation during Phase 0 research.
- macOS Automation/AppleScript permissions are granted to the process that runs the click callback (alerter, or whatever invokes `osascript`). First-click permission prompt is acceptable user experience; subsequent clicks are permission-silent.
- The tmux server, terminal emulator, and Claude Code all run on the same macOS host. Remote/SSH scenarios are out of scope.
- The tmux session has at most one workspace window named `workspace` per tms convention. The feature only cares about window+tab selection at the terminal-emulator level; within the selected terminal tab, tmux's own window/pane selection (handled by existing `cmd_switch`) continues to apply.

## Out of Scope

- **Cross-Space switching**: if the target tab is on a different macOS Space (Mission Control), the feature does NOT programmatically switch Spaces. User must navigate manually.
- **Stage Manager integration**: macOS 13+ Stage Manager may visually hide windows; the feature does not attempt to coerce Stage Manager state.
- **Spawning a new window/tab** when the session is detached — we fall through to the existing attach logic instead.
- **Terminal emulators without AppleScript APIs** (Ghostty, Alacritty, kitty, WezTerm at time of writing): feature is an enhancement for AppleScript-capable terminals only. These users keep the current behavior.
- **Remote tmux sessions over SSH**: `tmux list-clients` shows local clients only; a remote SSH-attached tmux client's TTY is on the remote machine and can't be matched to a local terminal tab.
- **Programmatic control of non-tmux applications**: this feature is specifically about routing to the tmux-attached tab. Non-tmux tabs (e.g., plain shell in another tab) are irrelevant and don't need identification.
