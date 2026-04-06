#!/usr/bin/env bash
# config.sh — YAML config parsing and validation using yq

# Load and validate config file. Sets CONFIG_FILE global.
# Dies if file not found or invalid.
config_load() {
    CONFIG_FILE="$(config_file)"
    if [[ ! -f "$CONFIG_FILE" ]]; then
        die "configuration file not found at $CONFIG_FILE"
    fi

    # Validate YAML is parseable
    if ! yq '.' "$CONFIG_FILE" &>/dev/null; then
        die "configuration file is not valid YAML: $CONFIG_FILE"
    fi

    # Run validation checks
    _config_validate
}

# Validate config structure and constraints
_config_validate() {
    local count
    count=$(yq '.projects | length' "$CONFIG_FILE")

    if [[ "$count" == "0" ]] || [[ "$count" == "null" ]]; then
        die "no projects defined in $CONFIG_FILE"
    fi

    local seen_names=()
    local i name dir

    for ((i = 0; i < count; i++)); do
        name=$(yq -r ".projects[$i].name" "$CONFIG_FILE")
        dir=$(yq -r ".projects[$i].dir" "$CONFIG_FILE")

        # Check required fields
        if [[ "$name" == "null" ]] || [[ -z "$name" ]]; then
            die "project at index $i missing required field 'name'"
        fi
        if [[ "$dir" == "null" ]] || [[ -z "$dir" ]]; then
            die "project '$name' missing required field 'dir'"
        fi

        # Check name validity (no dots or colons for tmux)
        if [[ "$name" == *"."* ]] || [[ "$name" == *":"* ]]; then
            die "project '$name' has invalid characters (dots and colons not allowed in tmux session names)"
        fi

        # Check for duplicate names
        for seen in "${seen_names[@]}"; do
            if [[ "$seen" == "$name" ]]; then
                die "duplicate project name '$name'"
            fi
        done
        seen_names+=("$name")

        # Validate servers if present
        local server_count
        server_count=$(yq ".projects[$i].servers | length" "$CONFIG_FILE")
        if [[ "$server_count" != "0" ]] && [[ "$server_count" != "null" ]]; then
            local seen_server_names=()
            local j sname scmd
            for ((j = 0; j < server_count; j++)); do
                sname=$(yq -r ".projects[$i].servers[$j].name" "$CONFIG_FILE")
                scmd=$(yq -r ".projects[$i].servers[$j].cmd" "$CONFIG_FILE")

                if [[ "$sname" == "null" ]] || [[ -z "$sname" ]]; then
                    die "project '$name' server at index $j missing required field 'name'"
                fi
                if [[ "$scmd" == "null" ]] || [[ -z "$scmd" ]]; then
                    die "project '$name' server '$sname' missing required field 'cmd'"
                fi

                for ss in "${seen_server_names[@]}"; do
                    if [[ "$ss" == "$sname" ]]; then
                        die "project '$name' has duplicate server name '$sname'"
                    fi
                done
                seen_server_names+=("$sname")
            done
        fi
    done
}

# Get the index of a project by name. Returns "" if not found.
_config_project_index() {
    local target="$1"
    local count
    count=$(yq '.projects | length' "$CONFIG_FILE")

    local i name
    for ((i = 0; i < count; i++)); do
        name=$(yq -r ".projects[$i].name" "$CONFIG_FILE")
        if [[ "$name" == "$target" ]]; then
            echo "$i"
            return 0
        fi
    done
    return 1
}

# Get project directory by name (expanded)
config_get_project_dir() {
    local idx
    idx=$(_config_project_index "$1") || return 1
    local dir
    dir=$(yq -r ".projects[$idx].dir" "$CONFIG_FILE")
    expand_path "$dir"
}

# List all project names, one per line
config_list_projects() {
    local count
    count=$(yq '.projects | length' "$CONFIG_FILE")

    local i
    for ((i = 0; i < count; i++)); do
        yq -r ".projects[$i].name" "$CONFIG_FILE"
    done
}

# Get project directory (raw, not expanded) by name
config_get_project_dir_raw() {
    local idx
    idx=$(_config_project_index "$1") || return 1
    yq -r ".projects[$idx].dir" "$CONFIG_FILE"
}

# Get server count for a project
config_get_server_count() {
    local idx
    idx=$(_config_project_index "$1") || return 1
    local count
    count=$(yq ".projects[$idx].servers | length" "$CONFIG_FILE")
    if [[ "$count" == "null" ]]; then
        echo "0"
    else
        echo "$count"
    fi
}

# Get server name by project name and server index
config_get_server_name() {
    local project="$1" server_idx="$2"
    local idx
    idx=$(_config_project_index "$project") || return 1
    yq -r ".projects[$idx].servers[$server_idx].name" "$CONFIG_FILE"
}

# Get server command by project name and server index
config_get_server_cmd() {
    local project="$1" server_idx="$2"
    local idx
    idx=$(_config_project_index "$project") || return 1
    yq -r ".projects[$idx].servers[$server_idx].cmd" "$CONFIG_FILE"
}

# Get server dir by project name and server index (returns project dir if not set)
config_get_server_dir() {
    local project="$1" server_idx="$2"
    local idx
    idx=$(_config_project_index "$project") || return 1
    local sdir
    sdir=$(yq -r ".projects[$idx].servers[$server_idx].dir" "$CONFIG_FILE")
    if [[ "$sdir" == "null" ]] || [[ -z "$sdir" ]]; then
        config_get_project_dir "$project"
    else
        expand_path "$sdir"
    fi
}
