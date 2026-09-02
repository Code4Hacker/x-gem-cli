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

### `xgem git pr`

Pushes the current branch and opens a GitHub PR via `gh`. The base branch is read from GitHub itself (`gh repo view --json defaultBranchRef`), not guessed. A single commit ahead of the base becomes the PR title as-is; multiple commits get a title derived from the branch name and a bulleted body listing each commit subject — either way you're shown the draft and can type a replacement title before it's created. If a PR for the branch already exists, it's opened instead of creating a duplicate. Without `gh` installed/authenticated, it prints (and offers to open) a GitHub compare URL instead.

### `xgem git sync`

Fetches and rebases the current branch onto the repo's base branch in one step. Conflict handling matches `xgem git cmt`: a real merge conflict is distinguished from a connection failure, with an offer to open VS Code.

### `xgem git clean-branches`

Prunes stale remote-tracking refs, then lists and (after confirmation) deletes local branches already merged into the base branch — never the current branch or `main`/`master`/`develop`/`dev`. Uses `git branch -d` (not `-D`), so a branch that isn't actually fully merged is left alone even if it slipped through. Branches merged via a GitHub squash-merge won't show up here (squash merges don't preserve ancestry) — delete those from GitHub's own "delete branch" button after merging, or locally once you've pulled a real ancestry-preserving merge.

### `xgem git hooks install` / `xgem git hooks uninstall`

Installs a `.git/hooks/pre-commit` hook that runs `xgem run <framework> lint` (and, if you opt in at install time, `test`) for every framework with those scripts, blocking the commit if any of them fail. Won't overwrite a pre-commit hook it didn't create without asking first; `uninstall` refuses to remove a hook it doesn't recognize as its own.

## `xgem release [major|minor|patch]`

Bumps the version in whichever of `package.json` / `pubspec.yaml` / `Cargo.toml` / `pyproject.toml` is present (asks which one if more than one is), defaulting to a `patch` bump if you don't pass a kind. Prepends a new `## vX.Y.Z` section to `CHANGELOG.md`, generated from `git log` since the last tag and bucketed into Features/Fixes/Other by conventional-commit prefix (`feat:`/`fix:`). Commits, tags (`vX.Y.Z`), and — after confirmation — pushes both.

## `xgem status`

A one-screen dashboard across every project `xgem init`/`xgem add` has ever touched (tracked in `~/.xgem/projects`, pruned automatically as directories disappear): branch, uncommitted-file count, ahead/behind its upstream, and which frameworks are configured — so you don't have to `cd` into each one to see what's dirty.

## `xgem bootstrap`

Clone-to-running in one command, for a project you just checked out — not a "create new project" wizard (that's `xgem init`). In order:

1. **Detects the framework** from marker files (`pubspec.yaml`, `go.mod`, `Cargo.toml`, `pyproject.toml`/`requirements.txt`/`setup.py`, `Package.swift`, or a `package.json` whose dependencies are grepped to tell `next`/`angular`/`vue`/`react` apart from plain `node`). No match → the same framework picker `xgem init` uses.
2. **`.env` setup** — if `.env.example` or `.env.sample` exists and `.env` doesn't, copies it and lists any `KEY=` lines left empty so you know what to fill in.
3. **Installs dependencies**, package-manager-aware for node-family projects (same lockfile detection as `hard-clean`), plus `flutter pub get` / `poetry install` or a `.venv` + `pip install` / `go mod download` / `cargo fetch` / `swift package resolve` as appropriate. Docker projects have nothing to install locally.
4. **Runs migrations** — best-effort and always behind a confirmation: a `migrate` script in `package.json`, else `npx prisma migrate dev` if `prisma/schema.prisma` exists, else `python3 manage.py migrate` if `manage.py` exists. No match → skipped silently, not every project has one.
5. **Offers to scaffold `.xgem-automate`** if this project hasn't been xgem-tracked before, so `xgem run`/`xgem status`/`xgem ci` work here too.
6. **Offers to launch the dev server** for node-family projects (`node`→`start`, `react`/`vue`/`angular`/`next`→`dev`) once step 5 has scaffolded that script.

Any tool that isn't installed is skipped with a warning rather than failing the whole run.

## `xgem ci`

Runs `lint` → `test` → `build` (in that order) for every framework already configured under `.xgem-automate/`, skipping any script that isn't scaffolded for a given framework. Unlike a pre-commit hook, it doesn't stop at the first failure — it runs everything and prints a pass/fail summary at the end, exiting non-zero if anything failed, so you see everything that's broken in one pass instead of a slow fix-one-rerun loop. Requires `.xgem-automate` to already exist (`xgem init`/`xgem add`/`xgem bootstrap` first).

## `xgem <framework>`

Prints that framework's status (whether it's been added to this workspace) and its available scripts — e.g. `xgem react`, `xgem flutter`. Doesn't run anything.

## `xgem --version`

Prints the installed version.
