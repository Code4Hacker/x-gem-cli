# Getting Started

## Install

Pick one:

```sh
# Homebrew (macOS/Linux)
brew install Code4Hacker/xgem/xgem

# npm (macOS/Linux/Windows — the only channel with Windows support)
npm install -g xgem-cli

# curl (macOS/Linux)
curl -fsSL https://raw.githubusercontent.com/Code4Hacker/x-gem-cli/xgem/install.sh | bash
```

Confirm it worked:

```sh
xgem --version
xgem doctor
```

`xgem doctor` reports your OS, architecture, and whether it can find git/flutter/node/python/go/cargo/docker (and, on macOS, Xcode/CocoaPods) — it doesn't fail if something's missing, it just tells you what it found. Run this first whenever something isn't working; most "xgem is broken" reports turn out to be "a required tool isn't on PATH", and this shows you that immediately.

## Two things xgem does

1. **Scaffolds automation** for a project (new or existing) — `xgem init` drops framework-specific `hard-clean`/`build`/`dev` scripts into a `.xgem-automate/` folder, and `xgem run <framework> <script>` runs them.
2. **Creates whole new projects**, for frameworks where that's worth automating (React, Vue, Angular, Next.js, Flutter) — real `npm create vite`/`create-next-app`/`ng new`/`flutter create` scaffolding, not a reimplementation, with framework-specific questions and a working dev-server/device launch at the end.

Everything else (`xgem git`, `xgem doctor`) is a standalone convenience layered on top — you don't need to have run `xgem init` to use them.

## Your first run

```sh
mkdir my-project && cd my-project
xgem init
```

You'll be asked which framework, then whether to create a brand-new project or use what's already in the directory. Answering "existing" (the default) is safe to run in a directory you already have code in — it only ever adds `.xgem-automate/` and a line to `.gitignore`, nothing else.

Answering "new" hands off to the real scaffolding tool for that framework (see [Frameworks](frameworks.md) for exactly what runs for each one). One thing worth knowing up front: **if you choose to create a project in a new folder, your terminal does not move into it afterward** — `xgem` is a separate process and can't change your shell's working directory (no CLI tool actually can, this isn't an xgem limitation specifically). It prints the exact `cd <name>` command to run; that's expected, not a bug.

## What gets created

```
.xgem-automate/
  <framework>/
    hard-clean.sh   # wipes caches/lockfiles/node_modules and reinstalls
    build.sh        # production build
    dev.sh          # dev server (web) — or start.sh for node, install.sh for python, etc.
```

Run any of them via `xgem run <framework> <script>`, e.g. `xgem run react hard-clean`. `.xgem-automate/` is automatically added to `.gitignore` — these are local automation scripts, not something to commit (they get regenerated deterministically from your project's actual state each time you run `xgem init`/`xgem add`).

## Next

- [Commands Reference](commands.md) for everything else `xgem` can do.
- [Frameworks](frameworks.md) if you want the exact detail on what "create a new project" does for your framework.
