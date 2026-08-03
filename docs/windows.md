# Windows Support

Homebrew and the curl installer are macOS/Linux only, same as any bash-based tool — that's a fixed constraint, not a gap that's going to close. npm is different: it's the one channel a Windows machine can actually reach, and it ships with a real native engine, not a WSL requirement.

## Why two engines exist

`xgem` is fundamentally a bash CLI. Bash doesn't exist natively on Windows, so `npm install -g xgem-cli` on Windows runs a separate, parallel implementation (`lib-win/`, driven by `bin/xgem.js`) instead of the bash one. On macOS/Linux, npm installs run the *exact same* bash engine as Homebrew/curl — `bin/xgem.js` there is a thin passthrough that just execs the real `bin/xgem` script — so there's only one implementation to trust on POSIX. Windows is the only platform with a second, independent one.

## What works on Windows

- `init` / `add` / `run` / `terminate`
- `doctor` (general — not `doctor ios`, see below)
- The full git workflow (`cmt` / `init` / `branch` / `rm-remote` / `rm-branch`)
- Flutter builds for **APK, App Bundle, and Windows desktop** targets

## What doesn't, and why

- **Flutter iOS/macOS builds** — Xcode has no Windows equivalent, full stop. `xgem doctor ios` on Windows explains this plainly instead of pretending to support it.
- **`swift` as a framework choice** — no meaningful Windows Swift toolchain story exists to automate.
- **Project creation wizards** (the "create a new project" flow for react/vue/angular/next/flutter) — these exist on the bash engine but haven't been ported to `lib-win/` yet. The scaffolding tools themselves (`create-vite`, `ng new`, etc.) are pure Node.js/cross-platform tooling and would work fine on Windows; this is a real gap, just not built yet, not an architectural limitation.

## Inside WSL

None of the above applies — WSL reports itself as Linux (`process.platform === 'linux'`), so a WSL install gets the full bash engine automatically, same as a native Linux machine. If you're using WSL specifically to get around Windows limitations, you already have the complete tool.
