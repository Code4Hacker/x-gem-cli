# Commands Reference

Global flags, valid on any command:

| Flag | Effect |
|---|---|
| `--yes` | Auto-confirm any yes/no prompt xgem itself would otherwise ask (doesn't affect prompts from an underlying tool like `create-next-app`'s own wizard) |
| `--dry-run` | Show what would happen without applying it (currently used by the iOS deployment-target reconciliation) |
| `--verbose` | Print debug-level logging that's normally suppressed |

---

## `xgem init`

Interactive. Prints a numbered list of frameworks (`flutter`, `node`, `python`, `react`, `vue`, `angular`, `next`, `go`, `rust`, `docker`, `swift`), then:

1. Asks whether to create a brand-new project or use what's already in the current directory (default: existing — safe to run in a directory you already have code in).
2. Either way, creates `.xgem-automate/<framework>/` with that framework's scripts and adds `.xgem-automate/` to `.gitignore`.
3. For frameworks with a real dev server (react/vue/angular/next), offers to launch it and open your default browser. For Flutter, offers to run on a picked device/simulator.

Refuses to run again if `.xgem-automate/` already exists in the current directory — use `xgem add` instead.

See [Frameworks](frameworks.md) for exactly what the "create new project" wizard does per framework.

## `xgem add`

Like `xgem init`, but for a workspace that's already been initialized — lists only the frameworks *not yet* added, lets you pick one to append. If every framework has already been added, offers to regenerate all of them from their current templates (useful after an xgem upgrade that changed template content).

Never runs the "create a new project" wizard — it assumes the project already exists, since you're adding automation *to* something, not creating something new.

## `xgem run <framework> <script>`

Runs a generated script directly, e.g. `xgem run react build`, `xgem run flutter hard-clean`. If the script doesn't exist, prints the ones that do, so you're not left guessing:

```
$ xgem run react harsh-clean
[FAIL] Script not found at .xgem-automate/react/harsh-clean.sh
Available scripts in 'react':
  - build
  - dev
  - hard-clean
```

For Flutter specifically, `xgem run flutter <script>` always goes through xgem's native SwiftPM-aware engine (see [The iOS Build Engine](ios-build-engine.md)), not the generated `.sh` file — the generated file is just a thin delegator to the same engine, kept for consistency/manual-run parity, not a second implementation.

## `xgem terminate`

Deletes `.xgem-automate/` entirely and cleans up the `.gitignore` entry. Asks for confirmation first (`--yes` skips that). Does not touch your actual project files — only xgem's own generated automation directory.

## `xgem doctor [ios]`

`xgem doctor` — reports OS, architecture, and whether it can find git/flutter/dart/node/python3/go/cargo/docker (and, on macOS, Xcode/CocoaPods). Never fails on a missing tool, just reports it — this is meant to be the first thing you run when something else isn't working.

`xgem doctor ios [path]` — standalone iOS build-readiness report: CocoaPods vs SwiftPM, the actual deployment target per build configuration (read via `xcodebuild`, not guessed), what your resolved SwiftPM plugins actually require, and what `FlutterGeneratedPluginSwiftPackage` currently declares — the exact pieces of information the deployment-target reconciliation engine uses, so you can see the diagnosis without triggering a build.

## `xgem git`

A convenience layer over common git workflows — none of it requires having run `xgem init` first.

### `xgem git init`

Runs `git init`, commits everything currently in the directory, then — if [GitHub CLI](https://cli.github.com) (`gh`) is installed and authenticated — offers to **actually create the GitHub repository** (`gh repo create <name> --public|--private --source=. --remote=origin --push`), not just wire a remote to a URL you had to go create by hand on github.com first. Falls back to the manual URL-entry flow if `gh` isn't available or authenticated, with a one-line pointer to `gh auth login`.

### `xgem git cmt "message"`

Stages (all files, or a space-separated list you choose), commits, and syncs with the remote:

- If there's nothing new to commit (e.g. you already committed and are just retrying), it doesn't abort — it still checks for and pushes any local commits already ahead of the remote.
- If the current branch has never been pushed before, it detects that specifically (via `git ls-remote`) and pushes directly to create it, instead of attempting a doomed `git pull --rebase` against a ref that doesn't exist yet.
- A real merge conflict during the rebase is distinguished from a genuine connection failure — you get an accurate message either way, and your commit is never at risk since it happens before any of this.

### `xgem git branch`

Lists local branches, lets you pick one or create a new one, checks it out, and remembers your choice (`git config --local xgem.default-branch`) as this repo's default. `xgem git cmt` always operates on whatever's actually checked out — that's the only thing that's correct for a commit — so this command's job is the interactive checkout/creation, not changing how `cmt` picks its branch.

### `xgem git rm-remote` / `xgem git rm-branch`

Interactive prompts to drop a configured remote, or safely delete a branch locally, remotely, or both (switches off a branch first if you're currently on the one being deleted).

## `xgem <framework>`

Prints that framework's status (whether it's been added to this workspace) and its available scripts — e.g. `xgem react`, `xgem flutter`. Doesn't run anything.

## `xgem --version`

Prints the installed version.
