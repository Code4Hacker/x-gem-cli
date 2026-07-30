# xgem

A framework-aware automation CLI. `xgem init` scaffolds clean/build/dev scripts
tailored to your project type (Flutter, Node, Python, React/Vue/Angular, Go,
Rust, Docker, Swift), `xgem run <framework> <script>` runs them, `xgem doctor`
reports on your environment, and `xgem git` wraps a common stage → commit →
rebase-pull → push workflow.

Flutter's iOS builds go through a dedicated engine that detects whether your
project uses CocoaPods or Swift Package Manager (SPM), figures out the actual
deployment target your resolved SPM plugins require (instead of guessing),
and reconciles it automatically — see [Why the iOS build engine exists](#why-the-ios-build-engine-exists).

## Install

### Homebrew (macOS/Linux)

```sh
brew install Code4Hacker/xgem/xgem
```

xgem isn't in Homebrew's central `homebrew-core` (that requires a formal submission/review), so it lives in its own tap (`Code4Hacker/homebrew-xgem`). The `user/repo/formula` form above taps and installs in one step — no separate `brew tap` needed.

### npm

```sh
npm install -g xgem-cli
```

Works natively on Windows too (no WSL needed) — npm's install runs a small Node.js
engine there instead of the bash one; see [Windows support](#windows-support).

### curl

```sh
curl -fsSL https://raw.githubusercontent.com/Code4Hacker/x-gem-cli/xgem/install.sh | bash
```

## Usage

```
xgem init                     Initialize tracking system and add first framework
xgem add                      Interactive state-aware addition of remaining frameworks
xgem run <framework> <script> Run a workspace automation command script
xgem terminate                Purge all generated automated layouts completely
xgem <framework> [help]       View tailored instructions for a specific script layout
xgem doctor                   Report on your environment (OS, arch, toolchains found)
xgem doctor ios [path]        Report on iOS build readiness: CocoaPods vs SPM, deployment
                               targets per config, and whether they're reconciled
xgem git cmt "message"        Auto-stage, commit, rebase-pull, and push
xgem git init                 Setup local repo, attach remote tracker shortcuts
xgem git rm-remote            Drop a configured remote
xgem git rm-branch            Safely drop local and/or remote branch
xgem --version                Print xgem's version

Flags (any command): --yes (skip confirmations), --dry-run (show, don't apply), --verbose
```

## Supported frameworks

flutter, node, python, react, vue, angular, go, rust, docker, swift

## Architecture

```
bin/xgem       thin dispatcher — no business logic, just resolves paths and routes commands
lib/
  logger.sh    log levels + verbose mode
  utils.sh     os/arch detection, confirm(), require_cmd()
  doctor.sh    environment + feature detection ("xgem doctor")
  ios.sh       the SwiftPM-aware iOS build engine
  flutter.sh   flutter command group (build/hard-clean/build-runner), delegates iOS builds to ios.sh
  git.sh       git cmt/init/rm-remote/rm-branch
  scaffold.sh  generic clean/build/dev handling for the other, simpler frameworks
templates/     the actual clean/build/dev script content xgem scaffolds into your project's .xgem-automate/
```

`xgem run flutter <script>` always goes through the native engine in `lib/flutter.sh`;
the `.xgem-automate/flutter/*.sh` files that get scaffolded into your project are thin
delegators to `xgem run flutter <script>`, so there's a single source of truth instead
of logic that can drift out of sync with two copies.

## Why the iOS build engine exists

Flutter auto-generates a wrapper Swift package, `FlutterGeneratedPluginSwiftPackage`,
that aggregates your plugins' SPM dependencies. Its declared minimum iOS platform can
desync from your app's own `IPHONEOS_DEPLOYMENT_TARGET` — a confirmed, currently-open
upstream Flutter bug ([flutter/flutter#186804](https://github.com/flutter/flutter/issues/186804),
[#189422](https://github.com/flutter/flutter/issues/189422),
[#162072](https://github.com/flutter/flutter/issues/162072)). A single `sed` patch to
`project.pbxproj` doesn't reliably fix this: there are multiple deployment-target entries
across Debug/Release/Profile × Runner/RunnerTests, and even a fully correct patch doesn't
force Flutter to regenerate the generated package.

`xgem run flutter build` (for the iOS target) instead:

1. Detects whether the project uses CocoaPods, SPM, or both.
2. Computes the deployment target actually required by your *resolved* SPM plugins
   (by reading their `ios/Package.swift` manifests via `.dart_tool/package_config.json`),
   instead of assuming a fixed value.
3. Shows a plan and asks for confirmation (unless `--yes`/`--dry-run`) before patching
   *every* `IPHONEOS_DEPLOYMENT_TARGET` occurrence in `project.pbxproj`.
4. Forces a clean regeneration (`flutter pub get` after clearing `ios/Flutter/ephemeral`)
   and verifies the regenerated package matches.
5. If it still doesn't (the upstream bug above), patches the generated package directly
   as a documented, loudly-logged last resort — never silently.

Run `xgem doctor ios` any time for a standalone readiness report without doing a build.

## Windows support

Homebrew and the curl installer are macOS/Linux only, same as any bash tool — that's
not going to change. npm is different: it's published with a small native Windows
engine (`lib-win/`, driven by `bin/xgem.js`) so `npm install -g xgem-cli` actually works
in `cmd.exe`/PowerShell, no WSL required.

What works on Windows: `init`/`add`/`run`/`terminate`, `doctor`, the git workflow
commands, and Flutter builds for **APK, App Bundle, and Windows desktop** targets. What doesn't:
Flutter **iOS/macOS** builds — Xcode has no Windows equivalent, so `xgem doctor ios`
explains that plainly instead of pretending. `swift` isn't offered as a framework
choice on Windows for the same reason. If you're inside WSL, none of this applies —
WSL reports itself as Linux, so you get the full bash engine automatically.

On macOS/Linux, npm installs run the exact same bash engine as Homebrew/curl (`bin/xgem.js`
is a thin passthrough that execs the real `bin/xgem` script) — there's only one
implementation to trust on POSIX; Windows is the only platform with a second one.

## Roadmap

Deferred to a follow-up pass, not yet in this release:
- Full self-healing/doctor treatment for the non-Flutter frameworks
- A plugin system (`xgem plugin install <name>`), starting with docker + firebase
- Shell completions, `--json` output, per-project config caching (stop re-prompting
  build name/number/platform every run)
- Deeper Android SDK/Java detection

## License

MIT
