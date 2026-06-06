#!/usr/bin/env bash
# notify.sh — macOS notification emission, project detection, and failure logging
#
# Sourced by bin/tms. Depends on lib/utils.sh (die/warn/
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

# --- click-to-exact-tab helpers (feature 004) ----------------------------
#
# These helpers are called from inside cmd_notify_hook's detached subshell
# on @CONTENTCLICKED. They identify the exact terminal window+tab hosting
# the originating tmux session via AppleScript (iTerm2 / Terminal.app
# only) by matching tmux's `client_tty` against the terminal's per-tab
# tty property. See specs/004-click-to-exact-tab/.

# _notify_classify_osascript_err <stderr-text>
#
# Pure-bash classifier. Maps osascript stderr to one of the discriminator
# values logged in the `applescript-failed` category. The `no-tty-match`
# mode is NOT classified here — callers signal it via osascript exit==1
# with empty stderr.
_notify_classify_osascript_err() {
    local stderr_text="$1"
    case "$stderr_text" in
        *"not authorized to send Apple events"*|*"-1743"*) printf 'permission-denied' ;;
        *"execution error"*|*"syntax error"*)               printf 'script-error' ;;
        *"Can"*"t get"*|*"doesn"*"t understand"*)           printf 'terminal-quit' ;;
        *)                                                   printf 'osascript-other' ;;
    esac
}

# _notify_iterm_applescript
#
# Print the iTerm2 AppleScript body. Iterates windows × tabs, matches
# `tty of current session of tab` against argv[0]; on match, raises the
# window and selects the tab. Returns 0 on match, 1 on no-match. See
# specs/004-click-to-exact-tab/contracts/applescript-payloads.md §Payload 1.
_notify_iterm_applescript() {
    cat <<'APPLESCRIPT'
on run argv
    set target_tty to item 1 of argv
    tell application "iTerm"
        activate
        repeat with w in windows
            repeat with t in tabs of w
                tell current session of t
                    if (tty as text) is equal to target_tty then
                        tell w to select
                        tell t to select
                        return 0
                    end if
                end tell
            end repeat
        end repeat
        return 1
    end tell
end run
APPLESCRIPT
}

# _notify_terminal_app_applescript
#
# Print the Terminal.app AppleScript body. Same shape as iTerm2 but with
# Terminal.app's dialect: `tty` is a property of `tab` directly (not
# nested under `current session`), and selection uses `set frontmost` /
# `set selected` rather than `tell to select`. See contracts/applescript-
# payloads.md §Payload 2. Empirical verification on a real Terminal.app
# instance is task T010 in the implementation plan.
_notify_terminal_app_applescript() {
    cat <<'APPLESCRIPT'
on run argv
    set target_tty to item 1 of argv
    tell application "Terminal"
        activate
        repeat with w in windows
            repeat with t in tabs of w
                if (tty of t as text) is equal to target_tty then
                    set frontmost of w to true
                    set selected of t to true
                    return 0
                end if
            end repeat
        end repeat
        return 1
    end tell
end run
APPLESCRIPT
}

# _notify_dispatch_osascript <body> <target-tty> <project> <ntype> <session-id>
#
# Run osascript with the given AppleScript body and target tty as argv[0].
# On exit 0: return 0 (caller skips fallback `open -b`).
# On exit 1 with empty stderr: log `applescript-failed no-tty-match`, return 1.
# On any other failure: classify via _notify_classify_osascript_err, log,
# return 1. Cleans up its stderr tmpfile in all branches.
_notify_dispatch_osascript() {
    local body="$1" target_tty="$2" project="$3" ntype="$4" sid="$5"
    local tmp
    tmp="${TMPDIR:-/tmp}/tms-osa-$$.err"
    local rc=0
    osascript -e "$body" -- "$target_tty" >/dev/null 2>"$tmp" || rc=$?
    if [[ "$rc" -eq 0 ]]; then
        rm -f "$tmp"
        return 0
    fi
    local stderr_text
    stderr_text=$(cat "$tmp" 2>/dev/null)
    rm -f "$tmp"
    local mode
    if [[ "$rc" -eq 1 ]] && [[ -z "$stderr_text" ]]; then
        mode="no-tty-match"
    else
        mode=$(_notify_classify_osascript_err "$stderr_text")
    fi
    notify_log_failure "applescript-failed" "$project" "$ntype" "$sid" "$mode"
    return 1
}

