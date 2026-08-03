# Frameworks

## Automation scripts

Every framework gets `hard-clean`/`build` at minimum, plus whatever else makes sense:

| Framework | Scripts |
|---|---|
| flutter | hard-clean, build, build-runner |
| node | hard-clean, build, start, +lint/test if `package.json` declares them |
| python | hard-clean, install |
| react / vue / angular / next | hard-clean, build, dev, +lint/test if `package.json` declares them |
| go | hard-clean, build |
| rust | hard-clean, build |
| docker | hard-clean, build-up |
| swift | hard-clean, build |

`lint`/`test` are only scaffolded when the project's actual `package.json` declares those scripts — not always generated and left to fail with "Missing script" on projects that don't have them.

## Package-manager detection

The node/react/vue/angular/next `hard-clean`/`build`/`dev`/`start`/`lint`/`test` scripts detect which package manager the project actually uses — checked in this order: `package.json`'s `"packageManager"` field, then lockfile presence (`pnpm-lock.yaml` → pnpm, `yarn.lock` → yarn, `bun.lockb`/`bun.lock` → bun, `package-lock.json` → npm), falling back to npm only if none of those exist yet (e.g. a project that's never had `install` run).

This matters most for `hard-clean`, which deletes `node_modules` and the lockfile before reinstalling: it only ever deletes the lockfile matching the *detected* manager. It will never delete `yarn.lock` and run `npm install` on a yarn project — doing that corrupts the project by introducing a conflicting lockfile, which is a real bug this was built specifically to stop happening.

`hard-clean` also checks a `.nvmrc` against the Node version actually running (`node -v`) and warns — doesn't block — on a mismatch.

## Creating a new project (`xgem init` → "new")

### react

Asks Vite vs Create React App ("the normal version"), then TypeScript vs JavaScript, then current directory vs a new folder.

- **Vite** (default): `npm create vite@latest . -- --template react[-ts] --no-immediate`, then xgem's own `npm install`. `--no-immediate` matters: `create-vite` has its own flag to install *and start the dev server itself*, which would otherwise block xgem — and if you Ctrl-C that, it kills the whole `xgem` process, including everything meant to run after it. This is exactly what "the automation doesn't get created" bug reports have turned out to be, for whichever framework's scaffolding tool has this kind of hidden step.
- **CRA**: `npx create-react-app . [--template typescript]`. Create React App has no flag to decouple scaffolding from installing — it's one atomic, slow call — so there's a small residual risk that interrupting it loses xgem's bookkeeping. xgem tells you this up front rather than pretending it doesn't apply.

### vue

`npm create vue@latest . --force`, letting Vue's own interactive prompts (router, Pinia, ESLint, testing) through rather than reimplementing them — create-vue doesn't install automatically, so xgem's own `npm install` runs after.

### angular

`ng new . --skip-install --skip-git` (via a local Angular CLI if you have one, `npx @angular/cli` otherwise), then xgem's own `npm install`. `--skip-git`: xgem has its own `xgem git init`, and Angular's own auto-commit would happen before `.xgem-automate` even exists. `--skip-install`: same reasoning as Vite's `--no-immediate` — Angular's own install step is famously slow (often 1–3 minutes), and decoupling it is what makes xgem's own setup safe from an impatient Ctrl-C.

### next

`npx create-next-app@latest . --skip-install`, then xgem's own `npm install` — same decoupling reasoning as Angular.

### flutter

`flutter create --no-pub .`, then xgem's own bookkeeping, then `flutter pub get` (the `--no-pub`/manual-`pub get` split exists for the same reason as the others). Then lists available devices/simulators via `flutter devices` and lets you pick one to run on — if none are running, falls back to listing available-but-not-booted emulators (`flutter emulators`) and offers to launch one.

### node / python / go / rust / docker / swift

No sub-wizard — just the ecosystem's own minimal init command (`npm init -y`, a `.venv`, `cargo init`, `go mod init`, a starter `Dockerfile`, `swift package init --type executable`). These don't have an install step slow enough to make the ordering fragile, so there's nothing to decouple.

## The "new folder, then where's my terminal" thing

If you choose "new folder" during any of the above, xgem's own process correctly ends up inside that new folder for the rest of its run — but once it exits, **your actual terminal is back wherever it started**. This isn't a bug: a child process (which `xgem` is, from your shell's point of view) cannot change its parent shell's working directory — no CLI tool can do this without you specifically sourcing a shell function, which xgem doesn't require you to set up. xgem prints the exact `cd <name>` to run as the last thing it does; that's the intended fix, not a workaround for something broken.
