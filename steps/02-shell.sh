#!/bin/bash
# fzf setup, zsh plugins, set default shell to zsh.
set -uo pipefail
[ -z "${OS_TYPE:-}" ] && source "${DOTFILES_DIR:-.}/lib/detect.sh"

echo "[02] Shell (fzf, zsh plugins)..."

if [ "$OS_TYPE" = "Darwin" ]; then
  "$(brew --prefix)/opt/fzf/install" --all --no-bash --no-fish
else
  FZF_INSTALL=$(find /usr/share -name install.sh 2>/dev/null | grep fzf | head -n 1)
  if [ -n "$FZF_INSTALL" ]; then
    bash "$FZF_INSTALL" --all --no-bash --no-fish
  elif fzf --zsh >/dev/null 2>&1; then
    fzf --zsh > ~/.fzf.zsh
  else
    {
      [ -f /usr/share/doc/fzf/examples/key-bindings.zsh ] && cat /usr/share/doc/fzf/examples/key-bindings.zsh
      [ -f /usr/share/doc/fzf/examples/completion.zsh ]   && cat /usr/share/doc/fzf/examples/completion.zsh
    } > ~/.fzf.zsh
  fi
fi

mkdir -p ~/.config/zsh-plugins
clone_plugin() {
  [ -d "$2" ] || { echo "  cloning $(basename "$2")..."; git clone --depth 1 "$1" "$2"; }
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
      sudo chsh -s "$ZSH_PATH" "$(whoami)" || true
    else
      echo "export SHELL=$ZSH_PATH" >> ~/.bashrc
      echo "exec $ZSH_PATH" >> ~/.bashrc
    fi
  fi
fi
echo "[02] done"
