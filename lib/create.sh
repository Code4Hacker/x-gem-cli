#!/bin/bash
# xgem project creation wizards — runs from `xgem init`, for frameworks
# with a real "ask sub-choice -> scaffold -> install -> launch" story
# worth building (react/vue/angular/next/flutter). The rest (node/python/
# go/rust/docker/swift) get a lighter "create with the ecosystem's own
# standard init command" step.
#
# Depends on lib/logger.sh, lib/utils.sh, lib/scaffold.sh. Uses `cd`
# directly (no subshells) so a newly created project directory persists as
# the cwd for the rest of `xgem init`.
#
# Ordering principle (this file's main correctness property): xgem's own
# bookkeeping (.xgem-automate + .gitignore, via _xgem_bookkeeping) always
# runs BEFORE the slow, interruptible step of each framework (an install,
# or an atomic scaffold+install like `ng new`) — never after. A real user
# hit this: Ctrl-C during `ng new`'s multi-minute install killed the whole
# xgem process before .xgem-automate was ever created, since it used to run
# only at the very end. Where a tool supports decoupling scaffold-from-
# install (--no-immediate, --skip-install, --no-pub), xgem scaffolds first
# (fast), does its own bookkeeping, then runs the install itself. Where a
# tool has no such flag (create-react-app), bookkeeping runs right after
# that one atomic call returns — a small residual risk, documented at the
# call site, not silently left as-was.
#
# Dev-server / device-run launch is deliberately deferred: creators only
# set XGEM_POST_INIT_LAUNCH_CMD (an array) rather than launching
# immediately, so `xgem init` finishes well before handing the terminal
# over to a long-running dev server.
XGEM_POST_INIT_LAUNCH_CMD=()

# Set by creators when a NEW folder was created (not "current directory").
# A child process can never change its parent shell's cwd, so once `xgem
# init` exits, the user's actual terminal is back wherever it started —
# xgem's own process is correctly cd'd into the new folder for the rest of
# ITS run, but that never propagates back. bin/xgem prints a "cd <name>"
# reminder using this at the very end.
XGEM_CREATED_NEW_FOLDER=""

# _xgem_bookkeeping <framework>
# Creates .xgem-automate + updates .gitignore. Called as early as the
# target directory allows, always before any slow/interruptible step.
_xgem_bookkeeping() {
    local fw=$1
    mkdir -p "$CONFIG_DIR"
    scaffold_inject_templates "$fw" "$CONFIG_DIR"
    log_success "Successfully appended standard scripts for: $CONFIG_DIR/$fw"

    if [ -f .gitignore ]; then
        if ! grep -q "$CONFIG_DIR/" .gitignore; then
            echo -e "\n$CONFIG_DIR/" >> .gitignore
            log_success "Added automation tracking to .gitignore"
        fi
    else
        echo "$CONFIG_DIR/" > .gitignore
        log_success "Created .gitignore and hidden tracking layer folder references."
    fi
}

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

# _enter_project_dir <project_dir> — mkdir+cd if a new folder was chosen,
# and records XGEM_CREATED_NEW_FOLDER. No-op for "." (current directory).
_enter_project_dir() {
    local project_dir=$1
    [ "$project_dir" = "." ] && return 0
    XGEM_CREATED_NEW_FOLDER="$project_dir"
    mkdir -p "$project_dir" && cd "$project_dir" || die "Could not enter $project_dir"
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

    # `flutter run` isn't a web dev server — no localhost URL to detect/
    # open, and it depends on fully-inherited interactive stdin for its
    # own hot-reload keybindings, which the background+log-tail approach
    # would break. Run it directly. (Whether to run at all was already
    # confirmed in _flutter_offer_run_on_device, so this doesn't ask again.)
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
    _enter_project_dir "$project_dir"

    if [[ "$variant" == cra* || "$variant" == CRA* ]]; then
        require_cmd npx "Install Node.js (npm ships with it): https://nodejs.org"
        # create-react-app has no flag to decouple scaffold-from-install
        # (confirmed: nothing in --help), so this one atomic call does
        # both — a Ctrl-C during its own install (it's known to be slow)
        # would still lose xgem's bookkeeping below. Accepted residual
        # risk for this specific, non-default, legacy-leaning option.
        log_info "Create React App scaffolds and installs in one step and can take a few minutes — best to let it finish without interrupting."
        local -a args=(create-react-app .)
        [ "$lang" = "ts" ] && args+=(--template typescript)
        npx "${args[@]}" || die "create-react-app failed."
        _xgem_bookkeeping react
        return 0
    fi

    require_cmd npm "Install Node.js (npm ships with it): https://nodejs.org"
    local template="react"
    [ "$lang" = "ts" ] && template="react-ts"
    # --no-immediate: create-vite's own "install deps and start dev server"
    # prompt would otherwise block here (and if Ctrl-C'd, kill this whole
    # xgem process). --overwrite: harmless here since the only files that
    # could exist at this point are ones xgem itself hasn't created yet
    # (bookkeeping happens after this call, deliberately).
    npm create vite@latest . -- --template "$template" --no-immediate --overwrite || die "npm create vite failed."
    _xgem_bookkeeping react
    log_info "Installing dependencies..."
    npm install
    XGEM_POST_INIT_LAUNCH_CMD=(npm run dev)
}

