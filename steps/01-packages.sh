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
  run sudo apt update
  run sudo apt install -y zsh neovim fzf zoxide eza bat ripgrep fd-find git-delta \
    nodejs npm curl git gh tealdeer software-properties-common wget
  run mkdir -p ~/.local/bin
  [ -n "$(command -v fdfind 2>/dev/null)" ] && run ln -sf "$(command -v fdfind)" ~/.local/bin/fd
  [ -n "$(command -v batcat 2>/dev/null)" ] && run ln -sf "$(command -v batcat)" ~/.local/bin/bat
else
  echo "Unsupported OS: $OS_TYPE"; exit 1
fi
echo "[01] done"
