#!/usr/bin/env node
// xgem npm entrypoint. On macOS/Linux this is a thin passthrough to the
// real, already-tested bash bin/xgem sitting next to it — zero logic
// duplication, zero behavioral change for POSIX users. On Windows it runs
// the native lib-win/*.js engine, since bash doesn't exist there.

const path = require('node:path');
const { spawnSync } = require('node:child_process');

if (process.platform !== 'win32') {
    const bashScript = path.join(__dirname, 'xgem');
    const result = spawnSync(bashScript, process.argv.slice(2), { stdio: 'inherit' });
    process.exit(result.status ?? 0);
}

// ---- Windows-native engine ----
const fs = require('node:fs');
const { logInfo, logSuccess, logWarn, logError, die, paint } = require('../lib-win/logger');
const { prompt } = require('../lib-win/utils');
const { cmdDoctor } = require('../lib-win/doctor');
const { cmdGit } = require('../lib-win/git');
const { cmdFlutter } = require('../lib-win/flutter');
const scaffold = require('../lib-win/scaffold');
const { cmdRelease } = require('../lib-win/release');
const { registryAdd, registryRemove } = require('../lib-win/registry');
const { cmdStatus } = require('../lib-win/status');
const { cmdBootstrap } = require('../lib-win/bootstrap');
const { cmdCi } = require('../lib-win/ci');

const CONFIG_DIR = '.xgem-automate';

function printBanner() {
    console.log(paint('yellow', ''));
    console.log('██╗  ██╗       ██████╗ ███████╗███╗   ███╗██╗███╗   ██╗██╗');
    console.log('╚██╗██╔╝      ██╔════╝ ██╔════╝████╗ ████║██║████╗  ██║██║');
    console.log(' ╚███╔╝ █████╗██║  ███╗█████╗  ██╔████╔██║██║██╔██╗ ██║██║');
    console.log(' ██╔██╗ ╚════╝██║   ██║██╔══╝  ██║╚██╔╝██║██║██║╚██╗██║██║');
    console.log('██╔╝ ██╗      ╚██████╔╝███████╗██║ ╚═╝ ██║██║██║ ╚████║██║');
    console.log('╚═╝  ╚═╝       ╚═════╝ ╚══════╝╚═╝     ╚═╝╚═╝╚═╝  ╚═══╝╚═╝');
    console.log(paint('cyan', '           ....Windows engine....\n'));
}

function printUsage() {
    console.log('Usage:');
    console.log('  xgem init                     - Initialize tracking system and add first framework');
    console.log('  xgem add                      - Interactive state-aware addition of remaining frameworks');
    console.log('  xgem run <framework> <script> - Run a workspace automation command script');
    console.log('  xgem terminate                - Purge all generated automated layouts completely');
    console.log('  xgem <framework> [help]       - View tailored instructions for a specific script layout');
    console.log('  xgem doctor [ios]             - Report on your environment / iOS build availability');
    console.log('  xgem git cmt "message"        - Auto-stage, commit, rebase-pull, and push');
    console.log('  xgem git init                 - Setup local repo, attach remote tracker shortcuts');
    console.log('  xgem git branch               - Pick, create, or switch branches; remembers your choice');
    console.log('  xgem git rm-remote            - Drop specified target remote tracing rules');
    console.log('  xgem git rm-branch            - Safely drop local and remote workspace branch states');
    console.log('  xgem git pr                   - Push current branch and open a GitHub PR (gh-backed)');
    console.log('  xgem git sync                 - Rebase current branch onto the repo\'s base branch');
    console.log('  xgem git clean-branches       - Delete local branches already merged into the base branch');
    console.log('  xgem git hooks <install|uninstall> - Manage a pre-commit lint/test hook');
    console.log('  xgem release [major|minor|patch] - Bump version, update CHANGELOG.md, tag, push');
    console.log('  xgem status                   - Dashboard across every xgem-tracked project');
    console.log('  xgem bootstrap                - Clone-to-running: detect framework, install, .env, migrate, launch');
    console.log('  xgem ci                       - Run lint/test/build for every configured framework, summarized');
    console.log('  xgem --version                - Print xgem\'s version');
    console.log('');
    console.log('Flags (any command): --yes (skip confirmations), --dry-run (show, don\'t apply), --verbose');
}

async function selectFramework(options) {
    options.forEach((fw, i) => console.log(`${i + 1}) ${fw}`));
    const choice = await prompt('Enter target selection number');
    const idx = parseInt(choice, 10) - 1;
    if (Number.isNaN(idx) || idx < 0 || idx >= options.length) return null;
    return options[idx];
}

async function cmdInit() {
    printBanner();
    if (fs.existsSync(CONFIG_DIR)) {
        logWarn("Workspace configuration layer already exists! Use 'xgem add' to append frameworks.");
        return;
    }
    fs.mkdirSync(CONFIG_DIR, { recursive: true });
    registryAdd(process.cwd());

    console.log('Select your starting framework architecture:');
    const fw = await selectFramework(scaffold.ALL_FRAMEWORKS);
    if (!fw) die('Invalid selection.');
    await scaffold.bookkeeping(fw, CONFIG_DIR);
}

