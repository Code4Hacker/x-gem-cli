# xgem documentation

- [Getting Started](getting-started.md) — install, first run, core concepts
- [Commands Reference](commands.md) — every command, every flag, with real examples
- [Frameworks](frameworks.md) — what `xgem init` actually does per framework, including the "create a new project" wizard and package-manager detection
- [Toolchains](toolchains.md) — how xgem finds Flutter/Node/etc. (including FVM and nvm installs), offers to install missing ones, and checks for updates
- [CI diagnosis](ci-diagnosis.md) — how `xgem ci` finds the real cause of a failure, groups it, explains the fix, and auto-fixes what's safe
- [The iOS Build Engine](ios-build-engine.md) — why Flutter's iOS builds need a dedicated engine, and exactly what it does
- [Windows Support](windows.md) — what works, what doesn't, and why
- [Troubleshooting / FAQ](troubleshooting.md) — common problems and their actual causes

If something here doesn't match reality, [open an issue](https://github.com/Code4Hacker/x-gem-cli/issues) — these docs describe the code as of the version you have installed (`xgem --version`), not an aspirational future state.