# --- notification hook entry point (cmd_notify_hook) --------------------

# cmd_notify_hook — subcommand body for `tms notify-hook`. Called by
# Claude Code's Notification hook with a JSON payload on stdin.
#
# The entire function body runs inside a subshell so that `set -euo
# pipefail`, the `trap ... ERR` handler, and variable/state mutations
# don't leak into the parent `bin/tms` process. Exit-code contract
# (FR-007 from feature 002): exits the subshell with status 0 on every
# branch; the parent `case` arm inherits that and exits 0 accordingly.
cmd_notify_hook() (
    set -euo pipefail

    # Trap: convert any unexpected error into a log entry; never block Claude Code.
    _hook_error_handler() {
        local exit_code="$?"
        notify_log_failure "hook-error" "-" "-" "-" "unexpected error at line $BASH_LINENO (exit $exit_code)" 2>/dev/null || true
        exit 0
    }
    trap '_hook_error_handler' ERR

    # --- read stdin ---
    # `cat` reads to EOF. Prior implementations tried to add a timeout
    # wrapper (`timeout 5 cat`) for defense-in-depth against a never-
    # closing pipe, but `timeout` is GNU coreutils — NOT on the typical
    # restricted PATH (e.g. /usr/bin:/bin) that Claude Code uses when
    # spawning hooks. When `timeout` isn't found, the wrapper silently
    # returned empty, dropping every payload. Claude Code's
    # `timeout: 10` in settings.json already bounds total hook runtime
    # server-side, so an inner timeout isn't needed anyway.
    local payload=""
    payload=$(cat)

    # --- parse-error branch ---
    if [[ -z "$payload" ]]; then
        notify_log_failure "parse-error" "-" "-" "-" "empty stdin"
        exit 0
    fi

    local hook_event_name
    hook_event_name=$(notify_parse_json_field "hook_event_name" "$payload")
    if [[ -z "$hook_event_name" ]] || [[ "$hook_event_name" != "Notification" ]]; then
        notify_log_failure "parse-error" "-" "-" "-" "$(printf '%.512s' "$payload")"
        exit 0
    fi

    # --- extract fields ---
    local cwd message notification_type session_id
    cwd=$(notify_parse_json_field "cwd" "$payload")
    message=$(notify_parse_json_field "message" "$payload")
    notification_type=$(notify_parse_json_field "notification_type" "$payload")
    session_id=$(notify_parse_json_field "session_id" "$payload")

    # Replace embedded newlines in message with spaces (FR-003)
    message="${message//$'\n'/ }"

    # Resolve real terminal bundle for click-time `open -b` foregrounding.
    # alerter defaults its --sender to com.apple.Terminal, which is the safe
    # delivery sender on macOS 26+, so we don't pass --sender ourselves.
    local term_bundle_id
    term_bundle_id=$(notify_resolve_term_bundle)

    # --- no-cwd branch ---
    if [[ -z "$cwd" ]]; then
        if command -v alerter >/dev/null 2>&1; then
            ( alerter --title "Claude Code" --message "${message:-Claude Code needs attention.}" --timeout 30 >/dev/null 2>&1 ) &
            disown 2>/dev/null || true
        fi
        notify_log_failure "no-cwd" "-" "$notification_type" "$session_id" "$message"
        exit 0
    fi

    # --- config load (lite — no full validation) ---
    # Hot path: full `config_load` does ~5N yq calls for per-project
    # validation and is the single biggest contributor to hook latency.
    # `config_load_lite` only sets CONFIG_FILE + verifies syntax
    # (~2 yq calls). The config is assumed well-formed at hook fire time
    # (other entry points like `tms start`/`list` run full validation
    # and would have caught issues earlier).
    if ! config_load_lite 2>/dev/null; then
        notify_log_failure "no-project-match" "-" "$notification_type" "$session_id" "config load failed; cwd=$cwd"
        exit 0
    fi

    # --- fast project resolution + notification settings (single yq call) ---
    # The previous implementation made ~80 yq calls across
    # notify_resolve_project_from_cwd + config_get_notifications_enabled
    # + config_get_notifications_sound (each doing per-project
    # _config_project_index iteration). At ~60ms per Python-yq startup,
    # that was 5+ seconds synchronous work in the hot path — blocking
    # Claude Code's interaction loop and violating SC-005 (<100ms p95
    # overhead). This fast path issues exactly TWO yq calls regardless
    # of project count, does the cwd match in bash, and lives within
    # the SC-005 budget.
    local projects_data global_sound
    projects_data=$(yq -r '.projects[]? | "\(.name)\t\(.dir)\t\(.notifications.enabled // true)\t\(.notifications.sound // "__ABSENT__")"' "$CONFIG_FILE" 2>/dev/null)
    global_sound=$(yq -r '.notifications.sound // ""' "$CONFIG_FILE" 2>/dev/null)
    # yq returns "null" as the literal string when the global .notifications.sound key is absent.
    [[ "$global_sound" == "null" ]] && global_sound=""

    local norm_cwd
    if [[ -d "$cwd" ]]; then
        norm_cwd=$(cd "$cwd" 2>/dev/null && pwd -P) || norm_cwd="$cwd"
    else
        norm_cwd="$cwd"
    fi

    local project_name="" proj_enabled="true" proj_sound_raw="__ABSENT__"
    local _pname _pdir _penabled _psound _expanded _norm_dir
    while IFS=$'\t' read -r _pname _pdir _penabled _psound; do
        [[ -z "$_pname" ]] && continue
        _expanded=$(expand_path "$_pdir")
        if [[ -d "$_expanded" ]]; then
            _norm_dir=$(cd "$_expanded" 2>/dev/null && pwd -P) || _norm_dir="$_expanded"
        else
            _norm_dir="$_expanded"
        fi
        if [[ "$norm_cwd" == "$_norm_dir" ]] || [[ "$norm_cwd" == "$_norm_dir/"* ]]; then
            project_name="$_pname"
            proj_enabled="$_penabled"
            proj_sound_raw="$_psound"
            break
        fi
    done <<< "$projects_data"

    # --- no-project-match branch ---
    if [[ -z "$project_name" ]]; then
        if command -v alerter >/dev/null 2>&1; then
            ( alerter --title "Claude Code" --message "${message:-Claude Code needs attention.}" --timeout 30 >/dev/null 2>&1 ) &
            disown 2>/dev/null || true
        fi
        notify_log_failure "no-project-match" "-" "$notification_type" "$session_id" "cwd=$cwd"
        exit 0
    fi

    # --- per-project opt-out ---
    if [[ "$proj_enabled" == "false" ]]; then
        exit 0
    fi

    # --- empty-message guard ---
    if [[ -z "$message" ]]; then
        message="Claude Code needs attention."
        notify_log_failure "empty-message" "$project_name" "$notification_type" "$session_id" "-"
    fi

    # --- alerter-missing check ---
    if ! command -v alerter >/dev/null 2>&1; then
        notify_log_failure "alerter-missing" "$project_name" "$notification_type" "$session_id" "$message"
        exit 0
    fi

    local tms_abs_path="$TMS_DIR/bin/tms"
    local log_path
    log_path=$(notify_log_path)

    # Resolve the notification sound: project-level present → use it
    # (empty string = explicit silence override); project-level absent
    # → fall back to global sound. Precedence matches the per-project
    # accessor we used before the fast-path rewrite.
    local notif_sound=""
    if [[ "$proj_sound_raw" != "__ABSENT__" ]]; then
        notif_sound="$proj_sound_raw"
    else
        notif_sound="$global_sound"
    fi

    # --- emit notification + dispatch click in a detached subshell ---
    # alerter blocks until user interaction or --timeout, then prints the
    # result to stdout. We background the whole sequence so the hook
    # returns immediately (FR-007, SC-005). On @CONTENTCLICKED we
    # foreground the user's terminal and run `tms switch <project>`.
    # On dismissal/timeout we exit silently. This is the macOS 26+-
    # compatible click mechanism (terminal-notifier's -execute does not
    # dispatch on recent macOS; see specs/002-.../research.md §7).
    #
    # --timeout 0 (no auto-close) so macOS's per-app "Persistent" alert
    # style preference (System Settings → Notifications → Terminal) is
    # honored end-to-end. A non-zero --timeout would force-close the
    # banner after that window, overriding the user's persistence
    # preference. To stop alerter processes from piling up while they
    # wait (each is a resident AppKit process ~30MB+), we pass
    # --group "$project_name": delivering a new banner for a project
    # removes that project's previous banner from Notification Center,
    # which trips the prior alerter's dismissal poll and makes it exit.
    # So at most one resident alerter per project survives, instead of
    # one per notification. The click action (switch to <project>) is
    # identical across a project's banners anyway, so only the latest is
    # useful.
    (
        local result
        local -a alerter_args=(
            --title "$project_name"
            --message "$message"
            --timeout 0
            --group "$project_name"
        )
        if [[ -n "$notif_sound" ]]; then
            alerter_args+=(--sound "$notif_sound")
        fi
        result=$(alerter "${alerter_args[@]}" 2>/dev/null) || result="@ERROR"

        case "$result" in
            @CONTENTCLICKED)
                # Feature 004: exact-tab selection via AppleScript on
                # iTerm2 / Terminal.app. Matches tmux client_tty against
                # the terminal's per-tab tty property. If the dispatch
                # succeeds, osascript's `activate` already raised the
                # app — skip the fallback `open -b` to avoid redundant
                # activation (research.md §8 happy-path optimization).
                local target_tty="" osa_handled=false osa_body=""
                target_tty=$(tmux list-clients -t "$project_name" -F '#{client_tty}' 2>/dev/null | head -1)
                if [[ -n "$target_tty" ]]; then
                    case "$term_bundle_id" in
                        com.googlecode.iterm2)
                            osa_body=$(_notify_iterm_applescript)
                            _notify_dispatch_osascript "$osa_body" "$target_tty" "$project_name" "$notification_type" "$session_id" && osa_handled=true
                            ;;
                        com.apple.Terminal)
                            osa_body=$(_notify_terminal_app_applescript)
                            _notify_dispatch_osascript "$osa_body" "$target_tty" "$project_name" "$notification_type" "$session_id" && osa_handled=true
                            ;;
                    esac
                fi
                if ! $osa_handled; then
                    open -b "$term_bundle_id" >/dev/null 2>&1 || true
                fi

                local switch_output=""
                if ! switch_output=$("$tms_abs_path" switch "$project_name" 2>&1); then
                    # Switch failed (typically: session not running). Log
                    # structured entry and fire a follow-up alerter so the
                    # user sees a visible reason instead of a silent failure.
                    notify_log_failure "switch-failed" "$project_name" "$notification_type" "$session_id" "$switch_output"
                    alerter \
                        --title "Claude Code — $project_name" \
                        --message "Session not running. Run 'tms start $project_name' to restart it." \
                        --timeout 10 \
                        >/dev/null 2>&1 || true
                fi
                ;;
            @TIMEOUT|@CLOSED)
                : # silent dismissal — no log entry, by design
                ;;
            *)
                notify_log_failure "alerter-failed" "$project_name" "$notification_type" "$session_id" "result=$result"
                ;;
        esac
    ) &
    disown 2>/dev/null || true

    exit 0
)

