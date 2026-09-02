#!/bin/bash
# xgem git workflow helper: cmt / init / branch / rm-remote / rm-branch /
# pr / sync / clean-branches / hooks.
# Depends on lib/logger.sh, lib/utils.sh.

# _git_default_remote -> "origin" if configured, else the first remote,
# else empty.
_git_default_remote() {
    if git remote | grep -q "^origin$"; then
        echo origin
    else
        git remote | head -n 1
    fi
}

# _git_base_branch <remote> -> the repo's default branch. Prefers gh's own
# knowledge of it (accurate, no guessing); falls back to probing common
# names against the remote's tracking refs when gh is unavailable/offline.
_git_base_branch() {
    local remote=$1
    local base
    if has_cmd gh; then
        base=$(gh repo view --json defaultBranchRef --jq .defaultBranchRef.name 2>/dev/null)
        [ -n "$base" ] && { echo "$base"; return 0; }
    fi
    local candidate
    for candidate in main master develop dev; do
        if git show-ref --verify --quiet "refs/remotes/$remote/$candidate"; then
            echo "$candidate"
            return 0
        fi
    done
    return 1
}

cmd_git_cmt() {
    local commit_msg=$1
    [ -n "$commit_msg" ] || die "Missing commit message!"

    log_info "Checking repository status..."
    git status -s
    echo ""

    local add_choice
    read -r -p "Do you want to add ALL files (a) or INDIVIDUAL files (i)? [a/i]: " add_choice
    if [[ "$add_choice" == "a" || "$add_choice" == "A" ]]; then
        git add .
        log_success "All files staged."
    elif [[ "$add_choice" == "i" || "$add_choice" == "I" ]]; then
        local -a specific_files
        read -r -p "Enter specific file paths to add (space separated): " -a specific_files
        git add "${specific_files[@]}"
        log_success "Selected files staged."
    else
        die "Invalid choice. Operation aborted."
    fi

    if git diff --cached --quiet; then
        log_warn "Nothing staged to commit — checking whether there's anything already committed to sync."
    else
        log_info "Committing changes..."
        if ! git commit -m "$commit_msg"; then
            die "Commit failed. Aborting before pull/push."
        fi
    fi

    local current_branch remote_name
    current_branch=$(git branch --show-current 2>/dev/null)
    remote_name=$(_git_default_remote)

    if [ -z "$remote_name" ]; then
        log_warn "No remote configured — sync was skipped."
        return 0
    fi

    # A pull needs something to pull FROM. If this branch has never been
    # pushed before, there's no remote ref to pull, and `git pull --rebase`
    # fails with "couldn't find remote ref <branch>" — which is not a
    # connection problem or a conflict, just a brand-new branch. Check for
    # that specific case first so it gets its own accurate message instead
    # of being lumped in with real connectivity failures.
    git ls-remote --exit-code --heads "$remote_name" "$current_branch" >/dev/null 2>&1
    local ls_remote_status=$?

    if [ "$ls_remote_status" -eq 2 ]; then
        log_info "'$current_branch' doesn't exist on '$remote_name' yet — pushing to create it..."
        if git push -u "$remote_name" "$current_branch"; then
            log_success "Git workflow complete! Branch created and pushed."
        else
            die "Push operation failed."
        fi
        return 0
    elif [ "$ls_remote_status" -ne 0 ]; then
        log_error "Could not reach '$remote_name' to check for '$current_branch' — this looks like a real connection problem."
        log_warn "Your commit is safe locally. Re-run 'xgem git cmt' once connectivity is restored, or push manually: git push $remote_name $current_branch"
        exit 1
    fi

    local ahead_count
    ahead_count=$(git rev-list --count "$remote_name/$current_branch..$current_branch" 2>/dev/null)
    if [ "$ahead_count" = "0" ]; then
        log_success "Already up to date with '$remote_name/$current_branch' — nothing to push."
        return 0
    fi

    log_info "Pulling updates from remote '$remote_name' on '$current_branch' via rebase..."
    if ! git pull --rebase "$remote_name" "$current_branch"; then
        local git_dir
        git_dir=$(git rev-parse --git-dir 2>/dev/null)
        if [ -d "$git_dir/rebase-merge" ] || [ -d "$git_dir/rebase-apply" ]; then
            log_error "MERGE CONFLICT DETECTED!"
            log_warn "Execution paused. Resolve conflicts to proceed."
        else
            log_error "Could not sync with '$remote_name' — this looks like a connection problem, not a merge conflict (see the git error above)."
            log_warn "Your commit is safe locally. Re-run 'xgem git cmt' once connectivity is restored, or push manually: git push $remote_name $current_branch"
            exit 1
        fi
        local open_editor
        read -r -p "Do you want to open VS Code to resolve this now? (y/n): " open_editor
        [[ "$open_editor" == "y" || "$open_editor" == "Y" ]] && code .
        exit 1
    fi

    log_success "Clean sync pull achieved. Pushing to upstream target..."
    if git push "$remote_name" "$current_branch"; then
        log_success "Git workflow complete! Code cleanly committed and synchronized."
    else
        die "Push operation failed."
    fi
}

