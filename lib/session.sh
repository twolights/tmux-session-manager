#!/usr/bin/env bash
# session.sh — tmux session creation and management

# Check if a tmux session with the given name exists
session_exists() {
    tmux has-session -t "=$1" 2>/dev/null
}

# Attach to (or switch to) an existing session
session_attach() {
    local session_name="$1"
    if [[ -n "${TMUX:-}" ]]; then
        # Already inside tmux — switch client
        tmux switch-client -t "$session_name"
    else
        tmux attach-session -t "$session_name"
    fi
}

# Create a new tmux session for a project
# Window 0: _servers (if configured), Window 1: workspace (neovim + Claude Code)
session_create() {
    local session_name="$1"
    local project_dir="$2"

    # Create session in detached mode — this becomes window 0
    tmux new-session -d -s "$session_name" -c "$project_dir"

    # Tag session as tms-managed and load key bindings
    tmux set-option -t "$session_name" @tms 1
    tmux set-option -g @tms_dir "$TMS_DIR"
    tmux source-file "$TMS_DIR/tmux/bindings.conf"

    # Enable visual bell so Claude Code notifications highlight the pane
    tmux set-option -t "$session_name" visual-bell on
    tmux set-option -t "$session_name" monitor-bell on

    # Start servers in window 0 (if configured), then create workspace in window 1
    servers_start "$session_name"

    # Create workspace window (window 1 if servers exist, window 0 if not)
    tmux new-window -t "$session_name" -n "workspace" -c "$project_dir"

    # Split vertically: left pane gets 60%, right pane 40%
    tmux split-window -h -t "${session_name}:workspace" -c "$project_dir" -l 40%

    # Left pane (pane 0): launch neovim
    tmux send-keys -t "${session_name}:workspace.0" 'nvim .' Enter

    # Right pane (pane 1): launch Claude Code
    tmux send-keys -t "${session_name}:workspace.1" 'claude --continue' Enter

    # Select the left (editor) pane as active
    tmux select-pane -t "${session_name}:workspace.0"

    # Focus the workspace window
    tmux select-window -t "${session_name}:workspace"
}

# cmd_start — main entry point for "tms start <project>"
cmd_start() {
    local project="$1"

    # Look up project in config
    local project_dir
    project_dir=$(config_get_project_dir "$project") || die "project '$project' not found in configuration"

    # Validate directory exists
    if [[ ! -d "$project_dir" ]]; then
        die "project directory does not exist: $project_dir"
    fi

    # Attach to existing or create new
    if session_exists "$project"; then
        session_attach "$project"
    else
        session_create "$project" "$project_dir"
        session_attach "$project"
    fi
}

# cmd_stop — main entry point for "tms stop <project>"
cmd_stop() {
    local project="$1"

    # Verify project exists in config
    config_get_project_dir "$project" >/dev/null || die "project '$project' not found in configuration"

    if session_exists "$project"; then
        tmux kill-session -t "=$project"
    else
        warn "session '$project' is not running"
    fi
}

# cmd_list — show all configured projects with running status
cmd_list() {
    local projects
    projects=$(config_list_projects)

    # Calculate max name length for alignment
    local max_len=0
    local name
    while IFS= read -r name; do
        [[ ${#name} -gt $max_len ]] && max_len=${#name}
    done <<< "$projects"

    # Print each project with status
    while IFS= read -r name; do
        local dir_raw
        dir_raw=$(config_get_project_dir_raw "$name")

        local status status_color
        if session_exists "$name"; then
            status="[running]"
            status_color="${GREEN}${BOLD}"
        else
            status="[stopped]"
            status_color="${DIM}"
        fi

        printf "  ${status_color}%-${max_len}s  %-9s${RESET}  %s\n" "$name" "$status" "$dir_raw"
    done <<< "$projects"
}
