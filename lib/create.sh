#!/bin/bash
# xgem project creation wizards — runs from `xgem init`, before
# scaffold_inject_templates, for frameworks with a real "ask sub-choice ->
# scaffold -> install -> launch" story worth building (react/vue/angular/
# next/flutter). The rest (node/python/go/rust/docker/swift) get a lighter
# "create with the ecosystem's own standard init command" step.
#
# Depends on lib/logger.sh, lib/utils.sh. Uses `cd` directly (no
# subshells) so a newly created project directory persists as the cwd for
# the rest of `xgem init` (template injection, .gitignore) without the
# caller needing to track/re-cd into a returned path.
#
# Dev-server launch is deliberately deferred: creators only set
# XGEM_POST_INIT_LAUNCH_CMD (an array) rather than launching immediately,
# so `xgem init` finishes template injection and .gitignore setup *before*
# handing the terminal over to a long-running dev server.
XGEM_POST_INIT_LAUNCH_CMD=()

# Set by creators when a NEW folder was created (not "current directory").
# A child process can never change its parent shell's cwd, so once `xgem
# init` exits, the user's actual terminal is back wherever it started —
# xgem's own process is correctly cd'd into the new folder for the rest of
# ITS run (template injection, dev server), but that never propagates back.
# bin/xgem prints a "cd <name>" reminder using this at the very end.
XGEM_CREATED_NEW_FOLDER=""

# _prompt_project_location <human label> -> echoes "." or a new folder name.
# Pure prompt-and-echo, no other stdout output, so it's safe to capture via
# command substitution.
_prompt_project_location() {
    local label=$1
    local choice
    read -r -p "Initialize $label in the current directory, or create a new folder? [current/new] (default: new): " choice
    choice=${choice:-new}
    if [[ "$choice" == c* || "$choice" == C* ]]; then
        echo "."
        return 0
    fi
    local name
    read -r -p "Project name: " name
    [ -n "$name" ] || die "Project name cannot be empty."
    echo "$name"
}

_open_url() {
    local url=$1
    case "$(detect_os)" in
        darwin) open "$url" 2>/dev/null ;;
        linux)  xdg-open "$url" 2>/dev/null ;;
        *) log_debug "Don't know how to open a browser on this OS — visit $url manually." ;;
    esac
}

# _launch_dev_server_and_open_browser <cmd...>
# Starts the dev server in the background, tails its log for the first
# http://localhost URL it prints — this works across Vite/CRA/Next/Angular
# without hardcoding any one framework's default port (which can differ or
# be taken already) — opens it, then waits so Ctrl-C stops the server
# normally instead of leaving it orphaned in the background.
_launch_dev_server_and_open_browser() {
    local log_file
    log_file=$(mktemp)
    log_info "Starting dev server: $*"
    "$@" > "$log_file" 2>&1 &
    local server_pid=$!

    local url="" waited=0
    while [ -z "$url" ] && [ "$waited" -lt 30 ] && kill -0 "$server_pid" 2>/dev/null; do
        url=$(grep -oE 'https?://(localhost|127\.0\.0\.1)[:0-9]*[^[:space:]]*' "$log_file" 2>/dev/null | head -1)
        if [ -z "$url" ]; then
            sleep 1
            waited=$((waited + 1))
        fi
    done

    if [ -n "$url" ]; then
        log_success "Dev server up at $url"
        _open_url "$url"
    elif kill -0 "$server_pid" 2>/dev/null; then
        log_warn "Dev server is running (pid $server_pid) but its URL wasn't detected automatically after ${waited}s — check the output below."
    else
        log_error "Dev server exited early."
    fi

    cat "$log_file" &
    wait "$server_pid" 2>/dev/null
}

