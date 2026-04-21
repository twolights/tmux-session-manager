---

description: "Task list for feature 002-claude-notification-hook"
---

# Tasks: Claude Code Notification Hook with Click-to-Switch

**Input**: Design documents from `/specs/002-claude-notification-hook/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/, quickstart.md

**Tests**: Not generated. The repo has no automated test harness. `quickstart.md` is the manual verification recipe; task T024 runs the full QS-1..QS-13 suite as the acceptance gate for the feature.

**Organization**: Tasks grouped by user story so each story is independently completable and testable as an MVP increment.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies on incomplete tasks)
- **[Story]**: Which user story this task belongs to (US1, US2, US3)
- Paths are absolute

## Path Conventions

Single-repo bash CLI layout (see plan.md §Project Structure). All paths rooted at `/Users/ykchen/Projects/ykchen/tmux-session-manager/`.

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Create skeleton files so all subsequent tasks can edit them without path-not-found errors. No business logic here.

- [ ] T001 [P] Create skeleton `/Users/ykchen/Projects/ykchen/tmux-session-manager/lib/notify.sh` with `#!/usr/bin/env bash` shebang and a one-line header comment (`# notify.sh — macOS notification emission, project detection, and failure logging`). File is sourced by `bin/tms` and `bin/tms-notify-hook`; no executable bit needed.
- [ ] T002 [P] Create skeleton `/Users/ykchen/Projects/ykchen/tmux-session-manager/bin/tms-notify-hook` with `#!/usr/bin/env bash`, `set -euo pipefail`, a one-line header comment, a stub `exit 0` body, and `chmod +x`. This is the Claude Code hook entry point.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core primitives that every user story depends on: project detection, failure logging, JSON parsing, terminal-bundle resolution, and the per-project opt-out config accessor.

**⚠️ CRITICAL**: No user story work can begin until this phase is complete.

- [ ] T003 [P] Implement `notify_log_path()` in `/Users/ykchen/Projects/ykchen/tmux-session-manager/lib/notify.sh`: compute `${TMS_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/tmux-session-manager}/notifications.log`, `mkdir -p` the directory on first call (mode 0755), and print the absolute path to stdout. Per research.md §4 and contracts/notifications-log-format.md.
- [ ] T004 Implement `notify_log_failure <category> <project-or-dash> <notification_type-or-dash> <session_id-or-dash> <message>` in `/Users/ykchen/Projects/ykchen/tmux-session-manager/lib/notify.sh` per contracts/notifications-log-format.md: tab-separated fields; ISO-8601 timestamp via `date '+%Y-%m-%dT%H:%M:%S%z'`; replace any embedded `\t` or `\n` in args with single space; truncate message to 200 chars with trailing `…`; single `printf '%s\n' >> $(notify_log_path)` write for atomicity. Depends on T003 (same file, uses `notify_log_path`).
- [ ] T005 Implement `notify_parse_json_field <field-name> <payload>` in `/Users/ykchen/Projects/ykchen/tmux-session-manager/lib/notify.sh` per contracts/tms-notify-hook-stdin.md §Parse strategy and data-model.md §Parse strategy: use `jq -r ".$field // empty"` when `command -v jq` succeeds; otherwise fall back to a narrow POSIX extractor that greps `"field":"value"` from the flat payload. Return empty string on missing field (never error). Depends on T004 (same file).
- [ ] T006 Implement `notify_resolve_project_from_cwd <cwd>` in `/Users/ykchen/Projects/ykchen/tmux-session-manager/lib/notify.sh` per research.md §5a: iterate `projects[]` from the tms config via existing `config_list_projects` + `config_get_project_dir`, realpath-normalize both the input cwd and each project dir, return the first project name whose normalized dir is a prefix of the normalized cwd (match at path-boundary only — `/a/b` must not prefix-match `/a/bc`). Print project name on stdout; exit 1 if no match. Depends on T005 (same file).
- [ ] T007 Implement `notify_resolve_term_bundle()` in `/Users/ykchen/Projects/ykchen/tmux-session-manager/lib/notify.sh` per research.md §5b: print `$__CFBundleIdentifier` if set; else map `$TERM_PROGRAM` via case statement (`iTerm.app` → `com.googlecode.iterm2`, `Apple_Terminal` → `com.apple.Terminal`, `ghostty` → `com.mitchellh.ghostty`, `alacritty` → `org.alacritty`, `kitty` → `net.kovidgoyal.kitty`, `WezTerm` → `com.github.wez.wezterm`); ultimate fallback `com.apple.Terminal`. Depends on T006 (same file).
- [ ] T008 [P] Extend `_config_validate()` in `/Users/ykchen/Projects/ykchen/tmux-session-manager/lib/config.sh` per data-model.md §Project (extended): after the existing per-project validation loop body, accept an optional `notifications` block. If `yq -r ".projects[$i].notifications | type"` is not `null` and not `!!map`, `die` with `project '<name>' notifications must be a map`. If `yq -r ".projects[$i].notifications.enabled | type"` is not `null` and not `!!bool`, `die` with `project '<name>' notifications.enabled must be a bool`. Absent block remains valid (opt-in default: true).
- [ ] T009 Implement `config_get_notifications_enabled <project-name>` in `/Users/ykchen/Projects/ykchen/tmux-session-manager/lib/config.sh` per data-model.md §Per-Project Notification Setting: look up project index via `_config_project_index`; read `yq -r ".projects[$idx].notifications.enabled"`; if value is `"null"` or empty, print `true` (default); if value is `"true"` or `"false"`, print verbatim; any other value should be unreachable given T008's validation. Depends on T008 (same file).

