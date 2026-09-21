#!/bin/bash
# xgem ci: run the checks for every configured framework before you push,
# then explain what failed: where, why, and how to fix it.
# Depends on lib/logger.sh, lib/utils.sh, lib/ci-diagnose.sh.

CI_FAILED_LABELS=()
CI_FAILED_CMDS=()
CI_FAILED_LOGS=()

_ci_log_dir() {
    mkdir -p "$CONFIG_DIR/ci"
    [ -f "$CONFIG_DIR/ci/.gitignore" ] || echo '*' > "$CONFIG_DIR/ci/.gitignore"
    echo "$CONFIG_DIR/ci"
}

# CI=true and a closed stdin make test runners (Vitest, Jest, Angular) run
# once and exit instead of entering watch mode or waiting on a prompt.
# Output goes to a log; --verbose also streams it. Records into
# results/overall_status of the calling cmd_ci.
_ci_run_step() {
    local label=$1 cmd=$2 log rc pid start secs ticks=0
    log="$(_ci_log_dir)/$(echo "$label" | tr ' /' '--').log"
    log_info "Running $label..."
    start=$SECONDS

    if [ "$XGEM_VERBOSE" = "1" ]; then
        CI=true bash -c "$cmd" < /dev/null 2>&1 | tee "$log"
        rc=${PIPESTATUS[0]}
    else
        CI=true bash -c "$cmd" < /dev/null > "$log" 2>&1 &
        pid=$!
        while kill -0 "$pid" 2>/dev/null; do
            sleep 0.2
            ticks=$((ticks + 1))
            [ $((ticks % 150)) -eq 0 ] && echo "      ...still running $label ($((SECONDS - start))s)"
        done
        wait "$pid"
        rc=$?
    fi

    secs=$((SECONDS - start))
    if [ "$rc" -eq 0 ]; then
        results+=("PASS  $label (${secs}s)")
    else
        results+=("FAIL  $label (${secs}s)")
        overall_status=1
        CI_FAILED_LABELS+=("$label")
        CI_FAILED_CMDS+=("$cmd")
        CI_FAILED_LOGS+=("$log")
    fi
}

_ci_flutter() {
    if ! tool_ensure flutter; then
        results+=("SKIP  flutter (flutter not found)")
        return 0
    fi
    _ci_run_step "flutter analyze" "flutter analyze"
    if [ -d test ]; then
        _ci_run_step "flutter test" "flutter test"
    else
        results+=("SKIP  flutter test (no test/ directory)")
    fi
}

_ci_run_all() {
    local fw_dir fw step needed
    local -a steps=(lint test build)

    for fw_dir in "$CONFIG_DIR"/*/; do
        [ -d "$fw_dir" ] || continue
        fw=$(basename "$fw_dir")
        [ "$fw" = "ci" ] && continue

        if [ "$fw" = "flutter" ]; then
            _ci_flutter
            continue
        fi

        needed=$(fw_required_tool "$fw")
        if [ -n "$needed" ] && [ "$fw" != "docker" ] && ! tool_ensure "$needed"; then
            results+=("SKIP  $fw ($needed not found)")
            continue
        fi

        for step in "${steps[@]}"; do
            [ -f "$CONFIG_DIR/$fw/$step.sh" ] || continue
            _ci_run_step "$fw $step" "bash \"$CONFIG_DIR/$fw/$step.sh\""
        done
    done
}

_ci_print_summary() {
    echo ""
    echo "=== xgem ci summary ==="
    printf '%s\n' "${results[@]}"
}

_ci_snapshot() {
    git rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 0
    git ls-files -m -o --exclude-standard | while IFS= read -r f; do
        [ -f "$f" ] && printf '%s %s\n' "$(git hash-object "$f")" "$f"
    done | sort
}

_ci_apply_fixes() {
    local cmd before after changed
    if [ ${#DIAG_AUTOFIX[@]} -eq 0 ]; then
        log_info "None of these failures has a safe automatic fix; the causes above need a code change."
        return 1
    fi

    before=$(_ci_snapshot)
    local ran=0
    for cmd in "${DIAG_AUTOFIX[@]}"; do
        confirm "Run the tool's own fixer: $cmd ?" || continue
        ran=1
        log_info "Running: $cmd"
        bash -c "$cmd" || log_warn "'$cmd' exited with an error (see output above)."
    done
    [ "$ran" -eq 1 ] || return 1

    after=$(_ci_snapshot)
    changed=$(comm -13 <(printf '%s\n' "$before") <(printf '%s\n' "$after") | cut -d' ' -f2-)
    if [ -n "$changed" ]; then
        log_success "The fixer changed $(printf '%s\n' "$changed" | wc -l | tr -d ' ') file(s); review them with git diff:"
        printf '%s\n' "$changed" | sed 's/^/    /'
    else
        log_info "The fixer didn't change any files."
    fi
    return 0
}

cmd_ci() {
    [ -d "$CONFIG_DIR" ] || die "No $CONFIG_DIR found — run 'xgem init' or 'xgem add' first."

    local want_fix=0 arg
    for arg in "$@"; do
        case "$arg" in
            --fix) want_fix=1 ;;
            *) die "Unknown option '$arg'. Usage: xgem ci [--fix] [--verbose]" ;;
        esac
    done

    local -a results=()
    local overall_status=0
    _ci_run_all

    if [ ${#results[@]} -eq 0 ]; then
        log_warn "No checks found under $CONFIG_DIR to run."
        return 0
    fi

    _ci_print_summary

    if [ "$overall_status" -eq 0 ]; then
        log_success "All checks passed."
        return 0
    fi

    local i
    DIAG_AUTOFIX=()
    for i in "${!CI_FAILED_LABELS[@]}"; do
        diagnose_step "${CI_FAILED_LABELS[$i]}" "${CI_FAILED_LOGS[$i]}"
    done

    if [ ${#DIAG_AUTOFIX[@]} -gt 0 ] && [ "$want_fix" -eq 0 ]; then
        echo ""
        log_info "Some of these can be fixed automatically. Run 'xgem ci --fix' to apply: ${DIAG_AUTOFIX[*]}"
    fi

    if [ "$want_fix" -eq 1 ] && _ci_apply_fixes; then
        local -a old_labels=("${CI_FAILED_LABELS[@]}") old_cmds=("${CI_FAILED_CMDS[@]}")
        CI_FAILED_LABELS=(); CI_FAILED_CMDS=(); CI_FAILED_LOGS=()
        results=()
        overall_status=0
        echo ""
        log_info "Re-running the failed steps..."
        for i in "${!old_labels[@]}"; do
            _ci_run_step "${old_labels[$i]}" "${old_cmds[$i]}"
        done
        _ci_print_summary
        if [ "$overall_status" -eq 0 ]; then
            log_success "All checks pass after the fixes."
            return 0
        fi
        DIAG_AUTOFIX=()
        echo ""
        log_warn "Still failing after the automatic fixes; what's left needs a manual change:"
        for i in "${!CI_FAILED_LABELS[@]}"; do
            diagnose_step "${CI_FAILED_LABELS[$i]}" "${CI_FAILED_LOGS[$i]}"
        done
    fi

    log_error "Some checks failed."
    return 1
}
