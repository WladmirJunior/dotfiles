#!/bin/bash
# Copy config files to the system.
set -uo pipefail
[ -z "${OS_TYPE:-}" ] && source "${DOTFILES_DIR:-.}/lib/detect.sh"
D="${DOTFILES_DIR:?DOTFILES_DIR not set}"

echo "[03] Applying dotfiles..."
mkdir -p ~/.config/nvim ~/.local/bin

cp "$D/config/zsh/zshrc" ~/.zshrc
cp "$D/config/nvim/init.lua" ~/.config/nvim/init.lua

# ghostty config + terminfo (desktop only or if ghostty is already installed)
if { [ "$OS_TYPE" = "Darwin" ] && [ "$IS_VM" = "no" ]; } || [ -d ~/.config/ghostty ]; then
  mkdir -p ~/.config/ghostty
  cp "$D/config/ghostty/config" ~/.config/ghostty/config
  if ! infocmp xterm-ghostty >/dev/null 2>&1 && [ -f "$D/config/ghostty/ghostty.terminfo" ]; then
    sudo tic -x "$D/config/ghostty/ghostty.terminfo" 2>/dev/null || tic -x "$D/config/ghostty/ghostty.terminfo" 2>/dev/null || true
  fi
fi

# git config (delta)
cp "$D/config/git/gitconfig" ~/.gitconfig.delta
git config --global include.path ~/.gitconfig.delta
if [ -z "$(git config --global user.name)" ] && [ "${INTERACTIVE:-no}" = "yes" ]; then
  read -p "Git name: " GIT_NAME
  read -p "Git email: " GIT_EMAIL
  git config --global user.name "$GIT_NAME"
  git config --global user.email "$GIT_EMAIL"
fi
echo "[03] done"
