// xgem Windows engine bootstrap — port of lib/bootstrap.sh. `swift` is
// omitted from detection, matching lib-win/scaffold.js's decision that
// there's no meaningful Windows Swift toolchain story.

const fs = require('node:fs');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const { logInfo, logSuccess, logWarn, logDebug, die } = require('./logger');
const { hasCmd, confirm, prompt } = require('./utils');
const scaffold = require('./scaffold');
const toolchain = require('./toolchain');

function run(cmd, args, opts = {}) {
    if (process.env.XGEM_DRY_RUN === '1') {
        logInfo(`(dry-run) would run: ${cmd} ${args.join(' ')}`);
        return { status: 0 };
    }
    return spawnSync(cmd, args, { stdio: 'inherit', shell: process.platform === 'win32', ...opts });
}

function detectFramework() {
    if (fs.existsSync('pubspec.yaml')) return 'flutter';
    if (fs.existsSync('go.mod')) return 'go';
    if (fs.existsSync('Cargo.toml')) return 'rust';
    if (fs.existsSync('pyproject.toml') || fs.existsSync('requirements.txt') || fs.existsSync('setup.py')) return 'python';
    if (fs.existsSync('package.json')) {
        const content = fs.readFileSync('package.json', 'utf8');
        if (content.includes('"next"')) return 'next';
        if (content.includes('"@angular/core"')) return 'angular';
        if (content.includes('"vue"')) return 'vue';
        if (content.includes('"react"')) return 'react';
        return 'node';
    }
    if (fs.existsSync('Dockerfile')) return 'docker';
    return '';
}

async function selectFrameworkManually() {
    scaffold.ALL_FRAMEWORKS.forEach((fw, i) => console.log(`${i + 1}) ${fw}`));
    const choice = await prompt('Enter target selection number');
    const idx = parseInt(choice, 10) - 1;
    if (Number.isNaN(idx) || idx < 0 || idx >= scaffold.ALL_FRAMEWORKS.length) die('Invalid selection.');
    return scaffold.ALL_FRAMEWORKS[idx];
}

async function bootstrapEnvFile() {
    if (fs.existsSync('.env')) { logDebug('.env already exists, leaving it as-is.'); return; }
    for (const example of ['.env.example', '.env.sample']) {
        if (!fs.existsSync(example)) continue;
        if (process.env.XGEM_DRY_RUN === '1') {
            logInfo(`(dry-run) would create .env from ${example}`);
            return;
        }
        fs.copyFileSync(example, '.env');
        logSuccess(`Created .env from ${example}.`);
        const missing = fs.readFileSync('.env', 'utf8')
            .split(/\r?\n/)
            .filter((line) => /^[A-Za-z_][A-Za-z0-9_]*=\s*$/.test(line))
            .map((line) => line.split('=')[0]);
        if (missing.length) {
            logWarn('These .env keys are empty — fill them in:');
            missing.forEach((k) => console.log(`  - ${k}`));
        }
        return;
    }
}

function nodePm() {
    if (fs.existsSync('pnpm-lock.yaml')) return 'pnpm';
    if (fs.existsSync('yarn.lock')) return 'yarn';
    if (fs.existsSync('bun.lockb') || fs.existsSync('bun.lock')) return 'bun';
    return 'npm';
}

function installWith(pm, extraArgs = []) {
    switch (pm) {
        case 'yarn': return run('yarn', extraArgs);
        case 'pnpm': return run('pnpm', ['install', ...extraArgs]);
        case 'bun': return run('bun', ['install', ...extraArgs]);
        default: return run('npm', ['install', ...extraArgs]);
    }
}

async function preflight(fw) {
    const tool = toolchain.fwTool(fw);
    if (tool && !(await toolchain.ensure(tool))) return false;
    if (fw === 'flutter' && !(await toolchain.ensure('dart'))) return false;
    if (['node', 'react', 'vue', 'angular', 'next'].includes(fw)) {
        const pm = nodePm();
        if (pm !== 'npm' && !hasCmd(pm)) {
            logWarn(`This project uses ${pm} (lockfile found) but '${pm}' isn't installed.`);
            console.log(`  Enable it via Node's bundled corepack:  corepack enable   (or: npm install -g ${pm})`);
            if (!(await confirm(`Run 'npm install -g ${pm}' now?`))) return false;
            run('npm', ['install', '-g', pm]);
        }
    }
    return true;
}

