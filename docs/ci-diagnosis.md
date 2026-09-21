# `xgem ci`: finding the real bug and how to fix it

`xgem ci` doesn't just say `FAIL`. For every failed step it shows where the problem is, groups repeated failures into their root causes, explains each cause, and says what to change. It can also run the tool's own auto-fixer for the ones that have one.

## What you see

A run is quiet: one line per step with its time, and the full output saved to `.xgem-automate/ci/<step>.log` (git-ignored). Add `--verbose` to stream the raw output live. A step that runs longer than 30 seconds prints a "still running" line so it doesn't look hung.

If something fails, after the summary you get a report per failed step:

```
FAIL node test   (15 findings, 3 distinct causes)   full log: .xgem-automate/ci/node-test.log

 1) No provider for HttpClient  x12 in 3 files
    test/a.test.js:2:29  Error: NullInjectorError: ... No provider for HttpClient!
        tests: a component > should create 1 | a component > should create 2 | ... (+1 more)
        2 | function boot(name) { throw new Error('NullInjectorError: ...
          |                             ^
      Why:  Angular can't create something because a service it needs isn't provided here ...
      Fix:  Provide it. In a test: TestBed.configureTestingModule({ providers: [TheService] }). ...
```

- **Grouped causes.** Twelve failing tests that all throw the same error are one cause, shown once with the affected tests listed, not twelve screens of output. Up to five causes are shown (most serious, then most frequent), each with up to three example locations; the rest are in the log.
- **Exact location.** `file:line:col` plus the offending source line with a caret under the column.
- **Why and Fix.** Plain-language explanation and the change to make, plus a docs link when the rule has a stable page (Dart, ESLint core rules, Rust error codes).
- **Nothing invented.** If a failure isn't in the knowledge base, you get the location, message and source line, and a note saying there's no known fix. If no file/line can be extracted at all, you get the last lines of the log.

## `xgem ci --fix`

Some causes have a safe automatic fix from the project's own tooling. Those are marked `[auto-fixable]`, and the fix command is shown. With `--fix`, xgem asks before running each one, lists the files it changed (review with `git diff`), then re-runs only the failed steps and reports what's still broken.

| Tool | Auto-fix command | What it covers |
|---|---|---|
| Dart / Flutter | `dart fix --apply` | unused imports, `const` constructors, super parameters, and other fixable lints |
| ESLint | your `lint` script with `--fix` | fixable style rules (only offered if your `lint` script runs `eslint` or `ng lint`) |
| Cargo | `cargo fix --allow-dirty --allow-staged` | fixable warnings (only offered when the code compiles) |

Test failures, type errors and missing imports have no automatic fix: xgem points at the cause instead. `--yes` pre-approves the fixers; `--dry-run` runs nothing.

## What it understands

Parsed from each tool's own output:

| Tool | Checked against real output |
|---|---|
| `flutter analyze` / `dart analyze`, `flutter test` | yes |
| TypeScript (`tsc`) | yes |
| ESLint | yes |
| Vitest (failures, startup errors) | yes |
| Jest | yes |
| Cargo | yes |
| Angular CLI build errors (`[ERROR] NG...`), Go compile errors | parsed from their documented formats; not yet checked against a live run |

Any other output falls back to a generic `file:line` + error-word match, then to the log tail. The same real-output samples are stored in `test/fixtures/ci/` and checked by `npm test` against both the bash and Windows engines.

## What it can't do

xgem doesn't rewrite your code and can't fix a wrong assertion or a logic bug. For those it shows the failing test, where it fails, and Expected vs Actual, so you know what to change. It never modifies files unless you run `--fix` and confirm.

## Adding an explanation

The explanations live in one tab-separated file, `templates/ci/fixes.tsv`, read by both engines:

```
id  kind  pattern  why  fix  autofix  docs  group
```

- `kind` is `code` (exact rule or error code, like `TS2322` or `unused_import`) or `regex` (matched against the message).
- `autofix` is a command, `@LINT_FIX@` (your project's lint script with `--fix`), or `-`.
- `docs` may use `@CODE@` for the code; `-` for none.
- `group` (regex rows): `match` clusters by the matched text (so `No provider for HttpClient` and `No provider for Router` stay separate causes); `id` clusters everything the row matches together.

Rows are checked in file order, `code` rows before `regex` rows.
