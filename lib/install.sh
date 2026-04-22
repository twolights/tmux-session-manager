#!/usr/bin/env bash
# install.sh — tms install/uninstall + OS-aware dependency hints

# --- flag parsing --------------------------------------------------------

# _install_parse_flags <argv...>
#
# Parse --prefix=<dir>, --uninstall, --dry-run. Sets module globals:
#   _INSTALL_PREFIX     (string; default "~/.local/bin")
#   _INSTALL_UNINSTALL  (bool; "true"/"false")
#   _INSTALL_DRY_RUN    (bool; "true"/"false")
_install_parse_flags() {
    _INSTALL_PREFIX="$HOME/.local/bin"
    _INSTALL_UNINSTALL="false"
    _INSTALL_DRY_RUN="false"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --prefix=*)    _INSTALL_PREFIX="${1#--prefix=}" ;;
            --uninstall)   _INSTALL_UNINSTALL="true" ;;
            --dry-run)     _INSTALL_DRY_RUN="true" ;;
            *) die "unknown flag '$1'. Usage: tms install [--prefix=<dir>] [--uninstall] [--dry-run]" ;;
        esac
        shift
    done
}

# --- OS detection --------------------------------------------------------

# _install_detect_os
#
# Print one of: macos | linux | other
_install_detect_os() {
    case "$(uname -s 2>/dev/null)" in
        Darwin) printf '%s\n' "macos" ;;
        Linux)  printf '%s\n' "linux" ;;
        *)      printf '%s\n' "other" ;;
    esac
}

# _install_detect_pkg_manager
#
# Probe the host for a supported Linux package manager in priority order:
# apt → dnf → pacman → zypper → apk. First match wins. Print the detected
# name (lowercase, e.g. "apt"); print empty if none matched. Only meaningful
# when _OS_BUCKET == linux — callers may skip the probe on non-Linux hosts.
_install_detect_pkg_manager() {
    local mgr
    for mgr in apt dnf pacman zypper apk; do
        if command -v "$mgr" >/dev/null 2>&1; then
            printf '%s\n' "$mgr"
            return 0
        fi
    done
    # Also try apt-get as a fallback for systems where `apt` is not in PATH
    # but `apt-get` is.
    if command -v apt-get >/dev/null 2>&1; then
        printf '%s\n' "apt"
        return 0
    fi
    printf '%s\n' ""
}

# --- prefix resolution --------------------------------------------------

# _install_resolve_prefix <raw-prefix>
#
# Expand ~ via utils.sh expand_path, create the dir if absent (mkdir -p,
# mode 0755), and print the resolved absolute path. Dies on mkdir failure.
_install_resolve_prefix() {
    local raw="$1"
    local expanded
    expanded=$(expand_path "$raw")

    if [[ ! -d "$expanded" ]]; then
        if ! mkdir -p -m 0755 "$expanded" 2>/dev/null; then
            die "could not create install prefix at $expanded."
        fi
    fi

    # Realpath-normalize to handle trailing slashes / symlinks in the prefix
    # path itself. POSIX portable: cd + pwd -P.
    (cd "$expanded" 2>/dev/null && pwd -P) || printf '%s\n' "$expanded"
}

# --- symlink classification (T005) ---------------------------------------

# _install_classify_target <target-path> <expected-source>
#
# Returns one of: absent | same-symlink | tms-mismatch-symlink |
# unrelated-symlink | non-symlink
_install_classify_target() {
    local target="$1"
    local expected="$2"

    if [[ -L "$target" ]]; then
        local current
        current=$(readlink "$target")
        if [[ "$current" == "$expected" ]]; then
            printf '%s\n' "same-symlink"
        elif [[ "$current" == */bin/tms ]]; then
            # Points at a tms checkout (possibly moved).
            printf '%s\n' "tms-mismatch-symlink"
        else
            printf '%s\n' "unrelated-symlink"
        fi
        return 0
    fi

    if [[ -e "$target" ]]; then
        printf '%s\n' "non-symlink"
        return 0
    fi

    printf '%s\n' "absent"
}

# --- symlink writer (T006) -----------------------------------------------

