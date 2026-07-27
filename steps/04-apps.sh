#!/bin/bash
# Base GUI apps + OS tweaks. Only the `desktop` profile runs this step, so the
# profile choice (not host detection) decides whether GUI apps get installed —
# headless hosts default to `minimal`, which skips this step entirely.
# Terminal, fonts, password manager, Touch ID for sudo. Personal apps
# (browsers, editors, container runtimes) live in a personal overlay.
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
  # the default-terminal setting now live in a personal overlay (every macOS
  # already ships Terminal.app, so a terminal isn't a base/public concern).
  # Record the undo only when the cask is missing, so rollback never uninstalls
  # a cask that predates this run (same pattern as lib/packages/brew.sh).
  if ! brew list --cask font-jetbrains-mono >/dev/null 2>&1; then
    [ "${DRY_RUN:-0}" != 1 ] && tx_brew_cask font-jetbrains-mono
    run brew install --cask font-jetbrains-mono
  fi

  # Touch ID for sudo — generic, stays in the public base.
  if ! grep -q "pam_tid" /etc/pam.d/sudo_local 2>/dev/null; then
    if [ "${DRY_RUN:-0}" = 1 ]; then
      echo "[dry-run] enable Touch ID for sudo (write pam_tid to /etc/pam.d/sudo_local)"
    elif [ -f /etc/pam.d/sudo_local ]; then
      # The file pre-exists without pam_tid (e.g. the user already added
      # pam_reattach). Append only our line; the undo strips only the pam_tid
      # line (the grep guard guarantees no pam_tid line predates this run),
      # leaving the user's content intact. grep -v to a temp file instead of
      # BSD sed -i '': the empty suffix token would not survive the JSONL undo
      # round-trip.
      tx_run "pam_tid:sudo_local" sudo sh -c \
        'grep -v pam_tid /etc/pam.d/sudo_local > /etc/pam.d/sudo_local.tx-tmp && mv /etc/pam.d/sudo_local.tx-tmp /etc/pam.d/sudo_local' \
        -- true
      echo "auth sufficient pam_tid.so" | sudo tee -a /etc/pam.d/sudo_local >/dev/null
    else
      # Stock macOS: the file is absent, so we create it. Undo: move the file we
      # create to recoverable trash (sudo equivalent of tx_created_path) instead
      # of deleting it outright.
      if command -v setup_trash_destination >/dev/null 2>&1; then
        pam_trash="$(setup_trash_destination sudo_local)"
        tx_run "pam_tid:sudo_local" sudo mv /etc/pam.d/sudo_local "$pam_trash" -- true
      fi
      echo "auth sufficient pam_tid.so" | sudo tee /etc/pam.d/sudo_local >/dev/null
    fi
  fi
fi
echo "[04] done"
