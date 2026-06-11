#!/bin/bash
# fzf setup, zsh plugins, set default shell to zsh.
set -uo pipefail
[ -z "${OS_TYPE:-}" ] && source "${DOTFILES_DIR:-.}/lib/detect.sh"
source "${DOTFILES_DIR:-.}/lib/ui.sh" 2>/dev/null || true
command -v run >/dev/null 2>&1 || run() { [ "${DRY_RUN:-0}" = 1 ] && { echo "[dry-run] $*"; return 0; }; "$@"; }

echo "[02] Shell (fzf, zsh plugins)..."

if [ "$OS_TYPE" = "Darwin" ]; then
  run "$(brew --prefix)/opt/fzf/install" --all --no-bash --no-fish
else
  FZF_INSTALL=$(find /usr/share -name install.sh 2>/dev/null | grep fzf | head -n 1)
  if [ -n "$FZF_INSTALL" ]; then
    run bash "$FZF_INSTALL" --all --no-bash --no-fish
  elif fzf --zsh >/dev/null 2>&1; then
    if [ "${DRY_RUN:-0}" = 1 ]; then echo "[dry-run] fzf --zsh > ~/.fzf.zsh"; else fzf --zsh > ~/.fzf.zsh; fi
  else
    if [ "${DRY_RUN:-0}" = 1 ]; then echo "[dry-run] assemble ~/.fzf.zsh from /usr/share/doc/fzf examples"; else
    {
      [ -f /usr/share/doc/fzf/examples/key-bindings.zsh ] && cat /usr/share/doc/fzf/examples/key-bindings.zsh
      [ -f /usr/share/doc/fzf/examples/completion.zsh ]   && cat /usr/share/doc/fzf/examples/completion.zsh
    } > ~/.fzf.zsh
    fi
  fi
fi

run mkdir -p ~/.config/zsh-plugins
clone_plugin() {
  [ -d "$2" ] || { echo "  cloning $(basename "$2")..."; run git clone --depth 1 "$1" "$2"; }
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
      run sudo chsh -s "$ZSH_PATH" "$(whoami)" || true
    elif [ "${DRY_RUN:-0}" = 1 ]; then
      echo "[dry-run] append 'export SHELL=$ZSH_PATH' and 'exec $ZSH_PATH' to ~/.bashrc"
    else
      echo "export SHELL=$ZSH_PATH" >> ~/.bashrc
      echo "exec $ZSH_PATH" >> ~/.bashrc
    fi
  fi
fi
echo "[02] done"
