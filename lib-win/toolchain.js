// xgem Windows engine toolchain layer — port of lib/toolchain.sh: finds
// tools where version managers keep them, offers to install missing ones,
// and reports/applies updates. Best-effort: not runtime-tested on Windows.

const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const https = require('node:https');
const { spawnSync } = require('node:child_process');
const { logInfo, logSuccess, logWarn, logError } = require('./logger');

const CACHE_DIR = process.env.XGEM_CACHE_DIR || path.join(os.homedir(), '.xgem', 'cache');
const HOME = os.homedir();
const EXTS = ['.exe', '.cmd', '.bat', ''];

const CANON = { npm: 'node', npx: 'node', corepack: 'node', pip: 'python', pip3: 'python', python3: 'python', rustc: 'cargo', rustup: 'cargo' };
const KNOWN = ['flutter', 'dart', 'node', 'python', 'go', 'cargo', 'docker', 'git', 'gh', 'fvm'];
const DISPLAY = { flutter: 'Flutter SDK', dart: 'Dart SDK', node: 'Node.js', python: 'Python 3', go: 'Go', cargo: 'Rust (cargo)', docker: 'Docker', git: 'Git', gh: 'GitHub CLI', fvm: 'FVM (Flutter Version Management)' };
const URLS = {
    flutter: 'https://docs.flutter.dev/get-started/install/windows',
    dart: 'https://docs.flutter.dev/get-started/install/windows',
    node: 'https://nodejs.org/en/download',
    python: 'https://www.python.org/downloads/windows/',
    go: 'https://go.dev/dl/',
    cargo: 'https://www.rust-lang.org/tools/install',
    docker: 'https://www.docker.com/products/docker-desktop/',
    git: 'https://git-scm.com/downloads/win',
    gh: 'https://cli.github.com',
    fvm: 'https://fvm.app/documentation/getting-started/installation',
};
const WINGET_IDS = { node: 'OpenJS.NodeJS.LTS', python: 'Python.Python.3.13', go: 'GoLang.Go', docker: 'Docker.DockerDesktop', git: 'Git.Git', gh: 'GitHub.cli', cargo: 'Rustlang.Rustup' };
const FW_TOOL = { flutter: 'flutter', node: 'node', react: 'node', vue: 'node', angular: 'node', next: 'node', python: 'python', go: 'go', rust: 'cargo' };

const canon = (t) => CANON[t] || t;
const isKnown = (t) => KNOWN.includes(canon(t));
const display = (t) => DISPLAY[t] || t;
const url = (t) => URLS[t] || '';
const fwTool = (fw) => FW_TOOL[fw] || '';

function findUp(rel) {
    let dir = process.cwd();
    for (;;) {
        if (dir === HOME && process.cwd() !== HOME) return null;
        const candidate = path.join(dir, rel);
        if (fs.existsSync(candidate)) return candidate;
        const parent = path.dirname(dir);
        if (parent === dir) return null;
        dir = parent;
    }
}

function readJson(file) {
    try { return JSON.parse(fs.readFileSync(file, 'utf8')); } catch { return null; }
}

function pin(tool) {
    let v = '';
    if (tool === 'flutter' || tool === 'dart') {
        const rc = findUp('.fvmrc');
        const cfg = findUp(path.join('.fvm', 'fvm_config.json'));
        if (rc) v = (readJson(rc) || {}).flutter || '';
        else if (cfg) v = (readJson(cfg) || {}).flutterSdkVersion || '';
    } else if (tool === 'node') {
        const f = findUp('.nvmrc');
        if (f) v = fs.readFileSync(f, 'utf8').trim().replace(/^v/, '');
    }
    return v;
}

function listDirs(dir) {
    try { return fs.readdirSync(dir, { withFileTypes: true }).filter((d) => d.isDirectory()).map((d) => d.name); } catch { return []; }
}

function newest(names) {
    return [...names].sort((a, b) => a.localeCompare(b, undefined, { numeric: true })).pop();
}

function fvmRoots() {
    return [process.env.FVM_CACHE_PATH, process.env.FVM_HOME, path.join(process.env.LOCALAPPDATA || '', 'fvm'), path.join(HOME, 'fvm'), path.join(HOME, '.fvm')].filter(Boolean);
}

