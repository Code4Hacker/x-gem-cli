// xgem Windows engine git workflow — port of lib/git.sh (cmt/init/rm-remote/rm-branch).
// git.exe behaves the same on Windows, so this is a straight port; the
// commit-exit-code check and origin-preference fix already in lib/git.sh
// carry over here too.

const { spawnSync } = require('node:child_process');
const { logInfo, logSuccess, logWarn, logError, die } = require('./logger');
const { prompt } = require('./utils');

function git(args, opts = {}) {
    return spawnSync('git', args, { stdio: 'inherit', ...opts });
}

function gitCapture(args) {
    const result = spawnSync('git', args, { encoding: 'utf8' });
    return (result.stdout || '').trim();
}

function remoteExists(name) {
    return gitCapture(['remote']).split(/\r?\n/).includes(name);
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
    const remoteName = remoteExists('origin') ? 'origin' : gitCapture(['remote']).split(/\r?\n/)[0];

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
        const path = require('node:path');
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

async function cmdInit() {
    logInfo('Initializing local Git repository...');
    git(['init']);

    let remoteName = 'origin';
    const remoteUrl = await prompt('Enter remote repository URL');
    if (remoteUrl) {
        const userRemoteName = await prompt('Enter remote name (default: origin)');
        if (userRemoteName) remoteName = userRemoteName;

        if (remoteExists(remoteName)) {
            git(['remote', 'set-url', remoteName, remoteUrl]);
            logSuccess(`Remote '${remoteName}' already existed. URL updated.`);
        } else {
            git(['remote', 'add', remoteName, remoteUrl]);
            logSuccess(`Remote '${remoteName}' successfully added.`);
        }
    }

    const branchName = (await prompt('Enter branch name (default: main)')) || 'main';
    git(['branch', '-M', branchName]);

    git(['add', '.']);
    git(['commit', '-m', 'initial changes']);
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

async function cmdGit(sub, arg) {
    switch (sub) {
        case 'cmt': return cmdCmt(arg);
        case 'init': return cmdInit();
        case 'branch': return cmdBranch();
        case 'rm-remote': return cmdRmRemote();
        case 'rm-branch': return cmdRmBranch();
        default: die(`Unknown git subcommand '${sub}'. Usage: xgem git <cmt|init|branch|rm-remote|rm-branch>`);
    }
}

module.exports = { cmdGit };
