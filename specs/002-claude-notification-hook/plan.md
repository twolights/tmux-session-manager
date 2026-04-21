# Implementation Plan: Claude Code Notification Hook with Click-to-Switch

**Branch**: `002-claude-notification-hook` | **Date**: 2026-04-21 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/002-claude-notification-hook/spec.md`

## Summary

Add a Claude Code `Notification` hook that emits a clickable macOS banner identifying the originating tms project and, when clicked, switches the active tmux session to that project and selects its workspace window (window 1) where Claude Code lives. The hook is globally on by default, opt-out per project via tms YAML config, and logs emission failures to a dedicated user-state log file. Implementation is a bash-based addition: one new library module, one hook entry point, two new `tms` subcommands (`switch`, `install-hooks`), and a schema extension in `projects.yml`.

## Technical Context

**Language/Version**: Bash 4+ (POSIX-compatible where feasible), consistent with existing `lib/*.sh` modules
**Primary Dependencies**: tmux 3.2+, yq (Python-based), fzf, Claude Code CLI, macOS system frameworks; new dependencies `alerter` (clickable banner — selected during bring-up after macOS 26 broke `terminal-notifier`'s click callbacks; see research.md §1 and §7) and `jq` (`tms install-hooks` settings.json round-trip)
**Storage**:
  - Config: `~/.config/tmux-session-manager/projects.yml` (YAML, existing) — extended with optional `projects[].notifications.enabled: false` flag
  - Claude Code settings: `~/.claude/settings.json` (JSON, modified by `tms install-hooks`)
  - Log: `${XDG_STATE_HOME:-$HOME/.local/state}/tms/notifications.log` (append-only text, created by the hook on first failure)
**Testing**: Manual scenario-based verification via `quickstart.md` (the project has no existing automated test harness; adding one is out of scope for this feature). Each acceptance scenario and each Phase 1 contract is mapped to a reproducible manual check.
**Target Platform**: macOS (Darwin), tmux 3.2+, Claude Code CLI with hook support
**Project Type**: Single-repo CLI tool (bash scripts + tmux configuration)
**Performance Goals**: Hook emission adds < 100 ms at p95 to Claude Code's interaction loop (SC-005). `alerter` is invoked in a detached background subshell (it blocks until click/timeout, so the subshell may live up to 60s — the parent hook returns immediately).
**Constraints**: Hook MUST NOT block, delay, or crash Claude Code (FR-007); failures isolated via subshell + explicit exit-code swallowing; all failure paths write to the log file rather than raising. No new runtime dependencies on languages outside bash/yq stack.
**Scale/Scope**: Single-user, single-machine; realistic upper bound ~20 concurrent tms projects. SC-004's cross-talk property is project-count-independent (each banner's click callback is baked at emission time, so no runtime routing decision exists that could disambiguate wrongly), so this feature does not have meaningful scaling concerns beyond the log volume bound (< 100 events/day typical).

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

The project's `.specify/memory/constitution.md` is an unfilled template (placeholder principles, no ratified version). There are no concrete gates to evaluate. The plan nonetheless adheres to the implicit conventions documented in the repo's CLAUDE.md:

- **Bash-first**: New code is bash, matches existing `lib/*.sh` style and uses the existing `utils.sh` helpers (`die`, `warn`, `require_cmd`, `expand_path`, `config_dir`).
- **yq Python variant**: Config-schema extension uses `yq -r` consistent with `lib/config.sh`.
- **tmux target syntax**: All new tmux commands avoid `=` prefix on pane/window selectors (per CLAUDE.md note about tmux 3.4 breakage).
- **Keybinding discipline**: No new tmux keybindings are introduced; existing `@tms` session-option gating is unchanged.
- **Additive to visual bell**: Per FR-009, existing `visual-bell` / `monitor-bell` settings in `session.sh` remain untouched.

**Gate status**: PASS (no violations; nothing to justify in Complexity Tracking).

**Post-Phase 1 re-check**: PASS. Phase 1 outputs (data-model, contracts, quickstart) introduce no new architectural patterns, no additional languages, and no new dependencies beyond the notifier binary (originally `terminal-notifier`; revised to `alerter` during bring-up — see research.md §1 and §7) and `jq`. Plan remains within the existing bash + yq + tmux surface.

## Project Structure

### Documentation (this feature)

```text
specs/002-claude-notification-hook/
├── plan.md              # This file (/speckit.plan output)
├── spec.md              # Feature specification (already written)
├── research.md          # Phase 0 output — notifier tool, hook payload, log location decisions
├── data-model.md        # Phase 1 output — entities + YAML/JSON schemas
├── quickstart.md        # Phase 1 output — manual verification recipe
├── contracts/           # Phase 1 output — CLI + hook payload + log-line contracts
│   ├── tms-switch-cli.md
│   ├── tms-install-hooks-cli.md
│   ├── tms-notify-hook-stdin.md
│   └── notifications-log-format.md
├── checklists/
│   └── requirements.md  # Already written by /speckit.specify
└── tasks.md             # Created by /speckit.tasks (NOT this command)
```

### Source Code (repository root)

```text
bin/
├── tms                      # (modified) add `switch` and `install-hooks` subcommand dispatch
├── tms-switch               # (unchanged) fzf-based interactive picker, still bound to prefix+P
└── tms-notify-hook          # (new) invoked by Claude Code's Notification hook; reads JSON on stdin

lib/
├── utils.sh                 # (unchanged)
├── config.sh                # (modified) add config_get_notifications_enabled helper + schema validation
├── session.sh               # (modified) add cmd_switch (direct, non-interactive session+window switch)
├── servers.sh               # (unchanged)
└── notify.sh                # (new) project detection, notifier invocation, log writer

config/
└── projects.example.yml     # (modified) document optional `notifications.enabled: false` opt-out

README.md                    # (modified) document `tms install-hooks` + opt-out flag
CLAUDE.md                    # (auto-updated by update-agent-context.sh)
```

**Structure Decision**: Single-project layout extending the existing `bin/` + `lib/` split. New code lives alongside current modules rather than introducing subdirectories — the feature is small (one library module, one hook entry point, two CLI subcommands) and the existing layout is flat by design. Manual verification replaces a test harness because no such harness exists in the repo today; adding one is explicitly out of scope for this feature.

## Complexity Tracking

> **Fill ONLY if Constitution Check has violations that must be justified**

Not applicable — Constitution Check passed with no violations.
