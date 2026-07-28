#!/bin/bash
# fzf setup, zsh plugins, set default shell to zsh.
# set -e: a failed mutation must fail the step (the orchestrator aborts and
# rolls back); without it the trailing "done" echo masked mid-step failures.
set -euo pipefail
[ -z "${OS_TYPE:-}" ] && source "${DOTFILES_DIR:-.}/lib/detect.sh"
source "${DOTFILES_DIR:-.}/lib/ui.sh" 2>/dev/null || true
# Transaction helpers: record mutations so the orchestrator can roll back on
# failure. When the lib isn't sourced (step run standalone), the tx_* calls
# below are stubbed to no-ops so the step still works on its own.
[ -f "${DOTFILES_DIR:-.}/lib/transaction.sh" ] && source "${DOTFILES_DIR:-.}/lib/transaction.sh" 2>/dev/null || true
for fn in tx_git_clone tx_created_path tx_mkdir tx_run; do
  command -v "$fn" >/dev/null 2>&1 || eval "$fn() { :; }"
done
command -v run >/dev/null 2>&1 || run() { [ "${DRY_RUN:-0}" = 1 ] && { echo "[dry-run] $*"; return 0; }; "$@"; }

echo "[02] Shell (fzf, zsh plugins)..."

# fzf's installers create ~/.fzf.zsh (and may append a source line to ~/.zshrc).
# Record ~/.fzf.zsh as a created path before any path that creates it, so a
# later-step failure moves the generated file to recoverable trash. tx_created_path
# only records when the file doesn't already exist; skip recording in dry-run.
if [ "$OS_TYPE" = "Darwin" ]; then
  [ "${DRY_RUN:-0}" != 1 ] && tx_created_path "$HOME/.fzf.zsh"
  run "$(brew --prefix)/opt/fzf/install" --all --no-bash --no-fish
else
  # `|| true`: no fzf installer found is a valid outcome (the elif/else below
  # handle it); under pipefail the empty grep would otherwise abort the step.
  FZF_INSTALL=$(find /usr/share -name install.sh 2>/dev/null | grep fzf | head -n 1 || true)
  if [ -n "$FZF_INSTALL" ]; then
    [ "${DRY_RUN:-0}" != 1 ] && tx_created_path "$HOME/.fzf.zsh"
    run bash "$FZF_INSTALL" --all --no-bash --no-fish
  elif fzf --zsh >/dev/null 2>&1; then
    if [ "${DRY_RUN:-0}" = 1 ]; then echo "[dry-run] fzf --zsh > ~/.fzf.zsh"; else
      tx_created_path "$HOME/.fzf.zsh"
      fzf --zsh > ~/.fzf.zsh
    fi
  else
    if [ "${DRY_RUN:-0}" = 1 ]; then echo "[dry-run] assemble ~/.fzf.zsh from /usr/share/doc/fzf examples"; else
    tx_created_path "$HOME/.fzf.zsh"
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
  # Record the clone's undo (move dest to recoverable trash) before cloning so
  # a later failure parks exactly what this run fetched. Skip recording in dry-run.
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
  ZSH_PATH="$(command -v zsh || true)"   # empty (not fatal) when zsh is absent
  if [ -n "$ZSH_PATH" ] && [ "$CURRENT_SHELL" != "$ZSH_PATH" ]; then
    echo "Setting default shell to zsh..."
    if command -v chsh >/dev/null 2>&1; then
      CHSH_PREFIX=""
      if [ "$(id -u)" -ne 0 ]; then
        command -v sudo >/dev/null 2>&1 && CHSH_PREFIX=sudo
      fi
      # Undo: set the login shell back to whatever it was before this run.
      [ "${DRY_RUN:-0}" != 1 ] && tx_run "chsh:$(whoami)" $CHSH_PREFIX chsh -s "$CURRENT_SHELL" "$(whoami)" -- true
      run $CHSH_PREFIX chsh -s "$ZSH_PATH" "$(whoami)" || true
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