**Checkpoint**: Foundation ready — US1, US2, US3 can now proceed.

---

## Phase 3: User Story 1 — Surfacing attention-needed events (Priority: P1) 🎯 MVP

**Goal**: When Claude Code's `Notification` hook fires inside a tms-managed project, a macOS banner appears with the tms project name as title and Claude's `message` payload as body. Respects the per-project `notifications.enabled: false` opt-out. Fails closed to an informative log entry on terminal-notifier errors, never blocks Claude Code.

**Independent Test**: Run quickstart.md QS-1 (install) and QS-2 (banner fires for running project). QS-6 validates opt-out. QS-13 validates the post-install permission probe added by T011.

### Implementation for User Story 1

- [ ] T010 [P] [US1] Implement the emission happy path in `/Users/ykchen/Projects/ykchen/tmux-session-manager/bin/tms-notify-hook` per contracts/tms-notify-hook-stdin.md §Behavior tree: source `lib/utils.sh`, `lib/config.sh`, `lib/notify.sh`; `config_load`; read stdin into `payload`; extract `cwd`, `message`, `notification_type`, `session_id` via `notify_parse_json_field`; resolve `project_name` via `notify_resolve_project_from_cwd`; check opt-out via `config_get_notifications_enabled` (exit 0 silently if false per data-model.md §Per-Project Notification Setting); invoke `terminal-notifier -title "$project_name" -message "$message"` in a detached background subshell (`( ... ) & disown 2>/dev/null || true`); on `terminal-notifier` missing in PATH call `notify_log_failure notifier-missing` etc.; wrap the whole script in a trap that converts any error into `notify_log_failure` + `exit 0` to guarantee FR-007 non-blocking. **MVP scope: no `-execute` click callback yet — T016 wires that in US2.** Leave a clearly-commented `# TODO(US2): add -execute "<click_cmd>" when cmd_switch lands` line at the exact insertion point.
- [ ] T011 [P] [US1] Implement `cmd_install_hooks` and `cmd_uninstall_hooks` in `/Users/ykchen/Projects/ykchen/tmux-session-manager/lib/notify.sh` per contracts/tms-install-hooks-cli.md: parse `--uninstall` and `--dry-run` flags; `require_cmd terminal-notifier`; `require_cmd jq`; verify `~/.claude/` exists; read `~/.claude/settings.json` (treat missing as `{}`); compute hook entry with absolute `$TMS_DIR/bin/tms-notify-hook` (resolved at invocation time) and `"timeout": 10`; locate any existing `.hooks.Notification[]` entry whose inner `.hooks[].command` ends with `bin/tms-notify-hook` and match/update/append accordingly; write atomically via `jq '...' > .tmp && mv .tmp settings.json`. After a successful install (or idempotent re-install), run the **post-install probe** per contracts/tms-install-hooks-cli.md §Post-install probe: invoke `terminal-notifier -title 'tms' -message 'Notification hook installed. You should see this banner.'` and unconditionally print the multi-line diagnostic block (banner confirmation prompt, System Settings path for terminal-notifier, absolute log file path). The probe replaces runtime permission-denied detection — it is the feature's sole mechanism for catching denied-permission setups. `--uninstall` removes matching entries; empties `.hooks.Notification` to key-absent; prints friendly message; does NOT run the probe. `--dry-run` prints a `diff -u` and exits 0 without writing or probing.
- [ ] T012 [US1] Add `install-hooks` subcommand dispatch in `/Users/ykchen/Projects/ykchen/tmux-session-manager/bin/tms`: source `lib/notify.sh` near the other `source` lines (after `servers.sh`); add `install-hooks)` case arm that calls `cmd_install_hooks "$@"`; update the `usage()` heredoc to document `tms install-hooks [--uninstall] [--dry-run]  Install or remove the Claude Code Notification hook`. Depends on T011.
- [ ] T013 [P] [US1] Document the feature in `/Users/ykchen/Projects/ykchen/tmux-session-manager/README.md` per FR-008: add a "Prerequisites" note mentioning `terminal-notifier` and `jq` as required only for the Notification feature; add an "Enabling Claude Code notifications" section covering `tms install-hooks`, the macOS permission-prompt step, the per-project opt-out (`notifications.enabled: false`), and where the log lives. Include a brief "Known limitation" paragraph: "If you run multiple windows of the same terminal emulator, clicking the banner foregrounds the app and retargets the tmux session correctly, but the tmux client may be in a non-frontmost window — cycle windows (⌘\` on macOS) to find it. Single-window users are unaffected." Link to `specs/002-claude-notification-hook/quickstart.md` for the full verification recipe.

