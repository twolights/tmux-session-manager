#!/usr/bin/env bash
# notify.sh — macOS notification emission, project detection, and failure logging
#
# Sourced by bin/tms and bin/tms-notify-hook. Depends on lib/utils.sh (die/warn/
# expand_path/require_cmd) and lib/config.sh (config_* helpers).

# --- logging --------------------------------------------------------------

# notify_log_path — print the absolute path to the notifications log file,
# creating its parent directory on first call (mode 0755).
#
# Resolution order:
#   1. $TMS_STATE_DIR                       (explicit override)
#   2. $XDG_STATE_HOME/tmux-session-manager (XDG default)
#   3. $HOME/.local/state/tmux-session-manager
notify_log_path() {
    local state_dir
    if [[ -n "${TMS_STATE_DIR:-}" ]]; then
        state_dir="$TMS_STATE_DIR"
    elif [[ -n "${XDG_STATE_HOME:-}" ]]; then
        state_dir="$XDG_STATE_HOME/tmux-session-manager"
    else
        state_dir="$HOME/.local/state/tmux-session-manager"
    fi
    [[ -d "$state_dir" ]] || mkdir -p -m 0755 "$state_dir"
    printf '%s\n' "$state_dir/notifications.log"
}

# notify_log_failure <category> <project|-> <notification_type|-> <session_id|-> <message>
#
# Appends a tab-separated line to the notifications log. Single printf call so
# the append is one write syscall (atomic up to PIPE_BUF).
notify_log_failure() {
    local category="${1:-unknown}"
    local project="${2:--}"
    local ntype="${3:--}"
    local sid="${4:--}"
    local message="${5:--}"

    # Scrub embedded tabs/newlines; truncate message to 200 chars with ellipsis.
    local p n s m
    p=$(printf '%s' "$project" | tr '\t\n\r' '   ')
    n=$(printf '%s' "$ntype"   | tr '\t\n\r' '   ')
    s=$(printf '%s' "$sid"     | tr '\t\n\r' '   ')
    m=$(printf '%s' "$message" | tr '\t\n\r' '   ')
    if [[ ${#m} -gt 200 ]]; then
        m="${m:0:199}…"
    fi

    local ts
    ts=$(date '+%Y-%m-%dT%H:%M:%S%z')

    local logfile
    logfile=$(notify_log_path)

    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$ts" "$category" "$p" "$n" "$s" "$m" >> "$logfile"
}

# --- JSON parsing (jq-optional) -------------------------------------------

# notify_parse_json_field <field-name> <payload>
#
# Prints the string value of a top-level flat field, or empty if missing.
# Prefers jq when present; otherwise falls back to a narrow POSIX extractor
# that handles the Claude Code Notification payload's flat-string shape.
notify_parse_json_field() {
    local field="$1"
    local payload="$2"

    if command -v jq >/dev/null 2>&1; then
        printf '%s' "$payload" | jq -r --arg f "$field" '.[$f] // empty' 2>/dev/null || true
        return 0
    fi

    # Fallback: find "field":"value" with minimal quote/escape handling.
    # This is deliberately narrow — it handles only flat string fields and
    # assumes no unescaped quotes or backslashes inside the value, which
    # matches the Claude Code Notification schema documented in
    # contracts/tms-notify-hook-stdin.md.
    printf '%s' "$payload" \
        | sed -n "s/.*\"${field}\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" \
        | head -n 1
}

# --- project detection ----------------------------------------------------

# notify_resolve_project_from_cwd <cwd>
#
# Given a working directory, find the tms project whose configured dir is an
# ancestor (path-boundary prefix) of <cwd>. Prints the project name on stdout
# and returns 0 on match; returns 1 with no output on no-match.
notify_resolve_project_from_cwd() {
    local input_cwd="$1"
    [[ -z "$input_cwd" ]] && return 1

    # Normalize via realpath when available; fall back to expand_path + pwd -P.
    local norm_cwd
    if [[ -d "$input_cwd" ]]; then
        norm_cwd=$(cd "$input_cwd" 2>/dev/null && pwd -P) || norm_cwd="$input_cwd"
    else
        norm_cwd="$input_cwd"
    fi

    local projects
    projects=$(config_list_projects) || return 1

    local name dir norm_dir
    while IFS= read -r name; do
        [[ -z "$name" ]] && continue
        dir=$(config_get_project_dir "$name") || continue
        if [[ -d "$dir" ]]; then
            norm_dir=$(cd "$dir" 2>/dev/null && pwd -P) || norm_dir="$dir"
        else
            norm_dir="$dir"
        fi
        # Path-boundary prefix: either equal, or project dir + '/' is a prefix.
        if [[ "$norm_cwd" == "$norm_dir" ]] || [[ "$norm_cwd" == "$norm_dir/"* ]]; then
            printf '%s\n' "$name"
            return 0
        fi
    done <<< "$projects"

    return 1
}

# --- terminal bundle detection --------------------------------------------

# notify_resolve_term_bundle
#
# Print the macOS bundle id of the terminal emulator hosting Claude Code.
# Used as the target for `open -b` in the click handler — must be the REAL
# terminal so the right window foregrounds when the user clicks the banner.
# Prefers $__CFBundleIdentifier (set by macOS for GUI-launched apps); falls
# back to a $TERM_PROGRAM lookup; ultimate fallback is Terminal.app.
notify_resolve_term_bundle() {
    if [[ -n "${__CFBundleIdentifier:-}" ]]; then
        printf '%s\n' "$__CFBundleIdentifier"
        return 0
    fi
    case "${TERM_PROGRAM:-}" in
        iTerm.app)      printf '%s\n' "com.googlecode.iterm2" ;;
        Apple_Terminal) printf '%s\n' "com.apple.Terminal" ;;
        ghostty)        printf '%s\n' "com.mitchellh.ghostty" ;;
        alacritty)      printf '%s\n' "org.alacritty" ;;
        kitty)          printf '%s\n' "net.kovidgoyal.kitty" ;;
        WezTerm)        printf '%s\n' "com.github.wez.wezterm" ;;
        *)              printf '%s\n' "com.apple.Terminal" ;;
    esac
}

