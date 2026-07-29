#!/bin/bash
# xgem installer
# Usage: curl -fsSL https://raw.githubusercontent.com/<owner>/<repo>/main/install.sh | bash
set -euo pipefail

REPO_RAW_URL="https://raw.githubusercontent.com/<owner>/<repo>/main/bin/xgem"
INSTALL_DIR="${XGEM_INSTALL_DIR:-$HOME/.local/bin}"

if [[ "$OSTYPE" != darwin* && "$OSTYPE" != linux* ]]; then
    echo "Error: xgem currently supports macOS and Linux only." >&2
    exit 1
fi

mkdir -p "$INSTALL_DIR"

echo "Downloading xgem to $INSTALL_DIR/xgem..."
curl -fsSL "$REPO_RAW_URL" -o "$INSTALL_DIR/xgem"
chmod +x "$INSTALL_DIR/xgem"

if [[ ":$PATH:" != *":$INSTALL_DIR:"* ]]; then
    echo ""
    echo "Warning: $INSTALL_DIR is not on your PATH."
    echo "Add this to your shell profile (~/.zshrc or ~/.bashrc):"
    echo "  export PATH=\"$INSTALL_DIR:\$PATH\""
fi

echo ""
echo "xgem installed. Run 'xgem' to get started."
