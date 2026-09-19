#!/bin/bash
# xgem toolchain layer: finds tools where version managers actually put them,
# offers to install missing ones, and reports/applies updates.
# Kept bash 3.2 compatible (macOS default): no associative arrays.
# Depends on lib/logger.sh, lib/utils.sh.

XGEM_CACHE_DIR="${XGEM_CACHE_DIR:-$HOME/.xgem/cache}"
: "${XGEM_NO_NETWORK:=0}"

TOOL_DIR=""
TOOL_PATH=""
TOOL_MANAGER=""
TOOL_ON_PATH=0

_tool_canon() {
    case "$1" in
        npm|npx|corepack) echo node ;;
        pip|pip3|python) echo python3 ;;
        rustc|rustup)    echo cargo ;;
        *)               echo "$1" ;;
    esac
}

tool_known() {
    case "$(_tool_canon "$1")" in
        flutter|dart|node|python3|go|cargo|docker|git|gh|swift|fvm) return 0 ;;
        *) return 1 ;;
    esac
}

tool_display() {
    case "$1" in
        flutter) echo "Flutter SDK" ;;
        dart)    echo "Dart SDK" ;;
        node)    echo "Node.js" ;;
        python3) echo "Python 3" ;;
        go)      echo "Go" ;;
        cargo)   echo "Rust (cargo)" ;;
        docker)  echo "Docker" ;;
        git)     echo "Git" ;;
        gh)      echo "GitHub CLI" ;;
        swift)   echo "Swift" ;;
        fvm)     echo "FVM (Flutter Version Management)" ;;
        *)       echo "$1" ;;
    esac
}

tool_url() {
    case "$1" in
        flutter|dart) echo "https://docs.flutter.dev/get-started/install" ;;
        node)    echo "https://nodejs.org/en/download" ;;
        python3) echo "https://www.python.org/downloads/" ;;
        go)      echo "https://go.dev/dl/" ;;
        cargo)   echo "https://www.rust-lang.org/tools/install" ;;
        docker)  echo "https://www.docker.com/products/docker-desktop/" ;;
        git)     echo "https://git-scm.com/downloads" ;;
        gh)      echo "https://cli.github.com" ;;
        swift)   echo "https://www.swift.org/install/" ;;
        fvm)     echo "https://fvm.app/documentation/getting-started/installation" ;;
    esac
}

# fw_required_tool <framework> -> the tool that framework's commands need.
fw_required_tool() {
    case "$1" in
        flutter) echo flutter ;;
        node|react|vue|angular|next) echo node ;;
        python) echo python3 ;;
        go) echo go ;;
        rust) echo cargo ;;
        swift) echo swift ;;
        docker) echo docker ;;
    esac
}

