#!/bin/bash
# xgem bootstrap: clone-to-running in one command, for a project you just
# checked out (not creating a new one — that's `xgem init`'s job).
# Depends on lib/logger.sh, lib/utils.sh, lib/scaffold.sh, lib/create.sh.

# _detect_framework -> a name from ALL_FRAMEWORKS, or empty if nothing
# recognizable was found. Never assumes; probes for marker files the same
# way lib/doctor.sh probes for tools instead of guessing.
_detect_framework() {
    [ -f pubspec.yaml ] && { echo flutter; return 0; }
    [ -f go.mod ] && { echo go; return 0; }
    [ -f Cargo.toml ] && { echo rust; return 0; }
    { [ -f pyproject.toml ] || [ -f requirements.txt ] || [ -f setup.py ]; } && { echo python; return 0; }
    [ -f Package.swift ] && { echo swift; return 0; }
    if [ -f package.json ]; then
        if grep -q '"next"' package.json; then echo next
        elif grep -q '"@angular/core"' package.json; then echo angular
        elif grep -q '"vue"' package.json; then echo vue
        elif grep -q '"react"' package.json; then echo react
        else echo node
        fi
        return 0
    fi
    [ -f Dockerfile ] && { echo docker; return 0; }
    return 1
}

_bootstrap_env_file() {
    [ -f .env ] && { log_debug ".env already exists, leaving it as-is."; return 0; }
    local example
    for example in .env.example .env.sample; do
        [ -f "$example" ] || continue
        cp "$example" .env
        log_success "Created .env from $example."
        local missing
        missing=$(grep -E '^[A-Za-z_][A-Za-z0-9_]*=[[:space:]]*$' .env | cut -d= -f1)
        if [ -n "$missing" ]; then
            log_warn "These .env keys are empty — fill them in:"
            echo "$missing" | sed 's/^/  - /'
        fi
        return 0
    done
}

_bootstrap_node_pm() {
    if [ -f pnpm-lock.yaml ]; then echo pnpm
    elif [ -f yarn.lock ]; then echo yarn
    elif [ -f bun.lockb ] || [ -f bun.lock ]; then echo bun
    else echo npm
    fi
}

_bootstrap_install() {
    local fw=$1
    case "$fw" in
        node|react|vue|angular|next)
            local pm
            pm=$(_bootstrap_node_pm)
            log_info "Installing dependencies with $pm..."
            case "$pm" in
                yarn) yarn ;;
                pnpm) pnpm install ;;
                bun)  bun install ;;
                *)    npm install ;;
            esac
            ;;
        flutter)
            has_cmd flutter || { log_warn "flutter not found — skipping 'flutter pub get'."; return 0; }
            log_info "Running flutter pub get..."
            flutter pub get
            ;;
        python)
            if [ -f pyproject.toml ] && has_cmd poetry; then
                log_info "Installing dependencies with poetry..."
                poetry install
            elif [ -f requirements.txt ]; then
                has_cmd python3 || { log_warn "python3 not found — skipping install."; return 0; }
                [ -d .venv ] || python3 -m venv .venv
                log_info "Installing dependencies into .venv..."
                .venv/bin/pip install -r requirements.txt
            fi
            ;;
        go)
            has_cmd go || { log_warn "go not found — skipping 'go mod download'."; return 0; }
            log_info "Running go mod download..."
            go mod download
            ;;
        rust)
            has_cmd cargo || { log_warn "cargo not found — skipping 'cargo fetch'."; return 0; }
            log_info "Running cargo fetch..."
            cargo fetch
            ;;
        swift)
            has_cmd swift || { log_warn "swift not found — skipping 'swift package resolve'."; return 0; }
            log_info "Running swift package resolve..."
            swift package resolve
            ;;
        docker)
            log_debug "Docker project — nothing to install locally."
            ;;
    esac
}

_bootstrap_migrations() {
    local fw=$1
    if [ "$fw" = "node" ] || [ "$fw" = "react" ] || [ "$fw" = "vue" ] || [ "$fw" = "angular" ] || [ "$fw" = "next" ]; then
        if _package_json_has_script migrate; then
            local pm
            pm=$(_bootstrap_node_pm)
            confirm "Run the project's 'migrate' script (via $pm)?" || return 0
            case "$pm" in
                yarn) yarn migrate ;;
                pnpm) pnpm run migrate ;;
                bun)  bun run migrate ;;
                *)    npm run migrate ;;
            esac
            return 0
        fi
    fi
    if [ -f prisma/schema.prisma ]; then
        confirm "Run 'npx prisma migrate dev'?" && npx prisma migrate dev
    elif [ -f manage.py ]; then
        has_cmd python3 && confirm "Run 'python3 manage.py migrate'?" && python3 manage.py migrate
    fi
}

_bootstrap_offer_dev_server() {
    local fw=$1
    local script=""
    case "$fw" in
        node) script=start ;;
        react|vue|angular|next) script=dev ;;
        *) return 0 ;;
    esac
    [ -f "$CONFIG_DIR/$fw/$script.sh" ] || return 0
    confirm "Launch the dev server now ('xgem run $fw $script')?" && scaffold_run_script "$fw" "$script" "$CONFIG_DIR"
}

cmd_bootstrap() {
    log_info "Detecting project framework..."
    local fw
    fw=$(_detect_framework)
    if [ -z "$fw" ]; then
        log_warn "Could not auto-detect the framework from any known marker file."
        echo "Pick one:"
        PS3="Enter target selection number: "
        select fw in "${ALL_FRAMEWORKS[@]}"; do
            [ -n "$fw" ] && break
            echo "Invalid selection."
        done
    else
        log_success "Detected: $fw"
    fi

    _bootstrap_env_file
    _bootstrap_install "$fw"
    _bootstrap_migrations "$fw"

    if [ ! -d "$CONFIG_DIR" ]; then
        confirm "Scaffold xgem automation scripts (.xgem-automate) for $fw too?" && _xgem_bookkeeping "$fw"
    fi

    _bootstrap_offer_dev_server "$fw"
    log_success "Bootstrap complete."
}
