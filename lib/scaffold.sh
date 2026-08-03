#!/bin/bash
# xgem generic scaffold engine for frameworks whose automation is just a
# canned script (node, python, react/vue/angular, go, rust, docker, swift,
# and flutter's on-disk copies) — one module driven by template files
# instead of near-duplicate per-framework code.
#
# Flutter's `xgem run flutter <script>` is intercepted earlier by
# lib/flutter.sh's native commands (see flutter_native_command_exists in
# bin/xgem's dispatch); the flutter templates here still get scaffolded to
# `.xgem-automate/flutter/` for manual use and documentation parity.
#
# Depends on lib/logger.sh and XGEM_HOME (set by bin/xgem).

ALL_FRAMEWORKS=(flutter node python react vue angular next go rust docker swift)

# _package_json_has_script <script> — checks the CURRENT directory's
# package.json, not a guess. Used to only offer lint/test automation when
# the project actually has those scripts, instead of always generating
# scripts that fail with "Missing script" on projects that don't.
_package_json_has_script() {
    [ -f package.json ] || return 1
    grep -qE "\"$1\"[[:space:]]*:" package.json 2>/dev/null
}

framework_scripts() {
    case "$1" in
        flutter) echo "hard-clean build build-runner" ;;
        node)
            local scripts="hard-clean build start"
            _package_json_has_script lint && scripts="$scripts lint"
            _package_json_has_script test && scripts="$scripts test"
            echo "$scripts"
            ;;
        python)  echo "hard-clean install" ;;
        react|vue|angular|next)
            local scripts="hard-clean build dev"
            _package_json_has_script lint && scripts="$scripts lint"
            _package_json_has_script test && scripts="$scripts test"
            echo "$scripts"
            ;;
        go)      echo "hard-clean build" ;;
        rust)    echo "hard-clean build" ;;
        docker)  echo "hard-clean build-up" ;;
        swift)   echo "hard-clean build" ;;
        *) return 1 ;;
    esac
}

_scaffold_template_dir() {
    local framework=$1
    case "$framework" in
        react|vue|angular|next) echo "$XGEM_HOME/templates/webframework" ;;
        *)                      echo "$XGEM_HOME/templates/$framework" ;;
    esac
}

# scaffold_inject_templates <framework> <config_dir>
scaffold_inject_templates() {
    local framework=$1
    local config_dir=$2
    local scripts src_dir dest_dir script

    scripts=$(framework_scripts "$framework") || die "Unknown framework '$framework'."
    src_dir=$(_scaffold_template_dir "$framework")
    dest_dir="$config_dir/$framework"
    mkdir -p "$dest_dir"

    for script in $scripts; do
        local src="$src_dir/${script}.sh.tmpl"
        local dest="$dest_dir/${script}.sh"
        if [ ! -f "$src" ]; then
            log_warn "Missing template $src, skipping."
            continue
        fi
        sed "s/__FRAMEWORK__/$framework/g" "$src" > "$dest"
        chmod +x "$dest"
    done
}

# scaffold_run_script <framework> <script> <config_dir>
scaffold_run_script() {
    local framework=$1
    local script=$2
    local config_dir=$3
    local target="$config_dir/$framework/${script}.sh"

    if [ -f "$target" ]; then
        log_info "Running script '$script' for $framework..."
        bash "$target"
    else
        log_error "Script not found at $target"
        if [ -d "$config_dir/$framework" ]; then
            echo "Available scripts in '$framework':"
            ls "$config_dir/$framework" | sed 's/\.sh$//' | sed 's/^/  - /'
        fi
        exit 1
    fi
}

scaffold_get_remaining_frameworks() {
    local config_dir=$1
    REMAINING_FWS=()
    local fw
    for fw in "${ALL_FRAMEWORKS[@]}"; do
        [ -d "$config_dir/$fw" ] || REMAINING_FWS+=("$fw")
    done
}
