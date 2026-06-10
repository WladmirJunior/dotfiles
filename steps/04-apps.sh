#!/bin/bash
# Base GUI apps + OS tweaks. Only the `desktop` profile runs this step, so the
# profile choice (not host detection) decides whether GUI apps get installed —
# headless hosts default to `minimal`, which skips this step entirely.
# Terminal, fonts, password manager, Touch ID for sudo. Personal apps
# (browsers, editors, container runtimes) live in the private overlay.
set -uo pipefail
[ -z "${OS_TYPE:-}" ] && source "${DOTFILES_DIR:-.}/lib/detect.sh"

echo "[04] Apps..."

if [ "$OS_TYPE" = "Darwin" ]; then
  brew install --cask ghostty font-jetbrains-mono
  brew install duti
  # 1Password 8 (current) ships via the brew cask from the official site, not the
  # App Store — the App Store only carries the legacy v7.
  if [ ! -d "/Applications/1Password.app" ]; then
    echo "1Password..."
    brew install --cask 1password || echo "  1Password failed"
  fi

  # Link Ghostty's config now that the app is installed (03-dotfiles runs before
  # this step, so on a first desktop install it couldn't link it yet).
  if [ -f "$DOTFILES_DIR/config/ghostty/config" ]; then
    mkdir -p "$HOME/.config/ghostty"
    ln -sf "$DOTFILES_DIR/config/ghostty/config" "$HOME/.config/ghostty/config"
    if ! infocmp xterm-ghostty >/dev/null 2>&1 && [ -f "$DOTFILES_DIR/config/ghostty/ghostty.terminfo" ]; then
      tic -x "$DOTFILES_DIR/config/ghostty/ghostty.terminfo" 2>/dev/null || true
    fi
  fi

  defaults write com.apple.Terminal "Default Terminal Application" -string "com.mitchellh.ghostty" 2>/dev/null || true
  if ! grep -q "pam_tid" /etc/pam.d/sudo_local 2>/dev/null; then
    echo "auth sufficient pam_tid.so" | sudo tee /etc/pam.d/sudo_local >/dev/null
  fi

elif [ "$OS_TYPE" = "Linux" ]; then
  if [ "${WANT_GHOSTTY:-no}" = "yes" ] || { [ "${INTERACTIVE:-no}" = "yes" ] && read -p "Install Ghostty? [y/N] " -n 1 -r && echo && [[ $REPLY =~ ^[Yy]$ ]]; }; then
    GHOSTTY_DEB=$(curl -s https://api.github.com/repos/ghostty-org/ghostty/releases/latest \
      | grep "browser_download_url.*\.deb" | grep -i "$(dpkg --print-architecture)" | cut -d '"' -f 4 | head -1)
    [ -n "$GHOSTTY_DEB" ] && { curl -L "$GHOSTTY_DEB" -o /tmp/ghostty.deb; sudo apt install -y /tmp/ghostty.deb; rm -f /tmp/ghostty.deb; }
  fi
fi
echo "[04] done"
