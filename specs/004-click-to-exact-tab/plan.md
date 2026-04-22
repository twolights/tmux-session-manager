# Implementation Plan: Click-to-Exact-Tab Notification Switch

**Branch**: `feat/click-to-exact-tab` (spec dir: `specs/004-click-to-exact-tab/`) | **Date**: 2026-04-22 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/004-click-to-exact-tab/spec.md`

## Summary

Extend feature 002's notification click callback so that, in addition to foregrounding the terminal application and running `tms switch`, it selects the exact terminal window + tab currently hosting the target tmux session. Matches by tmux `client_tty` against the terminal's per-tab TTY via AppleScript, supports iTerm2 and Terminal.app natively, and falls back to the existing `open -b` behavior on any other terminal or if the AppleScript step fails. AppleScript failures are logged to `notifications.log` under a new `applescript-failed` category so users can diagnose when exact-tab behavior regresses to fallback.

## Technical Context

**Language/Version**: Bash 4+ (existing) + AppleScript via `osascript` (new, macOS built-in — no new install-time dependency)
**Primary Dependencies**: `alerter` + `jq` (existing from feature 002/003); `osascript` (shipped with macOS; no `require_cmd` needed). No new third-party deps.
**Storage**: No new state. Reuses `notifications.log` from feature 002 for the new `applescript-failed` category.
**Testing**: Manual verification via `quickstart.md` (same harness-less pattern as features 001-003). Manual matrix: iTerm2 + Terminal.app × {single-tab, multi-tab same window, multi-window multi-tab} × {session attached, session detached}.
**Target Platform**: macOS only (AppleScript is macOS-exclusive). Other platforms' click callbacks continue to use the pre-feature `open -b` path unchanged.
**Project Type**: Single-repo CLI tool. No new subcommands.
**Performance Goals**:
  - Click-to-landed p95 < 2 seconds (preserves feature 002 SC-002).
  - AppleScript phase adds <500ms in the happy path (single `osascript` invocation, sub-second on macOS even with many tabs).
  - Single-window, single-tab regression budget: <50ms over pre-feature (FR-007).
**Constraints**:
  - Must preserve feature 002 FR-007 (never block Claude Code).
  - Must not crash the click callback on AppleScript error (FR-005 fallback chain).
  - TTY matching, not title matching (FR-002).
  - Cross-Space switching, Stage Manager, non-AppleScript terminals, session-unattached-anywhere — all explicitly out of scope.
**Scale/Scope**: Single-user, single-macOS-machine. Realistic upper bound: ~10 terminal tabs × 5 windows; AppleScript iteration should comfortably handle this.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

`.specify/memory/constitution.md` remains an unfilled template (same state as features 002/003). No ratified principles to enforce mechanically; the plan adheres to the implicit conventions in `CLAUDE.md`:

- **Bash-first (with macOS-specific glue only when unavoidable)**: AppleScript is introduced because the feature's entire value proposition — selecting a specific terminal tab — cannot be accomplished from bash alone on macOS. AppleScript is the platform-native mechanism; alternatives (window-title matching, window-manager hotkeys) are explicitly rejected in FR-002. The AppleScript is embedded as an inline `osascript -e` payload in lib/notify.sh, not a separate language-tool dependency.
- **tmux target syntax**: no `=` prefix used (this feature doesn't change tmux targets; it consumes `client_tty` read-only).
- **Non-blocking hook (FR-007 from feature 002)**: the AppleScript runs inside the already-detached subshell that handles clicks; the primary hook exit is unaffected.
- **Additive only**: no behavior change for non-iTerm2/non-Terminal.app terminals (FR-004); no regression for single-tab setups (FR-007 / SC-003).
- **No new install dependency**: `osascript` is shipped with macOS; nothing new for users to install.

**Gate status**: PASS. AppleScript is the *only* architectural addition (new language surface on macOS); its use is justified by direct, named requirements. No Complexity Tracking entries required.

**Post-Phase 1 re-check**: filled at end of this file after Phase 1 artifacts generated.

## Project Structure

### Documentation (this feature)

```text
specs/004-click-to-exact-tab/
├── plan.md              # This file (/speckit-plan output)
├── spec.md              # Feature specification (already written; 1 clarification resolved)
├── research.md          # Phase 0 output — AppleScript API details for iTerm2/Terminal.app,
│                        # osascript failure modes, TCC permission flow, TTY query timing
├── data-model.md        # Phase 1 output — entities + per-terminal AppleScript shape
├── quickstart.md        # Phase 1 output — manual verification across the matrix
├── contracts/           # Phase 1 output
│   ├── applescript-payloads.md            # iTerm2 + Terminal.app script contracts (input/output/exit-codes)
│   └── notifications-log-format-update.md # delta: new `applescript-failed` category
├── checklists/
│   └── requirements.md  # Already written by /speckit-specify (all items passing)
└── tasks.md             # Phase 2 output (/speckit-tasks; NOT created here)
```

### Source Code (repository root)

```text
bin/
├── tms                  # (unchanged)
└── tms-switch           # (unchanged)