_tool_pretty() {
    case "$1" in
        "$HOME"/*) printf '~%s' "${1#"$HOME"}" ;;
        *) printf '%s' "$1" ;;
    esac
}

_tool_find_up() {
    local dir=$PWD
    while [ -n "$dir" ]; do
        [ "$dir" = "$HOME" ] && [ "$PWD" != "$HOME" ] && break
        [ -e "$dir/$1" ] && { echo "$dir/$1"; return 0; }
        [ "$dir" = "/" ] && break
        dir=$(dirname "$dir")
    done
    return 1
}

# tool_pin <tool> -> the version this project pins for it, if any.
tool_pin() {
    local f v="" key
    case "$1" in
        flutter|dart)
            if f=$(_tool_find_up .fvmrc); then
                v=$(grep -oE '"flutter"[[:space:]]*:[[:space:]]*"[^"]+"' "$f" | sed -E 's/.*:[[:space:]]*"([^"]+)"/\1/')
            elif f=$(_tool_find_up .fvm/fvm_config.json); then
                v=$(grep -oE '"flutterSdkVersion"[[:space:]]*:[[:space:]]*"[^"]+"' "$f" | sed -E 's/.*:[[:space:]]*"([^"]+)"/\1/')
            fi
            key=flutter
            ;;
        node)
            if f=$(_tool_find_up .nvmrc); then
                v=$(tr -d '[:space:]' < "$f")
                v=${v#v}
            fi
            key=nodejs
            ;;
        python3) key=python ;;
        go)      key=golang ;;
        cargo)   key=rust ;;
        *)       key="" ;;
    esac
    if [ -z "$v" ] && [ -n "$key" ] && f=$(_tool_find_up .tool-versions); then
        v=$(awk -v k="$key" '$1==k {print $2; exit}' "$f")
    fi
    echo "$v"
}

_tool_fvm_roots() {
    [ -n "${FVM_CACHE_PATH:-}" ] && echo "$FVM_CACHE_PATH"
    [ -n "${FVM_HOME:-}" ] && echo "$FVM_HOME"
    echo "$HOME/fvm"
    echo "$HOME/.fvm"
    echo "$HOME/.fvm_flutter"
}

_tool_nvm_candidate() {
    local root=${NVM_DIR:-$HOME/.nvm} pin want v=""
    [ -d "$root/versions/node" ] || return 0
    pin=$(tool_pin node)
    if [[ "$pin" =~ ^[0-9] ]]; then
        v=$(ls -1 "$root/versions/node" | grep -E "^v${pin}" | sort -V | tail -1)
    fi
    if [ -z "$v" ] && [ -f "$root/alias/default" ]; then
        want=$(tr -d '[:space:]' < "$root/alias/default")
        want=${want#v}
        [[ "$want" =~ ^[0-9] ]] && v=$(ls -1 "$root/versions/node" | grep -E "^v${want}" | sort -V | tail -1)
    fi
    [ -z "$v" ] && v=$(ls -1 "$root/versions/node" | sort -V | tail -1)
    [ -n "$v" ] && printf '%s/versions/node/%s/bin\tnvm\n' "$root" "$v"
}

# _tool_candidates <canonical tool> -> "dir<TAB>manager" lines, best first.
_tool_candidates() {
    local canon=$1 root pin d v
    case "$canon" in
        flutter|dart)
            pin=$(tool_pin flutter)
            if d=$(_tool_find_up .fvm/flutter_sdk) && [ -d "$d/bin" ]; then
                printf '%s/bin\tfvm\n' "$d"
            fi
            while IFS= read -r root; do
                [ -n "$pin" ] && printf '%s/versions/%s/bin\tfvm\n' "$root" "$pin"
            done < <(_tool_fvm_roots)
            printf '%s/.fvm/flutter_sdk/bin\tfvm\n' "$HOME"
            while IFS= read -r root; do
                printf '%s/default/bin\tfvm\n' "$root"
            done < <(_tool_fvm_roots)
            while IFS= read -r root; do
                v=$(ls -1 "$root/versions" 2>/dev/null | sort -V | tail -1)
                [ -n "$v" ] && printf '%s/versions/%s/bin\tfvm\n' "$root" "$v"
            done < <(_tool_fvm_roots)
            printf '%s/.puro/envs/stable/flutter/bin\tpuro\n' "$HOME"
            printf '%s/development/flutter/bin\tother\n' "$HOME"
            printf '%s/flutter/bin\tother\n' "$HOME"
            ;;
        node)
            _tool_nvm_candidate
            printf '%s/.local/share/fnm/aliases/default/bin\tfnm\n' "$HOME"
            printf '%s/Library/Application Support/fnm/aliases/default/bin\tfnm\n' "$HOME"
            printf '%s/.volta/bin\tvolta\n' "$HOME"
            ;;
        python3) printf '%s/.pyenv/shims\tpyenv\n' "$HOME" ;;
        go)      printf '/usr/local/go/bin\tother\n' ;;
        cargo)   printf '%s/.cargo/bin\trustup\n' "$HOME" ;;
        docker)
            printf '/Applications/Docker.app/Contents/Resources/bin\tother\n'
            printf '%s/.docker/bin\tother\n' "$HOME"
            ;;
    esac
    printf '%s/.asdf/shims\tasdf\n' "$HOME"
    printf '%s/.local/share/mise/shims\tmise\n' "$HOME"
    printf '/opt/homebrew/bin\tbrew\n'
    printf '/usr/local/bin\tsystem\n'
}

_tool_manager_of() {
    case "$1" in
        */.nvm/*) echo nvm ;;
        */fvm/*|*/.fvm/*|*/.fvm_flutter/*) echo fvm ;;
        /opt/homebrew/*|*/Cellar/*|/home/linuxbrew/*) echo brew ;;
        */.cargo/*) echo rustup ;;
        */.pyenv/*) echo pyenv ;;
        */.asdf/*) echo asdf ;;
        */mise/*) echo mise ;;
        */.volta/*) echo volta ;;
        */.puro/*) echo puro ;;
        /usr/bin/*|/bin/*) echo system ;;
        *) echo other ;;
    esac
}

# tool_resolve <command> -> 0 if found; sets TOOL_PATH, TOOL_DIR,
# TOOL_MANAGER, TOOL_ON_PATH. Never calls has_cmd (no recursion).
tool_resolve() {
    local cmd=$1 canon dir via p d
    canon=$(_tool_canon "$cmd")
    TOOL_DIR=""; TOOL_PATH=""; TOOL_MANAGER=""; TOOL_ON_PATH=0

    p=$(command -v "$cmd" 2>/dev/null)
    if [ -n "$p" ] && [ -x "$p" ]; then
        TOOL_PATH=$p
        TOOL_DIR=$(dirname "$p")
        TOOL_ON_PATH=1
        TOOL_MANAGER=$(_tool_manager_of "$p")
        return 0
    fi

    while IFS=$'\t' read -r dir via; do
        [ -x "$dir/$cmd" ] || continue
        TOOL_PATH="$dir/$cmd"
        TOOL_DIR=$dir
        TOOL_MANAGER=$via
        return 0
    done < <(_tool_candidates "$canon")

    if [ "$canon" = "flutter" ] || [ "$canon" = "dart" ]; then
        if [ "$(command -v fvm 2>/dev/null)" ]; then
            d=$(fvm api context 2>/dev/null | grep -oE '"fvmDir"[[:space:]]*:[[:space:]]*"[^"]+"' | sed -E 's/.*"([^"]+)"$/\1/')
            for p in "$d/default/bin" "$d/versions/$(ls -1 "$d/versions" 2>/dev/null | sort -V | tail -1)/bin"; do
                [ -x "$p/$cmd" ] || continue
                TOOL_PATH="$p/$cmd"; TOOL_DIR=$p; TOOL_MANAGER=fvm
                return 0
            done
        fi
    fi
    return 1
}

tool_activate() {
    [ "$TOOL_ON_PATH" = "1" ] && return 0
    [ -n "$TOOL_DIR" ] || return 1
    PATH="$TOOL_DIR:$PATH"
    export PATH
    hash -r
}

# tool_version_of <canonical tool> -> installed version of TOOL_PATH.
tool_version_of() {
    local canon=$1 flag=--version sdk out
    case "$canon" in
        flutter)
            sdk="$(dirname "$TOOL_PATH")/.."
            if [ -f "$sdk/bin/cache/flutter.version.json" ]; then
                out=$(grep -oE '"frameworkVersion"[[:space:]]*:[[:space:]]*"[^"]+"' "$sdk/bin/cache/flutter.version.json" | sed -E 's/.*"([^"]+)"$/\1/')
                [ -n "$out" ] && { echo "$out"; return 0; }
            fi
            ;;
        go) flag=version ;;
        swift)
            "$TOOL_PATH" --version 2>&1 | grep -oE 'Swift version [0-9]+(\.[0-9]+)*' | head -1 | grep -oE '[0-9]+(\.[0-9]+)*'
            return 0
            ;;
    esac
    "$TOOL_PATH" $flag 2>&1 | head -3 | grep -oE '[0-9]+(\.[0-9]+)+' | head -1
}

_tool_ver_lt() {
    [ "$1" != "$2" ] && [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | head -1)" = "$1" ]
}

_tool_curl() {
    has_cmd curl || return 1
    curl -fsSL --connect-timeout 3 -m 8 "$1" 2>/dev/null
}

_tool_flutter_stable_from_json() {
    if command -v python3 >/dev/null 2>&1; then
        python3 -c 'import sys,json;d=json.load(sys.stdin);h=d["current_release"]["stable"];print(next(r["version"] for r in d["releases"] if r["hash"]==h and r["channel"]=="stable"))' 2>/dev/null
    elif command -v node >/dev/null 2>&1; then
        node -e 'let s="";process.stdin.on("data",c=>s+=c).on("end",()=>{const d=JSON.parse(s);const h=d.current_release.stable;console.log(d.releases.find(r=>r.hash===h&&r.channel==="stable").version)})' 2>/dev/null
    fi
}

_tool_brew_latest() {
    local formula=$1
    case "$1" in python3) formula=python@3 ;; esac
    HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_ANALYTICS=1 brew info --json=v2 "$formula" 2>/dev/null \
        | grep -oE '"stable": ?"[^"]+"' | head -1 | sed -E 's/.*: ?"([^"]+)"/\1/'
}

_tool_fetch_latest() {
    local canon=$1 os line
    case "$canon" in
        flutter)
            os=$(detect_os)
            [ "$os" = "darwin" ] && os=macos
            _tool_curl "https://storage.googleapis.com/flutter_infra_release/releases/releases_${os}.json" | _tool_flutter_stable_from_json
            ;;
        node)
            _tool_curl "https://nodejs.org/dist/index.json" | grep -m1 -E '"lts":"[A-Za-z]' | sed -E 's/.*"version":"v([^"]+)".*/\1/'
            ;;
        go)
            _tool_curl 'https://go.dev/VERSION?m=text' | head -1 | sed 's/^go//'
            ;;
        cargo)
            [ -x "${TOOL_DIR:-}/rustup" ] || return 0
            line=$("$TOOL_DIR/rustup" check 2>/dev/null | grep -m1 '^stable')
            case "$line" in
                *"Update available"*) echo "$line" | sed -E 's/.*-> ([0-9.]+).*/\1/' ;;
                *"Up to date"*)       echo "$line" | sed -E 's/.*: ([0-9.]+).*/\1/' ;;
            esac
            ;;
        dart) ;;
        *)
            [ "$TOOL_MANAGER" = "brew" ] && has_cmd brew && _tool_brew_latest "$canon"
            ;;
    esac
}

