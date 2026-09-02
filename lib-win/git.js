// xgem Windows engine git workflow — port of lib/git.sh (cmt/init/rm-remote/rm-branch).
// git.exe behaves the same on Windows, so this is a straight port; the
// commit-exit-code check and origin-preference fix already in lib/git.sh
// carry over here too.

const fs = require('node:fs');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const { logInfo, logSuccess, logWarn, logError, die } = require('./logger');
const { prompt, confirm, hasCmd, openUrl } = require('./utils');

function git(args, opts = {}) {
    return spawnSync('git', args, { stdio: 'inherit', ...opts });
}

function gh(args, opts = {}) {
    return spawnSync('gh', args, { stdio: 'inherit', ...opts });
}

function ghAuthenticated() {
    return spawnSync('gh', ['auth', 'status'], { stdio: 'ignore' }).status === 0;
}

function gitCapture(args) {
    const result = spawnSync('git', args, { encoding: 'utf8' });
    return (result.stdout || '').trim();
}

function ghCapture(args) {
    const result = spawnSync('gh', args, { encoding: 'utf8' });
    return result.status === 0 ? (result.stdout || '').trim() : '';
}

function remoteExists(name) {
    return gitCapture(['remote']).split(/\r?\n/).includes(name);
}

// defaultRemote() -> "origin" if configured, else the first remote, else ''.
function defaultRemote() {
    if (remoteExists('origin')) return 'origin';
    return gitCapture(['remote']).split(/\r?\n/)[0] || '';
}

// baseBranch(remote) -> the repo's default branch, via gh's own knowledge
// where possible, else probing common names against the remote's
// tracking refs.
function baseBranch(remote) {
    if (hasCmd('gh')) {
        const base = ghCapture(['repo', 'view', '--json', 'defaultBranchRef', '--jq', '.defaultBranchRef.name']);
        if (base) return base;
    }
    for (const candidate of ['main', 'master', 'develop', 'dev']) {
        if (git(['show-ref', '--verify', '--quiet', `refs/remotes/${remote}/${candidate}`], { stdio: 'ignore' }).status === 0) {
            return candidate;
        }
    }
    return '';
}

async function cmdCmt(commitMsg) {
    if (!commitMsg) die('Missing commit message!');

    logInfo('Checking repository status...');
    git(['status', '-s']);
    console.log('');

    const addChoice = (await prompt('Do you want to add ALL files (a) or INDIVIDUAL files (i)? [a/i]')).toLowerCase();
    if (addChoice === 'a') {
        git(['add', '.']);
        logSuccess('All files staged.');
    } else if (addChoice === 'i') {
        const files = await prompt('Enter specific file paths to add (space separated)');
        const fileList = files.split(/\s+/).filter(Boolean);
        if (fileList.length === 0) die('No files given.');
        git(['add', ...fileList]);
        logSuccess('Selected files staged.');
    } else {
        die('Invalid choice. Operation aborted.');
    }

    const hasStaged = spawnSync('git', ['diff', '--cached', '--quiet']).status !== 0;
    if (!hasStaged) {
        logWarn("Nothing staged to commit — checking whether there's anything already committed to sync.");
    } else {
        logInfo('Committing changes...');
        const commitResult = git(['commit', '-m', commitMsg]);
        if (commitResult.status !== 0) {
            die('Commit failed. Aborting before pull/push.');
        }
    }

    const currentBranch = gitCapture(['branch', '--show-current']);
    const remoteName = defaultRemote();

    if (!remoteName) {
        logWarn('No remote configured — sync was skipped.');
        return;
    }

    // A pull needs something to pull FROM. If this branch has never been
    // pushed before, there's no remote ref, and `git pull --rebase` fails
    // with "couldn't find remote ref <branch>" — not a connection problem
    // or a conflict, just a brand-new branch. Check for that case first.
    const lsRemoteStatus = spawnSync('git', ['ls-remote', '--exit-code', '--heads', remoteName, currentBranch]).status;

    if (lsRemoteStatus === 2) {
        logInfo(`'${currentBranch}' doesn't exist on '${remoteName}' yet — pushing to create it...`);
        if (git(['push', '-u', remoteName, currentBranch]).status === 0) {
            logSuccess('Git workflow complete! Branch created and pushed.');
        } else {
            die('Push operation failed.');
        }
        return;
    } else if (lsRemoteStatus !== 0) {
        logError(`Could not reach '${remoteName}' to check for '${currentBranch}' — this looks like a real connection problem.`);
        logWarn(`Your commit is safe locally. Re-run 'xgem git cmt' once connectivity is restored, or push manually: git push ${remoteName} ${currentBranch}`);
        process.exit(1);
    }

    const aheadCount = gitCapture(['rev-list', '--count', `${remoteName}/${currentBranch}..${currentBranch}`]);
    if (aheadCount === '0') {
        logSuccess(`Already up to date with '${remoteName}/${currentBranch}' — nothing to push.`);
        return;
    }

    logInfo(`Pulling updates from remote '${remoteName}' on '${currentBranch}' via rebase...`);
    const pullResult = git(['pull', '--rebase', remoteName, currentBranch]);
    if (pullResult.status !== 0) {
        const gitDir = gitCapture(['rev-parse', '--git-dir']);
        const fs = require('node:fs');
        const inConflict = fs.existsSync(path.join(gitDir, 'rebase-merge')) || fs.existsSync(path.join(gitDir, 'rebase-apply'));
        if (inConflict) {
            logError('MERGE CONFLICT DETECTED!');
            logWarn('Execution paused. Resolve conflicts to proceed.');
        } else {
            logError(`Could not sync with '${remoteName}' — this looks like a connection problem, not a merge conflict (see the git error above).`);
            logWarn(`Your commit is safe locally. Re-run 'xgem git cmt' once connectivity is restored, or push manually: git push ${remoteName} ${currentBranch}`);
        }
        process.exit(1);
    }

    logSuccess('Clean sync pull achieved. Pushing to upstream target...');
    const pushResult = git(['push', remoteName, currentBranch]);
    if (pushResult.status === 0) {
        logSuccess('Git workflow complete! Code cleanly committed and synchronized.');
    } else {
        die('Push operation failed.');
    }
}

