// xgem Windows engine release command — port of lib/release.sh.

const fs = require('node:fs');
const { spawnSync } = require('node:child_process');
const { logInfo, logSuccess, logWarn, die } = require('./logger');
const { prompt, confirm } = require('./utils');
const { defaultRemote } = require('./git');

const VERSION_FILES = ['package.json', 'pubspec.yaml', 'Cargo.toml', 'pyproject.toml'];

function detectVersionFiles() {
    return VERSION_FILES.filter((f) => fs.existsSync(f));
}

function readVersion(file) {
    const content = fs.readFileSync(file, 'utf8');
    if (file === 'package.json') {
        const m = content.match(/"version"\s*:\s*"([^"]+)"/);
        return m ? m[1] : '';
    }
    if (file === 'pubspec.yaml') {
        const m = content.match(/^version:\s*(\S+)/m);
        return m ? m[1] : '';
    }
    const m = content.match(/^version\s*=\s*"([^"]+)"/m);
    return m ? m[1] : '';
}

function writeVersion(file, newVersion) {
    const content = fs.readFileSync(file, 'utf8');
    let updated;
    if (file === 'package.json') {
        updated = content.replace(/"version"\s*:\s*"[^"]+"/, `"version": "${newVersion}"`);
    } else if (file === 'pubspec.yaml') {
        updated = content.replace(/^version:.*/m, `version: ${newVersion}`);
    } else {
        updated = content.replace(/^version\s*=\s*"[^"]+"/m, `version = "${newVersion}"`);
    }
    fs.writeFileSync(file, updated);
}

function bumpVersion(version, kind) {
    const plusIdx = version.indexOf('+');
    const core = plusIdx === -1 ? version : version.slice(0, plusIdx);
    const suffix = plusIdx === -1 ? '' : version.slice(plusIdx);

    const m = core.match(/^(\d+)\.(\d+)\.(\d+)$/);
    if (!m) return '';
    let [major, minor, patch] = m.slice(1).map(Number);
    if (kind === 'major') { major += 1; minor = 0; patch = 0; }
    else if (kind === 'minor') { minor += 1; patch = 0; }
    else { patch += 1; }
    return `${major}.${minor}.${patch}${suffix}`;
}

function git(args, opts = {}) {
    return spawnSync('git', args, { stdio: 'inherit', ...opts });
}

function gitCapture(args) {
    const result = spawnSync('git', args, { encoding: 'utf8' });
    return (result.stdout || '').trim();
}

function writeChangelog(version, lastTag) {
    const range = lastTag ? `${lastTag}..HEAD` : 'HEAD';
    const commits = gitCapture(['log', '--format=%s', range]).split(/\r?\n/).filter(Boolean);
    const features = commits.filter((c) => c.startsWith('feat'));
    const fixes = commits.filter((c) => c.startsWith('fix'));
    const other = commits.filter((c) => !c.startsWith('feat') && !c.startsWith('fix'));

    let section = `## v${version} - ${new Date().toISOString().slice(0, 10)}\n`;
    if (features.length) section += `\n### Features\n${features.map((c) => `- ${c}`).join('\n')}\n`;
    if (fixes.length) section += `\n### Fixes\n${fixes.map((c) => `- ${c}`).join('\n')}\n`;
    if (other.length) section += `\n### Other\n${other.map((c) => `- ${c}`).join('\n')}\n`;

    const existing = fs.existsSync('CHANGELOG.md')
        ? fs.readFileSync('CHANGELOG.md', 'utf8').split('\n').slice(1).join('\n')
        : '';
    fs.writeFileSync('CHANGELOG.md', `# Changelog\n\n${section}\n${existing}`);
}

async function cmdRelease(bumpKind) {
    const versionFiles = detectVersionFiles();
    if (versionFiles.length === 0) {
        die('No recognized version file (package.json/pubspec.yaml/Cargo.toml/pyproject.toml) found here.');
    }

    let file = versionFiles[0];
    if (versionFiles.length > 1) {
        console.log('Multiple version files found:');
        versionFiles.forEach((f, i) => console.log(`${i + 1}) ${f}`));
        const choice = await prompt(`Which is the canonical one to bump? [1-${versionFiles.length}]`);
        const idx = parseInt(choice, 10) - 1;
        if (Number.isNaN(idx) || idx < 0 || idx >= versionFiles.length) die('Invalid selection.');
        file = versionFiles[idx];
    }

    const current = readVersion(file);
    if (!current) die(`Could not read a version from ${file}.`);
    logInfo(`Current version in ${file}: ${current}`);

    if (bumpKind && !['major', 'minor', 'patch'].includes(bumpKind)) {
        die(`Unknown bump kind '${bumpKind}'. Usage: xgem release [major|minor|patch]`);
    }
    if (!bumpKind) {
        bumpKind = (await prompt('Bump [major/minor/patch]', 'patch')) || 'patch';
    }

    let newVersion = bumpVersion(current, bumpKind);
    if (!newVersion) {
        logWarn(`'${current}' isn't a plain X.Y.Z version — can't bump it automatically.`);
        newVersion = await prompt('Enter the new version directly');
        if (!newVersion) die('A new version is required.');
    }

    logInfo(`${current} -> ${newVersion}`);
    if (!(await confirm('Write this version, update CHANGELOG.md, commit, and tag?'))) {
        logInfo('Cancelled.');
        return;
    }

    writeVersion(file, newVersion);

    const lastTag = gitCapture(['describe', '--tags', '--abbrev=0']);
    writeChangelog(newVersion, lastTag);

    git(['add', file, 'CHANGELOG.md']);
    if (git(['commit', '-m', `chore(release): v${newVersion}`]).status !== 0) die('Commit failed.');
    if (git(['tag', '-a', `v${newVersion}`, '-m', `v${newVersion}`]).status !== 0) die('Tag failed.');
    logSuccess(`Committed and tagged v${newVersion}.`);

    const remote = defaultRemote();
    if (remote && (await confirm(`Push commit and tag to '${remote}'?`))) {
        const currentBranch = gitCapture(['branch', '--show-current']);
        const pushed = git(['push', remote, currentBranch]).status === 0
            && git(['push', remote, `v${newVersion}`]).status === 0;
        if (pushed) logSuccess(`Pushed v${newVersion} to '${remote}'.`);
        else die('Push failed — the commit and tag are safe locally.');
    }
}

module.exports = { cmdRelease };
