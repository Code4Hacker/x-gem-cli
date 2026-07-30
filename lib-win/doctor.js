// xgem Windows engine doctor — mirrors lib/doctor.sh's general report.
// No iOS/SwiftPM engine exists here (see flutter.js) since Xcode has no
// Windows equivalent; `doctor ios` explains that instead of pretending.

const { getVersion, detectArch } = require('./utils');
const { paint } = require('./logger');

function printGeneral() {
    console.log(paint('cyan', '=== xgem doctor (Windows) ==='));
    console.log(`OS:              win32`);
    console.log(`Arch:            ${detectArch()}`);
    console.log(`git:             ${getVersion('git') || 'not found'}`);
    console.log(`flutter:         ${getVersion('flutter') || 'not found'}`);
    console.log(`dart:            ${getVersion('dart') || 'not found'}`);
    console.log(`node:            ${getVersion('node') || 'not found'}`);
    console.log(`python:          ${getVersion('python') || getVersion('python3') || 'not found'}`);
    console.log(`go:              ${getVersion('go', ['version']) || 'not found'}`);
    console.log(`cargo:           ${getVersion('cargo') || 'not found'}`);
    console.log(`docker:          ${getVersion('docker') || 'not found'}`);
}

function printIos() {
    console.log(paint('cyan', '=== xgem doctor ios (Windows) ==='));
    console.log(paint('yellow', 'iOS/macOS builds are not available on Windows — Xcode has no Windows equivalent.'));
    console.log('Use WSL2 with a Mac, or a real Mac, for Flutter iOS builds.');
    const flutterVersion = getVersion('flutter');
    if (flutterVersion) {
        console.log(`\nflutter is installed here (${flutterVersion}) and can still build Android/Windows targets:`);
        console.log('  xgem run flutter build   (choose APK or Windows)');
    }
}

function cmdDoctor(target) {
    if (target === 'ios') {
        printIos();
    } else if (!target) {
        printGeneral();
    } else {
        const { die } = require('./logger');
        die(`Unknown doctor target '${target}'. Usage: xgem doctor [ios]`);
    }
}

module.exports = { cmdDoctor, printGeneral, printIos };
