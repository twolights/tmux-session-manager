# Research: Tmux Session Manager

**Date**: 2026-04-06
**Feature**: 001-tmux-session-manager

## Technology Decisions

### Decision 1: Implementation Language — Shell (Bash)

- **Decision**: Pure Bash scripts + tmux configuration
- **Rationale**: tmux is controlled via CLI commands and config files. Shell scripts are the natural fit — no compilation, no runtime dependencies, direct access to tmux commands. The user already has bash/zsh.
- **Alternatives considered**:
  - Python script: Adds a runtime dependency for no benefit; tmux interaction is all CLI calls anyway
  - Go/Rust compiled binary: Overkill for orchestrating tmux commands; harder to debug and modify
  - tmux plugin (TPM): Locks into plugin manager ecosystem; shell scripts are more portable and transparent

### Decision 2: Configuration Format — YAML

- **Decision**: YAML configuration file at `~/.config/tmux-session-manager/projects.yml`
- **Rationale**: YAML is human-readable, supports nested structures (projects → servers), and is easy to edit by hand. Parsing in bash can be done with simple awk/sed for the flat structure needed, or `yq` if available.
- **Alternatives considered**:
  - TOML: Good readability but less common tooling in shell environments
  - JSON: Harder to hand-edit (strict syntax, no comments)
  - Plain shell variables/sourced config: Simple but doesn't scale well for nested project/server definitions
  - tmux conf directives: Not designed for structured project data

### Decision 3: Server Popup Implementation — tmux display-popup with Persistent Panes

- **Decision**: Use tmux `display-popup` targeting a hidden window/pane where the server process runs persistently
- **Rationale**: `display-popup` alone is ephemeral (process dies when popup closes). Instead, run servers in dedicated panes within a hidden window of the session, and use `display-popup` to attach to that pane. This gives persistence + toggle behavior.
- **Alternatives considered**:
  - Pure `display-popup` with `-E`: Process lifecycle tied to popup visibility — closing kills the server
  - Separate tmux session per server: Works but adds session clutter and complicates the session chooser
  - Background processes (not in tmux): Loses the ability to view output interactively

### Decision 4: Project Launcher — Shell Script Entry Point

- **Decision**: A single `tms` (tmux-session) command as the main entry point
- **Rationale**: Simple CLI command that can be aliased or put on PATH. Subcommands: `tms start <project>`, `tms list`, `tms stop <project>`. Key bindings in tmux.conf call the same scripts.
- **Alternatives considered**:
  - Multiple separate scripts: Harder to discover and maintain
  - tmux.conf-only approach: Can't do config parsing or validation in tmux.conf alone

### Decision 5: Pane Layout — Vertical Split (Left: Neovim, Right: Claude Code)

- **Decision**: Vertical split with neovim on the left (60% width) and Claude Code on the right (40% width)
- **Rationale**: Neovim benefits from more horizontal space for code. Claude Code's chat interface works well in a narrower pane. Vertical split is standard for editor + assistant workflows.
- **Alternatives considered**:
  - Horizontal split: Wastes horizontal space for both panes; less natural for code editing
  - Equal 50/50 split: Doesn't optimize for the different needs of editor vs chat