# _install_symlink — create or update the tms symlink at _INSTALL_PREFIX/tms
# Honors _INSTALL_DRY_RUN (prints "[dry-run] would ..." instead of acting).
_install_symlink() {
    local target="$_INSTALL_PREFIX/tms"
    local source="$TMS_DIR/bin/tms"
    local state
    state=$(_install_classify_target "$target" "$source")

    case "$state" in
        absent)
            if [[ "$_INSTALL_DRY_RUN" == "true" ]]; then
                printf '[dry-run] would symlink %s → %s\n' "$target" "$source"
            else
                ln -s "$source" "$target" || die "failed to create symlink at $target"
                printf 'Installed tms at %s.\n' "$target"
            fi
            ;;
        same-symlink)
            printf 'tms is already installed at %s.\n' "$target"
            ;;
        tms-mismatch-symlink)
            local old
            old=$(readlink "$target")
            if [[ "$_INSTALL_DRY_RUN" == "true" ]]; then
                printf '[dry-run] would update symlink %s: %s → %s\n' "$target" "$old" "$source"
            else
                rm "$target" && ln -s "$source" "$target" \
                    || die "failed to update symlink at $target"
                printf 'Updated tms path: %s → %s\n' "$old" "$source"
            fi
            ;;
        unrelated-symlink)
            local current
            current=$(readlink "$target")
            die "$target is a symlink to $current which does not look like a tms checkout. Refusing to overwrite. Use --prefix=<dir> to install elsewhere."
            ;;
        non-symlink)
            die "$target exists and is not a symlink — refusing to overwrite. Move it aside or use --prefix=<dir>."
            ;;
    esac
}

# --- config bootstrap (T007) ---------------------------------------------

# _install_bootstrap_config — ensure ~/.config/tmux-session-manager/projects.yml
# exists, copying from config/projects.example.yml if absent. Never
# overwrites an existing file.
_install_bootstrap_config() {
    local cdir
    cdir="$(config_dir)"
    local target="$cdir/projects.yml"
    local source="$TMS_DIR/config/projects.example.yml"

    if [[ ! -d "$cdir" ]]; then
        if [[ "$_INSTALL_DRY_RUN" == "true" ]]; then
            printf '[dry-run] would create config dir %s\n' "$cdir"
        else
            mkdir -p -m 0755 "$cdir" || die "failed to create config dir $cdir"
        fi
    fi

    if [[ -f "$target" ]]; then
        printf 'Config already present at %s.\n' "$target"
        return 0
    fi

    if [[ "$_INSTALL_DRY_RUN" == "true" ]]; then
        printf '[dry-run] would copy %s → %s\n' "$source" "$target"
    else
        cp "$source" "$target" || die "failed to copy $source to $target"
        printf 'Created %s from example.\n' "$target"
    fi
}

# --- dependency probe (T008) ---------------------------------------------

# _install_check_deps — probe required + optional deps. Populates:
#   _MISSING_REQUIRED   (space-separated names: tmux/yq/fzf that are absent)
#   _MISSING_OPTIONAL   (space-separated names: alerter/jq — macOS only)
_install_check_deps() {
    _MISSING_REQUIRED=""
    _MISSING_OPTIONAL=""

    local dep
    for dep in tmux yq fzf; do
        if ! command -v "$dep" >/dev/null 2>&1; then
            _MISSING_REQUIRED="${_MISSING_REQUIRED:+$_MISSING_REQUIRED }$dep"
        fi
    done

    if [[ "$_OS_BUCKET" == "macos" ]]; then
        for dep in alerter jq; do
            if ! command -v "$dep" >/dev/null 2>&1; then
                _MISSING_OPTIONAL="${_MISSING_OPTIONAL:+$_MISSING_OPTIONAL }$dep"
            fi
        done
    fi
}

# --- hint rendering ------------------------------------------------------

# _install_hint_for <pkg> — print a single install-command line for <pkg>
# based on _OS_BUCKET (and _PKG_MGR for linux). The yq case always uses
# pip3 install yq regardless of OS, with a trailing Python-yq note.
_install_hint_for() {
    local pkg="$1"

    if [[ "$pkg" == "yq" ]]; then
        printf '    pip3 install yq    # (Python yq, not mikefarah/yq — see README)\n'
        return 0
    fi

    case "$_OS_BUCKET" in
        macos)
            printf '    brew install %s\n' "$pkg"
            ;;
        linux)
            case "${_PKG_MGR:-}" in
                apt)    printf '    sudo apt install %s\n' "$pkg" ;;
                dnf)    printf '    sudo dnf install %s\n' "$pkg" ;;
                pacman) printf '    sudo pacman -S %s\n' "$pkg" ;;
                zypper) printf '    sudo zypper install %s\n' "$pkg" ;;
                apk)    printf '    sudo apk add %s\n' "$pkg" ;;
                *)      printf '    Install %s via your distro'\''s package manager.\n' "$pkg" ;;
            esac
            ;;
        *)
            printf '    Install %s via your package manager.\n' "$pkg"
            ;;
    esac
}

