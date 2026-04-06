# claude-code-tmux-manager Development Guidelines

Auto-generated from all feature plans. Last updated: 2026-04-06

## Active Technologies

- Bash (POSIX-compatible where possible, bash 4+ for associative arrays) + tmux 3.2+, neovim, Claude Code CLI, yq (Python-based), fzf (001-tmux-session-manager)

## Project Structure

```text
bin/          # CLI entry points (tms, tms-switch)
lib/          # Shell library modules (config, session, servers, utils)
tmux/         # tmux bindings (auto-loaded, not sourced from .tmux.conf)
config/       # Example project configuration
specs/        # Feature specifications
```

## Commands

```bash
tms start <project>    # Launch or attach to a project workspace
tms stop <project>     # Stop a project session
tms list               # List all projects and their status
tms help               # Show usage
```

## Code Style

Bash (POSIX-compatible where possible, bash 4+ for associative arrays): Follow standard conventions

## Notes

- yq: uses Python-based yq (pip install yq), not mikefarah/yq. Use `yq -r` for raw string output.
- tmux targets: do not use `=` prefix with pane/window selectors (`:`, `.`) — breaks in tmux 3.4.
- Keybindings are auto-loaded by `tms start` and guarded with `@tms` session option.

## Recent Changes

- Auto-loaded keybindings with fzf session switcher (no .tmux.conf needed)
- Window layout: servers at window 0, workspace at window 1
- Claude Code launches with --continue to resume last session
- Visual bell notifications when Claude Code needs attention

<!-- MANUAL ADDITIONS START -->
<!-- MANUAL ADDITIONS END -->
