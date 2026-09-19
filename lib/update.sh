#!/bin/bash
# xgem update [tool]: show which installed toolchains have newer versions
# and apply the ones you approve.
# Depends on lib/logger.sh, lib/utils.sh, lib/toolchain.sh.

_update_one() {
    local tool=$1 explicit=$2 version latest cmd

    if ! tool_resolve "$tool"; then
        if [ "$explicit" = "1" ]; then
            tool_ensure "$tool"
        fi
        return 0
    fi

    version=$(tool_version_of "$tool")
    latest=$(XGEM_NO_NETWORK=1 tool_latest "$tool")

    if [ -z "$latest" ]; then
        [ "$explicit" = "1" ] && log_warn "Couldn't determine the latest $(tool_display "$tool") version (offline, or no version source for a $TOOL_MANAGER install)."
        return 0
    fi
    if [ -z "$version" ] || ! _tool_ver_lt "$version" "$latest"; then
        [ "$explicit" = "1" ] && log_success "$(tool_display "$tool") ${version:-} is up to date."
        return 0
    fi

    echo ""
    log_info "$(tool_display "$tool"): $version -> $latest"
    cmd=$(tool_update_cmd "$tool" "$latest")
    if [ -z "$cmd" ]; then
        echo "  No automated update route for this install ($TOOL_MANAGER). Download: $(tool_url "$tool")"
        return 0
    fi

    echo "  Update command: $cmd"
    confirm "Update $(tool_display "$tool") to $latest?" || return 0
    if ! bash -c "$cmd"; then
        log_error "Update failed (see output above)."
        return 0
    fi
    log_success "$(tool_display "$tool") update finished."

    if [ "$tool" = "flutter" ] && [ "$TOOL_MANAGER" = "fvm" ]; then
        confirm "Make Flutter $latest your global default (fvm global)?" && fvm global "$latest"
        if _tool_find_up .fvmrc >/dev/null || _tool_find_up .fvm/fvm_config.json >/dev/null; then
            confirm "Also pin $latest for the project in this directory (fvm use)?" && fvm use "$latest"
        fi
    fi
}

cmd_update() {
    local target=${1:-} t

    if [ -n "$target" ]; then
        tool_known "$target" || die "Unknown tool '$target'. Known: flutter node python3 go cargo docker git gh fvm swift"
        _update_one "$(_tool_canon "$target")" 1
        return 0
    fi

    if [ "$XGEM_NO_NETWORK" != "1" ]; then
        log_info "Checking installed tools for updates..."
        for t in flutter node cargo go fvm gh git docker python3; do
            ( tool_resolve "$t" && tool_latest "$t" ) >/dev/null 2>&1 &
        done
        wait
    fi

    for t in flutter node cargo go fvm gh git docker python3; do
        _update_one "$t" 0
    done
    echo ""
    log_success "Update check finished. Run 'xgem doctor' for the full toolchain report."
}
