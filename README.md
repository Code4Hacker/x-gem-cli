# xgem

A framework-aware automation CLI. `xgem init` can create a brand-new project
(real `npm create vite`/`create-next-app`/`create-vue`/`ng new`/`flutter create`
scaffolding, framework-specific questions, dependency install, and launching
the dev server in your browser or the app on a picked device/simulator) or
just scaffold clean/build/dev scripts into a project you already have
(Flutter, Node, Python, React/Vue/Angular/Next, Go, Rust, Docker, Swift).
`xgem run <framework> <script>` runs those scripts, `xgem doctor` reports on
your environment, and `xgem git` wraps a common stage → commit → rebase-pull
→ push workflow.

Flutter's iOS builds go through a dedicated engine that detects whether your
project uses CocoaPods or Swift Package Manager (SPM), figures out the actual
deployment target your resolved SPM plugins require (instead of guessing),
and reconciles it automatically.

**Full documentation: [docs/](https://github.com/Code4Hacker/x-gem-cli/blob/xgem/docs/README.md)** — getting started, every command in
depth, exactly what each framework's project-creation wizard does, the iOS build
engine explained, Windows support, and troubleshooting. This README is a summary.
(Absolute link on purpose — `docs/` isn't shipped inside the npm package itself,
so a relative link would 404 on npmjs.com's rendered README.)

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
xgem git branch               Pick, create, or switch branches; remembers your choice
xgem git rm-remote            Drop a configured remote
xgem git rm-branch            Safely drop local and/or remote branch
xgem --version                Print xgem's version

Flags (any command): --yes (skip confirmations), --dry-run (show, don't apply), --verbose
```

## Supported frameworks

flutter, node, python, react, vue, angular, next, go, rust, docker, swift

## Creating a new project

`xgem init` asks, per framework, whether to create a brand-new project or use
what's already in the directory — real `create-vite`/`create-vue`/`ng new`/
`create-next-app`/`flutter create` scaffolding, with framework-specific
questions and a working dev-server/device launch at the end. Package manager
(npm/yarn/pnpm/bun) is auto-detected everywhere, never assumed. Answering
"existing" (the default) skips all of this and just scaffolds
`.xgem-automate/` into the current directory. Full detail, including exactly
what runs for each framework: **[docs/frameworks.md](https://github.com/Code4Hacker/x-gem-cli/blob/xgem/docs/frameworks.md)**.

## Architecture

```
bin/xgem       thin dispatcher — no business logic, just resolves paths and routes commands
lib/
  logger.sh    log levels + verbose mode
  utils.sh     os/arch detection, confirm(), require_cmd()
  doctor.sh    environment + feature detection ("xgem doctor")
  ios.sh       the SwiftPM-aware iOS build engine
  flutter.sh   flutter command group (build/hard-clean/build-runner), delegates iOS builds to ios.sh
  git.sh       git cmt/init/branch/rm-remote/rm-branch
  scaffold.sh  generic clean/build/dev handling for the other, simpler frameworks
  create.sh    project creation wizards (react/vue/angular/next/simple frameworks)
templates/     the actual clean/build/dev script content xgem scaffolds into your project's .xgem-automate/
```

`xgem run flutter <script>` always goes through the native engine in `lib/flutter.sh`;
the `.xgem-automate/flutter/*.sh` files that get scaffolded into your project are thin
delegators to `xgem run flutter <script>`, so there's a single source of truth instead
of logic that can drift out of sync with two copies.

## Why the iOS build engine exists

Flutter auto-generates a wrapper Swift package, `FlutterGeneratedPluginSwiftPackage`,
whose declared minimum iOS platform can desync from your app's own
`IPHONEOS_DEPLOYMENT_TARGET` — independently, even when your app's own target is
already high enough. This is a confirmed, currently-open upstream Flutter bug
([flutter/flutter#186804](https://github.com/flutter/flutter/issues/186804),
[#189422](https://github.com/flutter/flutter/issues/189422),
[#162072](https://github.com/flutter/flutter/issues/162072)). `xgem run flutter build`
(iOS target) detects the actual requirement from your resolved SPM plugins, patches
every deployment-target occurrence, forces a clean regeneration, verifies it, and
falls back to a documented direct patch if the upstream bug is still biting — full
detail: **[docs/ios-build-engine.md](https://github.com/Code4Hacker/x-gem-cli/blob/xgem/docs/ios-build-engine.md)**. Run `xgem doctor ios`
any time for a standalone readiness report without doing a build.

## Windows support

Homebrew and the curl installer are macOS/Linux only, same as any bash tool. npm is
different: it ships a small native Windows engine (`lib-win/`) so `npm install -g
xgem-cli` actually works in `cmd.exe`/PowerShell, no WSL required — everything except
Flutter iOS/macOS builds (Xcode has no Windows equivalent) and the project-creation
wizards (not ported yet). Full detail: **[docs/windows.md](https://github.com/Code4Hacker/x-gem-cli/blob/xgem/docs/windows.md)**.

## Roadmap

Deferred to a follow-up pass, not yet in this release:
- Full self-healing/doctor treatment for the non-Flutter frameworks
- A plugin system (`xgem plugin install <name>`), starting with docker + firebase
- Shell completions, `--json` output, per-project config caching (stop re-prompting
  build name/number/platform every run)
- Deeper Android SDK/Java detection
- Project creation wizards on the Windows engine (`lib-win/`) — react/vue/angular/next
  scaffolding is pure Node.js tooling and would work fine there too, just not built yet

## License

MIT
