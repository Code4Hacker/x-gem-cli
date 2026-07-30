#!/bin/bash
# xgem git workflow helper: cmt / init / rm-remote / rm-branch.
# Depends on lib/logger.sh.

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
    if git remote | grep -q "^origin$"; then
        remote_name="origin"
    else
        remote_name=$(git remote | head -n 1)
    fi

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

cmd_git_init() {
    log_info "Initializing local Git repository..."
    git init

    local remote_name="origin" remote_url user_remote_name branch_name
    read -r -p "Enter remote repository URL: " remote_url
    if [ -n "$remote_url" ]; then
        read -r -p "Enter remote name (default: origin): " user_remote_name
        [ -n "$user_remote_name" ] && remote_name="$user_remote_name"

        if git remote | grep -q "^$remote_name$"; then
            git remote set-url "$remote_name" "$remote_url"
            log_success "Remote '$remote_name' already existed. URL updated."
        else
            git remote add "$remote_name" "$remote_url"
            log_success "Remote '$remote_name' successfully added."
        fi
    fi

    read -r -p "Enter branch name (default: main): " branch_name
    branch_name=${branch_name:-main}
    git branch -M "$branch_name"

    git add .
    git commit -m "initial changes" 2>/dev/null
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

# xgem git <cmt|init|rm-remote|rm-branch|branch> ...
cmd_git() {
    case "$1" in
        cmt)       cmd_git_cmt "$2" ;;
        init)      cmd_git_init ;;
        rm-remote) cmd_git_rm_remote ;;
        rm-branch) cmd_git_rm_branch ;;
        branch)    cmd_git_branch ;;
        *) die "Unknown git subcommand '$1'. Usage: xgem git <cmt|init|rm-remote|rm-branch|branch>" ;;
    esac
}
