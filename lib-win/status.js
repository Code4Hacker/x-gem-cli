// xgem status — port of lib/status.sh: a one-screen dashboard across every
// project xgem has ever scaffolded.

const fs = require('node:fs');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const { logInfo } = require('./logger');
const { registryList } = require('./registry');

function gitCaptureIn(cwd, args) {
    const result = spawnSync('git', args, { cwd, encoding: 'utf8' });
    return result.status === 0 ? (result.stdout || '').trim() : '';
}

function statusRow(projectPath, configDir) {
    const branch = gitCaptureIn(projectPath, ['branch', '--show-current']) || '-';
    const porcelain = gitCaptureIn(projectPath, ['status', '--porcelain']);
    const dirty = porcelain ? porcelain.split(/\r?\n/).filter(Boolean).length : 0;

    const counts = gitCaptureIn(projectPath, ['rev-list', '--left-right', '--count', '@{u}...HEAD']);
    let aheadBehind = '-';
    if (counts) {
        const [behind, ahead] = counts.split(/\s+/);
        aheadBehind = `-${behind} +${ahead}`;
    }

    const configPath = path.join(projectPath, configDir);
    const frameworks = fs.existsSync(configPath)
        ? fs.readdirSync(configPath, { withFileTypes: true }).filter((d) => d.isDirectory()).map((d) => d.name).join(',') || '-'
        : '-';

    return { projectPath, branch, dirty, aheadBehind, frameworks };
}

function pad(str, width) {
    return str.length >= width ? str : str + ' '.repeat(width - str.length);
}

async function cmdStatus(configDir) {
    const projects = registryList(configDir);
    if (projects.length === 0) {
        logInfo("No xgem-tracked projects found yet — run 'xgem init' in a project to start tracking it.");
        return;
    }

    console.log(`${pad('PROJECT', 45)} ${pad('BRANCH', 20)} ${pad('DIRTY', 6)} ${pad('AHEAD/BEHIND', 12)} FRAMEWORKS`);
    for (const p of projects) {
        const row = statusRow(p, configDir);
        console.log(`${pad(row.projectPath, 45)} ${pad(row.branch, 20)} ${pad(String(row.dirty), 6)} ${pad(row.aheadBehind, 12)} ${row.frameworks}`);
    }
}

module.exports = { cmdStatus };