async function bootstrapInstall(fw) {
    switch (fw) {
        case 'node':
        case 'react':
        case 'vue':
        case 'angular':
        case 'next': {
            const pm = nodePm();
            if (!(await confirm(`Install dependencies with ${pm}?`))) break;
            logInfo(`Installing dependencies with ${pm}...`);
            installWith(pm);
            break;
        }
        case 'flutter':
            if (!(await confirm("Run 'flutter pub get'?"))) break;
            run('flutter', ['pub', 'get']);
            break;
        case 'python':
            if (fs.existsSync('pyproject.toml') && hasCmd('poetry')) {
                if (!(await confirm('Install dependencies with poetry?'))) break;
                run('poetry', ['install']);
            } else if (fs.existsSync('requirements.txt')) {
                const py = hasCmd('python') ? 'python' : 'python3';
                if (!(await confirm('Create .venv and install requirements.txt into it?'))) break;
                if (!fs.existsSync('.venv')) run(py, ['-m', 'venv', '.venv']);
                const pipPath = process.platform === 'win32' ? path.join('.venv', 'Scripts', 'pip.exe') : path.join('.venv', 'bin', 'pip');
                run(pipPath, ['install', '-r', 'requirements.txt']);
            }
            break;
        case 'go':
            if (!(await confirm("Run 'go mod download'?"))) break;
            run('go', ['mod', 'download']);
            break;
        case 'rust':
            if (!(await confirm("Run 'cargo fetch'?"))) break;
            run('cargo', ['fetch']);
            break;
        case 'docker':
            logDebug('Docker project — nothing to install locally.');
            break;
        default:
            break;
    }
}

function packageJsonHasScript(name) {
    try {
        const pkg = JSON.parse(fs.readFileSync('package.json', 'utf8'));
        return Boolean(pkg.scripts && pkg.scripts[name]);
    } catch {
        return false;
    }
}

async function bootstrapMigrations(fw) {
    if (['node', 'react', 'vue', 'angular', 'next'].includes(fw) && packageJsonHasScript('migrate')) {
        const pm = nodePm();
        if (await confirm(`Run the project's 'migrate' script (via ${pm})?`)) {
            if (pm === 'yarn') run('yarn', ['migrate']);
            else if (pm === 'pnpm') run('pnpm', ['run', 'migrate']);
            else if (pm === 'bun') run('bun', ['run', 'migrate']);
            else run('npm', ['run', 'migrate']);
        }
        return;
    }
    if (fs.existsSync(path.join('prisma', 'schema.prisma'))) {
        if (await confirm("Run 'npx prisma migrate dev'?")) run('npx', ['prisma', 'migrate', 'dev']);
    } else if (fs.existsSync('manage.py')) {
        const py = hasCmd('python') ? 'python' : (hasCmd('python3') ? 'python3' : '');
        if (py && (await confirm(`Run '${py} manage.py migrate'?`))) run(py, ['manage.py', 'migrate']);
    }
}

async function offerDevServer(fw, configDir) {
    let script = '';
    if (fw === 'node') script = 'start';
    else if (['react', 'vue', 'angular', 'next'].includes(fw)) script = 'dev';
    else return;

    const target = path.join(configDir, fw, `${script}.mjs`);
    if (!fs.existsSync(target)) return;
    if (await confirm(`Launch the dev server now ('xgem run ${fw} ${script}')?`)) {
        scaffold.runScript(fw, script, configDir);
    }
}

async function cmdBootstrap(configDir) {
    logInfo('Detecting project framework...');
    let fw = detectFramework();
    if (!fw) {
        logWarn('Could not auto-detect the framework from any known marker file.');
        console.log('Pick one:');
        fw = await selectFrameworkManually();
    } else {
        logSuccess(`Detected: ${fw}`);
    }

    if (!(await preflight(fw))) die('Bootstrap stopped: a required tool is missing.');
    await bootstrapEnvFile();
    await bootstrapInstall(fw);
    await bootstrapMigrations(fw);

    if (!fs.existsSync(configDir)) {
        if (await confirm(`Scaffold xgem automation scripts (${configDir}) for ${fw} too?`)) {
            await scaffold.bookkeeping(fw, configDir);
        }
    }

    await offerDevServer(fw, configDir);
    logSuccess('Bootstrap complete.');
}

module.exports = { cmdBootstrap };