async function manualRemoteSetup(defaultRemoteName) {
    let remoteName = defaultRemoteName;
    const remoteUrl = await prompt('Enter remote repository URL (or leave blank to skip)');
    if (!remoteUrl) return;

    const userRemoteName = await prompt(`Enter remote name (default: ${remoteName})`);
    if (userRemoteName) remoteName = userRemoteName;

    if (remoteExists(remoteName)) {
        git(['remote', 'set-url', remoteName, remoteUrl]);
        logSuccess(`Remote '${remoteName}' already existed. URL updated.`);
    } else {
        git(['remote', 'add', remoteName, remoteUrl]);
        logSuccess(`Remote '${remoteName}' successfully added.`);
    }
}

async function cmdInit() {
    logInfo('Initializing local Git repository...');
    git(['init']);

    const branchName = (await prompt('Enter branch name (default: main)')) || 'main';
    git(['branch', '-M', branchName]);

    git(['add', '.']);
    git(['commit', '-m', 'initial changes']);

    // Real GitHub repo creation, not just wiring a remote to a URL you
    // already had to go create by hand — the whole point of `xgem git
    // init` over plain `git init`. Falls back to the manual-URL flow if
    // `gh` isn't installed/authenticated.
    if (hasCmd('gh') && ghAuthenticated()) {
        const createChoice = (await prompt('Create a new GitHub repository for this project right now? (Y/n)')) || 'y';
        if (createChoice.toLowerCase() === 'y') {
            const cwdName = path.basename(process.cwd());
            const repoName = (await prompt(`Repository name (default: ${cwdName})`)) || cwdName;
            const visibility = ((await prompt('Public or private? [public/private] (default: private)')) || 'private').toLowerCase();
            const visFlag = visibility.startsWith('pub') ? '--public' : '--private';

            const result = gh(['repo', 'create', repoName, visFlag, '--source=.', '--remote=origin', '--push']);
            if (result.status === 0) {
                logSuccess(`Created GitHub repo '${repoName}' and pushed '${branchName}' to it.`);
            } else {
                logError('gh repo create failed — falling back to manual remote setup.');
                await manualRemoteSetup('origin');
            }
            logSuccess('Local baseline configuration setup completed.');
            return;
        }
    } else if (hasCmd('gh')) {
        logWarn("GitHub CLI (gh) is installed but not authenticated — run 'gh auth login' to enable one-step repo creation next time.");
    }

    await manualRemoteSetup('origin');
    logSuccess('Local baseline configuration setup completed.');
}

