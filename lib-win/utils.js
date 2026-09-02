// xgem Windows engine utilities — mirrors lib/utils.sh.

const { spawnSync } = require('node:child_process');
const readline = require('node:readline');
const { logInfo, logDebug } = require('./logger');

function detectArch() {
    return process.arch === 'x64' ? 'x64' : process.arch;
}

// hasCmd(name) -> boolean, checked via `where` (a Windows builtin) so it
// works regardless of whether the tool itself supports --version.
function hasCmd(name) {
    const result = spawnSync('where', [name], { stdio: 'ignore', shell: false });
    return result.status === 0;
}

function requireCmd(name, hint) {
    if (!hasCmd(name)) {
        const { die } = require('./logger');
        die(hint ? `'${name}' is required but not found. ${hint}` : `'${name}' is required but not found in PATH.`);
    }
}

// getVersion(name, args) -> first line of stdout, or null if the command
// isn't present / errors out.
function getVersion(name, args = ['--version']) {
    if (!hasCmd(name)) return null;
    const result = spawnSync(name, args, { encoding: 'utf8' });
    if (result.error || result.status !== 0) return null;
    const out = (result.stdout || result.stderr || '').split(/\r?\n/)[0];
    return out ? out.trim() : null;
}

// openUrl(url) — best-effort browser open on Windows.
function openUrl(url) {
    spawnSync('cmd', ['/c', 'start', '""', url], { stdio: 'ignore' });
}

// confirm(prompt) -> Promise<boolean>. Honors XGEM_YES (auto-approve) and
// XGEM_DRY_RUN (always decline, just like lib/utils.sh's confirm()).
function confirm(prompt) {
    if (process.env.XGEM_DRY_RUN === '1') {
        logInfo(`(dry-run) would prompt: ${prompt}`);
        return Promise.resolve(false);
    }
    if (process.env.XGEM_YES === '1') {
        logDebug(`auto-confirmed (--yes): ${prompt}`);
        return Promise.resolve(true);
    }
    const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
    return new Promise((resolve) => {
        rl.question(`${prompt} [y/N]: `, (answer) => {
            rl.close();
            resolve(answer.trim().toLowerCase() === 'y');
        });
    });
}

// prompt(question, defaultValue) -> Promise<string>
function prompt(question, defaultValue = '') {
    const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
    const suffix = defaultValue ? ` [${defaultValue}]` : '';
    return new Promise((resolve) => {
        rl.question(`${question}${suffix}: `, (answer) => {
            rl.close();
            resolve(answer.trim() || defaultValue);
        });
    });
}

module.exports = { detectArch, hasCmd, requireCmd, getVersion, confirm, prompt, openUrl };
