# Quickstart: Tmux Session Manager

## Prerequisites

- tmux 3.2+ installed
- neovim installed and on PATH
- Claude Code CLI installed and on PATH
- `yq` installed for YAML parsing (`brew install yq` on macOS)

## Setup

1. Clone or copy the project scripts to a location on your PATH:

   ```bash
   # Example: link the tms command
   ln -s /path/to/claude-code-tmux-manager/bin/tms ~/.local/bin/tms
   ```

2. Create your project configuration:

   ```bash
   mkdir -p ~/.config/tmux-session-manager
   cp /path/to/claude-code-tmux-manager/config/projects.example.yml \
      ~/.config/tmux-session-manager/projects.yml
   ```

3. Edit `~/.config/tmux-session-manager/projects.yml` with your projects.

4. Source the tmux key bindings in your `~/.tmux.conf`:

   ```tmux
   source-file /path/to/claude-code-tmux-manager/tmux/bindings.conf
   ```

5. Reload tmux config:

   ```bash
   tmux source-file ~/.tmux.conf
   ```

## Usage

```bash
# Start a project workspace
tms start my-webapp

# List all projects and their status
tms list

# Stop a project session
tms stop my-webapp
```

### Key Bindings (inside tmux)

- `prefix + P` — Open project session chooser (switch between projects)
- `prefix + S` — Toggle server popup window for current project

## Verifying It Works

1. Add a test project to `projects.yml` pointing to any directory
2. Run `tms start <project-name>`
3. Verify: left pane has neovim, right pane has Claude Code
4. Press `ctrl-z` in the neovim pane to suspend to shell, `fg` to resume
5. Press `prefix + S` to toggle server popups (if configured)
