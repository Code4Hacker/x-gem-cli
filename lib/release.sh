#!/bin/bash
# xgem release: framework-aware version bump + changelog + tag + push.
# Depends on lib/logger.sh, lib/utils.sh, lib/git.sh (_git_default_remote).

_release_detect_version_files() {
    local -a found=()
    [ -f package.json ]   && found+=(package.json)
    [ -f pubspec.yaml ]   && found+=(pubspec.yaml)
    [ -f Cargo.toml ]     && found+=(Cargo.toml)
    [ -f pyproject.toml ] && found+=(pyproject.toml)
    printf '%s\n' "${found[@]}"
}

# _release_read_version <file> -> current version string (empty on failure)
_release_read_version() {
    case "$1" in
        package.json)
            grep -m1 '"version"' package.json | sed -E 's/.*"version"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/'
            ;;
        pubspec.yaml)
            grep '^version:' pubspec.yaml | head -1 | awk '{print $2}'
            ;;
        Cargo.toml|pyproject.toml)
            grep -m1 -E '^version[[:space:]]*=' "$1" | sed -E 's/^version[[:space:]]*=[[:space:]]*"([^"]+)".*/\1/'
            ;;
    esac
}

# _release_write_version <file> <new_version>
# Uses awk (not sed's GNU-only "0,/re/" first-match addressing, which BSD
# sed on macOS doesn't support) to replace only the first matching line.
_release_write_version() {
    local file=$1 new=$2 tmp
    tmp=$(mktemp)
    case "$file" in
        package.json)
            awk -v new="$new" '
                !done && /"version"[[:space:]]*:[[:space:]]*"[^"]*"/ {
                    sub(/"version"[[:space:]]*:[[:space:]]*"[^"]*"/, "\"version\": \"" new "\"")
                    done = 1
                }
                { print }
            ' "$file" > "$tmp" && mv "$tmp" "$file"
            ;;
        pubspec.yaml)
            sed -E "s/^version:.*/version: $new/" "$file" > "$tmp" && mv "$tmp" "$file"
            ;;
        Cargo.toml|pyproject.toml)
            awk -v new="$new" '
                !done && /^version[[:space:]]*=[[:space:]]*"[^"]*"/ {
                    sub(/^version[[:space:]]*=[[:space:]]*"[^"]*"/, "version = \"" new "\"")
                    done = 1
                }
                { print }
            ' "$file" > "$tmp" && mv "$tmp" "$file"
            ;;
    esac
}

# _release_bump <version> <major|minor|patch> -> new version, or empty if
# <version> isn't a plain X.Y.Z.
_release_bump() {
    local version=$1 kind=$2 suffix="" core
    core=${version%%+*}
    [ "$core" != "$version" ] && suffix="+${version#*+}"

    [[ "$core" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]] || return 1
    local major=${BASH_REMATCH[1]} minor=${BASH_REMATCH[2]} patch=${BASH_REMATCH[3]}
    case "$kind" in
        major) major=$((major + 1)); minor=0; patch=0 ;;
        minor) minor=$((minor + 1)); patch=0 ;;
        patch) patch=$((patch + 1)) ;;
    esac
    echo "${major}.${minor}.${patch}${suffix}"
}

_release_write_changelog() {
    local version=$1 last_tag=$2
    local -a features=() fixes=() other=()
    local subject

    while IFS= read -r subject; do
        [ -n "$subject" ] || continue
        case "$subject" in
            feat*) features+=("$subject") ;;
            fix*)  fixes+=("$subject") ;;
            *)     other+=("$subject") ;;
        esac
    done < <(git log --format='%s' "${last_tag:+$last_tag..}HEAD" 2>/dev/null)

    local tmp
    tmp=$(mktemp)
    {
        echo "## v$version - $(date +%Y-%m-%d)"
        if [ ${#features[@]} -gt 0 ]; then
            echo ""
            echo "### Features"
            printf -- '- %s\n' "${features[@]}"
        fi
        if [ ${#fixes[@]} -gt 0 ]; then
            echo ""
            echo "### Fixes"
            printf -- '- %s\n' "${fixes[@]}"
        fi
        if [ ${#other[@]} -gt 0 ]; then
            echo ""
            echo "### Other"
            printf -- '- %s\n' "${other[@]}"
        fi
        echo ""
        if [ -f CHANGELOG.md ]; then
            tail -n +2 CHANGELOG.md
        fi
    } > "$tmp"
    { echo "# Changelog"; echo ""; cat "$tmp"; } > CHANGELOG.md
    rm -f "$tmp"
}

cmd_release() {
    local -a version_files=()
    while IFS= read -r f; do version_files+=("$f"); done < <(_release_detect_version_files)
    [ ${#version_files[@]} -gt 0 ] || die "No recognized version file (package.json/pubspec.yaml/Cargo.toml/pyproject.toml) found here."

    local file
    if [ ${#version_files[@]} -eq 1 ]; then
        file="${version_files[0]}"
    else
        echo "Multiple version files found:"
        local i=1
        for f in "${version_files[@]}"; do
            echo "$i) $f"
            i=$((i + 1))
        done
        local choice
        read -r -p "Which is the canonical one to bump? [1-${#version_files[@]}]: " choice
        [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#version_files[@]} ] \
            || die "Invalid selection."
        file="${version_files[$((choice - 1))]}"
    fi

    local current new_version bump_kind
    current=$(_release_read_version "$file")
    [ -n "$current" ] || die "Could not read a version from $file."
    log_info "Current version in $file: $current"

    bump_kind=$1
    case "$bump_kind" in
        major|minor|patch) ;;
        "")
            read -r -p "Bump [major/minor/patch] (default: patch): " bump_kind
            bump_kind=${bump_kind:-patch}
            ;;
        *) die "Unknown bump kind '$bump_kind'. Usage: xgem release [major|minor|patch]" ;;
    esac

    new_version=$(_release_bump "$current" "$bump_kind")
    if [ -z "$new_version" ]; then
        log_warn "'$current' isn't a plain X.Y.Z version — can't bump it automatically."
        read -r -p "Enter the new version directly: " new_version
        [ -n "$new_version" ] || die "A new version is required."
    fi

    log_info "$current -> $new_version"
    confirm "Write this version, update CHANGELOG.md, commit, and tag?" || { log_info "Cancelled."; return 0; }

    _release_write_version "$file" "$new_version"

    local last_tag
    last_tag=$(git describe --tags --abbrev=0 2>/dev/null)
    _release_write_changelog "$new_version" "$last_tag"

    git add "$file" CHANGELOG.md
    git commit -m "chore(release): v$new_version" || die "Commit failed."
    git tag -a "v$new_version" -m "v$new_version" || die "Tag failed."
    log_success "Committed and tagged v$new_version."

    local remote current_branch
    remote=$(_git_default_remote)
    if [ -n "$remote" ] && confirm "Push commit and tag to '$remote'?"; then
        current_branch=$(git branch --show-current 2>/dev/null)
        git push "$remote" "$current_branch" && git push "$remote" "v$new_version" \
            && log_success "Pushed v$new_version to '$remote'." \
            || die "Push failed — the commit and tag are safe locally."
    fi
}