_cmd_git_init_manual_remote() {
    local remote_name=$1
    local remote_url user_remote_name
    read -r -p "Enter remote repository URL (or leave blank to skip): " remote_url
    [ -n "$remote_url" ] || return 0

    read -r -p "Enter remote name (default: $remote_name): " user_remote_name
    [ -n "$user_remote_name" ] && remote_name="$user_remote_name"

    if git remote | grep -q "^$remote_name$"; then
        git remote set-url "$remote_name" "$remote_url"
        log_success "Remote '$remote_name' already existed. URL updated."
    else
        git remote add "$remote_name" "$remote_url"
        log_success "Remote '$remote_name' successfully added."
    fi
}

cmd_git_init() {
    log_info "Initializing local Git repository..."
    git init

    local branch_name
    read -r -p "Enter branch name (default: main): " branch_name
    branch_name=${branch_name:-main}
    git branch -M "$branch_name"

    git add .
    git commit -m "initial changes" 2>/dev/null

    # Real GitHub repo creation, not just wiring a remote to a URL you
    # already had to go create by hand — this is the whole point of
    # `xgem git init` over plain `git init`. Falls back to the manual-URL
    # flow if `gh` isn't installed/authenticated.
    if has_cmd gh && gh auth status >/dev/null 2>&1; then
        local create_choice
        read -r -p "Create a new GitHub repository for this project right now? (Y/n): " create_choice
        create_choice=${create_choice:-y}
        if [[ "$create_choice" == "y" || "$create_choice" == "Y" ]]; then
            local repo_name visibility vis_flag
            read -r -p "Repository name (default: $(basename "$PWD")): " repo_name
            repo_name=${repo_name:-$(basename "$PWD")}
            read -r -p "Public or private? [public/private] (default: private): " visibility
            visibility=${visibility:-private}
            vis_flag="--private"
            [[ "$visibility" == pub* || "$visibility" == Pub* ]] && vis_flag="--public"

            if gh repo create "$repo_name" "$vis_flag" --source=. --remote=origin --push; then
                log_success "Created GitHub repo '$repo_name' and pushed '$branch_name' to it."
            else
                log_error "gh repo create failed — falling back to manual remote setup."
                _cmd_git_init_manual_remote origin
            fi
            log_success "Local baseline configuration setup completed."
            return 0
        fi
    elif has_cmd gh; then
        log_warn "GitHub CLI (gh) is installed but not authenticated — run 'gh auth login' to enable one-step repo creation next time."
    fi

    _cmd_git_init_manual_remote origin
    log_success "Local baseline configuration setup completed."
}

cmd_git_rm_remote() {
    log_info "Current configured remotes:"
    git remote -v
    echo ""

    local remote_name
    read -r -p "Enter the short remote name to remove (e.g. origin): " remote_name
    remote_name=${remote_name:-origin}

    if git remote | grep -q "^$remote_name$"; then
        git remote remove "$remote_name"
        log_success "Successfully removed remote reference configuration: $remote_name"
    else
        die "Remote tracking short-name '$remote_name' does not exist."
    fi
}

