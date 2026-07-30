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

    logInfo('Committing changes...');
    const commitResult = git(['commit', '-m', commitMsg]);
    if (commitResult.status !== 0) {
        die('Commit failed. Aborting before pull/push.');
    }

    const currentBranch = gitCapture(['branch', '--show-current']);
    const remoteName = remoteExists('origin') ? 'origin' : gitCapture(['remote']).split(/\r?\n/)[0];

    if (!remoteName) {
        logWarn('Local commit dropped cleanly, but no remote is configured — sync was skipped.');
        return;
    }

    logInfo(`Pulling updates from remote '${remoteName}' on '${currentBranch}' via rebase...`);
    const pullResult = git(['pull', '--rebase', remoteName, currentBranch]);
    if (pullResult.status !== 0) {
        logError('MERGE CONFLICT DETECTED!');
        logWarn('Execution paused. Resolve conflicts to proceed.');
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

async function cmdGit(sub, arg) {
    switch (sub) {
        case 'cmt': return cmdCmt(arg);
        case 'init': return cmdInit();
        case 'rm-remote': return cmdRmRemote();
        case 'rm-branch': return cmdRmBranch();
        default: die(`Unknown git subcommand '${sub}'. Usage: xgem git <cmt|init|rm-remote|rm-branch>`);
    }
}

module.exports = { cmdGit };
