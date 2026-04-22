---

description: "Task list for feature 004-click-to-exact-tab"
---

# Tasks: Click-to-Exact-Tab Notification Switch

**Input**: Design documents from `/specs/004-click-to-exact-tab/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/, quickstart.md

**Tests**: Not generated. Same harness-less pattern as features 001-003 — `quickstart.md` is the manual verification recipe; T011 runs the full QS-1..QS-9 suite as the acceptance gate.

**Organization**: Tasks grouped by user story so each story is independently completable and testable.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files / different functions, no dependencies on incomplete tasks)
- **[Story]**: Which user story this task belongs to (US1, US2, US3)
- Paths are absolute

## Path Conventions

Single-repo bash CLI layout (per plan.md §Project Structure). All paths rooted at `/Users/ykchen/Projects/ykchen/tmux-session-manager/`. The whole feature lives in `lib/notify.sh` plus README + a small CLAUDE.md update.

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Set up scaffolding for the new helper functions inside `lib/notify.sh`. Trivial — feature lives entirely in one file with no new modules.

- [X] T001 [P] Reserve a section in `/Users/ykchen/Projects/ykchen/tmux-session-manager/lib/notify.sh` for the new helpers: add a comment header `# --- click-to-exact-tab helpers (feature 004) ---` directly above the existing `cmd_notify_hook` definition. No business logic in this task; just makes a stable insertion point so subsequent tasks can edit a known location.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Pure-bash and pure-AppleScript primitives that all downstream tasks consume. No user story can complete without these. All live in `lib/notify.sh` so tasks are sequential within this phase.

**⚠️ CRITICAL**: No user story work can begin until this phase is complete.

- [X] T002 Implement `_notify_classify_osascript_err` in `/Users/ykchen/Projects/ykchen/tmux-session-manager/lib/notify.sh` per data-model.md §Click Action Payload (extended) and contracts/notifications-log-format-update.md: pure-bash function that takes osascript stderr text as `$1` and prints exactly one of `permission-denied`, `script-error`, `terminal-quit`, `osascript-other`. Discrimination patterns from research.md §3 — match `not authorized to send Apple events` or `(-1743)` → `permission-denied`; `execution error`/`syntax error` → `script-error`; `Can't get`/`doesn't understand` → `terminal-quit`; otherwise `osascript-other`. The `no-tty-match` mode is NOT a stderr classification — it's signaled by osascript exit==1 with empty stderr; callers handle that case explicitly.
- [X] T003 [P] Implement `_notify_iterm_applescript` in `/Users/ykchen/Projects/ykchen/tmux-session-manager/lib/notify.sh` per contracts/applescript-payloads.md §Payload 1: returns the iTerm2 AppleScript body as a single multi-line string (heredoc or inline `printf`). Body is the exact `on run argv` block from the contract — iterates `windows`, `tabs of w`, `tty of current session of t`, returns 0 on match (after `tell w to select` + `tell t to select`) and 1 on no match. Function takes no arguments; just produces the body string.
- [X] T004 [P] Implement `_notify_terminal_app_applescript` in `/Users/ykchen/Projects/ykchen/tmux-session-manager/lib/notify.sh` per contracts/applescript-payloads.md §Payload 2: returns the Terminal.app AppleScript body as a single multi-line string. Note the dialect differences: Terminal.app uses `tty of t` (not nested under `current session`), and selection uses `set frontmost of w to true` + `set selected of t to true`. Function takes no arguments; just produces the body string. Empirical verification of the Terminal.app shape is task T010; this task ships the contract-as-written.
- [X] T005 Implement `_notify_dispatch_osascript` in `/Users/ykchen/Projects/ykchen/tmux-session-manager/lib/notify.sh`: orchestrates a single osascript invocation. Takes args `<applescript_body> <target_tty> <project_name> <notification_type> <session_id>`. Captures osascript exit code and stderr to a tmpfile under `${TMPDIR:-/tmp}`. Branches on exit code: 0 → return 0 (caller skips fallback `open -b`); 1 with empty stderr → log `applescript-failed no-tty-match`, return 1; non-zero with stderr → call `_notify_classify_osascript_err` to get the mode, log `applescript-failed <mode>`, return 1. Cleans up tmpfile in all branches. Depends on T002 (uses classifier).

**Checkpoint**: Foundation ready — US1, US2, US3 can proceed.

---

## Phase 3: User Story 1 — Click lands on the exact terminal tab (Priority: P1) 🎯 MVP

**Goal**: When the click callback fires for an iTerm2- or Terminal.app-hosted session, the exact owning window+tab is selected via osascript. Falls back to existing behavior on AppleScript failure or for other terminals.

**Independent Test**: Run quickstart QS-1 (iTerm2 multi-window/multi-tab) and QS-2 (Terminal.app multi-tab). Both should land the user on the exact tab hosting the target session within 2 seconds. QS-6 verifies no regression for single-tab setups.

### Implementation for User Story 1