**Checkpoint**: User Story 1 is fully functional and testable independently. QS-1, QS-2, QS-6, QS-9, QS-13 pass. Banner appears but clicking it does nothing yet (US2).

---

## Phase 4: User Story 2 — One-click switch to the originating project (Priority: P1)

**Goal**: Clicking the banner brings the terminal to the foreground, switches the active tmux session to the originating project, and selects that session's workspace window (window 1).

**Independent Test**: Run quickstart.md QS-3 (click-to-switch lands on workspace window). QS-4 validates graceful failure when the target session has been stopped. QS-5 validates multi-project disambiguation.

### Implementation for User Story 2

- [ ] T014 [P] [US2] Implement `cmd_switch <project>` in `/Users/ykchen/Projects/ykchen/tmux-session-manager/lib/session.sh` per contracts/tms-switch-cli.md: look up project via `config_get_project_dir` (die if unknown, matching existing `cmd_start` error shape); if `session_exists` is **false**, `die "session '<project>' is not running. Run 'tms start <project>' to restart it."` — **do NOT delegate to `cmd_start`** (FR-006 / Edge Case 4: stopped sessions are a loud-error path, not an auto-restart path). If session exists, detect whether any tmux client is currently attached (`tmux list-clients -t "$project" 2>/dev/null | grep -q .`) — if yes, `tmux switch-client -t "$project"`; if no and running in a TTY (`[[ -t 0 ]]`), `tmux attach-session -t "$project"`; if no and non-TTY, `die "no tmux client to retarget; cannot switch from this context."`. After the switch/attach succeeds, run `tmux select-window -t "${project}:workspace"` to enforce the workspace-window landing per FR-004. Do NOT use `=` prefix with target strings (CLAUDE.md convention).
- [ ] T015 [US2] Add `switch` subcommand dispatch in `/Users/ykchen/Projects/ykchen/tmux-session-manager/bin/tms`: add `switch)` case arm alongside `start`/`stop`/`list` that validates a project name argument (same `[[ -z "${1:-}" ]] && die` pattern as existing subcommands), calls `config_load`, then `cmd_switch "$1"`. Update the `usage()` heredoc: add `  tms switch <project>    Switch the active tmux session to the project (non-interactive)`. Depends on T014.
- [ ] T016 [US2] Wire the click-callback into `/Users/ykchen/Projects/ykchen/tmux-session-manager/bin/tms-notify-hook` by replacing the T010 `# TODO(US2)` marker: compute `term_bundle_id` via `notify_resolve_term_bundle`; compute `tms_abs_path` as `$TMS_DIR/bin/tms` (already resolved at top of script); build `click_cmd` per data-model.md §Click Action Payload with shape `open -b '<bundle>' ; '<tms_abs_path>' switch '<project_name>' 2>&1 | tee -a '<log_path>' ; [ "${PIPESTATUS[0]:-0}" -ne 0 ] && terminal-notifier -title 'Claude Code — <project_name>' -message "Session not running. Run 'tms start <project_name>' to restart it."` — single-quote each substituted value with `'\''` escape for embedded apostrophes. The conditional follow-up `terminal-notifier` is what makes FR-006 "user-visible" when `tms switch` fails (e.g., stopped session); without it, stderr is swallowed by the Notification Center subshell. Pass the whole thing as `-execute "$click_cmd"` to the primary terminal-notifier invocation. Depends on T014.

