# tmux-session-manager (tms)

A CLI tool for managing tmux-based development workspaces, designed for developers using neovim and Claude Code together. Launch a fully configured workspace with editor + AI assistant in a single command.

## What it does

Each project gets a tmux session with:
- **Two-pane layout**: neovim (left, 60%) + Claude Code (right, 40%)
- **Background servers**: dev servers, databases, watchers in a dedicated window
- **Quick switching**: fzf-powered popup to jump between projects
- **Attention notifications**: visual bell when Claude Code needs input

## Prerequisites

- tmux 3.2+ (for popup window support)
- neovim
- [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code)
- [yq](https://kislyuk.github.io/yq/) (Python-based YAML/jq wrapper: `pip install yq`)
- [fzf](https://github.com/junegunn/fzf) (fuzzy finder for session switching)

**For Claude Code notification banners** (optional — see [Enabling Claude Code notifications](#enabling-claude-code-notifications)):
- [alerter](https://github.com/vjeantet/alerter): `brew install alerter`
- [jq](https://jqlang.github.io/jq/): `brew install jq`

## Installation

```bash
# 1. Clone the repo
git clone https://github.com/your-user/claude-code-tmux-manager.git
cd claude-code-tmux-manager

# 2. Bootstrap everything with one command
./bin/tms install

# 3. Edit your projects (see Configuration below)
$EDITOR ~/.config/tmux-session-manager/projects.yml
```

`tms install` does three things:

1. Symlinks `bin/tms` into `~/.local/bin/` (override with `--prefix=<dir>`).
2. Creates `~/.config/tmux-session-manager/projects.yml` from the bundled example *if* you don't already have one — never overwrites existing config.
3. Detects your OS and prints install commands for any missing dependencies:
   - **macOS**: `brew install tmux fzf` etc.
   - **Linux**: auto-detects apt/dnf/pacman/zypper/apk and prints the matching command (e.g. `sudo apt install tmux`).
   - Other: generic "install via your package manager" hints.

`tms install` is idempotent — run it again after moving the repo (it updates the symlink in place) or to re-check your dependency list.

```bash
./bin/tms install --dry-run      # preview without writing anything
./bin/tms install --uninstall    # remove the symlink (preserves your projects.yml)
./bin/tms install --prefix=~/bin # install to a different prefix
```

> **Note on Python yq**: tms uses the Python-based `yq` (kislyuk), not the Go-based `mikefarah/yq` that most distros ship as `yq`. `tms install` always recommends `pip3 install yq` regardless of platform for this reason.

Key bindings are loaded automatically when you run `tms start` — no `.tmux.conf` modification needed. Bindings only activate in tms-managed sessions.

## Usage

### CLI commands

```bash
tms start <project>    # Launch or attach to a project workspace
tms stop <project>     # Stop a project session
tms list               # Show all projects with status
tms switch <project>   # Switch the active tmux session to the project (non-interactive)
tms install            # Bootstrap install (symlink, config, dep hints) — see "Installation"
tms install-hooks      # Install the Claude Code Notification hook (see below)
tms help               # Show usage
```

### Tmux key bindings

These bindings are auto-loaded and only active in tms sessions:

| Binding      | Action                                          |
|--------------|--------------------------------------------------|
| `prefix + P` | Switch between tms projects (fzf popup)          |
| `prefix + S` | Toggle between workspace and server logs window  |
| `ctrl-z`     | Suspend neovim to drop to shell                  |
| `fg`         | Resume neovim                                    |

### Session layout

```
Window 0: _servers (background processes, if configured)
Window 1: workspace
  ┌──────────────────────┬───────────────────┐
  │                      │                   │
  │     neovim (60%)     │  Claude Code (40%)│
  │                      │                   │
  └──────────────────────┴───────────────────┘
```

### Example workflow

```bash
# Start working on a project
$ tms start my-webapp
# -> neovim + Claude Code are ready in a split layout
# -> Claude Code resumes your last session (--continue)

# Inside tmux, switch to another project
# prefix + P -> fzf popup with tms sessions only

# View server output (dev server, database, etc.)
# prefix + S -> switches to _servers window
# prefix + S -> switches back to workspace

# Done for the day
$ tms stop my-webapp
```

## Configuration

Edit `~/.config/tmux-session-manager/projects.yml`:

```yaml
projects:
  - name: my-webapp
    dir: ~/Projects/my-webapp
    servers:
      - name: dev-server
        cmd: npm run dev
      - name: db
        cmd: docker compose up postgres

  - name: api-service
    dir: ~/Projects/api-service
    servers:
      - name: api
        cmd: cargo run --release

  - name: dotfiles
    dir: ~/dotfiles
    # No servers - just neovim + Claude Code
```

### Project fields

| Field | Required | Description |
|-------|----------|-------------|
| `name` | Yes | Unique identifier, used as tmux session name (no dots or colons) |
| `dir` | Yes | Project directory path (`~` is expanded) |
| `servers` | No | List of background processes |

### Server fields

| Field | Required | Description |
|-------|----------|-------------|
| `name` | Yes | Display name shown in popup title |
| `cmd` | Yes | Shell command to run |
| `dir` | No | Working directory override (defaults to project dir) |

The config directory can be overridden with the `TMS_CONFIG_DIR` environment variable.

## Enabling Claude Code notifications

tms can show clickable macOS notification banners when Claude Code needs your attention, and clicking a banner switches your tmux session to the originating project.

### Setup

```bash
# Install dependencies (one-time)
brew install alerter jq

# Register the hook with Claude Code
tms install-hooks
```

`tms install-hooks` writes the hook entry to `~/.claude/settings.json` and fires a test banner to confirm macOS notification permissions are granted. If macOS prompts you to allow notifications for **Terminal**, click **Allow** (alerter delivers under Terminal's bundle for macOS 26+ compatibility — see [research notes](specs/002-claude-notification-hook/research.md#6-macos-26-compatibility-sender-bundle-override)). If you miss the prompt or the banner doesn't appear, open **System Settings → Notifications → Terminal** and enable notifications there.

Re-running `tms install-hooks` is idempotent. To remove the hook: `tms install-hooks --uninstall`.

#### Upgrading from an earlier install

Previously, the Notification hook was registered as a separate `bin/tms-notify-hook` binary. It's now a subcommand on the main `tms` binary (`tms notify-hook`). When you re-run `tms install-hooks` after pulling this change, it transparently rewrites any stale entry in `~/.claude/settings.json` and prints `Migrated tms-notify-hook entry to tms notify-hook.` once. After that, you can remove any manual `~/.local/bin/tms-notify-hook` symlink you may have created — it's no longer needed (the repo's `bin/tms-notify-hook` has been removed).

### Per-project opt-out

To disable banners for a specific project, add `notifications: { enabled: false }` to that project's entry in `projects.yml`:

```yaml
projects:
  - name: my-webapp
    dir: ~/Projects/my-webapp
    notifications:
      enabled: false   # suppress macOS banners for this project only
```

The visual bell in tmux continues to fire regardless of this setting.

### Diagnostic log

Failed notifications are logged to:
```
~/.local/state/tmux-session-manager/notifications.log
```

Override the directory with `TMS_STATE_DIR` or `XDG_STATE_HOME`.

### Known limitation — multiple terminal windows

If you have two or more windows of the same terminal emulator open, clicking the banner foregrounds the application but macOS chooses whichever window was most recently active as the frontmost OS window. The tmux client in any other window *does* get retargeted to the correct project, but it may be hidden behind the frontmost window — cycle windows (⌘\` on macOS) to find it. Single-window users are unaffected.

For the full verification recipe, see [`specs/002-claude-notification-hook/quickstart.md`](specs/002-claude-notification-hook/quickstart.md).

## License

MIT