cmd_git_rm_branch() {
    local target_branch
    read -r -p "Enter the name of the branch you want to target: " target_branch
    [ -n "$target_branch" ] || die "Branch name cannot be empty."

    local where_choice
    read -r -p "Where do you want to delete this branch? (l = local only, r = remote only, b = both) [l/r/b]: " where_choice
    echo ""

    if [[ "$where_choice" =~ ^[lLbB]$ ]]; then
        local current_branch
        current_branch=$(git branch --show-current 2>/dev/null)
        if [ "$current_branch" = "$target_branch" ]; then
            log_warn "You are currently sitting on '$target_branch'. Switching to safe branch..."
            git checkout main 2>/dev/null || git checkout master 2>/dev/null || git checkout dev 2>/dev/null
        fi

        log_info "Force deleting local branch '$target_branch'..."
        if git branch -D "$target_branch"; then
            log_success "Successfully deleted local copy of branch."
        else
            log_warn "Local branch could not be dropped (it may already be gone)."
        fi
    fi

    if [[ "$where_choice" =~ ^[rRbB]$ ]]; then
        local remote_target
        read -r -p "Enter remote identifier (short-name like 'origin'): " remote_target
        remote_target=${remote_target:-origin}

        log_info "Sending deletion request for remote branch '$target_branch' to server..."
        if git push "$remote_target" --delete "$target_branch"; then
            log_success "Successfully wiped out remote branch '$target_branch' from server."
        else
            die "Server rejected the branch drop execution request."
        fi
    fi
}

