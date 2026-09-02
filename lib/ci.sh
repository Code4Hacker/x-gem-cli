#!/bin/bash
# xgem ci: run lint -> test -> build for every configured framework before
# you push, so a CI failure gets caught locally first.
# Depends on lib/logger.sh.

cmd_ci() {
    [ -d "$CONFIG_DIR" ] || die "No $CONFIG_DIR found — run 'xgem init' or 'xgem add' first."

    local -a steps=(lint test build)
    local -a results=()
    local overall_status=0
    local fw_dir fw step

    for fw_dir in "$CONFIG_DIR"/*/; do
        [ -d "$fw_dir" ] || continue
        fw=$(basename "$fw_dir")
        for step in "${steps[@]}"; do
            [ -f "$CONFIG_DIR/$fw/$step.sh" ] || continue
            log_info "Running $fw $step..."
            if bash "$CONFIG_DIR/$fw/$step.sh"; then
                results+=("PASS  $fw $step")
            else
                results+=("FAIL  $fw $step")
                overall_status=1
            fi
        done
    done

    if [ ${#results[@]} -eq 0 ]; then
        log_warn "No lint/test/build scripts found under $CONFIG_DIR to run."
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
