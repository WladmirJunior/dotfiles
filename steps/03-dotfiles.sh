#!/bin/bash
# Link config files into the system using symlinks.
set -uo pipefail
[ -z "${OS_TYPE:-}" ] && source "${DOTFILES_DIR:-.}/lib/detect.sh"
D="${DOTFILES_DIR:?DOTFILES_DIR not set}"
# Source ui.sh for run()/note (dry-run + quarantine helpers). Falls back to a
# plain run() if sourced standalone, so the step still works on its own.
source "${DOTFILES_DIR:-.}/lib/ui.sh" 2>/dev/null || true
# Transaction helpers: record mutations so the orchestrator can roll back on
# failure. When the lib isn't sourced (step run standalone), the tx_* calls
# below are stubbed to no-ops so the step still works on its own.
[ -f "${DOTFILES_DIR:-.}/lib/transaction.sh" ] && source "${DOTFILES_DIR:-.}/lib/transaction.sh" 2>/dev/null || true
for fn in tx_mkdir tx_symlink tx_run; do
  command -v "$fn" >/dev/null 2>&1 || eval "$fn() { :; }"
done
command -v run >/dev/null 2>&1 || run() { [ "${DRY_RUN:-0}" = 1 ] && { echo "[dry-run] $*"; return 0; }; "$@"; }
command -v note >/dev/null 2>&1 || note() { echo "  $*"; }

# lnk: create parent dir + symlink, recording both for rollback. In dry-run we
# only announce (tx_mkdir/tx_symlink touch the disk), via the plain run().
lnk() {
  if [ "${DRY_RUN:-0}" = 1 ]; then
    run mkdir -p "$(dirname "$2")"; run ln -sf "$1" "$2"
  else
    tx_mkdir "$(dirname "$2")"
    tx_symlink "$1" "$2"
  fi
}

echo "[03] Applying dotfiles..."

# ~/.zshrc is a thin real file (not a symlink) so machine-local overlays can
# append to ~/.zshrc.local without writing into the versioned repo file.
if [ ! -f "$HOME/.zshrc" ] || [ -L "$HOME/.zshrc" ] || ! grep -q '.dotfiles/config/zsh/zshrc' "$HOME/.zshrc"; then
  if [ "${DRY_RUN:-0}" = 1 ]; then
    echo "[dry-run] write thin ~/.zshrc (sources ~/.dotfiles/config/zsh/zshrc)"
  else
    # Record an undo BEFORE overwriting: back up any existing ~/.zshrc and restore
    # it on rollback; if there was none, the undo just removes the file we write.
    if [ -e "$HOME/.zshrc" ]; then
      _zbak="$HOME/.zshrc.txbak.$$"
      cp -p "$HOME/.zshrc" "$_zbak" 2>/dev/null || cp "$HOME/.zshrc" "$_zbak"
      tx_run "write:.zshrc" mv "$_zbak" "$HOME/.zshrc" -- true
    else
      tx_run "write:.zshrc" rm -f "$HOME/.zshrc" -- true
    fi
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
    # tic compiles the entry into the terminfo db. Record it so the action is in
    # the log; the undo is best-effort (no clean per-entry removal), so it's a
    # no-op (true) rather than risking nuking unrelated terminfo data on rollback.
    [ "${DRY_RUN:-0}" != 1 ] && tx_run "tic:xterm-ghostty" true --
    run sudo tic -x "$D/config/ghostty/ghostty.terminfo" 2>/dev/null || run tic -x "$D/config/ghostty/ghostty.terminfo" 2>/dev/null || true
  fi
fi

# git config (delta) — cp because git include.path resolves symlinks fine,
# but we keep it as a copy to avoid git reading a path inside the repo.
# Back up any existing target to the quarantine bin (never blind-overwrite local
# edits) before copying, but only when the content actually differs.
DELTA="$HOME/.gitconfig.delta"
# Decide the undo for the cp below BEFORE we touch $DELTA: if it pre-exists, snapshot
# it and restore on rollback; otherwise the undo just removes the file we create.
DELTA_PREEXISTED=0; _delta_bak=""
if [ -e "$DELTA" ]; then
  DELTA_PREEXISTED=1; _delta_bak="$DELTA.txbak.$$"
fi
if [ -f "$DELTA" ] && ! cmp -s "$D/config/git/gitconfig" "$DELTA"; then
  QDIR="$HOME/.claude/quarantine/dotfiles-gitconfig-delta"
  run mkdir -p "$QDIR"
  run cp "$DELTA" "$QDIR/gitconfig.delta.$(date +%Y%m%d-%H%M%S 2>/dev/null || echo bak)"
  note "backed up existing ~/.gitconfig.delta to quarantine before overwrite"
fi
if [ "${DRY_RUN:-0}" = 1 ]; then
  run cp "$D/config/git/gitconfig" "$DELTA"
else
  if [ "$DELTA_PREEXISTED" = 1 ]; then
    cp -p "$DELTA" "$_delta_bak" 2>/dev/null || cp "$DELTA" "$_delta_bak"
    tx_run "cp:.gitconfig.delta" mv "$_delta_bak" "$DELTA" -- cp "$D/config/git/gitconfig" "$DELTA"
  else
    tx_run "cp:.gitconfig.delta" rm -f "$DELTA" -- cp "$D/config/git/gitconfig" "$DELTA"
  fi
fi
if [ "${DRY_RUN:-0}" = 1 ]; then
  run git config --global include.path "$DELTA"
else
  # Undo: drop the include.path entry we add (best-effort; --unset on the exact value).
  tx_run "git_include_path" git config --global --unset include.path "$DELTA" -- git config --global include.path "$DELTA"
fi
if [ -z "$(git config --global user.name)" ] && [ "${INTERACTIVE:-no}" = "yes" ]; then
  read -p "Git name: " GIT_NAME
  read -p "Git email: " GIT_EMAIL
  # Undo: unset the identity we just wrote (only set when previously empty).
  [ "${DRY_RUN:-0}" != 1 ] && tx_run "git_user_name" git config --global --unset user.name -- true
  [ "${DRY_RUN:-0}" != 1 ] && tx_run "git_user_email" git config --global --unset user.email -- true
  git config --global user.name "$GIT_NAME"
  git config --global user.email "$GIT_EMAIL"
fi
echo "[03] done"
