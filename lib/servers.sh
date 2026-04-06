#!/usr/bin/env bash
# servers.sh — Server process management (hidden windows, popups)

# Start all configured servers for a project in a hidden window.
# Creates a "_servers" window in the session with one pane per server.
# Called by session_create after pane setup.
servers_start() {
    local session_name="$1"

    local server_count
    server_count=$(config_get_server_count "$session_name")

    if [[ "$server_count" -eq 0 ]]; then
        return 0
    fi

    # Rename the initial window (window 0) to "_servers"
    tmux rename-window -t "${session_name}:0" "_servers"

    local i server_name server_cmd server_dir
    for ((i = 0; i < server_count; i++)); do
        server_name=$(config_get_server_name "$session_name" "$i")
        server_cmd=$(config_get_server_cmd "$session_name" "$i")
        server_dir=$(config_get_server_dir "$session_name" "$i")

        if [[ "$i" -eq 0 ]]; then
            # Use the first pane of the _servers window
            tmux send-keys -t "${session_name}:_servers.0" "cd '$server_dir' && echo '=== $server_name ===' && $server_cmd" Enter
        else
            # Split for additional servers
            tmux split-window -v -t "${session_name}:_servers" -c "$server_dir"
            tmux send-keys -t "${session_name}:_servers.$i" "echo '=== $server_name ===' && $server_cmd" Enter
        fi
    done

    # Even out the pane layout if multiple servers
    if [[ "$server_count" -gt 1 ]]; then
        tmux select-layout -t "${session_name}:_servers" even-vertical
    fi
}
