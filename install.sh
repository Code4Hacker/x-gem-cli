#!/bin/bash
# xgem installer
# Usage: curl -fsSL https://raw.githubusercontent.com/Code4Hacker/x-gem-cli/xgem/install.sh | bash
set -euo pipefail

REPO_URL="https://github.com/Code4Hacker/x-gem-cli.git"
SHARE_DIR="${XGEM_SHARE_DIR:-$HOME/.local/share/xgem}"
BIN_DIR="${XGEM_INSTALL_DIR:-$HOME/.local/bin}"

print_banner() {
    echo -e "\033[38;5;208m"
    echo -e "██╗  ██╗       ██████╗ ███████╗███╗   ███╗██╗███╗   ██╗██╗"
    echo -e "╚██╗██╔╝      ██╔════╝ ██╔════╝████╗ ████║██║████╗  ██║██║"
    echo -e " ╚███╔╝ █████╗██║  ███╗█████╗  ██╔████╔██║██║██╔██╗ ██║██║"
    echo -e " ██╔██╗ ╚════╝██║   ██║██╔══╝  ██║╚██╔╝██║██║██║╚██╗██║██║"
    echo -e "██╔╝ ██╗      ╚██████╔╝███████╗██║ ╚═╝ ██║██║██║ ╚████║██║"
    echo -e "╚═╝  ╚═╝       ╚═════╝ ╚══════╝╚═╝     ╚═╝╚═╝╚═╝  ╚═══╝╚═╝\033[0m"
    echo -e "\033[1;36m           ....installer....\033[0m\n"
}

# _spin <pid> <message> — animates a spinner next to <message> until <pid>
# exits, then clears the line. Falls back to a plain wait if the terminal
# doesn't support cursor control (e.g. piped/non-interactive output).
_spin() {
    local pid=$1
    local msg=$2

    if [ ! -t 1 ]; then
        wait "$pid"
        return $?
    fi

    local frames=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏)
    local n=${#frames[@]}
    local i=0
    tput civis 2>/dev/null || true
    while kill -0 "$pid" 2>/dev/null; do
        printf "\r\033[1;36m%s\033[0m %s" "${frames[$i]}" "$msg"
        i=$(( (i + 1) % n ))
        sleep 0.08
    done
    tput cnorm 2>/dev/null || true
    printf "\r\033[K"
    wait "$pid"
}

print_banner

case "$OSTYPE" in
    darwin*|linux*) ;;
    *)
        echo -e "\033[31mxgem does not run natively on this platform (detected: $OSTYPE).\033[0m"
        echo "It's a bash CLI built for macOS/Linux. On Windows, install WSL2 first:"
        echo "  https://learn.microsoft.com/windows/wsl/install"
        echo "Then run this same command again from inside your WSL terminal."
        exit 1
        ;;
esac

if ! command -v git >/dev/null 2>&1; then
    echo -e "\033[31mError: git is required to install xgem.\033[0m" >&2
    exit 1
fi

mkdir -p "$BIN_DIR"
rm -rf "$SHARE_DIR"

git clone --depth 1 "$REPO_URL" "$SHARE_DIR" --quiet &
clone_pid=$!
if ! _spin "$clone_pid" "Fetching xgem..."; then
    echo -e "\033[31mFailed to fetch xgem from $REPO_URL.\033[0m" >&2
    exit 1
fi
echo -e "\033[32m✓\033[0m Fetched xgem into $SHARE_DIR"

ln -sf "$SHARE_DIR/bin/xgem" "$BIN_DIR/xgem"
chmod +x "$SHARE_DIR/bin/xgem"
echo -e "\033[32m✓\033[0m Linked $BIN_DIR/xgem"

if [[ ":$PATH:" != *":$BIN_DIR:"* ]]; then
    echo ""
    echo -e "\033[33mWarning:\033[0m $BIN_DIR is not on your PATH."
    echo "Add this to your shell profile (~/.zshrc or ~/.bashrc):"
    echo "  export PATH=\"$BIN_DIR:\$PATH\""
fi

echo ""
echo -e "\033[1;32mxgem installed:\033[0m $("$BIN_DIR/xgem" --version 2>/dev/null || echo "(installed)")"
echo "Run 'xgem' to get started, or 'xgem doctor' for an environment report."
