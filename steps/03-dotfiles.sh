#!/bin/bash
# Link config files into the system using symlinks.
set -uo pipefail
[ -z "${OS_TYPE:-}" ] && source "${DOTFILES_DIR:-.}/lib/detect.sh"
D="${DOTFILES_DIR:?DOTFILES_DIR not set}"

lnk() { mkdir -p "$(dirname "$2")"; ln -sf "$1" "$2"; }

echo "[03] Applying dotfiles..."

# ~/.zshrc is a thin real file (not a symlink) so machine-local overlays can
# append to ~/.zshrc.local without writing into the versioned repo file.
if [ ! -f "$HOME/.zshrc" ] || [ -L "$HOME/.zshrc" ] || ! grep -q '.dotfiles/config/zsh/zshrc' "$HOME/.zshrc"; then
  cat > "$HOME/.zshrc" <<EOF
# Managed by dotfiles. Public config lives in the repo; local overlays in ~/.zshrc.local.
[ -f "\$HOME/.dotfiles/config/zsh/zshrc" ] && source "\$HOME/.dotfiles/config/zsh/zshrc"
EOF
fi
lnk "$D/config/nvim/init.lua"   "$HOME/.config/nvim/init.lua"

# ghostty config + terminfo (desktop only or if ghostty is already installed)
if { [ "$OS_TYPE" = "Darwin" ] && [ "$IS_VM" = "no" ]; } || [ -d ~/.config/ghostty ]; then
  lnk "$D/config/ghostty/config" "$HOME/.config/ghostty/config"
  if ! infocmp xterm-ghostty >/dev/null 2>&1 && [ -f "$D/config/ghostty/ghostty.terminfo" ]; then
    sudo tic -x "$D/config/ghostty/ghostty.terminfo" 2>/dev/null || tic -x "$D/config/ghostty/ghostty.terminfo" 2>/dev/null || true
  fi
fi

# git config (delta) — cp because git include.path resolves symlinks fine,
# but we keep it as a copy to avoid git reading a path inside the repo.
cp "$D/config/git/gitconfig" "$HOME/.gitconfig.delta"
git config --global include.path "$HOME/.gitconfig.delta"
if [ -z "$(git config --global user.name)" ] && [ "${INTERACTIVE:-no}" = "yes" ]; then
  read -p "Git name: " GIT_NAME
  read -p "Git email: " GIT_EMAIL
  git config --global user.name "$GIT_NAME"
  git config --global user.email "$GIT_EMAIL"
fi
echo "[03] done"
