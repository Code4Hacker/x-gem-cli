#!/bin/bash
# Removes an xgem install created by install.sh (curl-pipe path).
# npm/Homebrew installs should be removed via `npm uninstall -g xgem-cli` /
# `brew uninstall xgem` instead — this script only unwinds its own layout.
set -euo pipefail

SHARE_DIR="${XGEM_SHARE_DIR:-$HOME/.local/share/xgem}"
BIN_DIR="${XGEM_INSTALL_DIR:-$HOME/.local/bin}"
BIN_LINK="$BIN_DIR/xgem"

if [ -L "$BIN_LINK" ] || [ -f "$BIN_LINK" ]; then
    rm -f "$BIN_LINK"
    echo "Removed $BIN_LINK"
fi

if [ -d "$SHARE_DIR" ]; then
    rm -rf "$SHARE_DIR"
    echo "Removed $SHARE_DIR"
fi

echo "xgem uninstalled. Any .xgem-automate/ directories in your projects were left untouched — remove them with 'xgem terminate' from inside each project if desired."
