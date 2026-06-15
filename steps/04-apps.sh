#!/bin/bash
# Base GUI apps + OS tweaks. Only the `desktop` profile runs this step, so the
# profile choice (not host detection) decides whether GUI apps get installed —
# headless hosts default to `minimal`, which skips this step entirely.
# Terminal, fonts, password manager, Touch ID for sudo. Personal apps
# (browsers, editors, container runtimes) live in the private overlay.
set -uo pipefail
[ -z "${OS_TYPE:-}" ] && source "${DOTFILES_DIR:-.}/lib/detect.sh"
source "${DOTFILES_DIR:-.}/lib/ui.sh" 2>/dev/null || true
# Transaction helpers: record mutations so the orchestrator can roll back on
# failure. When the lib isn't sourced (step run standalone), the tx_* calls
# below are stubbed to no-ops so the step still works on its own.
[ -f "${DOTFILES_DIR:-.}/lib/transaction.sh" ] && source "${DOTFILES_DIR:-.}/lib/transaction.sh" 2>/dev/null || true
for fn in tx_brew_cask tx_apt_install tx_mkdir tx_symlink tx_run; do
  command -v "$fn" >/dev/null 2>&1 || eval "$fn() { :; }"
done
command -v run >/dev/null 2>&1 || run() { [ "${DRY_RUN:-0}" = 1 ] && { echo "[dry-run] $*"; return 0; }; "$@"; }

echo "[04] Apps..."

if [ "$OS_TYPE" = "Darwin" ]; then
  # Record the casks so a later failure uninstalls exactly what this run added.
  [ "${DRY_RUN:-0}" != 1 ] && tx_brew_cask ghostty font-jetbrains-mono
  run brew install --cask ghostty font-jetbrains-mono
  # 1Password is installed only if you opt into authentication (see install.sh);
  # duti (.md default-app helper) lives in the private overlay where it's used.

  # Link Ghostty's config now that the app is installed (03-dotfiles runs before
  # this step, so on a first desktop install it couldn't link it yet).
  if [ -f "$DOTFILES_DIR/config/ghostty/config" ]; then
    # tx_mkdir/tx_symlink create + record; in dry-run only announce via run().
    if [ "${DRY_RUN:-0}" = 1 ]; then
      run mkdir -p "$HOME/.config/ghostty"
      run ln -sf "$DOTFILES_DIR/config/ghostty/config" "$HOME/.config/ghostty/config"
    else
      tx_mkdir "$HOME/.config/ghostty"
      tx_symlink "$DOTFILES_DIR/config/ghostty/config" "$HOME/.config/ghostty/config"
    fi
    if ! infocmp xterm-ghostty >/dev/null 2>&1 && [ -f "$DOTFILES_DIR/config/ghostty/ghostty.terminfo" ]; then
      # Record the tic for visibility; undo is a no-op (no clean per-entry removal).
      [ "${DRY_RUN:-0}" != 1 ] && tx_run "tic:xterm-ghostty" true --
      run tic -x "$DOTFILES_DIR/config/ghostty/ghostty.terminfo" 2>/dev/null || true
    fi
  fi

  if [ "${DRY_RUN:-0}" = 1 ]; then
    echo "[dry-run] defaults write com.apple.Terminal Default Terminal Application -> ghostty"
  else
    # Undo: delete the default-terminal key we set (best-effort).
    tx_run "defaults:default-terminal" defaults delete com.apple.Terminal "Default Terminal Application" -- true
    defaults write com.apple.Terminal "Default Terminal Application" -string "com.mitchellh.ghostty" 2>/dev/null || true
  fi
  if ! grep -q "pam_tid" /etc/pam.d/sudo_local 2>/dev/null; then
    if [ "${DRY_RUN:-0}" = 1 ]; then
      echo "[dry-run] enable Touch ID for sudo (write pam_tid to /etc/pam.d/sudo_local)"
    else
      # The file had no pam_tid line (and usually doesn't exist at all on a clean
      # mac). Undo: remove the file we create via sudo. If sudo_local already
      # existed with other content this would over-remove, but the grep guard above
      # means we only reach here when it lacks pam_tid — on stock macOS that means
      # the file is absent, so creating+removing it is the correct inverse.
      tx_run "pam_tid:sudo_local" sudo rm -f /etc/pam.d/sudo_local -- true
      echo "auth sufficient pam_tid.so" | sudo tee /etc/pam.d/sudo_local >/dev/null
    fi
  fi

elif [ "$OS_TYPE" = "Linux" ]; then
  if [ "${WANT_GHOSTTY:-no}" = "yes" ] || { [ "${INTERACTIVE:-no}" = "yes" ] && read -p "Install Ghostty? [y/N] " -n 1 -r && echo && [[ $REPLY =~ ^[Yy]$ ]]; }; then
    GHOSTTY_DEB=$(curl -s https://api.github.com/repos/ghostty-org/ghostty/releases/latest \
      | grep "browser_download_url.*\.deb" | grep -i "$(dpkg --print-architecture)" | cut -d '"' -f 4 | head -1)
    [ -n "$GHOSTTY_DEB" ] && {
      run curl -L "$GHOSTTY_DEB" -o /tmp/ghostty.deb
      # Record the package so a later failure removes it. apt resolves the .deb's
      # package name to "ghostty"; tx_apt_install records `apt-get remove -y ghostty`.
      [ "${DRY_RUN:-0}" != 1 ] && { TX_SUDO="sudo" tx_apt_install ghostty; }
      run sudo apt install -y /tmp/ghostty.deb
      run rm -f /tmp/ghostty.deb
    }
  fi
fi
echo "[04] done"