lib/
├── utils.sh             # (unchanged)
├── config.sh            # (unchanged)
├── session.sh           # (unchanged — feature 003's pane-title routing still applies)
├── servers.sh           # (unchanged)
├── notify.sh            # (modified)
│                        # 1. Extend cmd_notify_hook's click-callback construction
│                        #    so that for iTerm2 and Terminal.app bundle ids it
│                        #    runs an `osascript -e '...'` step BEFORE the
│                        #    existing `open -b` + `tms switch` chain.
│                        # 2. The osascript reads the current target TTY at
│                        #    click time (not emission time) via
│                        #    `tmux list-clients -t <project> -F '#{client_tty}'`
│                        #    then executes the terminal-specific script payload
│                        #    that iterates windows/tabs and selects the match.
│                        # 3. On osascript non-zero exit or any non-match,
│                        #    `notify_log_failure applescript-failed <project> <type>
│                        #    <session-id> <failure-mode>` is called, then the
│                        #    existing open-b + tms switch fallback runs.
│                        # 4. Two new helpers: _notify_applescript_iterm and
│                        #    _notify_applescript_terminal_app returning the
│                        #    per-terminal script body as a single-quoted string.
└── install.sh           # (unchanged)

config/
└── projects.example.yml # (unchanged — no new config knobs for this feature)

README.md                # (modified) small addition under "Enabling Claude Code notifications"
                         # documenting the macOS Automation permission prompt on first click
                         # and the new log category for diagnosis.
CLAUDE.md                # (auto-updated if update-agent-context.sh supports this branch name;
                         # else manual update — add AppleScript to Active Technologies)
```

**Structure Decision**: Additive single-file change to `lib/notify.sh`. The feature modifies exactly one function (`cmd_notify_hook`'s click-callback construction block) plus adds 2 small helpers for the per-terminal AppleScript bodies. No new source files are justified — the AppleScript bodies are ~15-25 lines each and embed naturally in `notify.sh` alongside the code that dispatches them. If the bodies grow significantly in a follow-up (e.g., adding Hyper, Kitty when they gain AppleScript support), they can be extracted to `lib/terminal-automation.sh` then. Per YAGNI, not now.

## Complexity Tracking

> Fill ONLY if Constitution Check has violations that must be justified.

Not applicable — Constitution Check passed with no violations. AppleScript is a net-new platform surface but its use is directly mandated by FR-001/FR-002/FR-003 and there is no simpler mechanism on macOS to achieve exact tab selection.

---

## Post-Phase 1 re-check

Filled after research.md, data-model.md, contracts/, quickstart.md are generated:

**Status**: PASS.

Phase 1 outputs introduce:
- One new contract document (`contracts/applescript-payloads.md`) defining the iTerm2 and Terminal.app script shapes — literal AppleScript bodies with documented preconditions, expected stdout, and exit-code semantics.
- One delta document (`contracts/notifications-log-format-update.md`) adding the `applescript-failed` category to the feature 002 log contract.
- No new architectural patterns, no new languages beyond AppleScript (which is called via `osascript`, itself invoked from bash — same subprocess pattern we already use for `alerter`, `jq`, `yq`, `tmux`).
- No new state, no new subcommands.

The Phase 1 design confirms that the AppleScript addition fits inside the existing detached-subshell click-handler pattern without architectural changes. The `osascript -e '<body>'` call is semantically equivalent to the existing `alerter --title ...` subprocess call in the same subshell — one more fork+exec, one more exit code to branch on.
