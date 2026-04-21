# Feature Specification: Claude Code Notification Hook with Click-to-Switch

**Feature Branch**: `002-claude-notification-hook`
**Created**: 2026-04-21
**Status**: Draft
**Input**: User description: "add notification hook for Claude Code, send a macOS notification, when notification banner is clicked, use tms to switch to the project that sends notification"

## Clarifications

### Session 2026-04-21

- Q: Which Claude Code hook event(s) should trigger a macOS notification? → A: Only Claude Code's `Notification` hook (permission prompts, idle waiting).
- Q: When the user clicks the notification, what exact tmux destination should the switch land on? → A: Switch to the originating session and select the workspace window (window 1).
- Q: Once the hook is installed, is it enabled for all tms-managed projects by default, or opt-in per project? → A: Global ON by default, with a per-project opt-out flag in tms project config.
- Q: When the hook fails to emit a notification, where should the failure be surfaced? → A: Append to a dedicated tms log file under a standard user state directory.
- Q: What should the notification body contain? → A: Title = tms project name; body = Claude Code's `message` verbatim (macOS truncates as needed).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Surfacing attention-needed events from background projects (Priority: P1)

A developer is working on Project A while Claude Code is also running in a second tmux-managed project (Project B). When Claude Code in Project B fires its `Notification` hook (for example, it is asking for tool-use approval or is idle waiting for input), the developer currently has no way to notice this without manually cycling through tmux sessions. This feature surfaces that event as a native macOS notification that clearly identifies which project is asking for attention. Task-completion (`Stop`) and other lifecycle hooks are explicitly out of scope for v1.

**Why this priority**: Without reliable surfacing, the rest of the feature is worthless — missed prompts block productivity even when click-to-switch works perfectly. This delivers standalone value: the developer regains awareness of attention-needed events across concurrent projects.

**Independent Test**: Trigger Claude Code's `Notification` hook inside a tms-managed project while the developer is focused on a different tmux session or application. Confirm a macOS notification appears within a human-perceptible timeframe and its title or body clearly identifies the originating project by its tms project name.

**Acceptance Scenarios**:

1. **Given** Claude Code is running inside a tms-managed project session and the user is focused on another application, **When** Claude Code's `Notification` hook fires, **Then** a macOS notification appears that names the originating project and conveys the reason (e.g., "waiting for approval", "idle").
2. **Given** multiple tms-managed projects are running Claude Code concurrently, **When** two projects emit notification events in close succession, **Then** each notification displays its own project name so the developer can disambiguate.
3. **Given** the notification mechanism is configured, **When** Claude Code emits an event that would normally only ring the tmux visual bell, **Then** a macOS notification is emitted in addition to the existing visual bell, without suppressing it.

---

### User Story 2 - One-click switch to the originating project (Priority: P1)

When the developer sees the macOS notification banner and clicks it, the terminal is brought to focus and the tmux workspace switches to the project that emitted the event, landing the developer in the exact session where Claude Code is awaiting attention.

**Why this priority**: Seeing the notification is half the value; being dropped into the right session is the productivity payoff. Without click-to-switch, the developer still has to manually hunt for the session. This story is also P1 because it is the defining user-visible behavior promised by the feature description.

**Independent Test**: With the notification from Story 1 visible on screen, click the banner once and verify the terminal comes to the foreground, the active tmux session is the project named in the notification, and the active window is the workspace window (window 1) where Claude Code runs.

**Acceptance Scenarios**:

1. **Given** a macOS notification banner from this feature is visible, **When** the user clicks the banner, **Then** the terminal application gains focus, the active tmux session becomes the project named in the notification, and the workspace window (window 1) is selected.
2. **Given** the notification is clicked but the target project's tmux session has been stopped since the notification fired, **When** the switch is attempted, **Then** the system surfaces a clear, non-silent failure (e.g., a secondary notification or terminal message) rather than leaving the user on the wrong session with no feedback.
3. **Given** the notification is dismissed (swiped away or ignored until it disappears) rather than clicked, **When** the developer later runs `tms list` or similar, **Then** no residual state from the dismissed notification affects tms session status.

