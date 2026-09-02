#!/bin/bash
# xgem's global (cross-project) registry: which directories have been
# scaffolded with `xgem init`/`xgem add`, so `xgem status` can find them
# without the user having to remember or list them by hand.
# Depends on lib/logger.sh.

REGISTRY_FILE="${XGEM_REGISTRY_FILE:-$HOME/.xgem/projects}"

registry_add() {
    local path=$1
    mkdir -p "$(dirname "$REGISTRY_FILE")"
    touch "$REGISTRY_FILE"
    grep -qxF "$path" "$REGISTRY_FILE" || echo "$path" >> "$REGISTRY_FILE"
}

registry_remove() {
    local path=$1
    [ -f "$REGISTRY_FILE" ] || return 0
    local tmp
    tmp=$(mktemp)
    grep -vxF "$path" "$REGISTRY_FILE" > "$tmp" && mv "$tmp" "$REGISTRY_FILE"
}

# registry_list — prints one project path per line, pruning (and rewriting
# the registry for) any entry that no longer exists or is no longer
# xgem-tracked.
registry_list() {
    [ -f "$REGISTRY_FILE" ] || return 0
    local -a live=()
    local path
    while IFS= read -r path; do
        [ -n "$path" ] || continue
        if [ -d "$path/$CONFIG_DIR" ]; then
            live+=("$path")
        fi
    done < "$REGISTRY_FILE"

    printf '%s\n' "${live[@]}"

    local count
    count=$(wc -l < "$REGISTRY_FILE" | tr -d ' ')
    if [ "$count" != "${#live[@]}" ]; then
        printf '%s\n' "${live[@]}" > "$REGISTRY_FILE"
    fi
}