_create_vue() {
    require_cmd npm "Install Node.js (npm ships with it): https://nodejs.org"
    local project_dir
    project_dir=$(_prompt_project_location "Vue")
    _enter_project_dir "$project_dir"
    # create-vue doesn't install automatically (confirmed: no node_modules
    # after it runs), so there's already a natural gap here to bookkeep in
    # before the slow step. --force since this dir may be genuinely empty
    # or (for "current directory") may already contain unrelated files.
    npm create vue@latest . --force || die "npm create vue failed."
    _xgem_bookkeeping vue
    log_info "Installing dependencies..."
    npm install
    XGEM_POST_INIT_LAUNCH_CMD=(npm run dev)
}

_create_angular() {
    local project_dir
    project_dir=$(_prompt_project_location "Angular")
    _enter_project_dir "$project_dir"
    local -a ng_cmd=(ng)
    has_cmd ng || ng_cmd=(npx @angular/cli@latest)

    # --skip-install: ng new's own install is a multi-minute step (Angular
    # dependency trees are large) — decoupling it is exactly what let a
    # real user's Ctrl-C lose xgem's bookkeeping before this fix.
    # --skip-git: xgem has its own `xgem git init`; ng new's own auto-
    # commit would happen before .xgem-automate even exists.
    "${ng_cmd[@]}" new "$(basename "$PWD")" --directory=. --skip-install --skip-git \
        || die "ng new failed."
    _xgem_bookkeeping angular
    log_info "Installing dependencies..."
    npm install
    XGEM_POST_INIT_LAUNCH_CMD=(npm run start)
}

_create_next() {
    require_cmd npx "Install Node.js (npm ships with it): https://nodejs.org"
    local project_dir
    project_dir=$(_prompt_project_location "Next.js")
    _enter_project_dir "$project_dir"
    # --skip-install: decouple from create-next-app's own install, same
    # reasoning as Angular above.
    npx create-next-app@latest . --skip-install || die "create-next-app failed."
    _xgem_bookkeeping next
    log_info "Installing dependencies..."
    npm install
    XGEM_POST_INIT_LAUNCH_CMD=(npm run dev)
}

# Lighter path for frameworks without a dev-server/browser story — just the
# ecosystem's own standard init command, no sub-wizard. These are all fast
# (no multi-minute install step), so bookkeeping-then-init is low-risk
# regardless of ordering, but it's kept bookkeeping-first for consistency.
_create_simple() {
    local fw=$1
    local project_dir
    project_dir=$(_prompt_project_location "$fw")
    _enter_project_dir "$project_dir"
    _xgem_bookkeeping "$fw"

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
            cargo init || die "cargo init failed."
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
# Asks whether to create a new project or use what's already here. Either
# way, xgem's own bookkeeping (.xgem-automate + .gitignore) is guaranteed
# to happen — for "existing", immediately (nothing to interrupt); for
# "new", each creator handles it internally at the earliest safe point,
# per the ordering principle documented at the top of this file.
create_project_wizard() {
    local fw=$1
    local create_choice
    read -r -p "Create a brand-new $fw project, or use what's already in this directory? [new/existing] (default: existing): " create_choice
    create_choice=${create_choice:-existing}

    if [[ "$create_choice" != n* && "$create_choice" != N* ]]; then
        _xgem_bookkeeping "$fw"
        return 0
    fi

    case "$fw" in
        react)   _create_react ;;
        vue)     _create_vue ;;
        angular) _create_angular ;;
        next)    _create_next ;;
        flutter) create_flutter_project ;;
        node|python|go|rust|docker|swift) _create_simple "$fw" ;;
        *)
            log_debug "No creation wizard for '$fw'; using current directory as-is."
            _xgem_bookkeeping "$fw"
            ;;
    esac
}