**Checkpoint**: User Stories 1 AND 2 both work independently. QS-3, QS-4, QS-5 pass. MVP-plus-click is now shippable.

---

## Phase 5: User Story 3 — Graceful behavior outside tms-managed contexts (Priority: P3)

**Goal**: When Claude Code runs outside a tms-managed project, the hook degrades to either a plain notification (no click-to-switch) or clean skip, always exiting 0, and logs a diagnostic entry so the user can tell why no clickable banner appeared.

**Independent Test**: Run quickstart.md QS-7 (non-tms directory → no-project-match log), QS-11 (missing cwd → no-cwd log), and QS-10 (parse-error path). (QS-13, the install-time permission probe, was previously listed here during planning but was re-homed under US1 after the U1 remediation removed runtime permission-denied handling — it now validates T011's install probe, not US3's graceful-degradation scope.)

### Implementation for User Story 3

- [ ] T017 [US3] Add the no-cwd branch in `/Users/ykchen/Projects/ykchen/tmux-session-manager/bin/tms-notify-hook` per contracts/tms-notify-hook-stdin.md §Behavior tree: when `notify_parse_json_field cwd "$payload"` returns empty, emit a plain notification `terminal-notifier -title "Claude Code" -message "$message"` (no `-execute`), call `notify_log_failure no-cwd - "$notification_type" "$session_id" "$message"`, `exit 0`. Must be inserted before the project resolution step so it short-circuits cleanly.
- [ ] T018 [US3] Add the no-project-match branch in `/Users/ykchen/Projects/ykchen/tmux-session-manager/bin/tms-notify-hook`: when `notify_resolve_project_from_cwd "$cwd"` returns non-zero, emit a plain notification `terminal-notifier -title "Claude Code" -message "$message"` (no `-execute`), call `notify_log_failure no-project-match - "$notification_type" "$session_id" "cwd=$cwd"`, `exit 0`. Depends on T017 (adjacent logic in the same file).
- [ ] T019 [US3] Add the parse-error branch in `/Users/ykchen/Projects/ykchen/tmux-session-manager/bin/tms-notify-hook`: when stdin payload is empty OR when required fields `hook_event_name` is missing/empty OR `hook_event_name != "Notification"`, call `notify_log_failure parse-error - - - "$(printf '%.512s' "$payload")"`, `exit 0`. No notification emitted. Must be the first check after stdin read. Depends on T018 (same file).
- [ ] T020 [US3] Add the empty-message guard in `/Users/ykchen/Projects/ykchen/tmux-session-manager/bin/tms-notify-hook`: when `message` field is empty, substitute the body `Claude Code needs attention.` for the banner, call `notify_log_failure empty-message "$project_name" "$notification_type" "$session_id" "-"`, continue with normal emission (do NOT exit). Depends on T019 (same file).

*(T021 removed. The prior permission-denied deduplication task was deleted after analysis finding U1: terminal-notifier does not expose a reliable permission-denied exit signal on current macOS, so runtime detection is not possible. The denied-permission case is caught instead by T011's post-install probe. All terminal-notifier non-zero exits at runtime are now logged as `notifier-failed` without deduplication; real-world volume is bounded by Claude Code's notification cadence.)*

**Checkpoint**: All three user stories are independently functional. QS-7, QS-10, QS-11 pass.

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Documentation, config example, and end-to-end acceptance.

- [ ] T022 [P] Update `/Users/ykchen/Projects/ykchen/tmux-session-manager/config/projects.example.yml` per data-model.md §Project (extended): add a comment block under the existing "Optional fields" header documenting `notifications.enabled` (bool, default true, opt-out flag); add one example project showing `notifications: { enabled: false }` so the schema is discoverable. Do NOT change existing example projects — append only.
- [ ] T023 [P] Verify `/Users/ykchen/Projects/ykchen/tmux-session-manager/CLAUDE.md` reads correctly after the `update-agent-context.sh` auto-update: the "Recent Changes" section should include a bullet for feature 002. If the auto-generated line has a parsing typo (see the post-plan "mux" → "tmux" fix), correct it. No restructuring of this file beyond that.
- [ ] T024 Run the full quickstart.md verification suite (QS-1 through QS-13) from a clean state on `002-claude-notification-hook`. Any genuine failure re-opens the corresponding phase before this task can be marked done. Depends on all previous tasks.
- [ ] T025 Measure hook overhead per SC-005: `time echo '{"hook_event_name":"Notification","cwd":"<tms-managed-dir>","message":"perf test","notification_type":"idle_prompt"}' | /Users/ykchen/Projects/ykchen/tmux-session-manager/bin/tms-notify-hook`, repeated 20 times, record real-time p95 in the quickstart Acceptance Traceability Matrix SC-005 row. If p95 exceeds 100 ms, inspect the detached subshell pattern — the intended behavior is the script returns before terminal-notifier's round-trip. Depends on T024.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies. T001 and T002 can run in parallel.
- **Foundational (Phase 2)**: Depends on Setup. BLOCKS all user stories. Within this phase, `lib/notify.sh` work (T003→T004→T005→T006→T007) and `lib/config.sh` work (T008→T009) are independent streams that can run in parallel.
- **User Stories (Phase 3+)**: All depend on Foundational complete.
- **Polish (Phase 6)**: Depends on all desired user stories being complete.

