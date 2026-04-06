#!/usr/bin/env bash
# utils.sh — Shared utilities for tms

# Colors (disabled if stdout is not a terminal)
if [[ -t 1 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[0;33m'
    BOLD='\033[1m'
    DIM='\033[2m'
    RESET='\033[0m'
else
    RED=''
    GREEN=''
    YELLOW=''
    BOLD=''
    DIM=''
    RESET=''
fi

# Print error message to stderr and exit
die() {
    printf "${RED}Error: %s${RESET}\n" "$1" >&2
    exit 1
}

# Print warning to stderr
warn() {
    printf "${YELLOW}Warning: %s${RESET}\n" "$1" >&2
}

# Print info message
info() {
    printf "%s\n" "$1"
}

# Resolve ~ in paths to actual home directory
expand_path() {
    local path="$1"
    if [[ "$path" == "~"* ]]; then
        path="${HOME}${path#\~}"
    fi
    echo "$path"
}

# Check if a command exists
require_cmd() {
    if ! command -v "$1" &>/dev/null; then
        die "'$1' is required but not found in PATH"
    fi
}

# Get the tms config directory
config_dir() {
    echo "${TMS_CONFIG_DIR:-${HOME}/.config/tmux-session-manager}"
}

# Get the config file path
config_file() {
    echo "$(config_dir)/projects.yml"
}
