// xgem Windows engine ci — port of lib/ci.sh: run the checks for every
// configured framework before you push.

const fs = require('node:fs');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const { logInfo, logSuccess, logWarn, logError, die } = require('./logger');
const toolchain = require('./toolchain');

const STEPS = ['lint', 'test', 'build'];

function runStep(label, cmd, args, results) {
    logInfo(`Running ${label}...`);
    const result = spawnSync(cmd, args, {
        stdio: ['ignore', 'inherit', 'inherit'],
        env: { ...process.env, CI: 'true' },
        shell: cmd !== process.execPath,
    });
    const ok = (result.status ?? 1) === 0;
    results.push({ line: `${ok ? 'PASS ' : 'FAIL '} ${label}`, ok });
}

async function flutterSteps(results) {
    if (!(await toolchain.ensure('flutter'))) {
        results.push({ line: 'SKIP  flutter (flutter not found)', ok: true });
        return;
    }
    runStep('flutter analyze', 'flutter', ['analyze'], results);
    if (fs.existsSync('test')) {
        runStep('flutter test', 'flutter', ['test'], results);
    } else {
        results.push({ line: 'SKIP  flutter test (no test/ directory)', ok: true });
    }
}

async function cmdCi(configDir) {
    if (!fs.existsSync(configDir)) die(`No ${configDir} found — run 'xgem init' or 'xgem add' first.`);

    const results = [];

    for (const fw of fs.readdirSync(configDir, { withFileTypes: true }).filter((d) => d.isDirectory()).map((d) => d.name)) {
        if (fw === 'flutter') {
            await flutterSteps(results);
            continue;
        }
        const needed = toolchain.fwTool(fw);
        if (needed && !(await toolchain.ensure(needed))) {
            results.push({ line: `SKIP  ${fw} (${needed} not found)`, ok: true });
            continue;
        }
        for (const step of STEPS) {
            const target = path.join(configDir, fw, `${step}.mjs`);
            if (!fs.existsSync(target)) continue;
            runStep(`${fw} ${step}`, process.execPath, [target], results);
        }
    }

    if (results.length === 0) {
        logWarn(`No checks found under ${configDir} to run.`);
        return;
    }

    console.log('');
    console.log('=== xgem ci summary ===');
    results.forEach((r) => console.log(r.line));

    const overallOk = results.every((r) => r.ok);
    if (overallOk) logSuccess('All checks passed.');
    else logError('Some checks failed.');
    process.exitCode = overallOk ? 0 : 1;
}

module.exports = { cmdCi };