# --- install / uninstall hooks -------------------------------------------

# cmd_install_hooks [--uninstall] [--dry-run]
#
# Install or remove the tms-notify-hook entry in ~/.claude/settings.json.
cmd_install_hooks() {
    local do_uninstall=false do_dry_run=false
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --uninstall) do_uninstall=true ;;
            --dry-run)   do_dry_run=true ;;
            *) die "unknown option '$1'. Usage: tms install-hooks [--uninstall] [--dry-run]" ;;
        esac
        shift
    done

    # Preconditions (skip for uninstall — don't require alerter to uninstall)
    if [[ "$do_uninstall" == "false" ]]; then
        require_cmd alerter "brew install alerter"
        require_cmd jq "brew install jq"
    else
        require_cmd jq "brew install jq"
    fi

    if [[ ! -d "$HOME/.claude" ]]; then
        die "~/.claude/ not found. Run 'claude' at least once to initialize Claude Code before installing hooks."
    fi

    local settings_file="$HOME/.claude/settings.json"
    local tms_hook_path
    # TMS_DIR must be set in the calling context (bin/tms sets it at startup)
    tms_hook_path="${TMS_DIR}/bin/tms-notify-hook"

    # Read existing settings or start from empty object
    local original_json
    if [[ -f "$settings_file" ]]; then
        if ! original_json=$(jq '.' "$settings_file" 2>/dev/null); then
            die "~/.claude/settings.json is not valid JSON; refusing to modify."
        fi
    else
        original_json="{}"
    fi

    if [[ "$do_uninstall" == "true" ]]; then
        _install_hooks_uninstall "$original_json" "$settings_file" "$tms_hook_path" "$do_dry_run"
        return 0
    fi

    _install_hooks_install "$original_json" "$settings_file" "$tms_hook_path" "$do_dry_run"
}

