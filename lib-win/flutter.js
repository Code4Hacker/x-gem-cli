// xgem Windows engine flutter commands. hard-clean/build-runner have no
// platform-specific dependency and work as-is. build only offers targets
// that are actually buildable from a Windows host (APK, Windows desktop) —
// iOS/macOS need Xcode (a Mac), and Flutter can't cross-compile Linux
// desktop from Windows either, so those fail fast with a clear message
// instead of attempting anything.

const fs = require('node:fs');
const { spawnSync } = require('node:child_process');
const { logInfo, logSuccess, logError, die } = require('./logger');
const { prompt, requireCmd } = require('./utils');

function flutter(args) {
    return spawnSync('flutter', args, { stdio: 'inherit' });
}

async function cmdHardClean() {
    requireCmd('flutter', 'Install Flutter: https://docs.flutter.dev/get-started/install/windows');
    logInfo('Cleaning Flutter project...');
    fs.rmSync('pubspec.lock', { force: true });
    flutter(['clean']);
    logInfo('Getting Flutter packages...');
    flutter(['pub', 'get']);
    logInfo('Running Flutter...');
    flutter(['run', '-v']);
}

async function cmdBuildRunner() {
    requireCmd('flutter', 'Install Flutter: https://docs.flutter.dev/get-started/install/windows');
    logInfo('Running Flutter Build Runner...');
    const verboseChoice = ((await prompt('Run in verbose mode? (Y/n)')) || 'Y').toLowerCase();
    const args = ['pub', 'run', 'build_runner', 'build', '--delete-conflicting-outputs'];
    if (verboseChoice === 'y') args.push('-v');
    logInfo(`Executing: flutter ${args.join(' ')}`);
    flutter(args);
}

function pubspecVersion() {
    if (!fs.existsSync('pubspec.yaml')) return null;
    const content = fs.readFileSync('pubspec.yaml', 'utf8');
    const match = content.match(/^version:\s*(\S+)/m);
    return match ? match[1] : null;
}

async function cmdBuild() {
    requireCmd('flutter', 'Install Flutter: https://docs.flutter.dev/get-started/install/windows');
    console.log('--- Flutter Build Orchestrator (Windows) ---');

    let currentName = '';
    let currentNum = '';
    const currentFull = pubspecVersion();
    if (currentFull) {
        [currentName, currentNum = '1'] = currentFull.split('+');
        logInfo(`Current pubspec.yaml version: ${currentFull}`);
    }

    const buildName = (await prompt('Enter build version name', currentName || '1.0.0'));
    const buildNumber = (await prompt('Enter build number', currentNum || '1'));
    const isRelease = ((await prompt('Is this a release build? (Y/n)', 'y'))).toLowerCase();

    if (fs.existsSync('pubspec.yaml')) {
        const newVersion = `${buildName}+${buildNumber}`;
        logSuccess(`Updating pubspec.yaml to version: ${newVersion}`);
        const content = fs.readFileSync('pubspec.yaml', 'utf8');
        fs.writeFileSync('pubspec.yaml', content.replace(/^version:.*/m, `version: ${newVersion}`));
    }

    console.log('\nSelect Target Platform:');
    console.log('1) APK (Android)');
    console.log('2) App Bundle (Android, .aab — required for Play Store uploads)');
    console.log('3) Windows');
    console.log('(iOS/macOS require a Mac; Linux desktop can\'t be cross-built from Windows.)');
    const platformChoice = await prompt('Choose [1-3]');

    const mode = (isRelease === 'n') ? '--debug' : '--release';
    const buildArgs = [`--build-name=${buildName}`, `--build-number=${buildNumber}`];

    if (platformChoice === '1') {
        logInfo(`Building APK (${mode})...`);
        flutter(['build', 'apk', mode, ...buildArgs]);
    } else if (platformChoice === '2') {
        logInfo(`Building App Bundle (${mode})...`);
        flutter(['build', 'appbundle', mode, ...buildArgs]);
    } else if (platformChoice === '3') {
        logInfo(`Building Windows desktop app (${mode})...`);
        flutter(['build', 'windows', mode, ...buildArgs]);
    } else {
        die(`'${platformChoice}' isn't buildable from Windows. iOS/macOS need a Mac (xgem doctor ios explains more); Linux desktop needs a Linux host.`);
    }
}

async function cmdFlutter(script) {
    switch (script) {
        case 'hard-clean': return cmdHardClean();
        case 'build': return cmdBuild();
        case 'build-runner': return cmdBuildRunner();
        default: die(`No native flutter command for '${script}'.`);
    }
}

module.exports = { cmdFlutter };
