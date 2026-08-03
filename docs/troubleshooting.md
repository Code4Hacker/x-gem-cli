# Troubleshooting / FAQ

## `.xgem-automate` didn't get created after choosing "new"

If you interrupted (Ctrl-C) during project creation on an older xgem version, this could happen — a scaffolding tool's own slow install step (`ng new`, `create-vite`'s own dev-server auto-launch, etc.) blocking before xgem's bookkeeping ran. Fixed as of `2.0.0-alpha.11`+: xgem now creates `.xgem-automate` and updates `.gitignore` *before* any slow, interruptible step, for every framework, specifically so this can't happen anymore. If you still see it on a current version, that's a bug — please [file an issue](https://github.com/Code4Hacker/x-gem-cli/issues) with the exact command sequence.

## `xgem run <framework> build` says "Missing script"

This means the underlying tool (npm/yarn/pnpm) doesn't have that script in `package.json` — check with `npm run` (no script name) to see what's actually available, or `xgem run <framework> <anything-invalid>`, which lists the scripts xgem itself generated. If a script you expect (like `lint` or `test`) isn't listed, it's because xgem only scaffolds those when `package.json` actually declares them — re-run `xgem init`/`xgem add` after adding the script to pick it up.

## It deleted my yarn.lock / it's trying to use npm on my yarn project

This was a real bug, fixed as of `2.0.0-alpha.11`+: `hard-clean` now detects the package manager actually in use (via lockfile presence or `package.json`'s `packageManager` field) and only ever touches the matching lockfile. If you're still seeing npm/yarn confusion on a current version, run `xgem doctor` and check your xgem version, then file an issue.

## The Flutter iOS build fails with "requires minimum platform version X... but this target supports Y"

See [The iOS Build Engine](ios-build-engine.md) for the full explanation — this is a known, currently-open upstream Flutter bug that xgem specifically detects and works around. Run `xgem doctor ios` for a standalone diagnosis. If the engine's automatic fix doesn't resolve it, it falls back to a safety net that parses Xcode's own error and retries once — if it *still* fails after that, please file an issue with the full `xgem doctor ios` output and the build log.

## `xgem git init` isn't offering to create a GitHub repo

That feature needs [GitHub CLI](https://cli.github.com) (`gh`) installed *and* authenticated (`gh auth login`). Without it, `xgem git init` falls back to the manual remote-URL flow. Run `gh auth status` to check.

## npm install fails with `EBADPLATFORM` or a Windows-specific error

Make sure you're on a recent xgem version — earlier ones didn't have a Windows-native engine at all. `npm install -g xgem-cli` should now work directly on Windows (see [Windows Support](windows.md)) for everything except Flutter iOS/macOS builds, which need an actual Mac.

## The npm-installed `xgem --version` doesn't match what I just published/expect

`bin/xgem`'s own internal version banner (`lib/version.sh`'s `XGEM_VERSION`) is a separate constant from `package.json`'s version — they're kept in sync manually on each release. If they're out of sync, that's a release-process slip, not a sign the install didn't take — check `npm view xgem-cli version` against what's actually installed (`npm list -g xgem-cli`) to confirm the real package version.

## Still stuck

Run `xgem doctor` (or `xgem doctor ios` for Flutter iOS issues) and include its output when reporting a problem — most reports turn out to be a missing tool on PATH or a version mismatch, and that output makes the diagnosis immediate instead of a multi-round guessing game.
