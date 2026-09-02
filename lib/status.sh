#!/bin/bash
# xgem status: a one-screen dashboard across every project xgem has ever
# scaffolded, so a developer doesn't have to `cd` into each one just to see
# what's dirty. Depends on lib/logger.sh, lib/registry.sh.

# _status_row <path> — prints one tab-separated row: path, branch, dirty
# count, ahead/behind, frameworks. Run in a subshell so `cd` never leaks.
_status_row() {
    local path=$1
    (
        cd "$path" || exit 0
        local branch dirty ahead_behind frameworks
        branch=$(git branch --show-current 2>/dev/null)
        [ -n "$branch" ] || branch="-"
        dirty=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')
        ahead_behind=$(git rev-list --left-right --count '@{u}...HEAD' 2>/dev/null | awk '{print "-"$1" +"$2}')
        [ -n "$ahead_behind" ] || ahead_behind="-"
        frameworks=$(ls "$CONFIG_DIR" 2>/dev/null | tr '\n' ',' | sed 's/,$//')
        [ -n "$frameworks" ] || frameworks="-"
        printf '%s\t%s\t%s\t%s\t%s\n' "$path" "$branch" "$dirty" "$ahead_behind" "$frameworks"
    )
}

cmd_status() {
    local -a projects=()
    while IFS= read -r p; do
        [ -n "$p" ] && projects+=("$p")
    done < <(registry_list)

    if [ ${#projects[@]} -eq 0 ]; then
        log_info "No xgem-tracked projects found yet — run 'xgem init' in a project to start tracking it."
        return 0
    fi

    printf '%-45s %-20s %-6s %-10s %s\n' "PROJECT" "BRANCH" "DIRTY" "AHEAD/BEHIND" "FRAMEWORKS"
    local p row
    for p in "${projects[@]}"; do
        row=$(_status_row "$p")
        IFS=$'\t' read -r path branch dirty ahead_behind frameworks <<< "$row"
        printf '%-45s %-20s %-6s %-10s %s\n' "$path" "$branch" "$dirty" "$ahead_behind" "$frameworks"
    done
}
