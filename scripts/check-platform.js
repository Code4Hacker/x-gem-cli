#!/usr/bin/env node
// Runs as npm's preinstall step. xgem is a bash CLI (osascript/xcodebuild
// for the iOS engine, sh-isms throughout) with no Windows-native equivalent,
// so this exists purely to fail with an actionable message instead of npm's
// generic EBADPLATFORM error.

if (process.platform !== 'darwin' && process.platform !== 'linux') {
    console.error('');
    console.error('\x1b[31mxgem does not run natively on Windows.\x1b[0m');
    console.error("It's a bash CLI, and its Flutter iOS build engine shells out to Xcode tools that only exist on macOS.");
    console.error('');
    console.error('\x1b[36mTo use xgem on Windows, install WSL2 first:\x1b[0m');
    console.error('  https://learn.microsoft.com/windows/wsl/install');
    console.error('Then run this same install command again from inside your WSL terminal (it reports itself as Linux).');
    console.error('');
    process.exit(1);
}