# tool_latest <canonical tool> -> newest known version; cached 12h. With
# XGEM_NO_NETWORK=1 only the cache is consulted.
tool_latest() {
    local canon=$1 f v
    f="$XGEM_CACHE_DIR/latest-$canon"
    if [ "$XGEM_NO_NETWORK" = "1" ]; then
        [ -f "$f" ] && cat "$f"
        return 0
    fi
    if [ -f "$f" ] && [ -n "$(find "$f" -mmin -720 2>/dev/null)" ]; then
        cat "$f"
        return 0
    fi
    v=$(_tool_fetch_latest "$canon")
    if [ -n "$v" ]; then
        mkdir -p "$XGEM_CACHE_DIR"
        echo "$v" > "$f"
        echo "$v"
    elif [ -f "$f" ]; then
        cat "$f"
    fi
}

# tool_install_cmd <canonical tool> -> a shell command that installs it on
# this platform, or empty if there's no safe automated route.
tool_install_cmd() {
    local canon=$1 nvm_sh="${NVM_DIR:-$HOME/.nvm}/nvm.sh"
    case "$(detect_os)" in
        darwin)
            case "$canon" in
                flutter|dart)
                    if has_cmd fvm; then echo "fvm install stable && fvm global stable"
                    else echo "brew install --cask flutter"; fi ;;
                node)
                    if [ -s "$nvm_sh" ]; then echo "bash -c 'source \"$nvm_sh\" && nvm install --lts'"
                    else echo "brew install node"; fi ;;
                python3) echo "brew install python" ;;
                go)      echo "brew install go" ;;
                docker)  echo "brew install --cask docker-desktop" ;;
                git)     echo "brew install git" ;;
                gh)      echo "brew install gh" ;;
                fvm)     echo "brew install fvm" ;;
                cargo)   echo "curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y" ;;
                swift)   echo "xcode-select --install" ;;
            esac
            ;;
        linux)
            case "$canon" in
                cargo) echo "curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y" ;;
                fvm)   echo "curl -fsSL https://fvm.app/install.sh | bash" ;;
                node)
                    [ -s "$nvm_sh" ] && echo "bash -c 'source \"$nvm_sh\" && nvm install --lts'" ;;
            esac
            ;;
    esac
}

