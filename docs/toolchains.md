# Toolchains: how xgem finds, installs, and updates your tools

xgem shells out to real tools (Flutter, Node, Go, Rust, Python, Docker, ...). This page explains how it decides a tool is "there", what it does when one isn't, and how updates work.

## How xgem finds a tool

It checks, in order:

1. **`PATH`** — the normal lookup.
2. **A project pin** — `.fvmrc` / `.fvm/fvm_config.json` (Flutter), `.nvmrc` (Node), or `.tool-versions` (asdf/mise-style). If your project says Flutter `3.35.0` and that SDK is installed, it's the one used.
3. **Version-manager locations** — FVM (`~/fvm`, `~/.fvm`, `$FVM_CACHE_PATH`), nvm (`~/.nvm/versions/node/*`, honoring `.nvmrc` and nvm's default alias), fnm, Volta, asdf, mise, pyenv, rustup (`~/.cargo/bin`), puro, Homebrew, and the usual install folders.

When a tool is found off `PATH`, xgem puts it on **its own process's** `PATH` for the rest of that command. It never edits your shell config.

### Why `flutter` can be "installed" but invisible

`alias flutter='fvm flutter'` (and nvm, which is a shell *function*) only exist inside your interactive shell. A script — including xgem, a git hook, or CI — can't see aliases or shell functions, so `command -v flutter` fails there even though typing `flutter` in your terminal works. xgem sidesteps this by looking where FVM/nvm actually store the SDK, and `xgem doctor` tells you when that's what happened:

```
flutter   3.44.6   ~/.fvm/flutter_sdk/bin/flutter (fvm)
          ! not on PATH: found via fvm, so plain scripts and CI won't see it
```

If you want plain scripts to see it too, put FVM's global SDK on your `PATH`: `export PATH="$HOME/fvm/default/bin:$PATH"` (after `fvm global <version>`).

## When a tool is missing

For any command that needs a tool (`xgem bootstrap`, `xgem ci`, `xgem run flutter ...`, project creation), xgem:

1. Says which tool is needed and that it wasn't found anywhere it looked.
2. Prints the **official download link**.
3. Shows the **exact install command** it would run (for example `brew install go`, `fvm install stable && fvm global stable`, or the official rustup script) and asks for confirmation.
4. If you say yes, runs it, re-checks, and **carries on with what you originally asked for**.

If you say no, or there's no safe automated route (or the installer it needs, like Homebrew or winget, isn't present), it stops and leaves you with the link. Nothing is installed without your confirmation; `--dry-run` shows the command without running it, and `--yes` pre-approves.

| Tool | macOS | Windows | Linux |
|---|---|---|---|
| Flutter | `fvm install stable && fvm global stable` if FVM is present, else `brew install --cask flutter` | via FVM if present, else link only | link only |
| Node | `nvm install --lts` if nvm is present, else `brew install node` | `winget` | nvm if present, else link |
| Python, Go, Git, GitHub CLI, Docker | `brew` | `winget` | link |
| Rust | official rustup script | `winget` (rustup) | official rustup script |
| FVM | `brew install fvm` | `dart pub global activate fvm` | official install script |

## `xgem doctor`

Lists each tool with its version, **where it was found and how** (`via fvm`, `via nvm`, `via brew`, ...), whether an update is available, and — for anything missing — the download link and install command. It also lists which version managers it detected and warns when your project's pinned version differs from the active one.

Latest versions come from the vendors' own release feeds (Flutter's release manifest, nodejs.org's LTS index, go.dev) and Homebrew for brew-managed tools. Results are cached for 12 hours in `~/.xgem/cache`, so repeat runs are fast, and `--no-network` skips lookups and uses only the cache (offline-safe).

## `xgem update [tool]`

Compares installed vs latest and, per tool, shows the exact command and asks before running it:

- **Flutter (FVM):** `fvm install <latest>`, then offers `fvm global <latest>` and, inside a pinned project, `fvm use <latest>`.
- **Node (nvm):** `nvm install --lts`. **Rust:** `rustup update`. **Homebrew-managed tools** (git, gh, docker, python, fvm, go, ...): `brew upgrade <name>`.
- Anything else: the download link.

`xgem update flutter` on a machine without Flutter offers to install it instead.

This covers the toolchains themselves. It does not update your project's own dependencies (`npm outdated`, `flutter pub outdated`, and so on).