---

### User Story 3 - Graceful behavior outside tms-managed contexts (Priority: P3)

A developer runs Claude Code in a directory that is not registered as a tms project (e.g., quick exploration in `~/scratch`). Notifications should still be useful — either by surfacing a plain notification without a broken click target, or by omitting click-to-switch cleanly — rather than crashing the hook or producing a dead banner.

**Why this priority**: This is a graceful-degradation case. The core feature works without it for the common tms-managed workflow, but shipping without this behavior creates sharp edges for the minority of sessions started outside tms.

**Independent Test**: Start Claude Code in a non-tms directory, trigger Claude Code's `Notification` hook, and verify the hook either fires a plain notification with no click action or skips cleanly without error — and in particular does not emit a notification whose click action fails silently or opens the wrong session.

**Acceptance Scenarios**:

1. **Given** Claude Code is running outside any tms-managed project, **When** Claude Code's `Notification` hook fires, **Then** the hook does not error and either fires a clearly labeled plain notification or skips emission.
2. **Given** the hook cannot determine the originating project name, **When** a notification is emitted, **Then** the banner does not advertise a click-to-switch behavior it cannot fulfill.

---

### Edge Cases

- Notification permissions for the notifier tool are denied at the OS level: the hook must not block Claude Code (FR-007). Because the underlying notifier does not expose a reliable permission-denied runtime signal on current macOS, this feature detects the denied-permission case proactively at `tms install-hooks` time via a probe banner and clear instructions pointing the user to System Settings → Notifications, rather than attempting to detect it on every runtime event. Runtime failures that do produce a non-zero exit are logged as `alerter-failed` without deduplication; volume is bounded by Claude Code's notification cadence.
- The developer is already focused on the originating project's tmux session when the event fires: notification still emits (matching Claude Code's own hook behavior); clicking it is a no-op switch and must not produce errors.
- Two different projects emit notifications near-simultaneously and the developer clicks one while the other is still on screen: the click must route to the correct project, not the most recent.
- The tmux server hosting the target project has been killed (or the session otherwise stopped) between notification emission and the click: `tms switch` MUST NOT auto-start a fresh session implicitly; it MUST exit non-zero with a clear stderr message, and the click callback MUST fire a follow-up macOS notification titled with the project name and a body directing the user to run `tms start <project>`. This is what "fail loudly enough for the user to notice" means in this feature.
- The click payload carries a project name that no longer exists in tms configuration (renamed or removed project): surface a clear error; do not create a new session implicitly.
- Claude Code emits many notifications in rapid succession (e.g., a noisy approval loop): the user relies on macOS Notification Center's default coalescing behavior in v1. Application-level duplicate suppression is explicitly deferred (see Assumptions) and is revisited only if that default proves insufficient in practice.
- The user is on a different macOS Space or has Do Not Disturb on: standard macOS behavior applies; the feature does not attempt to override system-level notification policy.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST emit a macOS notification whenever Claude Code's `Notification` hook fires inside a tms-managed project session. Other Claude Code hooks (`Stop`, `SubagentStop`, `SessionEnd`, etc.) are out of scope for v1 and MUST NOT trigger macOS notifications through this feature.
- **FR-002**: The notification MUST identify the originating project by the project name registered in tms configuration, visibly distinguishable from notifications emitted by other projects.
- **FR-003**: The notification's title MUST be the tms project name, and its body MUST be Claude Code's hook `message` payload rendered verbatim (macOS Notification Center is allowed to truncate for display). The feature MUST NOT perform application-level truncation, summarization, or substitution of the message text.
- **FR-004**: The notification banner MUST be clickable, and clicking it MUST bring the terminal application to the foreground, switch the active tmux session to the originating project's session, and select that session's workspace window (window 1, where Claude Code runs) so the user lands directly on the awaiting prompt.
- **FR-005**: The click-to-switch action MUST use the existing tms switching mechanism rather than re-implementing session navigation, so that behavior stays consistent with `tms` CLI usage.
- **FR-006**: If the originating project's tmux session no longer exists when the notification is clicked, the system MUST surface a user-visible error rather than silently failing or switching to an unrelated session.
- **FR-007**: The hook MUST NOT block, delay, or crash Claude Code when notification emission fails (e.g., permission denied, notifier binary missing); failures must be isolated from Claude Code's main interaction loop. Each failure MUST be appended (with timestamp, originating project name if known, and error reason) to a dedicated tms log file under a standard user state directory so the user can diagnose why notifications are not appearing.
- **FR-008**: Installation/configuration of the hook MUST be discoverable — a developer who reads the project README or runs `tms help` should be able to find how to enable it without inspecting source code.
- **FR-009**: The feature MUST coexist with the existing tmux visual bell notification behavior rather than replacing it; both channels operate together.
- **FR-010**: When Claude Code runs outside a tms-managed project, the hook MUST degrade gracefully — either emitting a notification with no click-to-switch or skipping emission — without producing errors or dead banners whose click actions fail silently.
- **FR-011**: Once installed, the hook MUST be enabled for all tms-managed projects by default. A per-project opt-out flag in tms project configuration MUST suppress macOS notification emission for that project without affecting other projects or the existing tmux visual bell.