# tool_ensure <tool> -> 0 once the tool is usable. Explains what's needed,
# where to get it, and offers to install it; the caller then continues with
# whatever was originally requested.
tool_ensure() {
    local tool=$1 canon recipe
    canon=$(_tool_canon "$tool")
    has_cmd "$tool" && return 0

    log_warn "$(tool_display "$canon") is required for this but wasn't found (checked PATH, version managers like fvm/nvm, and common install locations)."
    echo "  Download: $(tool_url "$canon")"

    recipe=$(tool_install_cmd "$canon")
    if [ -z "$recipe" ]; then
        log_info "Install it from the link above, then re-run this command."
        return 1
    fi

    case "$recipe" in
        brew*)
            if ! command -v brew >/dev/null 2>&1; then
                log_info "That install route needs Homebrew (https://brew.sh) — install it first, or use the download link above."
                return 1
            fi
            ;;
    esac

    echo "  Install command: $recipe"
    confirm "Install $(tool_display "$canon") now?" || { log_info "Skipped. Install it from the link above when you're ready."; return 1; }

    if ! bash -c "$recipe"; then
        log_error "The install command failed (see its output above)."
        return 1
    fi

    hash -r
    if has_cmd "$tool"; then
        log_success "$(tool_display "$canon") is ready."
        return 0
    fi
    log_warn "Install finished but '$tool' still isn't reachable — you may need to open a new terminal or add it to PATH."
    return 1
}

# tool_update_cmd <canonical tool> -> command that updates it given the
# current TOOL_MANAGER, or empty when only a manual download applies.
tool_update_cmd() {
    local canon=$1 latest=$2 nvm_sh="${NVM_DIR:-$HOME/.nvm}/nvm.sh"
    case "$canon" in
        flutter)
            case "$TOOL_MANAGER" in
                fvm)  echo "fvm install $latest" ;;
                brew) echo "brew upgrade --cask flutter" ;;
                *)    echo "flutter upgrade" ;;
            esac ;;
        node)
            case "$TOOL_MANAGER" in
                nvm)  echo "bash -c 'source \"$nvm_sh\" && nvm install --lts'" ;;
                brew) echo "brew upgrade node" ;;
            esac ;;
        cargo) [ "$TOOL_MANAGER" = "rustup" ] && echo "rustup update" ;;
        *)
            [ "$TOOL_MANAGER" = "brew" ] && case "$canon" in
                python3) echo "brew upgrade python" ;;
                docker)  echo "brew upgrade docker" ;;
                *)       echo "brew upgrade $canon" ;;
            esac ;;
    esac
}