- [X] T006 [US1] Modify the `@CONTENTCLICKED` branch of `cmd_notify_hook` in `/Users/ykchen/Projects/ykchen/tmux-session-manager/lib/notify.sh` to query the target TTY at click time and dispatch to osascript when applicable. Per research.md §5 (click-time TTY query) and §8 (decision tree): immediately after the `case "$result" in @CONTENTCLICKED)` line, add `target_tty=$(tmux list-clients -t "$project_name" -F '#{client_tty}' 2>/dev/null | head -1)`. Then `local osa_handled=false`. If `$target_tty` is non-empty AND `$term_bundle_id` is `com.googlecode.iterm2` or `com.apple.Terminal`, look up the appropriate AppleScript body via `_notify_iterm_applescript` or `_notify_terminal_app_applescript`, call `_notify_dispatch_osascript` with body + tty + project metadata, and set `osa_handled=true` if it returned 0. After this block, the existing `open -b "$term_bundle_id"` should be guarded by `if ! $osa_handled; then open -b ... ; fi` so the redundant activation is skipped on AppleScript success (research.md §8 happy-path optimization). Depends on T003, T004, T005.
- [X] T007 [US1] Verify the existing `tms switch "$project_name" 2>&1 | tee -a ...` line and the conditional follow-up alerter on switch failure remain untouched after T006's edit — these are downstream of the dispatch and run regardless of which path (osascript or fallback) was used. Critical: feature 003's pane-title routing inside `cmd_switch` (selecting the workspace's claude-titled pane) must still apply because we still call `tms switch` post-dispatch. This is a code review task, not a code change — confirm by reading the modified function end-to-end.

**Checkpoint**: User Story 1 functional and testable. QS-1, QS-2, QS-6, QS-7 pass.

---

## Phase 4: User Story 2 — Graceful fallback on non-AppleScript terminals (Priority: P2)

**Goal**: Terminals other than iTerm2 and Terminal.app continue to work exactly as they did pre-feature, with no new errors logged and no perceptible behavior change.

**Independent Test**: Run quickstart QS-5 (Ghostty or similar). Banner click should foreground the terminal and switch tmux session — same behavior as pre-feature. No `applescript-failed` log entry.

### Implementation for User Story 2

- [X] T008 [US2] No new code. The branching in T006 already routes only `com.googlecode.iterm2` and `com.apple.Terminal` through the osascript path; everything else falls through to the existing `open -b` + `tms switch` chain (which is the pre-feature behavior). This task is verification only: run QS-5 with Ghostty (or temporarily set `__CFBundleIdentifier=com.mitchellh.ghostty` to simulate); confirm (a) no osascript invocation, (b) no `applescript-failed` log entry, (c) terminal foregrounds + tmux session switches. **VERIFIED**: simulated via `__CFBundleIdentifier=com.mitchellh.ghostty bin/tms notify-hook`, no applescript-failed log entry emitted.

**Checkpoint**: User Story 2 verified. QS-5 passes.

---

## Phase 5: User Story 3 — Detached session graceful fallback (Priority: P3)

**Goal**: When the resolved tmux session has no attached client (detached), the click handler does not attempt osascript, falls through cleanly to `open -b` + `tms switch` (which attaches the session somewhere). No window/tab spawning logic is added.

**Independent Test**: Run quickstart QS-3. Trigger a notification for a detached session, click the banner, verify the existing fallback runs and `applescript-failed no-tty-match` is logged.

### Implementation for User Story 3

- [X] T009 [US3] Verification only. The empty-`target_tty` branch in T006 already short-circuits the osascript dispatch when `tmux list-clients -t <project>` returns nothing. **VERIFIED**: fired hook with a project that has no attached client (`25-plus`, stopped session); `tmux list-clients -t 25-plus` returned empty, osascript was not invoked, no applescript-failed log entry. Fallback `open -b` ran. Confirm by code review that:
   - When `$target_tty` is empty, `_notify_dispatch_osascript` is NOT called (so no `applescript-failed` log fires for the trivially-detached case).
   - The fallback `open -b` runs.
   - The existing `tms switch` runs and exercises `cmd_switch`'s attach-on-no-client logic.
   Then run QS-3 (`tms test-hooks --project <detached-project>` after detaching) to verify behavior end-to-end.

**Checkpoint**: User Story 3 verified. QS-3 passes (with `applescript-failed no-tty-match` only when osascript was actually invoked and returned 1 — NOT when the path was skipped due to empty target_tty).

---

## Phase 6: Polish & Cross-Cutting Concerns

- [ ] T010 Empirically verify the Terminal.app AppleScript body in `/Users/ykchen/Projects/ykchen/tmux-session-manager/lib/notify.sh` (created in T004) actually works on a real Terminal.app session. Run `osascript -e "$(some-test-driver returning the body)" -- /dev/ttysXXX` against a Terminal.app instance with at least one tmux client attached. If the script needs syntax adjustments (e.g., property name differences in newer macOS Terminal versions), update T004's body and re-run. Update contracts/applescript-payloads.md §Payload 2 if any deviation from the contract-as-written. **User-driven**: requires running Terminal.app since the developer machine for this feature was iTerm2-only during research.
- [X] T011 [P] Update `/Users/ykchen/Projects/ykchen/tmux-session-manager/README.md`'s "Enabling Claude Code notifications" section: add a 2-3 sentence subsection titled "Exact tab selection (iTerm2 / Terminal.app)" explaining (a) on first click, macOS will prompt for Automation permission to control the terminal; clicking Allow makes subsequent clicks land on the exact tab; (b) failures show in `notifications.log` under `applescript-failed`; (c) other terminals continue to work as before.
- [ ] T012 Run the full quickstart QS-1..QS-9 suite from `/Users/ykchen/Projects/ykchen/tmux-session-manager/specs/004-click-to-exact-tab/quickstart.md` against a real multi-window iTerm2 setup. Mark passing scenarios in the acceptance traceability matrix. Any genuine failure re-opens the corresponding phase. Depends on T010 if Terminal.app verification reveals required script tweaks.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: T001 only. Trivial.
- **Foundational (Phase 2)**: Depends on Setup. T002 → T003/T004 (parallel) → T005. Sequential within `lib/notify.sh` for symbol ordering.
- **User Stories (Phase 3, 4, 5)**: All depend on Foundational. US1 (T006-T007) is the only one with code changes; US2/US3 are verification-only since the dispatch in T006 already encodes their behavior (other-terminal pass-through, empty-tty short-circuit).
- **Polish (Phase 6)**: T010 (Terminal.app verification) can technically run in parallel with US1 implementation if a Terminal.app environment is available; T011 (README) and T012 (full QS run) come last.

### User Story Dependencies

- **US1 (P1, MVP)**: Depends on Foundational T002-T005. Tasks T006-T007 implement the click-time dispatch and verify the post-dispatch chain.
- **US2 (P2)**: Depends on Foundational + US1's T006 (which contains the bundle-id branch that routes other terminals to the existing path).
- **US3 (P3)**: Depends on Foundational + US1's T006 (which contains the empty-target_tty short-circuit).

US1 dominates — US2 and US3 are essentially "verify the dispatch in T006 also handles these cases correctly." This is by design: spec.md FRs are tightly interrelated and a single dispatch tree handles all three stories.

### Within Each User Story

- **US1**: T006 → T007 sequential (T007 reads the post-T006 state for verification).
- **US2 / US3**: single verification task each.

### Parallel Opportunities

- **Setup**: T001 alone.
- **Foundational**: T003 and T004 parallel (different functions in same file; non-conflicting if you commit them in order). T002 → T005 sequential since T005 calls T002.
- **US1**: T006 → T007 sequential.
- **US2 / US3**: independent of each other; both are verification-only and require no new code.
- **Polish**: T010 independent of T011/T012. T011 + T012 sequential (don't run QS until README is at least drafted so you can spot-check the install instructions).

---

## Parallel Example: User Story 1 setup phase

```bash
# After Phase 1 + T002:
Task: "Implement _notify_iterm_applescript (T003)"
Task: "Implement _notify_terminal_app_applescript (T004)"

# Then:
Task: "Implement _notify_dispatch_osascript (T005)"
Task: "Modify @CONTENTCLICKED branch (T006)"
Task: "Verify post-dispatch chain (T007)"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Phase 1: trivial section header.
2. Phase 2: 4 helper functions (T002 classifier, T003 iTerm body, T004 Terminal body, T005 dispatch).
3. Phase 3: extend `@CONTENTCLICKED` branch to dispatch to osascript when applicable, fall back gracefully.
4. **STOP and VALIDATE**: Run QS-1 (iTerm2 multi-window) — confirm exact-tab works. QS-6 (single-tab regression) — confirm no slowdown. Ship as "exact-tab on iTerm2 + graceful everywhere else."

### Incremental Delivery

1. Setup + Foundational + US1 → exact-tab works on iTerm2 (MVP). Terminal.app body present but contract-shape-only.
2. Verify on Terminal.app (T010); fix body if needed. Both AppleScript-capable terminals now work.
3. Verify US2 + US3 pass-through behavior (no code changes).
4. Polish: README + full QS run.

### Single-developer notes

- Single developer can implement all 12 tasks in a single sitting; the file is small and changes are localized.
- Natural commit boundaries: end of Phase 2 (helpers ready), end of Phase 3 (US1 functional on iTerm2), end of Phase 6 (full feature).

---

## Notes

- No automated test tasks. Per plan.md Testing line, this project has no harness and adding one is out of scope.
- `[P]` markers respect both file-independence and logical ordering. Within `lib/notify.sh`, "different function" + "no symbol dependency" qualifies as parallel-capable for the purposes of dispatching agent work; if doing it sequentially in one editor session, the order is T002 → T003 → T004 → T005.
- File paths are absolute so each task is executable without ambient context.
- The script-based `.specify/scripts/bash/*` helpers do not support slash-prefixed branch names like `feat/click-to-exact-tab`; this tasks.md was written manually per the same workaround used in features 003 and 004's earlier phases.
- Terminal.app empirical verification (T010) is **mandatory before claiming US1 complete on Terminal.app** — the developer machine for the spec/plan/tasks phase ran iTerm2 only, so the Terminal.app script body in T004 reflects the documented contract but has not been runtime-validated.