async function cmdRmRemote() {
    logInfo('Current configured remotes:');
    git(['remote', '-v']);
    console.log('');

    const remoteName = (await prompt('Enter the short remote name to remove (e.g. origin)')) || 'origin';
    if (remoteExists(remoteName)) {
        git(['remote', 'remove', remoteName]);
        logSuccess(`Successfully removed remote reference configuration: ${remoteName}`);
    } else {
        die(`Remote tracking short-name '${remoteName}' does not exist.`);
    }
}

async function cmdRmBranch() {
    const targetBranch = await prompt('Enter the name of the branch you want to target');
    if (!targetBranch) die('Branch name cannot be empty.');

    const whereChoice = (await prompt('Where do you want to delete this branch? (l = local only, r = remote only, b = both) [l/r/b]')).toLowerCase();
    console.log('');

    if (whereChoice === 'l' || whereChoice === 'b') {
        const currentBranch = gitCapture(['branch', '--show-current']);
        if (currentBranch === targetBranch) {
            logWarn(`You are currently sitting on '${targetBranch}'. Switching to safe branch...`);
            for (const fallback of ['main', 'master', 'dev']) {
                if (git(['checkout', fallback], { stdio: 'ignore' }).status === 0) break;
            }
        }

        logInfo(`Force deleting local branch '${targetBranch}'...`);
        if (git(['branch', '-D', targetBranch]).status === 0) {
            logSuccess('Successfully deleted local copy of branch.');
        } else {
            logWarn('Local branch could not be dropped (it may already be gone).');
        }
    }

    if (whereChoice === 'r' || whereChoice === 'b') {
        const remoteTarget = (await prompt("Enter remote identifier (short-name like 'origin')")) || 'origin';
        logInfo(`Sending deletion request for remote branch '${targetBranch}' to server...`);
        if (git(['push', remoteTarget, '--delete', targetBranch]).status === 0) {
            logSuccess(`Successfully wiped out remote branch '${targetBranch}' from server.`);
        } else {
            die('Server rejected the branch drop execution request.');
        }
    }
}

// Lists local branches, lets the user pick one (or create a new one),
// checks it out, and remembers it as this repo's default. cmt always
// operates on whatever's actually checked out — this command's job is the
// checkout + remembering, not changing how cmt picks its branch.
async function cmdBranch() {
    const branches = gitCapture(['branch', '--format=%(refname:short)']).split(/\r?\n/).filter(Boolean);
    if (branches.length === 0) die('No local branches found.');

    const currentBranch = gitCapture(['branch', '--show-current']);

    console.log('Available branches:');
    branches.forEach((b, i) => {
        console.log(`${i + 1}) ${b}${b === currentBranch ? ' (current)' : ''}`);
    });
    const createOption = branches.length + 1;
    console.log(`${createOption}) Create new branch`);

    const choice = await prompt(`Select [1-${createOption}]`);

    if (choice === String(createOption)) {
        const newBranch = await prompt('Enter new branch name');
        if (!newBranch) die('Branch name cannot be empty.');
        if (git(['checkout', '-b', newBranch]).status !== 0) die(`Could not create branch '${newBranch}'.`);
        git(['config', '--local', 'xgem.default-branch', newBranch]);
        logSuccess(`Created and switched to '${newBranch}', set as default for this repo.`);
        return;
    }

    const idx = parseInt(choice, 10) - 1;
    if (Number.isNaN(idx) || idx < 0 || idx >= branches.length) die('Invalid selection.');

    const selected = branches[idx];
    if (selected !== currentBranch) {
        if (git(['checkout', selected]).status !== 0) die(`Could not switch to branch '${selected}'.`);
    }
    git(['config', '--local', 'xgem.default-branch', selected]);
    logSuccess(`Switched to '${selected}' and set as default for this repo.`);
}