function candidates(tool) {
    const out = [];
    const add = (dir, manager) => out.push({ dir, manager });
    const pf = process.env.ProgramFiles || 'C:\\Program Files';
    const local = process.env.LOCALAPPDATA || path.join(HOME, 'AppData', 'Local');

    if (tool === 'flutter' || tool === 'dart') {
        const proj = findUp(path.join('.fvm', 'flutter_sdk'));
        if (proj) add(path.join(proj, 'bin'), 'fvm');
        const p = pin('flutter');
        for (const root of fvmRoots()) if (p) add(path.join(root, 'versions', p, 'bin'), 'fvm');
        add(path.join(HOME, '.fvm', 'flutter_sdk', 'bin'), 'fvm');
        for (const root of fvmRoots()) add(path.join(root, 'default', 'bin'), 'fvm');
        for (const root of fvmRoots()) {
            const v = newest(listDirs(path.join(root, 'versions')));
            if (v) add(path.join(root, 'versions', v, 'bin'), 'fvm');
        }
        add('C:\\src\\flutter\\bin', 'other');
        add(path.join(HOME, 'development', 'flutter', 'bin'), 'other');
    } else if (tool === 'node') {
        const nvmHome = process.env.NVM_HOME;
        if (nvmHome) {
            const p = pin('node');
            const names = listDirs(nvmHome).filter((n) => /^v?\d/.test(n));
            const match = p && /^\d/.test(p) ? names.filter((n) => n.replace(/^v/, '').startsWith(p)) : [];
            const pick = newest(match.length ? match : names);
            if (pick) add(path.join(nvmHome, pick), 'nvm');
        }
        if (process.env.NVM_SYMLINK) add(process.env.NVM_SYMLINK, 'nvm');
        add(path.join(local, 'Volta', 'bin'), 'volta');
        add(path.join(pf, 'nodejs'), 'other');
    } else if (tool === 'python') {
        const base = path.join(local, 'Programs', 'Python');
        const v = newest(listDirs(base));
        if (v) add(path.join(base, v), 'other');
    } else if (tool === 'go') {
        add(path.join(pf, 'Go', 'bin'), 'other');
    } else if (tool === 'cargo') {
        add(path.join(HOME, '.cargo', 'bin'), 'rustup');
    } else if (tool === 'docker') {
        add(path.join(pf, 'Docker', 'Docker', 'resources', 'bin'), 'other');
    } else if (tool === 'git') {
        add(path.join(pf, 'Git', 'cmd'), 'other');
    } else if (tool === 'gh') {
        add(path.join(pf, 'GitHub CLI'), 'other');
    }
    return out;
}

function managerOf(p) {
    const s = p.replace(/\\/g, '/').toLowerCase();
    if (s.includes('/fvm/') || s.includes('/.fvm/')) return 'fvm';
    if (s.includes('/nvm')) return 'nvm';
    if (s.includes('/.cargo/')) return 'rustup';
    if (s.includes('/volta/')) return 'volta';
    if (s.includes('/winget/') || s.includes('/scoop/')) return 'package manager';
    return 'other';
}

function whereFirst(cmd) {
    const r = spawnSync('where', [cmd], { encoding: 'utf8', shell: false });
    if (r.status !== 0) return '';
    return (r.stdout || '').split(/\r?\n/).find(Boolean) || '';
}

// resolve(cmd) -> { path, dir, manager, onPath } or null
function resolve(cmd) {
    const c = canon(cmd);
    const onPath = whereFirst(cmd);
    if (onPath) return { path: onPath, dir: path.dirname(onPath), manager: managerOf(onPath), onPath: true };
    for (const { dir, manager } of candidates(c)) {
        for (const ext of EXTS) {
            const full = path.join(dir, cmd + ext);
            if (fs.existsSync(full) && fs.statSync(full).isFile()) return { path: full, dir, manager, onPath: false };
        }
    }
    return null;
}

function activate(found) {
    if (!found || found.onPath) return;
    process.env.PATH = `${found.dir}${path.delimiter}${process.env.PATH || ''}`;
}

function versionOf(t, found) {
    if (t === 'flutter') {
        const sdk = path.join(path.dirname(found.path), '..');
        const j = readJson(path.join(sdk, 'bin', 'cache', 'flutter.version.json'));
        if (j && j.frameworkVersion) return j.frameworkVersion;
    }
    const args = t === 'go' ? ['version'] : ['--version'];
    const r = spawnSync(found.path, args, { encoding: 'utf8', shell: /\.(cmd|bat)$/i.test(found.path) });
    const m = ((r.stdout || '') + (r.stderr || '')).split(/\r?\n/).slice(0, 3).join(' ').match(/\d+(\.\d+)+/);
    return m ? m[0] : '';
}

