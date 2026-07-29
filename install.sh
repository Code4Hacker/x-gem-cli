#!/bin/bash
# xgem installer
# Usage: curl -fsSL https://raw.githubusercontent.com/<owner>/<repo>/main/install.sh | bash
set -euo pipefail

REPO_URL="https://github.com/<owner>/<repo>.git"
SHARE_DIR="${XGEM_SHARE_DIR:-$HOME/.local/share/xgem}"
BIN_DIR="${XGEM_INSTALL_DIR:-$HOME/.local/bin}"

case "$OSTYPE" in
    darwin*|linux*) ;;
    *) echo "Error: xgem currently supports macOS and Linux only." >&2; exit 1 ;;
esac

if ! command -v git >/dev/null 2>&1; then
    echo "Error: git is required to install xgem." >&2
    exit 1
fi

mkdir -p "$BIN_DIR"

echo "Fetching xgem into $SHARE_DIR..."
rm -rf "$SHARE_DIR"
git clone --depth 1 "$REPO_URL" "$SHARE_DIR" --quiet

ln -sf "$SHARE_DIR/bin/xgem" "$BIN_DIR/xgem"
chmod +x "$SHARE_DIR/bin/xgem"

if [[ ":$PATH:" != *":$BIN_DIR:"* ]]; then
    echo ""
    echo "Warning: $BIN_DIR is not on your PATH."
    echo "Add this to your shell profile (~/.zshrc or ~/.bashrc):"
    echo "  export PATH=\"$BIN_DIR:\$PATH\""
fi

echo ""
echo "xgem installed. Run 'xgem' to get started, or 'xgem doctor' for an environment report."