async function cmdPr(configDir) {
    const currentBranch = gitCapture(['branch', '--show-current']);
    if (!currentBranch) die('Not on a branch (detached HEAD?) — nothing to open a PR from.');
    const remote = defaultRemote();
    if (!remote) die('No remote configured.');

    if (!hasCmd('gh') || !ghAuthenticated()) {
        if (hasCmd('gh')) logWarn("GitHub CLI (gh) is installed but not authenticated — run 'gh auth login' to enable 'xgem git pr'.");
        else logWarn('GitHub CLI (gh) is not installed — install it for \'xgem git pr\' to open PRs directly: https://cli.github.com');
        const remoteUrl = gitCapture(['remote', 'get-url', remote]);
        const ownerRepo = remoteUrl.replace(/^git@[^:]+:/, '').replace(/^https?:\/\/[^/]+\//, '').replace(/\.git$/, '');
        if (!ownerRepo) die(`Could not determine owner/repo from remote '${remote}' (${remoteUrl}).`);
        const base = baseBranch(remote) || 'main';
        const url = `https://github.com/${ownerRepo}/compare/${base}...${currentBranch}?expand=1`;
        logInfo(`Open this URL to create the PR manually: ${url}`);
        if (await confirm('Open it in your browser now?')) openUrl(url);
        return;
    }

    const base = baseBranch(remote);
    if (!base) die("Could not determine the repo's base branch.");
    if (currentBranch === base) die(`You're on '${base}' — switch to a feature branch first.`);

    logInfo(`Pushing '${currentBranch}' to '${remote}'...`);
    if (git(['push', '-u', remote, currentBranch]).status !== 0) die('Push failed.');

    if (spawnSync('gh', ['pr', 'view', '--json', 'number'], { stdio: 'ignore' }).status === 0) {
        logSuccess(`A PR for '${currentBranch}' already exists.`);
        if (await confirm('Open it in your browser?')) gh(['pr', 'view', '--web']);
        return;
    }

    const commits = gitCapture(['log', '--format=%s', `${remote}/${base}..HEAD`]).split(/\r?\n/).filter(Boolean);
    let title;
    let body;
    if (commits.length <= 1) {
        title = commits[0] || '';
        body = '';
    } else {
        const spaced = currentBranch.replace(/[-_]/g, ' ');
        title = spaced.charAt(0).toUpperCase() + spaced.slice(1);
        body = commits.map((c) => `- ${c}`).join('\n');
    }

    const titleOverride = await prompt(`PR title [${title}]`);
    if (titleOverride) title = titleOverride;
    if (!title) die('A PR title is required.');

    if (gh(['pr', 'create', '--title', title, '--body', body, '--base', base]).status === 0) {
        logSuccess('PR created.');
        if (await confirm('Open it in your browser?')) gh(['pr', 'view', '--web']);
    } else {
        die('gh pr create failed.');
    }
}

async function cmdSync() {
    const remote = defaultRemote();
    if (!remote) die('No remote configured.');
    const base = baseBranch(remote);
    if (!base) die("Could not determine the repo's base branch.");
    const currentBranch = gitCapture(['branch', '--show-current']);

    logInfo(`Fetching '${base}' from '${remote}'...`);
    if (git(['fetch', remote, base]).status !== 0) die('Fetch failed.');

    logInfo(`Rebasing '${currentBranch}' onto '${remote}/${base}'...`);
    if (git(['rebase', `${remote}/${base}`]).status === 0) {
        logSuccess(`'${currentBranch}' is now up to date with '${remote}/${base}'.`);
        return;
    }

    const gitDir = gitCapture(['rev-parse', '--git-dir']);
    const inConflict = fs.existsSync(path.join(gitDir, 'rebase-merge')) || fs.existsSync(path.join(gitDir, 'rebase-apply'));
    if (inConflict) {
        logError('MERGE CONFLICT DETECTED!');
        logWarn("Execution paused. Resolve conflicts, then 'git rebase --continue'.");
        const openEditor = (await prompt('Do you want to open VS Code to resolve this now? (y/n)')).toLowerCase();
        if (openEditor === 'y') spawnSync('code', ['.'], { stdio: 'inherit' });
    } else {
        logError('Rebase failed — this looks like a connection problem, not a merge conflict (see the git error above).');
    }
    process.exit(1);
}

async function cmdCleanBranches() {
    const remote = defaultRemote();
    if (!remote) die('No remote configured.');

    logInfo(`Pruning stale remote-tracking refs on '${remote}'...`);
    if (git(['fetch', remote, '--prune']).status !== 0) die('Fetch failed.');

    const base = baseBranch(remote);
    if (!base) die("Could not determine the repo's base branch.");
    const currentBranch = gitCapture(['branch', '--show-current']);
    const protectedNames = new Set([currentBranch, 'main', 'master', 'develop', 'dev']);

    const candidates = gitCapture(['branch', '--format=%(refname:short)', '--merged', `${remote}/${base}`])
        .split(/\r?\n/)
        .filter((b) => b && !protectedNames.has(b));

    if (candidates.length === 0) {
        logSuccess('No merged local branches to clean up.');
        return;
    }

    logInfo(`Local branches already merged into '${base}':`);
    candidates.forEach((b) => console.log(`  - ${b}`));

    if (!(await confirm(`Delete all ${candidates.length} of these local branches?`))) {
        logInfo('Cancelled.');
        return;
    }

    for (const b of candidates) {
        if (git(['branch', '-d', b]).status === 0) {
            logSuccess(`Deleted '${b}'.`);
        } else {
            logWarn(`Could not delete '${b}' (not fully merged?) — left as-is.`);
        }
    }
}

const HOOK_MARKER = '# xgem-managed-hook';

async function cmdHooksInstall(configDir) {
    const gitDir = gitCapture(['rev-parse', '--git-dir']);
    if (!gitDir) die('Not a git repository.');
    const hooksDir = path.join(gitDir, 'hooks');
    const hookPath = path.join(hooksDir, 'pre-commit');

    if (fs.existsSync(hookPath) && !fs.readFileSync(hookPath, 'utf8').includes(HOOK_MARKER)) {
        logWarn("An existing pre-commit hook was found that xgem didn't create.");
        if (!(await confirm('Overwrite it?'))) { logInfo('Cancelled.'); return; }
    }

    const runTests = (await prompt('Also run tests before commit (slower)? (y/N)')).toLowerCase() === 'y';
    const xgemPath = process.argv[1];

    const lines = ['#!/bin/sh', HOOK_MARKER];
    let checksAdded = 0;
    if (fs.existsSync(configDir)) {
        for (const fw of fs.readdirSync(configDir, { withFileTypes: true }).filter((d) => d.isDirectory()).map((d) => d.name)) {
            if (fs.existsSync(path.join(configDir, fw, 'lint.mjs'))) {
                lines.push(`node "${xgemPath}" run ${fw} lint || exit 1`);
                checksAdded += 1;
            }
            if (runTests && fs.existsSync(path.join(configDir, fw, 'test.mjs'))) {
                lines.push(`node "${xgemPath}" run ${fw} test || exit 1`);
                checksAdded += 1;
            }
        }
    }

    fs.mkdirSync(hooksDir, { recursive: true });
    fs.writeFileSync(hookPath, lines.join('\n') + '\n', { mode: 0o755 });

    if (checksAdded === 0) {
        logWarn(`No lint/test scripts found under ${configDir} — installed a hook that doesn't check anything yet.`);
    }
    logSuccess(`Installed pre-commit hook at ${hookPath}.`);
}

async function cmdHooksUninstall() {
    const gitDir = gitCapture(['rev-parse', '--git-dir']);
    if (!gitDir) die('Not a git repository.');
    const hookPath = path.join(gitDir, 'hooks', 'pre-commit');

    if (!fs.existsSync(hookPath)) { logInfo('No pre-commit hook installed.'); return; }
    if (!fs.readFileSync(hookPath, 'utf8').includes(HOOK_MARKER)) {
        die(`${hookPath} wasn't created by xgem — not removing it.`);
    }
    fs.rmSync(hookPath);
    logSuccess('Removed pre-commit hook.');
}

async function cmdHooks(sub, configDir) {
    switch (sub) {
        case 'install': return cmdHooksInstall(configDir);
        case 'uninstall': return cmdHooksUninstall();
        default: die('Usage: xgem git hooks <install|uninstall>');
    }
}

async function cmdGit(sub, arg, configDir) {
    switch (sub) {
        case 'cmt': return cmdCmt(arg);
        case 'init': return cmdInit();
        case 'branch': return cmdBranch();
        case 'rm-remote': return cmdRmRemote();
        case 'rm-branch': return cmdRmBranch();
        case 'pr': return cmdPr(configDir);
        case 'sync': return cmdSync();
        case 'clean-branches': return cmdCleanBranches();
        case 'hooks': return cmdHooks(arg, configDir);
        default: die(`Unknown git subcommand '${sub}'. Usage: xgem git <cmt|init|branch|rm-remote|rm-branch|pr|sync|clean-branches|hooks>`);
    }
}

module.exports = { cmdGit, defaultRemote };
