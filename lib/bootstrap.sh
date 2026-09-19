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
        if [ "$XGEM_DRY_RUN" = "1" ]; then
            log_info "(dry-run) would create .env from $example"
            return 0
        fi
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

_bootstrap_preflight() {
    local fw=$1 tool pm
    tool=$(fw_required_tool "$fw")
    [ -n "$tool" ] && [ "$fw" != "docker" ] && { tool_ensure "$tool" || return 1; }
    case "$fw" in
        flutter) tool_ensure dart || return 1 ;;
        node|react|vue|angular|next)
            pm=$(_bootstrap_node_pm)
            if [ "$pm" != "npm" ] && ! has_cmd "$pm"; then
                log_warn "This project uses $pm (lockfile found) but '$pm' isn't installed."
                echo "  Enable it via Node's bundled corepack:  corepack enable   (or: npm install -g $pm)"
                if confirm "Run 'npm install -g $pm' now?"; then
                    _bootstrap_run npm install -g "$pm" || return 1
                else
                    return 1
                fi
            fi
            ;;
    esac
    return 0
}

_bootstrap_run() {
    if [ "$XGEM_DRY_RUN" = "1" ]; then
        log_info "(dry-run) would run: $*"
        return 0
    fi
    "$@"
}

_bootstrap_install() {
    local fw=$1
    case "$fw" in
        node|react|vue|angular|next)
            local pm
            pm=$(_bootstrap_node_pm)
            confirm "Install dependencies with $pm?" || return 0
            log_info "Installing dependencies with $pm..."
            case "$pm" in
                yarn) _bootstrap_run yarn ;;
                pnpm) _bootstrap_run pnpm install ;;
                bun)  _bootstrap_run bun install ;;
                *)    _bootstrap_run npm install ;;
            esac
            ;;
        flutter)
            confirm "Run 'flutter pub get'?" || return 0
            _bootstrap_run flutter pub get
            ;;
        python)
            if [ -f pyproject.toml ] && has_cmd poetry; then
                confirm "Install dependencies with poetry?" || return 0
                _bootstrap_run poetry install
            elif [ -f requirements.txt ]; then
                confirm "Create .venv and install requirements.txt into it?" || return 0
                [ -d .venv ] || _bootstrap_run python3 -m venv .venv
                _bootstrap_run .venv/bin/pip install -r requirements.txt
            fi
            ;;
        go)
            confirm "Run 'go mod download'?" || return 0
            _bootstrap_run go mod download
            ;;
        rust)
            confirm "Run 'cargo fetch'?" || return 0
            _bootstrap_run cargo fetch
            ;;
        swift)
            confirm "Run 'swift package resolve'?" || return 0
            _bootstrap_run swift package resolve
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

    _bootstrap_preflight "$fw" || die "Bootstrap stopped: a required tool is missing."
    _bootstrap_env_file
    _bootstrap_install "$fw"
    _bootstrap_migrations "$fw"

    if [ ! -d "$CONFIG_DIR" ]; then
        confirm "Scaffold xgem automation scripts (.xgem-automate) for $fw too?" && _xgem_bookkeeping "$fw"
    fi

    _bootstrap_offer_dev_server "$fw"
    log_success "Bootstrap complete."
}