### User Story Dependencies

- **US1 (P1)**: Depends only on Foundational. Fully independently testable once complete (banner fires, opt-out works, click is a no-op).
- **US2 (P1)**: Depends on Foundational. Shares the `bin/tms-notify-hook` file with US1, so T016 must run after T010. But T014 and T015 (session.sh, tms dispatch) are independent of US1 and could technically run in parallel with US1 tasks.
- **US3 (P3)**: Depends on Foundational. Shares `bin/tms-notify-hook` with US1 (T017-T020 add branches to what T010 established), so these must run after T010. No tasks outside `bin/tms-notify-hook` in this phase after the U1 remediation removed T021.

### Within Each User Story

- Models / shared primitives are in Foundational, not per-story.
- Within US2: T014 (cmd_switch) blocks T015 (dispatch) and T016 (click-cmd wiring).
- Within US3: T017 → T018 → T019 → T020 are sequential edits to the same file.

### Parallel Opportunities

- **Setup**: T001, T002 in parallel.
- **Foundational**: two streams run in parallel — `{T003→T004→T005→T006→T007}` on `lib/notify.sh` and `{T008→T009}` on `lib/config.sh`.
- **US1**: T010, T011, T013 run in parallel (different files). T012 queues after T011.
- **US2**: T014 runs. T015 queues after T014. T016 queues after T014 (and also after T010 for the `bin/tms-notify-hook` file).
- **US3**: T017, T018, T019, T020 sequential on the same file. No parallelism available inside this phase.
- **Polish**: T022, T023 parallel; T024, T025 sequential at the end.

---

## Parallel Example: User Story 1

```bash
# After Foundational checkpoint, launch in parallel:
Task: "Implement emission happy path in bin/tms-notify-hook (T010)"
Task: "Implement cmd_install_hooks in lib/notify.sh (T011)"
Task: "Document tms install-hooks in README.md (T013)"

# Then T012 runs after T011 completes:
Task: "Add install-hooks dispatch in bin/tms (T012)"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Phase 1: Setup — two trivial skeleton files.
2. Phase 2: Foundational — one focused session (notify.sh primitives + config accessor).
3. Phase 3: User Story 1 — `tms install-hooks` wires Claude Code; banners fire with project name + Claude's message; opt-out works.
4. **STOP and VALIDATE**: Run QS-1, QS-2, QS-6, QS-9. Ship as "notifications land but aren't clickable yet."

### Incremental Delivery

1. Setup + Foundational → primitives ready.
2. Add US1 → banners appear → ship (MVP).
3. Add US2 → banners click through to the right workspace window → ship.
4. Add US3 → non-tms contexts log informatively → ship.
5. Polish → docs, example config, full QS run, perf measurement.

### Parallel Team Strategy (single-developer notes)

- This feature is small enough for one developer; parallelism in the task graph is mostly about pipelining file-independent edits within a single session rather than splitting across developers.
- The natural cut points for commits are: end of Phase 2, end of Phase 3 (MVP tag), end of Phase 4, end of Phase 5, end of Phase 6.

---

## Notes

- No automated test tasks. Per plan.md Testing line, this project has no harness and adding one is out of scope for feature 002. `quickstart.md` is the gate.
- `[P]` markers respect both file-independence and logical ordering — if task B needs a symbol defined by task A, B is not [P] even if they edit different files.
- File paths are absolute so each task is executable without ambient context.
- FR-011 (per-project opt-out) is implemented across T008, T009 (config plumbing), T010 (check in hook), and T022 (documentation). It deliberately does not get its own user-story phase because it is a control knob layered on US1, not a standalone user journey.
- SC-005 (< 100 ms p95 hook overhead) is verified in T025 via measurement, not by code; the architectural guarantor is the detached background subshell in T010.
