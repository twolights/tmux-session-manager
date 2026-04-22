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

# Lightweight config load — sets CONFIG_FILE and verifies syntactic validity
# but skips _config_validate's per-project structural checks. Cost: ~2 yq
# calls vs ~5N+1 in config_load. Use on hot paths (notification click →
# tms switch) where errors are tolerable as long as the malformed-config
# case is still surfaced via a fallback to _config_validate when lookups
# fail (see config_project_exists_or_validate).
config_load_lite() {
    CONFIG_FILE="$(config_file)"
    if [[ ! -f "$CONFIG_FILE" ]]; then
        die "configuration file not found at $CONFIG_FILE"
    fi
    if ! yq '.' "$CONFIG_FILE" &>/dev/null; then
        die "configuration file is not valid YAML: $CONFIG_FILE"
    fi
}

# Validate config structure and constraints
_config_validate() {
    local count
    count=$(yq '.projects | length' "$CONFIG_FILE")

    if [[ "$count" == "0" ]] || [[ "$count" == "null" ]]; then
        die "no projects defined in $CONFIG_FILE"
    fi

    # Validate optional top-level notifications block (global defaults).
    # Siblings of `projects:`. Absent is OK.
    local gnotif_type gsound_type
    gnotif_type=$(yq '.notifications | type' "$CONFIG_FILE")
    if [[ "$gnotif_type" != '"null"' ]] && [[ "$gnotif_type" != '"object"' ]]; then
        die "top-level 'notifications' must be a map"
    fi
    gsound_type=$(yq '.notifications.sound | type' "$CONFIG_FILE")
    if [[ "$gsound_type" != '"null"' ]] && [[ "$gsound_type" != '"string"' ]]; then
        die "top-level 'notifications.sound' must be a string"
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
        if [[ ${#seen_names[@]} -gt 0 ]]; then
            for seen in "${seen_names[@]}"; do
                if [[ "$seen" == "$name" ]]; then
                    die "duplicate project name '$name'"
                fi
            done
        fi
        seen_names+=("$name")

        # Validate optional notifications block (type-check only; absent is OK).
        # Python-based yq emits JSON types as quoted strings: "null", "object", "boolean".
        local notif_type notif_enabled_type
        notif_type=$(yq ".projects[$i].notifications | type" "$CONFIG_FILE")
        if [[ "$notif_type" != '"null"' ]] && [[ "$notif_type" != '"object"' ]]; then
            die "project '$name' notifications must be a map"
        fi
        notif_enabled_type=$(yq ".projects[$i].notifications.enabled | type" "$CONFIG_FILE")
        if [[ "$notif_enabled_type" != '"null"' ]] && [[ "$notif_enabled_type" != '"boolean"' ]]; then
            die "project '$name' notifications.enabled must be a bool"
        fi
        local notif_sound_type
        notif_sound_type=$(yq ".projects[$i].notifications.sound | type" "$CONFIG_FILE")
        if [[ "$notif_sound_type" != '"null"' ]] && [[ "$notif_sound_type" != '"string"' ]]; then
            die "project '$name' notifications.sound must be a string"
        fi

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

                if [[ ${#seen_server_names[@]} -gt 0 ]]; then
                    for ss in "${seen_server_names[@]}"; do
                        if [[ "$ss" == "$sname" ]]; then
                            die "project '$name' has duplicate server name '$sname'"
                        fi
                    done
                fi
                seen_server_names+=("$sname")
            done
        fi
    done
}

# Single-yq-call existence check for a project name. Returns 0 if found,
# 1 otherwise. Avoids _config_project_index's per-project iteration loop
# (one yq invocation per project). Use on hot paths.
config_project_exists() {
    local target="$1"
    [[ -z "$target" ]] && return 1
    local found
    found=$(yq -r --arg name "$target" '.projects[]? | select(.name == $name) | .name' "$CONFIG_FILE" 2>/dev/null | head -1)
    [[ "$found" == "$target" ]]
}

# Lookup-with-fallback: if config_project_exists returns false, run full
# validation (_config_validate) so a malformed config dies with the precise
# original-quality error before we report "not found". Returns 0 if the
# project exists; returns 1 (via die in _config_validate, or explicitly)
# otherwise. Caller still needs to die on the 1 return for the genuine
# not-found case.
config_project_exists_or_validate() {
    local target="$1"
    if config_project_exists "$target"; then
        return 0
    fi
    # Lite check failed — could be missing project OR malformed config.
    # Surface any structural error first; if validation passes, the
    # project is genuinely not registered.
    _config_validate
    return 1
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

# Get per-project notification opt-out state. Prints "true" or "false".
# Absent field → "true" (global-on default per FR-011).
config_get_notifications_enabled() {
    local idx
    idx=$(_config_project_index "$1") || return 1
    local val
    val=$(yq -r ".projects[$idx].notifications.enabled" "$CONFIG_FILE")
    if [[ "$val" == "null" ]] || [[ -z "$val" ]]; then
        printf '%s\n' "true"
    else
        printf '%s\n' "$val"
    fi
}

# Get the notification sound for a project. Precedence:
#   1. projects[idx].notifications.sound is present → use it
#      (including explicit empty string, which means "silent").
#   2. Else top-level notifications.sound → use it.
#   3. Else → empty string (silent).
# "Present" means the YAML key exists, even if the value is "".
# yq reports absent keys as "null" and empty-string values as the empty
# string — so we distinguish the two by checking the raw value against
# the literal string "null".
config_get_notifications_sound() {
    local idx
    idx=$(_config_project_index "$1") || return 1
    local proj_raw
    proj_raw=$(yq -r ".projects[$idx].notifications.sound" "$CONFIG_FILE")
    if [[ "$proj_raw" != "null" ]]; then
        # Field is present at the project level (empty string = explicit silence).
        printf '%s\n' "$proj_raw"
        return 0
    fi
    # Fall through to global.
    local global_raw
    global_raw=$(yq -r '.notifications.sound' "$CONFIG_FILE")
    if [[ "$global_raw" != "null" ]]; then
        printf '%s\n' "$global_raw"
        return 0
    fi
    # Nothing set anywhere — silent.
    printf '%s\n' ""
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
