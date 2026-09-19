#!/bin/bash
# xgem ci: run the checks for every configured framework before you push,
# so a CI failure gets caught locally first.
# Depends on lib/logger.sh, lib/utils.sh.

# CI=true and a closed stdin make test runners (Vitest, Jest, Angular) run
# once and exit instead of entering watch mode or waiting on a prompt.
# Records into results/overall_status of the calling cmd_ci.
_ci_run_step() {
    local label=$1
    shift
    log_info "Running $label..."
    if CI=true "$@" < /dev/null; then
        results+=("PASS  $label")
    else
        results+=("FAIL  $label")
        overall_status=1
    fi
}

_ci_flutter() {
    if ! tool_ensure flutter; then
        results+=("SKIP  flutter (flutter not found)")
        return 0
    fi
    _ci_run_step "flutter analyze" flutter analyze
    if [ -d test ]; then
        _ci_run_step "flutter test" flutter test
    else
        results+=("SKIP  flutter test (no test/ directory)")
    fi
}

cmd_ci() {
    [ -d "$CONFIG_DIR" ] || die "No $CONFIG_DIR found — run 'xgem init' or 'xgem add' first."

    local -a steps=(lint test build)
    local -a results=()
    local overall_status=0
    local fw_dir fw step

    for fw_dir in "$CONFIG_DIR"/*/; do
        [ -d "$fw_dir" ] || continue
        fw=$(basename "$fw_dir")

        if [ "$fw" = "flutter" ]; then
            _ci_flutter
            continue
        fi

        local needed
        needed=$(fw_required_tool "$fw")
        if [ -n "$needed" ] && [ "$fw" != "docker" ] && ! tool_ensure "$needed"; then
            results+=("SKIP  $fw ($needed not found)")
            continue
        fi

        for step in "${steps[@]}"; do
            [ -f "$CONFIG_DIR/$fw/$step.sh" ] || continue
            _ci_run_step "$fw $step" bash "$CONFIG_DIR/$fw/$step.sh"
        done
    done

    if [ ${#results[@]} -eq 0 ]; then
        log_warn "No checks found under $CONFIG_DIR to run."
        return 0
    fi

    echo ""
    echo "=== xgem ci summary ==="
    printf '%s\n' "${results[@]}"

    if [ "$overall_status" -eq 0 ]; then
        log_success "All checks passed."
    else
        log_error "Some checks failed."
    fi
    return "$overall_status"
}
