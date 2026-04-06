# Data Model: Tmux Session Manager

**Date**: 2026-04-06
**Feature**: 001-tmux-session-manager

## Entities

### Project

Represents a configured development workspace.

| Field          | Type       | Required | Description                                         |
|----------------|------------|----------|-----------------------------------------------------|
| name           | string     | yes      | Unique project identifier (used as tmux session name) |
| dir            | string     | yes      | Absolute path to the project working directory      |
| servers        | Server[]   | no       | List of server commands to run in popup windows     |

**Constraints**:
- `name` must be unique across all projects
- `name` must be valid as a tmux session name (no dots or colons)
- `dir` must be an existing directory on disk (validated at launch time)

### Server

A background process associated with a project, viewable via popup window.

| Field   | Type   | Required | Description                                       |
|---------|--------|----------|---------------------------------------------------|
| name    | string | yes      | Display name for the server (shown in popup title) |
| cmd     | string | yes      | Shell command to start the server                  |
| dir     | string | no       | Working directory override (defaults to project dir) |

**Constraints**:
- `name` must be unique within a project
- `cmd` is executed via the user's shell

### Session (Runtime — Not Persisted)

A running tmux session for a project. Exists only at runtime.

| Field          | Type      | Description                                        |
|----------------|-----------|----------------------------------------------------|
| session_name   | string    | Matches project `name`                             |
| editor_pane    | pane_id   | Pane running neovim (left, 60%)                    |
| claude_pane    | pane_id   | Pane running Claude Code (right, 40%)              |
| server_window  | window_id | Hidden window containing server panes (if any)     |

## Configuration File Example

```yaml
# ~/.config/tmux-session-manager/projects.yml

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
    # No servers — just neovim + Claude Code
```

## State Transitions

### Session Lifecycle

```
[Not Running] ---(tms start)---> [Running]
[Running] ------(tms stop)-----> [Not Running]
[Running] ------(tms start)----> [Attached] (reattach to existing)
```

### Server Process Lifecycle

```
[Not Started] ---(workspace launch)---> [Running in hidden pane]
[Running] ------(process crashes)-----> [Exited — error visible in pane]
[Exited] -------(user restarts)-------> [Running in hidden pane]
```
