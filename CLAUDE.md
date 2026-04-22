# claude-code-tmux-manager Development Guidelines

Auto-generated from all feature plans. Last updated: 2026-04-22

## Active Technologies
- Bash 4+ (POSIX-compatible where feasible), consistent with existing `lib/*.sh` modules + tmux 3.2+, yq (Python-based), fzf, Claude Code CLI, macOS system frameworks; `alerter` + `jq` from feature 002; AppleScript via `osascript` (macOS built-in, no new install dep) — invoked only on iTerm2 and Terminal.app to select the exact terminal window/tab hosting the target tmux session (004-click-to-exact-tab)

- Bash 4+ (POSIX-compatible where feasible), consistent with existing `lib/*.sh` modules + tmux 3.2+, yq (Python-based), fzf, Claude Code CLI, macOS system frameworks; `alerter` (clickable banner — chosen after macOS 26 made `terminal-notifier`'s click callbacks non-functional, see specs/002-.../research.md §7) and `jq` (settings.json round-trip) from feature 002; no new runtime deps added in feature 003 (003-tms-install-bootstrap)

- Bash 4+ (POSIX-compatible where feasible), consistent with existing `lib/*.sh` modules + tmux 3.2+, yq (Python-based), fzf, Claude Code CLI, macOS system frameworks; new dependencies `alerter` (clickable banner — chosen after macOS 26 made `terminal-notifier`'s click callbacks non-functional, see specs/002-.../research.md §7) and `jq` (settings.json round-trip) (002-claude-notification-hook)

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
tms switch <project>   # Switch active tmux session to the project (fast path)
tms list               # List all projects and their status
tms install            # Bootstrap install: symlink bin/tms, copy example config,
                       # print OS-aware dependency hints (macOS/Linux/other)
tms install-hooks      # Register Claude Code Notification hook (macOS only)
tms notify-hook        # (subcommand used by Claude Code; not typed by users)
tms help               # Show usage
```

## Code Style

Bash (POSIX-compatible where possible, bash 4+ for associative arrays): Follow standard conventions

## Notes

- yq: uses Python-based yq (pip install yq), not mikefarah/yq. Use `yq -r` for raw string output.
- tmux targets: do not use `=` prefix with pane/window selectors (`:`, `.`) — breaks in tmux 3.4.
- Keybindings are auto-loaded by `tms start` and guarded with `@tms` session option.

## Recent Changes
- 004-click-to-exact-tab: Extended the notification click callback to use AppleScript (osascript) on iTerm2 and Terminal.app so clicking a banner selects the exact window+tab hosting the target tmux session (matched by tty). Fallback to existing `open -b` + `tms switch` behavior on other terminals or if AppleScript fails. New `applescript-failed` log category for diagnostic breadcrumb.

- 003-tms-install-bootstrap: Added `tms install` subcommand (symlink, config bootstrap, OS-aware dep hints for macOS/Linux/generic), folded `bin/tms-notify-hook` into `tms notify-hook` subcommand (single-binary footprint), added FR-014 migration for existing `~/.claude/settings.json` entries from feature 002.

- 002-claude-notification-hook: Added clickable macOS notifications via `alerter` (after bring-up testing on macOS 26.4 showed `terminal-notifier`'s `-execute` click callbacks no longer dispatch on recent macOS — `alerter` blocks until click and prints `@CONTENTCLICKED` to stdout, sidestepping the broken callback path); new dependencies `alerter` + `jq`

- Auto-loaded keybindings with fzf session switcher (no .tmux.conf needed)
- Window layout: servers at window 0, workspace at window 1

<!-- MANUAL ADDITIONS START -->
<!-- MANUAL ADDITIONS END -->