### Key Entities *(include if feature involves data)*

- **Notification Event**: Represents a single Claude Code `Notification` hook invocation. Carries the originating tms project name (used as the notification title), the `message` payload from Claude Code (used verbatim as the notification body), and a timestamp. Consumed to produce exactly one macOS notification.
- **Project**: The tms-registered project associated with a notification. Identified by the project name used in tms configuration; this name is both the display label on the notification and the argument used by the click-to-switch action.
- **Click Action Payload**: The data embedded in the notification that, when the banner is clicked, tells the system which project to switch to. Must be derivable at emission time, not resolved lazily at click time.
- **Per-Project Notification Setting**: A boolean opt-out stored in each tms project's configuration. Absent or false means notifications are emitted for that project (the default); true suppresses macOS notification emission for that project only.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A developer running Claude Code in a background project can identify which project needs attention within 3 seconds of the event firing, without switching tmux sessions manually.
- **SC-002**: Clicking a notification banner lands the developer in the correct project's tmux session in under 2 seconds from click to visible session switch.
- **SC-003**: Over a week of multi-project Claude Code use, the developer misses zero attention-needed prompts they would have otherwise missed under the pre-feature baseline (validated by self-report or log comparison).
- **SC-004**: Clicking a notification never switches to a project other than the one that emitted it, demonstrated for 2+ concurrent projects via QS-5. The property is architecturally project-count-independent: project identity is baked into each banner's click callback at emission time (see data-model.md §Click Action Payload), so correctness at N=2 implies correctness at N.
- **SC-005**: Notification emission adds no user-perceptible latency to Claude Code's main interaction loop — measured by before/after response-time comparison on a scripted interaction showing no regression greater than 100 ms at the 95th percentile.

## Assumptions

- The target platform is macOS only. The tmux-session-manager project already targets Darwin (per the environment), and the user request specifies macOS notifications; cross-platform parity is out of scope for v1.
- A supported macOS notifier tool capable of firing clickable banners with a custom click-action payload is available or installable as a dependency. The specific tool is an implementation detail and intentionally left to the plan phase.
- The mechanism for identifying the "originating project" from inside the hook uses the tmux session or working directory associated with the Claude Code process at the moment the hook fires, mapped back to a tms project name via existing tms configuration.
- The developer has granted the relevant macOS notification permission to whichever application ultimately delivers the banner. If they have not, the feature surfaces the failure once but does not attempt to bypass OS permission prompts.
- The existing tmux visual bell behavior (referenced in the project's CLAUDE.md) remains in place; this feature is additive.
- Duplicate/rapid-fire notifications use whatever default coalescing macOS Notification Center provides; explicit application-level rate limiting is deferred unless testing shows it to be necessary (see edge case above).
- The click-to-switch action is allowed to use whichever terminal-application focus mechanism is conventional on macOS (e.g., activating the frontmost terminal process); the feature does not guarantee behavior across every exotic terminal emulator.
