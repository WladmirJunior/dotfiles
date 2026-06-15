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
  # Programming font (used by editors/terminals). Ghostty + its config/theme and
  # the default-terminal setting now live in the private overlay (every macOS
  # already ships Terminal.app, so a terminal isn't a base/public concern).
  [ "${DRY_RUN:-0}" != 1 ] && tx_brew_cask font-jetbrains-mono
  run brew install --cask font-jetbrains-mono

  # Touch ID for sudo — generic, stays in the public base.
  if ! grep -q "pam_tid" /etc/pam.d/sudo_local 2>/dev/null; then
    if [ "${DRY_RUN:-0}" = 1 ]; then
      echo "[dry-run] enable Touch ID for sudo (write pam_tid to /etc/pam.d/sudo_local)"
    else
      # The file had no pam_tid line (and usually doesn't exist at all on a clean
      # mac). Undo: remove the file we create via sudo. The grep guard means we
      # only reach here when it lacks pam_tid — on stock macOS the file is absent,
      # so creating+removing it is the correct inverse.
      tx_run "pam_tid:sudo_local" sudo rm -f /etc/pam.d/sudo_local -- true
      echo "auth sufficient pam_tid.so" | sudo tee /etc/pam.d/sudo_local >/dev/null
    fi
  fi
fi
echo "[04] done"
