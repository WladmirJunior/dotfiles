#!/bin/bash
# fzf setup, zsh plugins, set default shell to zsh.
set -uo pipefail
[ -z "${OS_TYPE:-}" ] && source "${DOTFILES_DIR:-.}/lib/detect.sh"
source "${DOTFILES_DIR:-.}/lib/ui.sh" 2>/dev/null || true
# Transaction helpers: record mutations so the orchestrator can roll back on
# failure. When the lib isn't sourced (step run standalone), the tx_* calls
# below are stubbed to no-ops so the step still works on its own.
[ -f "${DOTFILES_DIR:-.}/lib/transaction.sh" ] && source "${DOTFILES_DIR:-.}/lib/transaction.sh" 2>/dev/null || true
for fn in tx_git_clone tx_mkdir tx_run; do
  command -v "$fn" >/dev/null 2>&1 || eval "$fn() { :; }"
done
command -v run >/dev/null 2>&1 || run() { [ "${DRY_RUN:-0}" = 1 ] && { echo "[dry-run] $*"; return 0; }; "$@"; }

echo "[02] Shell (fzf, zsh plugins)..."

# fzf's installers create ~/.fzf.zsh (and may append a source line to ~/.zshrc).
# Record removal of ~/.fzf.zsh as the undo before any path that creates it, so a
# later-step failure cleans up the generated file. Only record when we'd actually
# create it (it wasn't already there) and not in dry-run.
if [ "$OS_TYPE" = "Darwin" ]; then
  [ "${DRY_RUN:-0}" != 1 ] && [ ! -e "$HOME/.fzf.zsh" ] && tx_run "fzf_install" rm -f "$HOME/.fzf.zsh" -- true
  run "$(brew --prefix)/opt/fzf/install" --all --no-bash --no-fish
else
  FZF_INSTALL=$(find /usr/share -name install.sh 2>/dev/null | grep fzf | head -n 1)
  if [ -n "$FZF_INSTALL" ]; then
    [ "${DRY_RUN:-0}" != 1 ] && [ ! -e "$HOME/.fzf.zsh" ] && tx_run "fzf_install" rm -f "$HOME/.fzf.zsh" -- true
    run bash "$FZF_INSTALL" --all --no-bash --no-fish
  elif fzf --zsh >/dev/null 2>&1; then
    if [ "${DRY_RUN:-0}" = 1 ]; then echo "[dry-run] fzf --zsh > ~/.fzf.zsh"; else
      [ ! -e "$HOME/.fzf.zsh" ] && tx_run "fzf_zsh" rm -f "$HOME/.fzf.zsh" -- true
      fzf --zsh > ~/.fzf.zsh
    fi
  else
    if [ "${DRY_RUN:-0}" = 1 ]; then echo "[dry-run] assemble ~/.fzf.zsh from /usr/share/doc/fzf examples"; else
    [ ! -e "$HOME/.fzf.zsh" ] && tx_run "fzf_zsh" rm -f "$HOME/.fzf.zsh" -- true
    {
      [ -f /usr/share/doc/fzf/examples/key-bindings.zsh ] && cat /usr/share/doc/fzf/examples/key-bindings.zsh
      [ -f /usr/share/doc/fzf/examples/completion.zsh ]   && cat /usr/share/doc/fzf/examples/completion.zsh
    } > ~/.fzf.zsh
    fi
  fi
fi

# tx_mkdir both creates the dir and records its removal (only if it had to create
# it). In dry-run it must not touch the disk, so fall back to the announce-only run().
if [ "${DRY_RUN:-0}" = 1 ]; then run mkdir -p ~/.config/zsh-plugins; else tx_mkdir ~/.config/zsh-plugins; fi
clone_plugin() {
  # Record the clone's undo (rm -rf dest) before cloning so a later failure removes
  # exactly what this run fetched. Skip recording in dry-run.
  [ -d "$2" ] || {
    echo "  cloning $(basename "$2")..."
    [ "${DRY_RUN:-0}" != 1 ] && tx_git_clone "$1" "$2"
    run git clone --depth 1 "$1" "$2"
  }
}
clone_plugin https://github.com/zdharma-continuum/fast-syntax-highlighting.git ~/.config/zsh-plugins/fast-syntax-highlighting
clone_plugin https://github.com/Aloxaf/fzf-tab.git ~/.config/zsh-plugins/fzf-tab
clone_plugin https://github.com/MichaelAquilina/zsh-you-should-use.git ~/.config/zsh-plugins/zsh-you-should-use

if [ "$OS_TYPE" = "Linux" ]; then
  CURRENT_SHELL="$(getent passwd "$(whoami)" | cut -d: -f7)"
  ZSH_PATH="$(command -v zsh)"
  if [ -n "$ZSH_PATH" ] && [ "$CURRENT_SHELL" != "$ZSH_PATH" ]; then
    echo "Setting default shell to zsh..."
    if command -v chsh >/dev/null 2>&1; then
      # Undo: set the login shell back to whatever it was before this run.
      [ "${DRY_RUN:-0}" != 1 ] && tx_run "chsh:$(whoami)" sudo chsh -s "$CURRENT_SHELL" "$(whoami)" -- true
      run sudo chsh -s "$ZSH_PATH" "$(whoami)" || true
    elif [ "${DRY_RUN:-0}" = 1 ]; then
      echo "[dry-run] append 'export SHELL=$ZSH_PATH' and 'exec $ZSH_PATH' to ~/.bashrc"
    else
      # Undo: strip the two exact lines we appended (best-effort; sed -i in place).
      tx_run "bashrc_exec_zsh" sed -i "\\#^export SHELL=$ZSH_PATH\$#d;\\#^exec $ZSH_PATH\$#d" "$HOME/.bashrc" -- true
      echo "export SHELL=$ZSH_PATH" >> ~/.bashrc
      echo "exec $ZSH_PATH" >> ~/.bashrc
    fi
  fi
fi
echo "[02] done"