async function cmdAdd() {
    if (!fs.existsSync(CONFIG_DIR)) die("System tracking layer not found. Run 'xgem init' first.");

    const remaining = scaffold.getRemainingFrameworks(CONFIG_DIR);
    if (remaining.length === 0) {
        logWarn('All available framework blocks are already generated inside the workspace!');
        const restore = (await prompt('Do you want to restore/regenerate all framework templates to defaults? (y/n)')).toLowerCase();
        if (restore === 'y') {
            for (const fw of scaffold.ALL_FRAMEWORKS) scaffold.injectTemplates(fw, CONFIG_DIR);
            logSuccess('All framework automation layouts cleanly re-generated!');
        }
        return;
    }

    console.log('Select a framework script block to add:');
    const fw = await selectFramework(remaining);
    if (!fw) { console.log('Operation canceled.'); return; }
    scaffold.injectTemplates(fw, CONFIG_DIR);
    logSuccess(`Successfully loaded and updated files for: ${CONFIG_DIR}/${fw}`);
}

async function cmdRun(fw, script) {
    if (!fw || !script) die('Usage: xgem run <framework> <script>');
    if (fw === 'flutter' && ['hard-clean', 'build', 'build-runner'].includes(script)) {
        await cmdFlutter(script);
    } else {
        scaffold.runScript(fw, script, CONFIG_DIR);
    }
}

async function cmdTerminate() {
    if (!fs.existsSync(CONFIG_DIR)) die(`Tracking layer ${CONFIG_DIR} not found. Nothing to terminate.`);

    logWarn(`Initiating core termination sequence for ${CONFIG_DIR}...`);
    const folders = fs.readdirSync(CONFIG_DIR, { withFileTypes: true })
        .filter((d) => d.isDirectory())
        .map((d) => d.name);

    const { confirm } = require('../lib-win/utils');
    const ok = await confirm(`This deletes ${CONFIG_DIR} and everything in it. Continue?`);
    if (!ok) { logInfo('Cancelled.'); return; }

    for (const fw of folders) {
        console.log(`  [ x ] Removing ${fw}...`);
        fs.rmSync(path.join(CONFIG_DIR, fw), { recursive: true, force: true });
    }
    fs.rmSync(CONFIG_DIR, { recursive: true, force: true });
    registryRemove(process.cwd());

    if (fs.existsSync('.gitignore')) {
        const lines = fs.readFileSync('.gitignore', 'utf8').split(/\r?\n/).filter((l) => l !== `${CONFIG_DIR}/`);
        fs.writeFileSync('.gitignore', lines.join('\n'));
        logSuccess('Cleaned up .gitignore tracking records.');
    }

    logSuccess(`Termination complete. Total blocks destroyed: ${folders.length} (${folders.join(', ') || 'none'})`);
}

function printFrameworkHelp(fw) {
    console.log(paint('cyan', `=== ${fw.toUpperCase()} Automation Blueprint (Windows) ===`));
    if (!fs.existsSync(path.join(CONFIG_DIR, fw))) {
        logWarn('Status: Not currently injected in this workspace.');
        console.log("Run 'xgem add' to instantly append its structural scripts.\n");
    } else {
        logSuccess(`Status: Active & Mounted inside ${CONFIG_DIR}/${fw}/`);
        console.log('');
    }
    console.log(`To execute scripts, use: xgem run ${fw} <script>\n`);
    console.log('Configured Commands:');
    for (const script of scaffold.frameworkScripts(fw) || []) {
        console.log(`  ${script}`);
    }
    if (fw === 'flutter') {
        console.log('');
        logInfo("Flutter builds on Windows support APK, App Bundle, and Windows desktop targets. Run 'xgem doctor ios' for why iOS/macOS aren't available here.");
    }
    console.log('');
}

async function main() {
    const rawArgs = process.argv.slice(2);
    const args = [];
    for (const arg of rawArgs) {
        if (arg === '--yes') process.env.XGEM_YES = '1';
        else if (arg === '--dry-run') process.env.XGEM_DRY_RUN = '1';
        else if (arg === '--verbose') process.env.XGEM_VERBOSE = '1';
        else args.push(arg);
    }

    const [cmd, a2, a3] = args;

    switch (cmd) {
        case 'init': return cmdInit();
        case 'add': return cmdAdd();
        case 'run': return cmdRun(a2, a3);
        case 'terminate': return cmdTerminate();
        case 'git':
            if (!a2) die('Usage: xgem git <cmt|init|branch|rm-remote|rm-branch|pr|sync|clean-branches|hooks>');
            return cmdGit(a2, a3, CONFIG_DIR);
        case 'doctor': return cmdDoctor(a2);
        case 'release': return cmdRelease(a2);
        case 'status': return cmdStatus(CONFIG_DIR);
        case 'bootstrap': return cmdBootstrap(CONFIG_DIR);
        case 'ci': return cmdCi(CONFIG_DIR);
        case '--version':
        case '-V':
        case 'version': {
            const pkg = require('../package.json');
            console.log(`xgem ${pkg.version} (Windows engine)`);
            return;
        }
        case 'flutter':
        case 'node':
        case 'python':
        case 'react':
        case 'vue':
        case 'angular':
        case 'next':
        case 'go':
        case 'rust':
        case 'docker':
            return printFrameworkHelp(cmd);
        default:
            return printUsage();
    }
}

main().catch((err) => {
    logError(err.message || String(err));
    process.exit(1);
});
