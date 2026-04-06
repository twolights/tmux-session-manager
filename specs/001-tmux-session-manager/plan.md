# Implementation Plan: Tmux Session Manager

**Branch**: `001-tmux-session-manager` | **Date**: 2026-04-06 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/001-tmux-session-manager/spec.md`

## Summary

Build a CLI tool (`tms`) and tmux key bindings for managing multiple Claude Code + neovim project workspaces. Each project gets a tmux session with a fixed two-pane layout (neovim left, Claude Code right) and optional server processes running in toggleable popup windows. Implemented as pure Bash scripts with YAML configuration.

## Technical Context

**Language/Version**: Bash (POSIX-compatible where possible, bash 4+ for associative arrays)
**Primary Dependencies**: tmux 3.2+, neovim, Claude Code CLI, yq (YAML parser)
**Storage**: YAML config file at `~/.config/tmux-session-manager/projects.yml`
**Testing**: Manual integration tests (shell script verifying tmux session state)
**Target Platform**: macOS, Linux (any system with tmux)
**Project Type**: CLI tool (shell scripts + tmux configuration)
**Performance Goals**: Session launch < 5s, switching < 2s, popup toggle < 1s
**Constraints**: No external runtime dependencies beyond tmux, yq, neovim, Claude Code
**Scale/Scope**: Personal developer tool; ~5-20 projects configured

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

Constitution is a blank template — no project-specific gates defined. No violations to evaluate.

**Pre-Phase 0**: PASS (no gates)
**Post-Phase 1**: PASS (no gates)

## Project Structure

### Documentation (this feature)

```text
specs/001-tmux-session-manager/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/
│   └── cli.md           # CLI contract
└── tasks.md             # Phase 2 output (created by /speckit.tasks)
```

### Source Code (repository root)

```text
bin/
└── tms                  # Main entry point script

lib/
├── config.sh            # YAML config parsing and validation
├── session.sh           # tmux session creation and management
├── servers.sh           # Server process management (hidden windows, popups)
└── utils.sh             # Shared utilities (colors, error handling)

tmux/
└── bindings.conf        # Key binding definitions (source-file'd by user)

config/
└── projects.example.yml # Example configuration file
```

**Structure Decision**: Flat single-project layout. `bin/` for the entry point, `lib/` for modular shell functions sourced by `tms`, `tmux/` for tmux config fragments, `config/` for example files.

## Complexity Tracking

No constitution violations to justify.