# cmd_git_branch: lists local branches, lets the user pick one (or create a
# new one), checks it out, and remembers it as this repo's default so
# there's a quick way back to it later. `xgem git cmt` always operates on
# whatever's actually checked out (that's the only thing that's correct for
# a commit), so this command's job is the checkout + remembering, not
# changing how cmt picks its branch.
cmd_git_branch() {
    local -a branches=()
    while IFS= read -r line; do
        [ -n "$line" ] && branches+=("$line")
    done < <(git branch --format='%(refname:short)' 2>/dev/null)

    [ ${#branches[@]} -gt 0 ] || die "No local branches found."

    local current_branch
    current_branch=$(git branch --show-current 2>/dev/null)

    echo "Available branches:"
    local i=1 b
    for b in "${branches[@]}"; do
        if [ "$b" = "$current_branch" ]; then
            echo "$i) $b (current)"
        else
            echo "$i) $b"
        fi
        i=$((i + 1))
    done
    local create_option=$i
    echo "$create_option) Create new branch"

    local choice
    read -r -p "Select [1-$create_option]: " choice

    if [ "$choice" = "$create_option" ]; then
        local new_branch
        read -r -p "Enter new branch name: " new_branch
        [ -n "$new_branch" ] || die "Branch name cannot be empty."
        git checkout -b "$new_branch" || die "Could not create branch '$new_branch'."
        git config --local xgem.default-branch "$new_branch"
        log_success "Created and switched to '$new_branch', set as default for this repo."
        return 0
    fi

    if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt ${#branches[@]} ]; then
        die "Invalid selection."
    fi

    local selected="${branches[$((choice - 1))]}"
    if [ "$selected" != "$current_branch" ]; then
        git checkout "$selected" || die "Could not switch to branch '$selected'."
    fi
    git config --local xgem.default-branch "$selected"
    log_success "Switched to '$selected' and set as default for this repo."
}

cmd_git_pr() {
    local current_branch remote base
    current_branch=$(git branch --show-current 2>/dev/null)
    [ -n "$current_branch" ] || die "Not on a branch (detached HEAD?) — nothing to open a PR from."
    remote=$(_git_default_remote)
    [ -n "$remote" ] || die "No remote configured."

    if ! has_cmd gh || ! gh auth status >/dev/null 2>&1; then
        has_cmd gh && log_warn "GitHub CLI (gh) is installed but not authenticated — run 'gh auth login' to enable 'xgem git pr'." \
            || log_warn "GitHub CLI (gh) is not installed — install it for 'xgem git pr' to open PRs directly: https://cli.github.com"
        local url owner_repo remote_url
        remote_url=$(git remote get-url "$remote" 2>/dev/null)
        owner_repo=$(echo "$remote_url" | sed -E 's#^git@[^:]+:##; s#^https?://[^/]+/##; s#\.git$##')
        [ -n "$owner_repo" ] || die "Could not determine owner/repo from remote '$remote' ($remote_url)."
        base=$(_git_base_branch "$remote")
        url="https://github.com/$owner_repo/compare/${base:-main}...$current_branch?expand=1"
        log_info "Open this URL to create the PR manually: $url"
        confirm "Open it in your browser now?" && _open_url "$url"
        return 0
    fi

    base=$(_git_base_branch "$remote") || die "Could not determine the repo's base branch."
    [ "$current_branch" != "$base" ] || die "You're on '$base' — switch to a feature branch first."

    log_info "Pushing '$current_branch' to '$remote'..."
    git push -u "$remote" "$current_branch" || die "Push failed."

    if gh pr view --json number >/dev/null 2>&1; then
        log_success "A PR for '$current_branch' already exists."
        confirm "Open it in your browser?" && gh pr view --web
        return 0
    fi

    local commits commit_count title body
    commits=$(git log --format='%s' "$remote/$base..HEAD" 2>/dev/null)
    commit_count=$(echo "$commits" | grep -c .)

    if [ "$commit_count" -le 1 ]; then
        title=$(echo "$commits" | head -1)
        body=""
    else
        # sed's \U (uppercase-first) is GNU-only — BSD sed on macOS passes
        # it through literally instead of applying it. Capitalize via tr
        # on just the first character instead, which is portable.
        title=$(echo "$current_branch" | sed -E 's/[-_]/ /g')
        title="$(echo "${title:0:1}" | tr '[:lower:]' '[:upper:]')${title:1}"
        body=$(echo "$commits" | sed 's/^/- /')
    fi

    local title_override
    read -r -p "PR title [$title]: " title_override
    [ -n "$title_override" ] && title="$title_override"
    [ -n "$title" ] || die "A PR title is required."

    if gh pr create --title "$title" --body "$body" --base "$base"; then
        log_success "PR created."
        confirm "Open it in your browser?" && gh pr view --web
    else
        die "gh pr create failed."
    fi
}

cmd_git_sync() {
    local remote base current_branch
    remote=$(_git_default_remote)
    [ -n "$remote" ] || die "No remote configured."
    base=$(_git_base_branch "$remote") || die "Could not determine the repo's base branch."
    current_branch=$(git branch --show-current 2>/dev/null)

    log_info "Fetching '$base' from '$remote'..."
    git fetch "$remote" "$base" || die "Fetch failed."

    log_info "Rebasing '$current_branch' onto '$remote/$base'..."
    if git rebase "$remote/$base"; then
        log_success "'$current_branch' is now up to date with '$remote/$base'."
        return 0
    fi

    local git_dir
    git_dir=$(git rev-parse --git-dir 2>/dev/null)
    if [ -d "$git_dir/rebase-merge" ] || [ -d "$git_dir/rebase-apply" ]; then
        log_error "MERGE CONFLICT DETECTED!"
        log_warn "Execution paused. Resolve conflicts, then 'git rebase --continue'."
        local open_editor
        read -r -p "Do you want to open VS Code to resolve this now? (y/n): " open_editor
        [[ "$open_editor" == "y" || "$open_editor" == "Y" ]] && code .
    else
        log_error "Rebase failed — this looks like a connection problem, not a merge conflict (see the git error above)."
    fi
    exit 1
}

cmd_git_clean_branches() {
    local remote base current_branch
    remote=$(_git_default_remote)
    [ -n "$remote" ] || die "No remote configured."

    log_info "Pruning stale remote-tracking refs on '$remote'..."
    git fetch "$remote" --prune || die "Fetch failed."

    base=$(_git_base_branch "$remote") || die "Could not determine the repo's base branch."
    current_branch=$(git branch --show-current 2>/dev/null)

    local -a candidates=()
    while IFS= read -r b; do
        [ -n "$b" ] || continue
        case "$b" in
            "$current_branch"|main|master|develop|dev) continue ;;
        esac
        candidates+=("$b")
    done < <(git branch --format='%(refname:short)' --merged "$remote/$base" 2>/dev/null)

    if [ ${#candidates[@]} -eq 0 ]; then
        log_success "No merged local branches to clean up."
        return 0
    fi

    log_info "Local branches already merged into '$base':"
    printf '  - %s\n' "${candidates[@]}"

    confirm "Delete all ${#candidates[@]} of these local branches?" || { log_info "Cancelled."; return 0; }

    local b
    for b in "${candidates[@]}"; do
        if git branch -d "$b" >/dev/null 2>&1; then
            log_success "Deleted '$b'."
        else
            log_warn "Could not delete '$b' (not fully merged?) — left as-is."
        fi
    done
}

_GIT_HOOK_MARKER="# xgem-managed-hook"

cmd_git_hooks_install() {
    local git_dir hook_path
    git_dir=$(git rev-parse --git-dir 2>/dev/null) || die "Not a git repository."
    hook_path="$git_dir/hooks/pre-commit"

    if [ -f "$hook_path" ] && ! grep -qF "$_GIT_HOOK_MARKER" "$hook_path"; then
        log_warn "An existing pre-commit hook was found that xgem didn't create."
        confirm "Overwrite it?" || { log_info "Cancelled."; return 0; }
    fi

    local run_tests xgem_path
    read -r -p "Also run tests before commit (slower)? (y/N): " run_tests
    xgem_path=$(command -v xgem)
    [ -n "$xgem_path" ] || die "Could not resolve xgem's own path via 'command -v xgem'."

    local checks_added=0
    {
        echo "#!/bin/bash"
        echo "$_GIT_HOOK_MARKER"
        local fw
        for fw in "$CONFIG_DIR"/*/; do
            [ -d "$fw" ] || continue
            fw=$(basename "$fw")
            if [ -f "$CONFIG_DIR/$fw/lint.sh" ]; then
                echo "\"$xgem_path\" run $fw lint || exit 1"
                checks_added=$((checks_added + 1))
            fi
            if [[ "$run_tests" == "y" || "$run_tests" == "Y" ]] && [ -f "$CONFIG_DIR/$fw/test.sh" ]; then
                echo "\"$xgem_path\" run $fw test || exit 1"
                checks_added=$((checks_added + 1))
            fi
        done
    } > "$hook_path"
    chmod +x "$hook_path"

    if [ "$checks_added" -eq 0 ]; then
        log_warn "No lint/test scripts found under $CONFIG_DIR — installed a hook that doesn't check anything yet."
    fi
    log_success "Installed pre-commit hook at $hook_path."
}

cmd_git_hooks_uninstall() {
    local git_dir hook_path
    git_dir=$(git rev-parse --git-dir 2>/dev/null) || die "Not a git repository."
    hook_path="$git_dir/hooks/pre-commit"

    [ -f "$hook_path" ] || { log_info "No pre-commit hook installed."; return 0; }
    grep -qF "$_GIT_HOOK_MARKER" "$hook_path" || die "$hook_path wasn't created by xgem — not removing it."

    rm -f "$hook_path"
    log_success "Removed pre-commit hook."
}

cmd_git_hooks() {
    case "$1" in
        install)   cmd_git_hooks_install ;;
        uninstall) cmd_git_hooks_uninstall ;;
        *) die "Usage: xgem git hooks <install|uninstall>" ;;
    esac
}

# xgem git <cmt|init|rm-remote|rm-branch|branch|pr|sync|clean-branches|hooks> ...
cmd_git() {
    case "$1" in
        cmt)            cmd_git_cmt "$2" ;;
        init)           cmd_git_init ;;
        rm-remote)      cmd_git_rm_remote ;;
        rm-branch)      cmd_git_rm_branch ;;
        branch)         cmd_git_branch ;;
        pr)             cmd_git_pr ;;
        sync)           cmd_git_sync ;;
        clean-branches) cmd_git_clean_branches ;;
        hooks)          cmd_git_hooks "$2" ;;
        *) die "Unknown git subcommand '$1'. Usage: xgem git <cmt|init|rm-remote|rm-branch|branch|pr|sync|clean-branches|hooks>" ;;
    esac
}