function verLt(a, b) {
    const pa = a.split('.').map(Number);
    const pb = b.split('.').map(Number);
    for (let i = 0; i < Math.max(pa.length, pb.length); i++) {
        const x = pa[i] || 0;
        const y = pb[i] || 0;
        if (x !== y) return x < y;
    }
    return false;
}

function fetchText(u) {
    return new Promise((resolveP) => {
        const req = https.get(u, { timeout: 8000 }, (res) => {
            if (res.statusCode !== 200) { res.resume(); resolveP(''); return; }
            let data = '';
            res.setEncoding('utf8');
            res.on('data', (c) => { data += c; });
            res.on('end', () => resolveP(data));
        });
        req.on('timeout', () => { req.destroy(); resolveP(''); });
        req.on('error', () => resolveP(''));
    });
}

async function fetchLatest(t) {
    if (t === 'flutter') {
        const j = JSON.parse((await fetchText('https://storage.googleapis.com/flutter_infra_release/releases/releases_windows.json')) || 'null');
        if (!j) return '';
        const rel = j.releases.find((r) => r.hash === j.current_release.stable && r.channel === 'stable');
        return rel ? rel.version : '';
    }
    if (t === 'node') {
        const list = JSON.parse((await fetchText('https://nodejs.org/dist/index.json')) || 'null');
        const lts = list && list.find((r) => r.lts);
        return lts ? lts.version.replace(/^v/, '') : '';
    }
    if (t === 'go') {
        return ((await fetchText('https://go.dev/VERSION?m=text')).split(/\r?\n/)[0] || '').replace(/^go/, '');
    }
    return '';
}

// latest(t) -> newest known version, cached 12h; noNetwork uses only the cache.
async function latest(t, noNetwork = process.env.XGEM_NO_NETWORK === '1') {
    const f = path.join(CACHE_DIR, `latest-${t}`);
    const fresh = fs.existsSync(f) && Date.now() - fs.statSync(f).mtimeMs < 12 * 3600 * 1000;
    if (noNetwork || fresh) return fs.existsSync(f) ? fs.readFileSync(f, 'utf8').trim() : '';
    let v = '';
    try { v = await fetchLatest(t); } catch { v = ''; }
    if (v) {
        fs.mkdirSync(CACHE_DIR, { recursive: true });
        fs.writeFileSync(f, v);
        return v;
    }
    return fs.existsSync(f) ? fs.readFileSync(f, 'utf8').trim() : '';
}

function installCmd(t) {
    if (t === 'flutter' || t === 'dart') {
        return resolve('fvm') ? 'fvm install stable && fvm global stable' : '';
    }
    if (t === 'fvm') return 'dart pub global activate fvm';
    if (WINGET_IDS[t]) return `winget install --id ${WINGET_IDS[t]} -e`;
    return '';
}

function updateCmd(t, latestVersion, manager) {
    if (t === 'flutter' && manager === 'fvm') return `fvm install ${latestVersion}`;
    if (t === 'cargo' && manager === 'rustup') return 'rustup update';
    if (WINGET_IDS[t] && t !== 'cargo') return `winget upgrade --id ${WINGET_IDS[t]} -e`;
    return '';
}

// ensure(t) -> true once the tool is usable, after explaining what's needed
// and (with confirmation) installing it.
async function ensure(tool) {
    const { confirm } = require('./utils');
    const t = canon(tool);
    let found = resolve(tool);
    if (found) { activate(found); return true; }

    logWarn(`${display(t)} is required for this but wasn't found (checked PATH, version managers like fvm/nvm, and common install locations).`);
    console.log(`  Download: ${url(t)}`);
    const recipe = installCmd(t);
    if (!recipe) {
        logInfo('Install it from the link above, then re-run this command.');
        return false;
    }
    if (recipe.startsWith('winget') && !whereFirst('winget')) {
        logInfo('That install route needs winget (App Installer from the Microsoft Store) — install it first, or use the download link above.');
        return false;
    }
    console.log(`  Install command: ${recipe}`);
    if (!(await confirm(`Install ${display(t)} now?`))) {
        logInfo("Skipped. Install it from the link above when you're ready.");
        return false;
    }
    const r = spawnSync(recipe, { stdio: 'inherit', shell: true });
    if (r.status !== 0) { logError('The install command failed (see its output above).'); return false; }
    found = resolve(tool);
    if (found) { activate(found); logSuccess(`${display(t)} is ready.`); return true; }
    logWarn(`Install finished but '${tool}' still isn't reachable — you may need to open a new terminal.`);
    return false;
}

module.exports = { canon, isKnown, display, url, fwTool, pin, resolve, activate, versionOf, verLt, latest, installCmd, updateCmd, ensure, findUp, KNOWN };
