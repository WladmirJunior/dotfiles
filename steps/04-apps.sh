#!/bin/bash
# GUI apps + AI tools + OS tweaks. Desktop only (skips headless/VM).
# Supports WANT_CHROME, WANT_FIREFOX, WANT_ZED, WANT_AI env flags (yes/no).
set -uo pipefail
[ -z "${OS_TYPE:-}" ] && source "${DOTFILES_DIR:-.}/lib/detect.sh"

if [ "${HEADLESS:-no}" = "yes" ]; then
  echo "[04] headless: skipping GUI apps"; exit 0
fi
if [ "$OS_TYPE" = "Darwin" ] && [ "$IS_VM" = "yes" ]; then
  echo "[04] VM: skipping GUI apps"; exit 0
fi

echo "[04] Apps..."

ask() {
  local q="$1" var="$2" def="${3:-no}"
  local preset="${!var:-}"
  if [ -n "$preset" ]; then echo "$preset"; return; fi
  if [ "${INTERACTIVE:-no}" != "yes" ]; then echo "$def"; return; fi
  read -p "$q [y/N] " -n 1 -r; echo >&2
  [[ $REPLY =~ ^[Yy]$ ]] && echo "yes" || echo "no"
}

if [ "$OS_TYPE" = "Darwin" ]; then
  brew install --cask ghostty font-jetbrains-mono font-monaspace typora brave-browser
  brew install duti
  if [ ! -d "/Applications/1Password.app" ]; then
    echo "1Password: install from the App Store (opening)..."
    open "macappstore://apps.apple.com/app/1password-7-password-manager/id1333542190" 2>/dev/null || true
  fi
  [ "$(ask 'Install Chrome?' WANT_CHROME no)" = "yes" ] && brew install --cask google-chrome
  [ "$(ask 'Install Firefox?' WANT_FIREFOX no)" = "yes" ] && brew install --cask firefox
  [ "$(ask 'Install Zed?' WANT_ZED no)" = "yes" ] && brew install --cask zed
  [ "$(ask 'Install OrbStack?' WANT_ORBSTACK no)" = "yes" ] && brew install --cask orbstack
  [ "$(ask 'Install Colima?' WANT_COLIMA no)" = "yes" ] && brew install colima docker docker-buildx

elif [ "$OS_TYPE" = "Linux" ]; then
  if [ "$(ask 'Install Typora?' WANT_TYPORA no)" = "yes" ] && ! command -v typora >/dev/null 2>&1; then
    wget -qO - https://typora.io/linux/public-key.asc | sudo tee /etc/apt/trusted.gpg.d/typora.asc >/dev/null
    sudo add-apt-repository -y 'deb https://typora.io/linux ./'
    sudo apt-get update -q && sudo apt-get install -y typora
  fi
  if [ "$(ask 'Install Ghostty?' WANT_GHOSTTY no)" = "yes" ]; then
    GHOSTTY_DEB=$(curl -s https://api.github.com/repos/ghostty-org/ghostty/releases/latest \
      | grep "browser_download_url.*\.deb" | grep -i "$(dpkg --print-architecture)" | cut -d '"' -f 4 | head -1)
    [ -n "$GHOSTTY_DEB" ] && { curl -L "$GHOSTTY_DEB" -o /tmp/ghostty.deb; sudo apt install -y /tmp/ghostty.deb; rm -f /tmp/ghostty.deb; }
  fi
fi

if [ "$(ask 'Install AI tools (Gemini, Claude, Copilot, Codex, Cursor)?' WANT_AI no)" = "yes" ]; then
  [ "$OS_TYPE" = "Darwin" ] && brew install --cask codex
  sudo npm install -g @google/gemini-cli @anthropic-ai/claude-code
  gh extension install github/gh-copilot 2>/dev/null || true
  curl https://cursor.com/install -fsS | bash || true
fi

if [ "$OS_TYPE" = "Darwin" ]; then
  defaults write com.apple.Terminal "Default Terminal Application" -string "com.mitchellh.ghostty" 2>/dev/null || true
  if ! grep -q "pam_tid" /etc/pam.d/sudo_local 2>/dev/null; then
    echo "auth sufficient pam_tid.so" | sudo tee /etc/pam.d/sudo_local >/dev/null
  fi
  command -v duti >/dev/null 2>&1 && [ -d "/Applications/Typora.app" ] && duti -s abnerworks.Typora .md all 2>/dev/null || true
  if [ -d "/Applications/Brave Browser.app" ] && command -v duti >/dev/null 2>&1; then
    duti -s com.brave.Browser http 2>/dev/null; duti -s com.brave.Browser https 2>/dev/null
  fi
  [ -d "/Applications/Zed.app" ] && [ ! -f "/usr/local/bin/zed" ] && ln -sf /Applications/Zed.app/Contents/MacOS/cli /usr/local/bin/zed 2>/dev/null || true
elif [ "$OS_TYPE" = "Linux" ]; then
  command -v typora >/dev/null 2>&1 && xdg-mime default typora.desktop text/markdown 2>/dev/null || true
fi
echo "[04] done"
