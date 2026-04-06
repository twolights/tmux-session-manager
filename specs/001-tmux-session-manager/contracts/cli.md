# CLI Contract: tms

The `tms` command is the single entry point for managing tmux project sessions.

## Commands

### `tms start <project-name>`

Launch or attach to a project workspace.

| Behavior | Description |
|----------|-------------|
| **No existing session** | Creates tmux session named `<project-name>`, splits into two panes (neovim left 60%, Claude Code right 40%), starts configured servers in hidden window, attaches |
| **Session exists** | Attaches to existing session (or switches client if already inside tmux) |
| **Project not found** | Prints error to stderr, exits with code 1 |
| **Directory missing** | Prints error to stderr, exits with code 1 |

**Exit codes**: 0 = success, 1 = error

### `tms stop <project-name>`

Kill a project session and all its processes (including servers).

| Behavior | Description |
|----------|-------------|
| **Session running** | Kills the tmux session (all panes and windows), exits 0 |
| **Session not running** | Prints warning to stderr, exits 0 |
| **Project not found** | Prints error to stderr, exits 1 |

### `tms list`

Show all configured projects and their running status.

**Output format** (stdout):

```
  my-webapp      [running]  ~/Projects/my-webapp
  api-service    [stopped]  ~/Projects/api-service
  dotfiles       [running]  ~/dotfiles
```

- Green/bold for running, dim for stopped (when terminal supports color)
- Columns: project name, status, directory

**Exit codes**: 0 = success, 1 = config error

## Configuration

**Path**: `~/.config/tmux-session-manager/projects.yml`

**Validation errors** (printed to stderr):
- `Error: project '<name>' missing required field 'dir'`
- `Error: duplicate project name '<name>'`
- `Error: configuration file not found at <path>`

## tmux Key Bindings

Installed via `source-file` in user's tmux.conf.

| Binding      | Action                                              |
|--------------|-----------------------------------------------------|
| `prefix + P` | `choose-tree` filtered to managed project sessions  |
| `prefix + S` | Toggle server popup for the current session's project |
