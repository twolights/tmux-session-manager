# bash completion for tms
#
# Install:
#   mkdir -p ~/.local/share/bash-completion/completions
#   ln -sf "$(pwd)/completion/tms.bash" \
#       ~/.local/share/bash-completion/completions/tms
#
# Then restart your shell (or `source ~/.bashrc`).

# Print the list of project names from projects.yml. Uses plain sed rather
# than yq to keep tab completion responsive — Python-yq has a ~200ms
# startup cost. The regex matches the canonical tms YAML shape:
#     projects:
#       - name: my-project
# Specifically matches exactly 2 leading spaces + "- name:" so that
# server entries (at 6-space indent inside `servers:`) don't show up.
# Unusual indentation won't match and those projects won't autocomplete,
# but typing the name manually still works.
_tms_projects() {
    local config="${TMS_CONFIG_DIR:-$HOME/.config/tmux-session-manager}/projects.yml"
    [[ -f "$config" ]] || return 0
    sed -n 's/^  - name:[[:space:]]*\([^[:space:]]*\).*/\1/p' "$config"
}

_tms() {
    local cur prev
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"

    local subcommands="start stop list switch install install-hooks test-hooks help"

    # First positional: subcommand.
    if [[ $COMP_CWORD -eq 1 ]]; then
        COMPREPLY=( $(compgen -W "$subcommands" -- "$cur") )
        return
    fi

    local subcmd="${COMP_WORDS[1]}"
    case "$subcmd" in
        start|stop|switch)
            if [[ $COMP_CWORD -eq 2 ]]; then
                local projects
                projects=$(_tms_projects)
                COMPREPLY=( $(compgen -W "$projects" -- "$cur") )
            fi
            ;;
        install)
            # --prefix=<dir> gets file-completion; bare flags otherwise.
            case "$cur" in
                --prefix=*)
                    local prefix_val="${cur#--prefix=}"
                    COMPREPLY=( $(compgen -d -- "$prefix_val" | sed "s|^|--prefix=|") )
                    ;;
                *)
                    COMPREPLY=( $(compgen -W "--prefix= --uninstall --dry-run" -- "$cur") )
                    ;;
            esac
            ;;
        install-hooks)
            COMPREPLY=( $(compgen -W "--uninstall --dry-run" -- "$cur") )
            ;;
        test-hooks)
            case "$prev" in
                --project)
                    local projects
                    projects=$(_tms_projects)
                    COMPREPLY=( $(compgen -W "$projects" -- "$cur") )
                    ;;
                --message)
                    # Freeform string — no completion.
                    COMPREPLY=()
                    ;;
                *)
                    COMPREPLY=( $(compgen -W "--message --project" -- "$cur") )
                    ;;
            esac
            ;;
    esac
}

complete -F _tms tms
