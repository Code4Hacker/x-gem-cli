// xgem update [tool] — port of lib/update.sh.

const { spawnSync } = require('node:child_process');
const { logInfo, logSuccess, logWarn, logError, die } = require('./logger');
const { confirm } = require('./utils');
const toolchain = require('./toolchain');

const DEFAULT_TOOLS = ['flutter', 'node', 'cargo', 'go', 'fvm', 'gh', 'git', 'docker', 'python'];

async function updateOne(tool, explicit) {
    const found = toolchain.resolve(tool);
    if (!found) {
        if (explicit) await toolchain.ensure(tool);
        return;
    }

    const version = toolchain.versionOf(tool, found);
    const newest = await toolchain.latest(tool, true);
    if (!newest) {
        if (explicit) logWarn(`Couldn't determine the latest ${toolchain.display(tool)} version (offline, or no version source).`);
        return;
    }
    if (!version || !toolchain.verLt(version, newest)) {
        if (explicit) logSuccess(`${toolchain.display(tool)} ${version} is up to date.`);
        return;
    }

    console.log('');
    logInfo(`${toolchain.display(tool)}: ${version} -> ${newest}`);
    const cmd = toolchain.updateCmd(tool, newest, found.manager);
    if (!cmd) {
        console.log(`  No automated update route for this install (${found.manager}). Download: ${toolchain.url(tool)}`);
        return;
    }
    console.log(`  Update command: ${cmd}`);
    if (!(await confirm(`Update ${toolchain.display(tool)} to ${newest}?`))) return;
    if (spawnSync(cmd, { stdio: 'inherit', shell: true }).status !== 0) {
        logError('Update failed (see output above).');
        return;
    }
    logSuccess(`${toolchain.display(tool)} update finished.`);

    if (tool === 'flutter' && found.manager === 'fvm') {
        if (await confirm(`Make Flutter ${newest} your global default (fvm global)?`)) {
            spawnSync(`fvm global ${newest}`, { stdio: 'inherit', shell: true });
        }
        if ((toolchain.findUp('.fvmrc') || toolchain.findUp('.fvm')) && (await confirm(`Also pin ${newest} for the project in this directory (fvm use)?`))) {
            spawnSync(`fvm use ${newest}`, { stdio: 'inherit', shell: true });
        }
    }
}

async function cmdUpdate(target) {
    if (target) {
        if (!toolchain.isKnown(target)) die(`Unknown tool '${target}'. Known: ${toolchain.KNOWN.join(' ')}`);
        await updateOne(toolchain.canon(target), true);
        return;
    }
    if (process.env.XGEM_NO_NETWORK !== '1') {
        logInfo('Checking installed tools for updates...');
        await Promise.all(DEFAULT_TOOLS.filter((t) => toolchain.resolve(t)).map((t) => toolchain.latest(t)));
    }
    for (const t of DEFAULT_TOOLS) await updateOne(t, false);
    console.log('');
    logSuccess("Update check finished. Run 'xgem doctor' for the full toolchain report.");
}

module.exports = { cmdUpdate };
