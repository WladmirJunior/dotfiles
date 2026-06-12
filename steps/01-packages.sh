#!/bin/bash
# Install essential CLI tools (brew on Mac, apt on Linux).
# Requires: DOTFILES_DIR in env.
set -uo pipefail
[ -z "${OS_TYPE:-}" ] && source "${DOTFILES_DIR:-.}/lib/detect.sh"
source "${DOTFILES_DIR:-.}/lib/ui.sh" 2>/dev/null || true
command -v run >/dev/null 2>&1 || run() { [ "${DRY_RUN:-0}" = 1 ] && { echo "[dry-run] $*"; return 0; }; "$@"; }

echo "[01] CLI packages..."

if [ "$OS_TYPE" = "Darwin" ]; then
  if ! command -v brew >/dev/null 2>&1; then
    echo "Installing Homebrew..."
    run /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    [ "${DRY_RUN:-0}" = 1 ] || eval "$(/opt/homebrew/bin/brew shellenv)"
  fi
  # gum is NOT installed here: the UI uses our fork binary (table --width/
  # --border-row), fetched by ui_bootstrap_gum in install.sh. See lib/ui.sh.
  run brew install git gh neovim fzf zoxide eza bat ripgrep fd git-delta tlrc node usbutils
elif [ "$OS_TYPE" = "Linux" ]; then
  # On a clean apt-based image we may run as root (no sudo). Pick the right prefix.
  SUDO=""
  [ "$(id -u)" -ne 0 ] && command -v sudo >/dev/null 2>&1 && SUDO=sudo

  run $SUDO apt-get update -qq
  # Install in two passes so a missing package in one distro (e.g. trixie removed
  # `software-properties-common` from the default repo) doesn't drop the rest.
  # First pass: core tools that must be there. Second pass: nice-to-haves, best-effort.
  run $SUDO env DEBIAN_FRONTEND=noninteractive apt-get install -y \
    zsh neovim fzf zoxide bat ripgrep fd-find git-delta nodejs npm curl git gh wget
  # Best-effort extras; never abort if one is missing in this distro.
  for pkg in eza tealdeer software-properties-common; do
    run $SUDO env DEBIAN_FRONTEND=noninteractive apt-get install -y "$pkg" 2>/dev/null \
      || echo "  skip: $pkg not available in this distro"
  done
  run mkdir -p ~/.local/bin
  [ -n "$(command -v fdfind 2>/dev/null)" ] && run ln -sf "$(command -v fdfind)" ~/.local/bin/fd
  [ -n "$(command -v batcat 2>/dev/null)" ] && run ln -sf "$(command -v batcat)" ~/.local/bin/bat
else
  echo "Unsupported OS: $OS_TYPE"; exit 1
fi
echo "[01] done"