_install_hooks_install() {
    local original_json="$1" settings_file="$2" tms_hook_path="$3" do_dry_run="$4"

    # Build the desired hook entry
    local new_entry
    new_entry=$(jq -n --arg cmd "$tms_hook_path" \
        '{"matcher":"","hooks":[{"type":"command","command":$cmd,"timeout":10}]}')

    # Check if an entry with a command ending in bin/tms-notify-hook already exists
    local existing_cmd existing_idx
    existing_idx=$(printf '%s' "$original_json" | \
        jq -r '(.hooks.Notification // []) | to_entries[] | select(.value.hooks[]?.command | endswith("bin/tms-notify-hook")) | .key' \
        2>/dev/null | head -1)

    local new_json action_msg

    if [[ -n "$existing_idx" ]]; then
        existing_cmd=$(printf '%s' "$original_json" | \
            jq -r --argjson idx "$existing_idx" \
            '(.hooks.Notification[$idx].hooks[] | select(.command | endswith("bin/tms-notify-hook"))).command' \
            2>/dev/null | head -1)

        if [[ "$existing_cmd" == "$tms_hook_path" ]]; then
            printf 'tms-notify-hook is already installed at %s.\n' "$tms_hook_path"
            # Still run the probe even on idempotent re-install
            if [[ "$do_dry_run" == "false" ]]; then
                _install_hooks_probe "$tms_hook_path"
            fi
            return 0
        fi

        # Path mismatch — update in place
        new_json=$(printf '%s' "$original_json" | \
            jq --argjson idx "$existing_idx" --argjson entry "$new_entry" \
            '.hooks.Notification[$idx] = $entry')
        action_msg="Updated tms-notify-hook path: ${existing_cmd} → ${tms_hook_path}"
    else
        # No existing tms entry — append
        new_json=$(printf '%s' "$original_json" | \
            jq --argjson entry "$new_entry" \
            '.hooks.Notification = ((.hooks.Notification // []) + [$entry])')
        action_msg="Installed tms-notify-hook at ${tms_hook_path}."
    fi

    if [[ "$do_dry_run" == "true" ]]; then
        diff -u <(printf '%s\n' "$original_json") <(printf '%s\n' "$new_json") || true
        return 0
    fi

    # Atomic write
    local tmp_file="${settings_file}.tmp"
    if ! printf '%s\n' "$new_json" > "$tmp_file"; then
        die "failed to write settings.json; .tmp preserved at ${tmp_file}."
    fi
    if ! mv "$tmp_file" "$settings_file"; then
        die "failed to move ${tmp_file} to ${settings_file}; .tmp preserved at ${tmp_file}."
    fi

    printf '%s\n' "$action_msg"
    _install_hooks_probe "$tms_hook_path"
}

_install_hooks_uninstall() {
    local original_json="$1" settings_file="$2" tms_hook_path="$3" do_dry_run="$4"

    # Check if any tms entry exists
    local has_entry
    has_entry=$(printf '%s' "$original_json" | \
        jq -r '(.hooks.Notification // [])[] | .hooks[]? | select(.command | endswith("bin/tms-notify-hook")) | .command' \
        2>/dev/null | head -1)

    if [[ -z "$has_entry" ]]; then
        printf 'No tms-notify-hook installed.\n'
        return 0
    fi

    # Filter out tms entries
    local new_json
    new_json=$(printf '%s' "$original_json" | jq '
        if (.hooks.Notification | length) > 0 then
            .hooks.Notification = [
                .hooks.Notification[] |
                select(.hooks | map(select(.command | endswith("bin/tms-notify-hook"))) | length == 0)
            ] |
            if (.hooks.Notification | length) == 0 then del(.hooks.Notification) else . end
        else . end
    ')

    if [[ "$do_dry_run" == "true" ]]; then
        diff -u <(printf '%s\n' "$original_json") <(printf '%s\n' "$new_json") || true
        return 0
    fi

    local tmp_file="${settings_file}.tmp"
    if ! printf '%s\n' "$new_json" > "$tmp_file"; then
        die "failed to write settings.json; .tmp preserved at ${tmp_file}."
    fi
    if ! mv "$tmp_file" "$settings_file"; then
        die "failed to move ${tmp_file} to ${settings_file}; .tmp preserved at ${tmp_file}."
    fi

    printf 'Removed tms-notify-hook.\n'
}

_install_hooks_probe() {
    local tms_hook_path="$1"
    local log_path
    log_path=$(notify_log_path)

    # alerter defaults --sender to com.apple.Terminal (the only universally
    # working sender on macOS 26+), so we don't pass --sender ourselves.
    alerter \
        --title 'tms' \
        --message 'Notification hook installed. You should see this banner.' \
        --timeout 10 \
        >/dev/null 2>&1 &
    disown 2>/dev/null || true

    cat <<PROBE

If you saw a macOS banner titled 'tms' just now, notifications are working.
If macOS asked you to allow notifications for 'Terminal' (alerter delivers
under Terminal's bundle for compatibility), click Allow — you're done.
If nothing appeared, open:

    System Settings → Notifications → Terminal

and turn notifications on for that entry. Claude Code's Notification hook
will fire banners through the same permission, so this is a one-time setup.

Diagnostic log for any future failures:
    ${log_path}
PROBE
}
