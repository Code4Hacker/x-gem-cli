#!/bin/bash
# xgem shared utilities — os/arch detection, confirmation prompts, command checks.
# Depends on lib/logger.sh being sourced first.

: "${XGEM_YES:=0}"
: "${XGEM_DRY_RUN:=0}"

# detect_os -> darwin | linux | unknown
detect_os() {
    case "$(uname -s)" in
        Darwin) echo "darwin" ;;
        Linux)  echo "linux" ;;
        *)      echo "unknown" ;;
    esac
}

# detect_arch -> arm64 | x86_64 | <raw uname -m>
detect_arch() {
    uname -m
}

# is_apple_silicon -> 0 (true) if darwin + arm64, 1 otherwise
is_apple_silicon() {
    [ "$(detect_os)" = "darwin" ] && [ "$(detect_arch)" = "arm64" ]
}

# has_cmd <name> -> 0/1, no output
has_cmd() {
    command -v "$1" >/dev/null 2>&1
}

# require_cmd <name> [install-hint]
require_cmd() {
    local name=$1
    local hint=${2:-}
    if ! has_cmd "$name"; then
        if [ -n "$hint" ]; then
            die "'$name' is required but not found. $hint"
        else
            die "'$name' is required but not found in PATH."
        fi
    fi
}

# confirm "prompt text" -> 0 if approved, 1 otherwise
# Honors XGEM_YES=1 (from --yes) to auto-approve, and always returns 1
# (declines) under XGEM_DRY_RUN so callers never apply changes in dry-run mode.
confirm() {
    local prompt=$1
    if [ "$XGEM_DRY_RUN" = "1" ]; then
        log_info "(dry-run) would prompt: $prompt"
        return 1
    fi
    if [ "$XGEM_YES" = "1" ]; then
        log_debug "auto-confirmed (--yes): $prompt"
        return 0
    fi
    local reply
    read -r -p "$prompt [y/N]: " reply
    [[ "$reply" == "y" || "$reply" == "Y" ]]
}
