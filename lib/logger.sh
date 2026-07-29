#!/bin/bash
# xgem logger — consistent log levels + verbose/debug mode.
# Sourced by bin/xgem before any other lib module.

: "${XGEM_VERBOSE:=0}"

_c_red=$'\033[31m'
_c_green=$'\033[32m'
_c_yellow=$'\033[33m'
_c_blue=$'\033[1;34m'
_c_gray=$'\033[90m'
_c_reset=$'\033[0m'

log_info()    { echo -e "${_c_blue}[INFO]${_c_reset} $*"; }
log_success() { echo -e "${_c_green}[ OK ]${_c_reset} $*"; }
log_warn()    { echo -e "${_c_yellow}[WARN]${_c_reset} $*" >&2; }
log_error()   { echo -e "${_c_red}[FAIL]${_c_reset} $*" >&2; }

log_debug() {
    [ "$XGEM_VERBOSE" = "1" ] || return 0
    echo -e "${_c_gray}[DBG ] $*${_c_reset}" >&2
}

# die <message> [exit_code]
die() {
    log_error "$1"
    exit "${2:-1}"
}
