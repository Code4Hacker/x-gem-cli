// xgem Windows engine doctor — mirrors lib/doctor.sh's toolchain report.
// No iOS/SwiftPM engine exists here (see flutter.js) since Xcode has no
// Windows equivalent; `doctor ios` explains that instead of pretending.

const os = require('node:os');
const { detectArch } = require('./utils');
const { paint, logInfo } = require('./logger');
const toolchain = require('./toolchain');

const TOOLS = ['git', 'flutter', 'dart', 'node', 'python', 'go', 'cargo', 'docker', 'gh', 'fvm'];

const pretty = (p) => (p.startsWith(os.homedir()) ? `~${p.slice(os.homedir().length)}` : p);

async function printGeneral() {
    console.log(paint('cyan', '=== xgem doctor (Windows) ==='));
    console.log(`OS:   win32   Arch: ${detectArch()}\n`);

    const noNetwork = process.env.XGEM_NO_NETWORK === '1';
    if (!noNetwork) {
        logInfo('Checking installed tools and the latest available versions...');
        await Promise.all(TOOLS.filter((t) => toolchain.resolve(t)).map((t) => toolchain.latest(t)));
    }

    console.log(paint('cyan', 'Toolchains'));
    for (const t of TOOLS) {
        const found = toolchain.resolve(t);
        if (!found) {
            console.log(`  ${t.padEnd(9)} ${'not found'.padEnd(11)} download: ${toolchain.url(t)}`);
            const recipe = toolchain.installCmd(t);
            if (recipe) console.log(`            install:  ${recipe}   (or run: xgem update ${t})`);
            continue;
        }
        const version = toolchain.versionOf(t, found);
        const shown = found.manager === 'other' ? '' : ` (${found.manager})`;
        console.log(`  ${t.padEnd(9)} ${(version || 'unknown').padEnd(11)} ${pretty(found.path)}${shown}`);
        if (!found.onPath && t !== 'dart') {
            console.log(`            ! not on PATH: found via ${found.manager}, so plain scripts and CI won't see it (xgem resolves it for its own commands)`);
        }
        const newer = await toolchain.latest(t, true);
        if (version && newer && toolchain.verLt(version, newer)) {
            console.log(`            ^ update available: ${version} -> ${newer}   (run: xgem update ${t})`);
        }
        const pinned = t === 'dart' ? '' : toolchain.pin(t);
        if (pinned && version && /^\d/.test(pinned) && !version.startsWith(pinned)) {
            console.log(`            ! this project pins ${t} ${pinned} but the active one is ${version}`);
        }
    }
}

function printIos() {
    console.log(paint('cyan', '=== xgem doctor ios (Windows) ==='));
    console.log(paint('yellow', 'iOS/macOS builds are not available on Windows — Xcode has no Windows equivalent.'));
    console.log('Use WSL2 with a Mac, or a real Mac, for Flutter iOS builds.');
    const found = toolchain.resolve('flutter');
    if (found) {
        console.log(`\nflutter is installed here (${toolchain.versionOf('flutter', found)}) and can still build Android/Windows targets:`);
        console.log('  xgem run flutter build   (choose APK or Windows)');
    }
}

async function cmdDoctor(target) {
    if (target === 'ios') {
        printIos();
    } else if (!target) {
        await printGeneral();
    } else {
        const { die } = require('./logger');
        die(`Unknown doctor target '${target}'. Usage: xgem doctor [ios] [--no-network]`);
    }
}

module.exports = { cmdDoctor, printGeneral, printIos };
