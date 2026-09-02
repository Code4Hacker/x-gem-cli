// xgem Windows engine ci — port of lib/ci.sh: run lint -> test -> build for
// every configured framework before you push.

const fs = require('node:fs');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const { logInfo, logSuccess, logWarn, logError, die } = require('./logger');

const STEPS = ['lint', 'test', 'build'];

async function cmdCi(configDir) {
    if (!fs.existsSync(configDir)) die(`No ${configDir} found — run 'xgem init' or 'xgem add' first.`);

    const results = [];
    let overallOk = true;

    for (const fw of fs.readdirSync(configDir, { withFileTypes: true }).filter((d) => d.isDirectory()).map((d) => d.name)) {
        for (const step of STEPS) {
            const target = path.join(configDir, fw, `${step}.mjs`);
            if (!fs.existsSync(target)) continue;
            logInfo(`Running ${fw} ${step}...`);
            const result = spawnSync(process.execPath, [target], { stdio: 'inherit' });
            const ok = (result.status ?? 1) === 0;
            results.push(`${ok ? 'PASS ' : 'FAIL '} ${fw} ${step}`);
            if (!ok) overallOk = false;
        }
    }

    if (results.length === 0) {
        logWarn(`No lint/test/build scripts found under ${configDir} to run.`);
        return;
    }

    console.log('');
    console.log('=== xgem ci summary ===');
    results.forEach((r) => console.log(r));

    if (overallOk) logSuccess('All checks passed.');
    else logError('Some checks failed.');
    process.exitCode = overallOk ? 0 : 1;
}

module.exports = { cmdCi };