# --- test notification hook ----------------------------------------------

# cmd_test_hooks [--message <text>] [--project <name>]
#
# Fire a synthetic Claude Code Notification payload through cmd_notify_hook
# so the user can verify the full pipeline (banner delivery, sound, click-
# to-switch eligibility) without waiting for a real Claude Code event.
# Prints the resolved project + settings so the user can see what got
# applied before the banner appears.
cmd_test_hooks() {
    local message="tms notification test — if you see this banner, hooks work."
    local override_project=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --message=*)  message="${1#--message=}" ;;
            --message)    shift; message="${1:-}" ;;
            --project=*)  override_project="${1#--project=}" ;;
            --project)    shift; override_project="${1:-}" ;;
            *) die "unknown option '$1'. Usage: tms test-hooks [--message <text>] [--project <name>]" ;;
        esac
        shift || true
    done

    require_cmd alerter "brew install alerter"
    require_cmd jq "brew install jq"

    # Use config_load (full validation) so any malformed config surfaces
    # cleanly before the hook runs.
    config_load

    # Resolve project — either the user-supplied override, or via cwd.
    local project_name="" cwd="$PWD"
    if [[ -n "$override_project" ]]; then
        if ! config_project_exists "$override_project"; then
            die "project '$override_project' not found in configuration"
        fi
        project_name="$override_project"
        cwd=$(config_get_project_dir "$project_name")
    else
        project_name=$(notify_resolve_project_from_cwd "$cwd" 2>/dev/null || printf '')
    fi

    # Print what got resolved so the user sees the effective settings
    # *before* the banner fires (handy for debugging "why no sound?").
    printf 'Test notification pipeline:\n'
    printf '    cwd:     %s\n' "$cwd"
    if [[ -n "$project_name" ]]; then
        printf '    project: %s\n' "$project_name"
        local enabled sound
        enabled=$(config_get_notifications_enabled "$project_name" 2>/dev/null || printf 'true')
        sound=$(config_get_notifications_sound "$project_name" 2>/dev/null || printf '')
        printf '    enabled: %s' "$enabled"
        if [[ "$enabled" == "false" ]]; then
            printf '  (banner will be suppressed — project has opted out)'
        fi
        printf '\n'
        if [[ -n "$sound" ]]; then
            printf '    sound:   %s\n' "$sound"
        else
            printf '    sound:   (none — silent)\n'
        fi
    else
        printf '    project: (no match — hook will emit a plain banner, no click-to-switch)\n'
    fi
    printf '    message: %s\n' "$message"
    printf '\nFiring hook...\n'

    # Build a JSON payload matching Claude Code's Notification schema.
    # Using jq to get proper escaping for the message/cwd fields.
    local payload
    payload=$(jq -n \
        --arg cwd "$cwd" \
        --arg msg "$message" \
        '{
            hook_event_name: "Notification",
            cwd: $cwd,
            message: $msg,
            notification_type: "idle_prompt",
            session_id: "tms-test"
        }')

    printf '%s' "$payload" | cmd_notify_hook
    local rc=$?

    printf 'Hook returned exit=%d. Banner should appear within a second.\n' "$rc"
    printf 'If nothing appears, check the diagnostic log:\n    %s\n' "$(notify_log_path)"
}

