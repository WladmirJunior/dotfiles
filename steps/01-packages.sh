#!/bin/bash
# Install essential CLI tools (brew on Mac, apt on Linux).
# Requires: DOTFILES_DIR in env.
set -uo pipefail
[ -z "${OS_TYPE:-}" ] && source "${DOTFILES_DIR:-.}/lib/detect.sh"

echo "[01] CLI packages..."

if [ "$OS_TYPE" = "Darwin" ]; then
  if ! command -v brew >/dev/null 2>&1; then
    echo "Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    eval "$(/opt/homebrew/bin/brew shellenv)"
  fi
  brew install git neovim fzf zoxide eza bat ripgrep fd git-delta tlrc node usbutils
elif [ "$OS_TYPE" = "Linux" ]; then
  sudo apt update
  sudo apt install -y zsh neovim fzf zoxide eza bat ripgrep fd-find git-delta \
    nodejs npm curl git tealdeer software-properties-common wget
  mkdir -p ~/.local/bin
  [ -n "$(command -v fdfind 2>/dev/null)" ] && ln -sf "$(command -v fdfind)" ~/.local/bin/fd
  [ -n "$(command -v batcat 2>/dev/null)" ] && ln -sf "$(command -v batcat)" ~/.local/bin/bat
else
  echo "Unsupported OS: $OS_TYPE"; exit 1
fi
echo "[01] done"