_ask_launch_dev_server() {
    [ ${#XGEM_POST_INIT_LAUNCH_CMD[@]} -gt 0 ] || return 0

    # `flutter run` isn't a web dev server — it has no localhost URL to
    # detect/open, and it depends on a fully-inherited interactive stdin
    # for its own hot-reload keybindings (r/R/q/etc.), which the
    # background+log-tail approach below would break. Run it directly.
    # (Whether to run at all was already confirmed in
    # _flutter_offer_run_on_device before this command was ever set, so
    # this doesn't ask again.)
    if [ "${XGEM_POST_INIT_LAUNCH_CMD[0]}" = "flutter" ]; then
        "${XGEM_POST_INIT_LAUNCH_CMD[@]}"
        return 0
    fi

    local answer
    read -r -p "Launch the dev server now and open it in your browser? (Y/n): " answer
    answer=${answer:-y}
    [[ "$answer" == "y" || "$answer" == "Y" ]] && _launch_dev_server_and_open_browser "${XGEM_POST_INIT_LAUNCH_CMD[@]}"
}

_create_react() {
    local variant lang project_dir
    read -r -p "Use Vite or Create React App (the 'normal' version)? [vite/cra] (default: vite): " variant
    variant=${variant:-vite}
    read -r -p "TypeScript or JavaScript? [ts/js] (default: ts): " lang
    lang=${lang:-ts}
    project_dir=$(_prompt_project_location "React")
    [ "$project_dir" != "." ] && XGEM_CREATED_NEW_FOLDER="$project_dir"

    if [[ "$variant" == cra* || "$variant" == CRA* ]]; then
        require_cmd npx "Install Node.js (npm ships with it): https://nodejs.org"
        local -a args=(create-react-app)
        [ "$project_dir" != "." ] && args+=("$project_dir") || args+=(.)
        [ "$lang" = "ts" ] && args+=(--template typescript)
        npx "${args[@]}" || die "create-react-app failed."
    else
        require_cmd npm "Install Node.js (npm ships with it): https://nodejs.org"
        local template="react"
        [ "$lang" = "ts" ] && template="react-ts"
        # --no-immediate: create-vite's own "install deps and start dev
        # server" prompt would otherwise block here and, if Ctrl-C'd, kill
        # this whole xgem process before it ever reaches template
        # injection / .gitignore setup below. xgem handles install/launch
        # itself instead, after everything else is done.
        npm create vite@latest "$project_dir" -- --template "$template" --no-immediate || die "npm create vite failed."
    fi

    [ "$project_dir" != "." ] && { cd "$project_dir" || die "Could not enter $project_dir"; }
    log_info "Installing dependencies..."
    npm install
    XGEM_POST_INIT_LAUNCH_CMD=(npm run dev)
}

_create_vue() {
    require_cmd npm "Install Node.js (npm ships with it): https://nodejs.org"
    local project_dir
    project_dir=$(_prompt_project_location "Vue")
    [ "$project_dir" != "." ] && XGEM_CREATED_NEW_FOLDER="$project_dir"
    npm create vue@latest "$project_dir" || die "npm create vue failed."
    [ "$project_dir" != "." ] && { cd "$project_dir" || die "Could not enter $project_dir"; }
    log_info "Installing dependencies..."
    npm install
    XGEM_POST_INIT_LAUNCH_CMD=(npm run dev)
}

_create_angular() {
    local project_dir
    project_dir=$(_prompt_project_location "Angular")
    [ "$project_dir" != "." ] && XGEM_CREATED_NEW_FOLDER="$project_dir"
    local -a ng_cmd=(ng)
    has_cmd ng || ng_cmd=(npx @angular/cli@latest)

    if [ "$project_dir" = "." ]; then
        "${ng_cmd[@]}" new "$(basename "$PWD")" --directory=. || die "ng new failed."
    else
        "${ng_cmd[@]}" new "$project_dir" || die "ng new failed."
        cd "$project_dir" || die "Could not enter $project_dir"
    fi
    XGEM_POST_INIT_LAUNCH_CMD=(npm run start)
}

_create_next() {
    require_cmd npx "Install Node.js (npm ships with it): https://nodejs.org"
    local project_dir
    project_dir=$(_prompt_project_location "Next.js")
    [ "$project_dir" != "." ] && XGEM_CREATED_NEW_FOLDER="$project_dir"
    npx create-next-app@latest "$project_dir" || die "create-next-app failed."
    [ "$project_dir" != "." ] && { cd "$project_dir" || die "Could not enter $project_dir"; }
    XGEM_POST_INIT_LAUNCH_CMD=(npm run dev)
}

# Lighter path for frameworks without a dev-server/browser story — just the
# ecosystem's own standard init command, no sub-wizard.
_create_simple() {
    local fw=$1
    local project_dir
    project_dir=$(_prompt_project_location "$fw")
    [ "$project_dir" != "." ] && XGEM_CREATED_NEW_FOLDER="$project_dir"
    [ "$project_dir" != "." ] && { mkdir -p "$project_dir" && cd "$project_dir" || die "Could not enter $project_dir"; }

    case "$fw" in
        node)
            require_cmd npm "Install Node.js (npm ships with it): https://nodejs.org"
            npm init -y
            ;;
        python)
            require_cmd python3 "Install Python 3: https://www.python.org/downloads/"
            python3 -m venv .venv
            log_success "Created .venv — activate with 'source .venv/bin/activate'."
            ;;
        go)
            require_cmd go "Install Go: https://go.dev/doc/install"
            local module_name
            read -r -p "Module name (e.g. github.com/you/project): " module_name
            [ -n "$module_name" ] || module_name=$(basename "$PWD")
            go mod init "$module_name"
            ;;
        rust)
            require_cmd cargo "Install Rust: https://www.rust-lang.org/tools/install"
            if [ "$project_dir" != "." ]; then
                cd .. || return 1
                cargo new "$project_dir" || die "cargo new failed."
                cd "$project_dir" || die "Could not enter $project_dir"
            else
                cargo init || die "cargo init failed."
            fi
            ;;
        swift)
            require_cmd swift "Install Swift: https://www.swift.org/install/"
            swift package init --type executable
            ;;
        docker)
            if [ ! -f Dockerfile ]; then
                cat > Dockerfile << 'EOF'
FROM alpine:latest
WORKDIR /app
COPY . .
CMD ["sh"]
EOF
                log_success "Created a starter Dockerfile — edit it for your actual base image/entrypoint."
            else
                log_warn "Dockerfile already exists, leaving it as-is."
            fi
            ;;
    esac
}

# create_project_wizard <framework>
# Asks whether to create a new project or use what's already here; if
# creating, dispatches to the right per-framework creator. Leaves the
# process cwd inside the (possibly new) project directory either way.
create_project_wizard() {
    local fw=$1
    local create_choice
    read -r -p "Create a brand-new $fw project, or use what's already in this directory? [new/existing] (default: existing): " create_choice
    create_choice=${create_choice:-existing}
    [[ "$create_choice" == n* || "$create_choice" == N* ]] || return 0

    case "$fw" in
        react)   _create_react ;;
        vue)     _create_vue ;;
        angular) _create_angular ;;
        next)    _create_next ;;
        flutter) create_flutter_project ;;
        node|python|go|rust|docker|swift) _create_simple "$fw" ;;
        *) log_debug "No creation wizard for '$fw'; using current directory as-is." ;;
    esac
}
