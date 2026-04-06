# Tasks: Tmux Session Manager

**Input**: Design documents from `/specs/001-tmux-session-manager/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/cli.md

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

---

## Phase 1: Setup

**Purpose**: Create project directory structure and shared utilities

- [x] T001 Create directory structure: `bin/`, `lib/`, `tmux/`, `config/`
- [x] T002 [P] Create shared utilities (color output, error handling, path helpers) in `lib/utils.sh`
- [x] T003 [P] Create example configuration file in `config/projects.example.yml` with sample project entries per data-model.md schema

---

## Phase 2: Foundational (Config Parsing)

**Purpose**: Configuration loading and validation — blocks all user stories

**CRITICAL**: No user story work can begin until this phase is complete

- [x] T004 Implement YAML config parser using `yq` in `lib/config.sh` — functions: `config_load`, `config_get_project`, `config_list_projects`, `config_get_servers`
- [x] T005 Implement config validation in `lib/config.sh` — check required fields (name, dir), unique project names, print errors to stderr per CLI contract
- [x] T006 Create `bin/tms` entry point script — argument parsing for subcommands (`start`, `stop`, `list`), source all `lib/*.sh` files, validate config on startup

**Checkpoint**: `tms list` can load and validate config (shows project names even if sessions aren't managed yet)

---

## Phase 3: User Story 1 — Start a Project Workspace (Priority: P1) MVP

**Goal**: Launch a tmux session with neovim (left, 60%) + Claude Code (right, 40%) for a configured project

**Independent Test**: Run `tms start <project>` and verify tmux session has two panes with correct programs in the project directory. Run again and verify it reattaches instead of creating a duplicate.

### Implementation for User Story 1

- [x] T007 [US1] Implement `session_create` in `lib/session.sh` — create named tmux session, set working directory, split into two panes (vertical, 60/40), launch neovim in left pane and Claude Code in right pane
- [x] T008 [US1] Implement `session_exists` in `lib/session.sh` — check if tmux session with given name already exists
- [x] T009 [US1] Implement `session_attach` in `lib/session.sh` — attach to existing session (use `switch-client` if already inside tmux, `attach-session` otherwise)
- [x] T010 [US1] Implement `tms start` subcommand in `bin/tms` — look up project in config, validate directory exists, call `session_exists` → `session_attach` or `session_create`
- [x] T011 [US1] Handle error cases in `tms start`: project not found (exit 1), directory missing (exit 1), per CLI contract error messages

**Checkpoint**: `tms start <project>` creates a working two-pane session. `tms start` again reattaches. Neovim is suspendable with ctrl-z.

---

## Phase 4: User Story 2 — Switch Between Projects (Priority: P1)

**Goal**: Key binding to switch between active project sessions using tmux's built-in session chooser

**Independent Test**: Launch two projects with `tms start`, press `prefix + P`, verify session chooser appears with both sessions, select one to switch.

### Implementation for User Story 2

- [x] T012 [US2] Create tmux key bindings file `tmux/bindings.conf` with `prefix + P` bound to `choose-tree -s` (session chooser)
- [x] T013 [US2] Add installation instructions to `tmux/bindings.conf` as comments — how to source-file in user's tmux.conf

**Checkpoint**: With `bindings.conf` sourced, `prefix + P` opens the session chooser showing all active project sessions.

---

## Phase 5: User Story 3 — Manage Server Processes in Popup Windows (Priority: P2)

**Goal**: Start project servers in hidden tmux panes, toggle visibility via popup windows

**Independent Test**: Configure a project with server commands, run `tms start`, press `prefix + S` to see server output in a popup, dismiss and verify main workspace is undisturbed.

### Implementation for User Story 3

- [x] T014 [US3] Implement `servers_start` in `lib/servers.sh` — for each server in project config, create a hidden window in the session and run the server command in a pane within it
- [x] T015 [US3] Implement `servers_popup_toggle` in `lib/servers.sh` — use `display-popup` to attach to the hidden server window/pane, showing server output; dismiss hides it
- [x] T016 [US3] Handle multiple servers in `lib/servers.sh` — each server gets its own pane in the hidden window, popup cycles through or shows a selection
- [x] T017 [US3] Integrate server startup into `session_create` in `lib/session.sh` — call `servers_start` after pane setup if project has servers configured
- [x] T018 [US3] Add `prefix + S` key binding in `tmux/bindings.conf` to call `servers_popup_toggle` for the current session

**Checkpoint**: Servers run in the background, popup toggle shows/hides server output, main panes remain undisturbed.

---

## Phase 6: User Story 4 — Configure Project List (Priority: P2)

**Goal**: Well-documented configuration format with clear validation errors

**Independent Test**: Create a config file with valid and invalid entries, run `tms list` or `tms start` and verify correct parsing and clear error messages.

### Implementation for User Story 4

- [x] T019 [US4] Add comprehensive comments and documentation to `config/projects.example.yml` — all fields, optional vs required, server examples
- [x] T020 [US4] Enhance config validation in `lib/config.sh` — check for empty name, empty dir, duplicate server names within a project, provide line-specific error context

**Checkpoint**: Example config is self-documenting. Validation catches all malformed entries with actionable error messages.

---

## Phase 7: User Story 5 — View and Navigate Project List (Priority: P3)

**Goal**: `tms list` shows all projects with running/stopped status in a formatted table

**Independent Test**: Configure 3+ projects, start some, run `tms list`, verify all projects shown with correct status and directory paths.

### Implementation for User Story 5

- [x] T021 [US5] Implement `tms list` subcommand in `bin/tms` — iterate all projects from config, check session existence, format output with aligned columns
- [x] T022 [US5] Add color output to `tms list` — green/bold for running, dim for stopped (respecting terminal color support)
- [x] T023 [US5] Implement `tms stop` subcommand in `bin/tms` — kill tmux session by name, handle "not running" gracefully per CLI contract

**Checkpoint**: `tms list` shows a clean table of all projects with accurate status. `tms stop` cleanly kills sessions.

---

## Phase 8: Polish & Cross-Cutting Concerns

**Purpose**: Final improvements across all stories

- [x] T024 [P] Add a README.md with installation, configuration, and usage instructions
- [x] T025 [P] Add `tms` help output (`tms --help`, `tms help`) showing all subcommands and usage
- [x] T026 Validate quickstart.md workflow end-to-end — follow all steps and verify they work
- [x] T027 [P] Add tmux version check to `bin/tms` — warn if tmux < 3.2 (popup support required)

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — can start immediately
- **Foundational (Phase 2)**: Depends on Setup — BLOCKS all user stories
- **US1 (Phase 3)**: Depends on Foundational — core session management
- **US2 (Phase 4)**: Depends on US1 (needs sessions to exist to switch between)
- **US3 (Phase 5)**: Depends on US1 (servers attach to sessions created by US1)
- **US4 (Phase 6)**: Depends on Foundational (enhances config already built)
- **US5 (Phase 7)**: Depends on Foundational and US1 (list needs session state)
- **Polish (Phase 8)**: Depends on all desired user stories being complete

### User Story Dependencies

- **US1 (P1)**: After Foundational — no story dependencies. **This is the MVP.**
- **US2 (P1)**: After US1 — needs active sessions to switch between
- **US3 (P2)**: After US1 — servers are part of session creation
- **US4 (P2)**: After Foundational — can run in parallel with US1
- **US5 (P3)**: After Foundational + US1 — needs session existence checks

### Parallel Opportunities

- T002 and T003 can run in parallel (different files)
- US4 (config docs/validation) can run in parallel with US1 (session management)
- T024, T025, T027 in Polish phase can all run in parallel

---

## Parallel Example: Phase 1 Setup

```bash
# These tasks write to different files — run in parallel:
Task T002: "Create shared utilities in lib/utils.sh"
Task T003: "Create example config in config/projects.example.yml"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup
2. Complete Phase 2: Foundational (config parsing)
3. Complete Phase 3: User Story 1 (workspace launch)
4. **STOP and VALIDATE**: `tms start <project>` creates a working neovim + Claude Code session
5. Usable as a personal tool at this point

### Incremental Delivery

1. Setup + Foundational → Config loads and validates
2. Add US1 → `tms start` works → **MVP!**
3. Add US2 → `prefix + P` switches between projects
4. Add US3 → Server popups work
5. Add US4 → Config is well-documented with better validation
6. Add US5 → `tms list` and `tms stop` work
7. Polish → README, help text, version checks

---

## Notes

- [P] tasks = different files, no dependencies
- [Story] label maps task to specific user story for traceability
- Each user story should be independently completable and testable
- Commit after each task or logical group
- Stop at any checkpoint to validate story independently
