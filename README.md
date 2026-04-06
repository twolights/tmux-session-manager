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

## Installation

```bash
# 1. Clone the repo
git clone https://github.com/your-user/claude-code-tmux-manager.git

# 2. Add tms to your PATH
ln -s /path/to/claude-code-tmux-manager/bin/tms ~/.local/bin/tms

# 3. Create your config
mkdir -p ~/.config/tmux-session-manager
cp /path/to/claude-code-tmux-manager/config/projects.example.yml \
   ~/.config/tmux-session-manager/projects.yml

# 4. Edit projects.yml with your projects (see Configuration below)
```

Key bindings are loaded automatically when you run `tms start` -- no `.tmux.conf` modification needed. Bindings only activate in tms-managed sessions.

## Usage

### CLI commands

```bash
tms start <project>    # Launch or attach to a project workspace
tms stop <project>     # Stop a project session
tms list               # Show all projects with status
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

## License

MIT