# --- install / uninstall hooks -------------------------------------------

# _resolve_write_target <path>
#
# If <path> is a symlink, resolve it (following chains) and print the
# real file location. Otherwise print <path> unchanged. Used before
# atomic `.tmp` writes so that `mv .tmp real-file` updates the real
# target of a symlinked config instead of replacing the symlink itself
# with the tmp file.
#
# `mv tmp.json dest.json` when dest.json is a symlink replaces the
# symlink with tmp.json (POSIX rename semantics on symlinks). Users who
# manage ~/.claude/settings.json as a symlink to a dotfiles repo end up
# with their dotfiles disconnected. Pre-resolve the symlink so the write
# lands on the dotfiles file and the symlink stays intact.
_resolve_write_target() {
    local path="$1"
    if [[ ! -L "$path" ]]; then
        printf '%s\n' "$path"
        return 0
    fi
    # Walk the symlink chain manually so this works on macOS BSD readlink
    # (which doesn't support -f). Equivalent to `readlink -f` / `realpath`.
    local current="$path"
    local hop
    while [[ -L "$current" ]]; do
        hop=$(readlink "$current")
        if [[ "$hop" = /* ]]; then
            current="$hop"
        else
            current="$(cd "$(dirname "$current")" && pwd)/$hop"
        fi
    done
    printf '%s\n' "$current"
}

# _atomic_write <target> <content>
#
# Atomic write via .tmp + mv, resolving <target> through symlinks so
# symlinked config files (common for dotfiles setups) stay intact.
_atomic_write() {
    local target="$1"
    local content="$2"
    local real_target
    real_target=$(_resolve_write_target "$target")
    local tmp_file="${real_target}.tmp"
    if ! printf '%s\n' "$content" > "$tmp_file"; then
        die "failed to write ${real_target}; .tmp preserved at ${tmp_file}."
    fi
    if ! mv "$tmp_file" "$real_target"; then
        die "failed to move ${tmp_file} to ${real_target}; .tmp preserved at ${tmp_file}."
    fi
}

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
    # Register the hook command via the `tms install` default symlink
    # prefix (~/.local/bin/tms) rather than the repo's absolute path.
    # Rationale: if the user moves the repo, a single `tms install` run
    # updates the symlink and settings.json stays valid. Claude Code
    # expands `~/` via its shell-spawning invocation (same pattern as
    # the pre-existing `~/bin/slack-notify-channel.sh` entries users
    # typically have alongside). `bin/tms notify-hook` is a two-token
    # shell string: argv[0]=tms, argv[1]=notify-hook.
    tms_hook_path='~/.local/bin/tms notify-hook'

    # Warn if the symlink isn't actually set up at the registered path.
    # Claude Code would silently get ENOENT on the spawn otherwise.
    local resolved_hook="$HOME/.local/bin/tms"
    if [[ ! -x "$resolved_hook" ]]; then
        warn "expected tms symlink at $resolved_hook but did not find an executable there; run 'tms install' first, or settings.json will reference a dangling path."
    fi

    # Read existing settings or start from empty object
    local original_json
    if [[ -f "$settings_file" ]]; then
        if ! original_json=$(jq '.' "$settings_file" 2>/dev/null); then
            die "~/.claude/settings.json is not valid JSON; refusing to modify."
        fi
    else
        original_json="{}"
    fi

    # --- Feature 003 migration step (runs unconditionally) ---
    # Rewrite any .hooks.Notification[].hooks[].command ending in
    # `bin/tms-notify-hook` to the new `<TMS_DIR>/bin/tms notify-hook`
    # form. Idempotent: re-running on already-migrated JSON finds no
    # matches and produces an identical result (so no message is
    # printed). Runs before the install/uninstall branch so --uninstall
    # also benefits from the migration when locating entries.
    local migrated_json
    migrated_json=$(printf '%s' "$original_json" | jq --arg newcmd "$tms_hook_path" '
        .hooks.Notification = (
            (.hooks.Notification // [])
            | map(
                .hooks |= map(
                    if (.command | endswith("bin/tms-notify-hook"))
                    then .command = $newcmd
                    else .
                    end
                )
            )
        )
    ')
    if [[ "$original_json" != "$migrated_json" ]]; then
        printf 'Migrated tms-notify-hook entry to tms notify-hook.\n'
        # Persist the migrated JSON to disk immediately. Otherwise, when the
        # post-migration state matches "already installed", _install_hooks_
        # install short-circuits without writing, leaving the on-disk entry
        # pointing at the stale path.
        if [[ "$do_dry_run" == "false" ]]; then
            _atomic_write "$settings_file" "$migrated_json"
        fi
        original_json="$migrated_json"
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

    # Check if an entry with a command ending in "bin/tms notify-hook" already exists
    local existing_cmd existing_idx
    existing_idx=$(printf '%s' "$original_json" | \
        jq -r '(.hooks.Notification // []) | to_entries[] | select(.value.hooks[]?.command | endswith("bin/tms notify-hook")) | .key' \
        2>/dev/null | head -1)

    local new_json action_msg

    if [[ -n "$existing_idx" ]]; then
        existing_cmd=$(printf '%s' "$original_json" | \
            jq -r --argjson idx "$existing_idx" \
            '(.hooks.Notification[$idx].hooks[] | select(.command | endswith("bin/tms notify-hook"))).command' \
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

    _atomic_write "$settings_file" "$new_json"

    printf '%s\n' "$action_msg"
    _install_hooks_probe "$tms_hook_path"
}

_install_hooks_uninstall() {
    local original_json="$1" settings_file="$2" tms_hook_path="$3" do_dry_run="$4"

    # Check if any tms entry exists
    local has_entry
    has_entry=$(printf '%s' "$original_json" | \
        jq -r '(.hooks.Notification // [])[] | .hooks[]? | select(.command | endswith("bin/tms notify-hook")) | .command' \
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
                select(.hooks | map(select(.command | endswith("bin/tms notify-hook"))) | length == 0)
            ] |
            if (.hooks.Notification | length) == 0 then del(.hooks.Notification) else . end
        else . end
    ')

    if [[ "$do_dry_run" == "true" ]]; then
        diff -u <(printf '%s\n' "$original_json") <(printf '%s\n' "$new_json") || true
        return 0
    fi

    _atomic_write "$settings_file" "$new_json"

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