# _install_print_hints — render the dep-hint block. Uses _MISSING_REQUIRED
# and _MISSING_OPTIONAL populated by _install_check_deps.
_install_print_hints() {
    local printed_something="false"

    if [[ -n "$_MISSING_REQUIRED" ]]; then
        printf '\nMissing dependencies — install with:\n\n'
        local pkg
        for pkg in $_MISSING_REQUIRED; do
            _install_hint_for "$pkg"
        done
        printed_something="true"
    fi

    if [[ "$_OS_BUCKET" == "macos" ]] && [[ -n "$_MISSING_OPTIONAL" ]]; then
        printf '\nOptional dependencies for Claude notifications — install with:\n\n'
        local pkg
        for pkg in $_MISSING_OPTIONAL; do
            _install_hint_for "$pkg"
        done
        printed_something="true"
    fi

    # Non-macOS footer (FR-006): state that notifications are macOS-only,
    # replacing where optional-deps would go on macOS.
    if [[ "$_OS_BUCKET" != "macos" ]]; then
        printf '\nNote: Claude Code notification banners are macOS-only in this version.\n'
        printed_something="true"
    fi

    # Suppress the variable-not-used shellcheck nag.
    [[ "$printed_something" == "true" ]] || true
}

# --- PATH-on-prefix check (T010) -----------------------------------------

# _install_check_path — warn if _INSTALL_PREFIX is not on $PATH.
_install_check_path() {
    local prefix_abs="$_INSTALL_PREFIX"  # already realpath-normalized
    local entry norm_entry
    local IFS=":"
    for entry in $PATH; do
        [[ -z "$entry" ]] && continue
        if [[ -d "$entry" ]]; then
            norm_entry=$(cd "$entry" 2>/dev/null && pwd -P) || norm_entry="$entry"
        else
            norm_entry="$entry"
        fi
        if [[ "$norm_entry" == "$prefix_abs" ]]; then
            return 0  # on PATH, no warning
        fi
    done

    cat <<WARN

Note: $prefix_abs is not on your \$PATH.
To use \`tms\` from any shell, add this line to your shell rc (~/.zshrc, ~/.bashrc, etc.):

    export PATH="$prefix_abs:\$PATH"
WARN
}

# --- next-step block (T011) ----------------------------------------------

# _install_print_next_steps — final user-facing guidance.
_install_print_next_steps() {
    local cdir
    cdir="$(config_dir)"
    printf '\nNext steps:\n'
    printf '    1. Edit %s/projects.yml to add your projects.\n' "$cdir"
    if [[ "$_OS_BUCKET" == "macos" ]]; then
        printf '    2. (macOS only) Run `tms install-hooks` to enable Claude Code notifications.\n'
    fi
}

# --- uninstall (T013) ----------------------------------------------------

# _install_uninstall_symlink — remove the tms symlink, preserving config.
_install_uninstall_symlink() {
    local target="$_INSTALL_PREFIX/tms"
    local source="$TMS_DIR/bin/tms"
    local state
    state=$(_install_classify_target "$target" "$source")

    case "$state" in
        absent)
            printf 'No tms install found at %s.\n' "$target"
            return 0
            ;;
        same-symlink)
            if [[ "$_INSTALL_DRY_RUN" == "true" ]]; then
                printf '[dry-run] would remove symlink %s\n' "$target"
            else
                rm "$target" || die "failed to remove $target"
                printf 'Removed tms symlink at %s.\n' "$target"
            fi
            ;;
        tms-mismatch-symlink)
            local old
            old=$(readlink "$target")
            if [[ "$_INSTALL_DRY_RUN" == "true" ]]; then
                printf '[dry-run] would remove symlink %s (pointing at %s)\n' "$target" "$old"
            else
                rm "$target" || die "failed to remove $target"
                printf 'Removed tms symlink at %s (was pointing at %s).\n' "$target" "$old"
            fi
            ;;
        unrelated-symlink)
            local current
            current=$(readlink "$target")
            die "$target is a symlink to $current which does not look like a tms checkout. Refusing to remove. Remove it manually if needed."
            ;;
        non-symlink)
            die "$target exists and is not a symlink — not a tms install. Leaving it alone."
            ;;
    esac
}

# --- top-level orchestrators (T012, T013) --------------------------------

# cmd_install — entry point for `tms install [--prefix=<dir>] [--uninstall] [--dry-run]`
cmd_install() {
    _install_parse_flags "$@"
    _OS_BUCKET=$(_install_detect_os)
    _INSTALL_PREFIX=$(_install_resolve_prefix "$_INSTALL_PREFIX")

    # Only set _PKG_MGR on Linux (T020 fills it in; stays empty elsewhere).
    if [[ "$_OS_BUCKET" == "linux" ]] && declare -F _install_detect_pkg_manager >/dev/null; then
        _PKG_MGR=$(_install_detect_pkg_manager)
    else
        _PKG_MGR=""
    fi

    if [[ "$_INSTALL_UNINSTALL" == "true" ]]; then
        _install_uninstall_symlink
        printf '\nNote: Claude Code hook registration (if any) is unchanged. Run `tms install-hooks --uninstall` to remove it.\n'
        return 0
    fi

    _install_symlink
    _install_bootstrap_config
    _install_check_deps
    _install_print_hints
    _install_check_path
    _install_print_next_steps
}

