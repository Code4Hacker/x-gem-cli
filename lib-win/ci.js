// xgem Windows engine ci — port of lib/ci.sh: run the checks for every
// configured framework, then explain what failed and how to fix it.

const fs = require('node:fs');
const path = require('node:path');
const { spawn, spawnSync } = require('node:child_process');
const { logInfo, logSuccess, logWarn, logError, die } = require('./logger');
const { confirm } = require('./utils');
const toolchain = require('./toolchain');
const { diagnoseStep } = require('./ci-diagnose');

const STEPS = ['lint', 'test', 'build'];

function logDir(configDir) {
    const dir = path.join(configDir, 'ci');
    fs.mkdirSync(dir, { recursive: true });
    const ignore = path.join(dir, '.gitignore');
    if (!fs.existsSync(ignore)) fs.writeFileSync(ignore, '*\n');
    return dir;
}

// A step is { label, cmd, args, shell }. Output goes to a log; --verbose also streams it.
function runStep(step, ctx) {
    return new Promise((resolve) => {
        const log = path.join(logDir(ctx.configDir), `${step.label.replace(/[ /\\]/g, '-')}.log`);
        logInfo(`Running ${step.label}...`);
        const start = Date.now();
        const out = fs.openSync(log, 'w');
        const verbose = process.env.XGEM_VERBOSE === '1';
        const child = spawn(step.cmd, step.args, {
            stdio: ['ignore', verbose ? 'pipe' : out, verbose ? 'pipe' : out],
            env: { ...process.env, CI: 'true' },
            shell: step.shell,
        });
        if (verbose) {
            child.stdout.on('data', (d) => { process.stdout.write(d); fs.writeSync(out, d); });
            child.stderr.on('data', (d) => { process.stderr.write(d); fs.writeSync(out, d); });
        }
        const beat = setInterval(() => console.log(`      ...still running ${step.label} (${Math.round((Date.now() - start) / 1000)}s)`), 30000);
        child.on('close', (code) => {
            clearInterval(beat);
            fs.closeSync(out);
            const secs = Math.round((Date.now() - start) / 1000);
            const ok = code === 0;
            ctx.results.push({ line: `${ok ? 'PASS ' : 'FAIL '} ${step.label} (${secs}s)`, ok });
            if (!ok) ctx.failed.push({ step, log });
            resolve();
        });
        child.on('error', () => child.emit('close', 1));
    });
}

async function collectSteps(configDir, ctx) {
    const steps = [];
    for (const fw of fs.readdirSync(configDir, { withFileTypes: true }).filter((d) => d.isDirectory() && d.name !== 'ci').map((d) => d.name)) {
        if (fw === 'flutter') {
            if (!(await toolchain.ensure('flutter'))) { ctx.results.push({ line: 'SKIP  flutter (flutter not found)', ok: true }); continue; }
            steps.push({ label: 'flutter analyze', cmd: 'flutter analyze', args: [], shell: true });
            if (fs.existsSync('test')) steps.push({ label: 'flutter test', cmd: 'flutter test', args: [], shell: true });
            else ctx.results.push({ line: 'SKIP  flutter test (no test/ directory)', ok: true });
            continue;
        }
        const needed = toolchain.fwTool(fw);
        if (needed && !(await toolchain.ensure(needed))) { ctx.results.push({ line: `SKIP  ${fw} (${needed} not found)`, ok: true }); continue; }
        for (const s of STEPS) {
            const target = path.join(configDir, fw, `${s}.mjs`);
            if (fs.existsSync(target)) steps.push({ label: `${fw} ${s}`, cmd: process.execPath, args: [target], shell: false });
        }
    }
    return steps;
}

function printSummary(results) {
    console.log('');
    console.log('=== xgem ci summary ===');
    results.forEach((r) => console.log(r.line));
}

function snapshot() {
    const r = spawnSync('git', ['ls-files', '-m', '-o', '--exclude-standard'], { encoding: 'utf8' });
    if (r.status !== 0) return new Map();
    const map = new Map();
    for (const f of r.stdout.split(/\r?\n/).filter(Boolean)) {
        const h = spawnSync('git', ['hash-object', f], { encoding: 'utf8' });
        if (h.status === 0) map.set(f, h.stdout.trim());
    }
    return map;
}

function diagnoseAll(failed) {
    const autofix = [];
    for (const { step, log } of failed) {
        const d = diagnoseStep(step.label, log);
        console.log(d.text);
        for (const a of d.autofix) if (!autofix.includes(a)) autofix.push(a);
    }
    return autofix;
}

async function applyFixes(autofix) {
    if (!autofix.length) {
        logInfo('None of these failures has a safe automatic fix; the causes above need a code change.');
        return false;
    }
    const before = snapshot();
    let ran = false;
    for (const cmd of autofix) {
        if (!(await confirm(`Run the tool's own fixer: ${cmd} ?`))) continue;
        ran = true;
        logInfo(`Running: ${cmd}`);
        if (spawnSync(cmd, { stdio: 'inherit', shell: true }).status !== 0) logWarn(`'${cmd}' exited with an error (see output above).`);
    }
    if (!ran) return false;
    const after = snapshot();
    const changed = [...after].filter(([f, h]) => before.get(f) !== h).map(([f]) => f);
    if (changed.length) {
        logSuccess(`The fixer changed ${changed.length} file(s); review them with git diff:`);
        changed.forEach((f) => console.log(`    ${f}`));
    } else {
        logInfo("The fixer didn't change any files.");
    }
    return true;
}

async function cmdCi(configDir, args = []) {
    if (!fs.existsSync(configDir)) die(`No ${configDir} found — run 'xgem init' or 'xgem add' first.`);
    for (const a of args) if (a && a !== '--fix') die(`Unknown option '${a}'. Usage: xgem ci [--fix] [--verbose]`);
    const wantFix = args.includes('--fix');

    const ctx = { configDir, results: [], failed: [] };
    const steps = await collectSteps(configDir, ctx);
    for (const s of steps) await runStep(s, ctx);

    if (ctx.results.length === 0) { logWarn(`No checks found under ${configDir} to run.`); return; }
    printSummary(ctx.results);

    if (ctx.results.every((r) => r.ok)) { logSuccess('All checks passed.'); return; }

    const autofix = diagnoseAll(ctx.failed);
    if (autofix.length && !wantFix) {
        console.log('');
        logInfo(`Some of these can be fixed automatically. Run 'xgem ci --fix' to apply: ${autofix.join(' ')}`);
    }

    if (wantFix && (await applyFixes(autofix))) {
        const retry = ctx.failed.map((f) => f.step);
        const next = { configDir, results: [], failed: [] };
        console.log('');
        logInfo('Re-running the failed steps...');
        for (const s of retry) await runStep(s, next);
        printSummary(next.results);
        if (next.results.every((r) => r.ok)) { logSuccess('All checks pass after the fixes.'); return; }
        console.log('');
        logWarn("Still failing after the automatic fixes; what's left needs a manual change:");
        diagnoseAll(next.failed);
    }

    logError('Some checks failed.');
    process.exitCode = 1;
}

module.exports = { cmdCi };
