# xgem

A framework-aware automation CLI. `xgem init` scaffolds clean/build/dev scripts
tailored to your project type (Flutter, Node, Python, React/Vue/Angular, Go,
Rust, Docker, Swift), `xgem run <framework> <script>` runs them, and `xgem git`
wraps a common stage → commit → rebase-pull → push workflow.

## Install

### Homebrew (macOS/Linux)

```sh
brew tap <owner>/xgem
brew install xgem
```

### npm

```sh
npm install -g xgem-cli
```

### curl

```sh
curl -fsSL https://raw.githubusercontent.com/<owner>/<repo>/main/install.sh | bash
```

## Usage

```
xgem init                     Initialize tracking system and add first framework
xgem add                      Interactive state-aware addition of remaining frameworks
xgem run <framework> <script> Run a workspace automation command script
xgem terminate                Purge all generated automated layouts completely
xgem <framework> [help]       View tailored instructions for a specific script layout
xgem git cmt "message"        Auto-stage, commit, rebase-pull, and push
xgem git init                 Setup local repo, attach remote tracker shortcuts
xgem git rm-remote            Drop a configured remote
xgem git rm-branch            Safely drop local and/or remote branch
```

## Supported frameworks

flutter, node, python, react, vue, angular, go, rust, docker, swift

## License

MIT
