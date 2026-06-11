#!/bin/bash
# Link config files into the system using symlinks.
set -uo pipefail
[ -z "${OS_TYPE:-}" ] && source "${DOTFILES_DIR:-.}/lib/detect.sh"
D="${DOTFILES_DIR:?DOTFILES_DIR not set}"
# Source ui.sh for run()/note (dry-run + quarantine helpers). Falls back to a
# plain run() if sourced standalone, so the step still works on its own.
source "${DOTFILES_DIR:-.}/lib/ui.sh" 2>/dev/null || true
command -v run >/dev/null 2>&1 || run() { [ "${DRY_RUN:-0}" = 1 ] && { echo "[dry-run] $*"; return 0; }; "$@"; }

lnk() { run mkdir -p "$(dirname "$2")"; run ln -sf "$1" "$2"; }

echo "[03] Applying dotfiles..."

# ~/.zshrc is a thin real file (not a symlink) so machine-local overlays can
# append to ~/.zshrc.local without writing into the versioned repo file.
if [ ! -f "$HOME/.zshrc" ] || [ -L "$HOME/.zshrc" ] || ! grep -q '.dotfiles/config/zsh/zshrc' "$HOME/.zshrc"; then
  if [ "${DRY_RUN:-0}" = 1 ]; then
    echo "[dry-run] write thin ~/.zshrc (sources ~/.dotfiles/config/zsh/zshrc)"
  else
    cat > "$HOME/.zshrc" <<EOF
# Managed by dotfiles. Public config lives in the repo; local overlays in ~/.zshrc.local.
[ -f "\$HOME/.dotfiles/config/zsh/zshrc" ] && source "\$HOME/.dotfiles/config/zsh/zshrc"
EOF
  fi
fi
lnk "$D/config/nvim/init.lua"   "$HOME/.config/nvim/init.lua"

# ghostty config + terminfo. Link it whenever Ghostty is installed (or its config
# dir already exists) — don't gate on IS_VM: a desktop-profile VM with a UI gets
# Ghostty too. 04-apps (desktop profile) installs Ghostty before this matters on
# reruns; on first run the app may not be present yet, so also accept the dir.
if [ -d /Applications/Ghostty.app ] || command -v ghostty >/dev/null 2>&1 || [ -d ~/.config/ghostty ]; then
  lnk "$D/config/ghostty/config" "$HOME/.config/ghostty/config"
  if ! infocmp xterm-ghostty >/dev/null 2>&1 && [ -f "$D/config/ghostty/ghostty.terminfo" ]; then
    run sudo tic -x "$D/config/ghostty/ghostty.terminfo" 2>/dev/null || run tic -x "$D/config/ghostty/ghostty.terminfo" 2>/dev/null || true
  fi
fi

# git config (delta) — cp because git include.path resolves symlinks fine,
# but we keep it as a copy to avoid git reading a path inside the repo.
# Back up any existing target to the quarantine bin (never blind-overwrite local
# edits) before copying, but only when the content actually differs.
DELTA="$HOME/.gitconfig.delta"
if [ -f "$DELTA" ] && ! cmp -s "$D/config/git/gitconfig" "$DELTA"; then
  QDIR="$HOME/.claude/quarantine/dotfiles-gitconfig-delta"
  run mkdir -p "$QDIR"
  run cp "$DELTA" "$QDIR/gitconfig.delta.$(date +%Y%m%d-%H%M%S 2>/dev/null || echo bak)"
  note "backed up existing ~/.gitconfig.delta to quarantine before overwrite"
fi
run cp "$D/config/git/gitconfig" "$DELTA"
run git config --global include.path "$DELTA"
if [ -z "$(git config --global user.name)" ] && [ "${INTERACTIVE:-no}" = "yes" ]; then
  read -p "Git name: " GIT_NAME
  read -p "Git email: " GIT_EMAIL
  git config --global user.name "$GIT_NAME"
  git config --global user.email "$GIT_EMAIL"
fi
echo "[03] done"
