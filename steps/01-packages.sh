#!/bin/bash
# Install essential CLI tools (brew on Mac, apt on Linux).
# Requires: DOTFILES_DIR in env.
set -uo pipefail
[ -z "${OS_TYPE:-}" ] && source "${DOTFILES_DIR:-.}/lib/detect.sh"
source "${DOTFILES_DIR:-.}/lib/ui.sh" 2>/dev/null || true
# Transaction helpers: record mutations so the orchestrator can roll back on
# failure. When the lib isn't sourced (step run standalone), the tx_* calls
# below are stubbed to no-ops so the step still works on its own.
[ -f "${DOTFILES_DIR:-.}/lib/transaction.sh" ] && source "${DOTFILES_DIR:-.}/lib/transaction.sh" 2>/dev/null || true
for fn in tx_brew_install tx_brew_cask tx_apt_install tx_brew_self; do
  command -v "$fn" >/dev/null 2>&1 || eval "$fn() { :; }"
done
command -v run >/dev/null 2>&1 || run() { [ "${DRY_RUN:-0}" = 1 ] && { echo "[dry-run] $*"; return 0; }; "$@"; }

echo "[01] CLI packages..."

if [ "$OS_TYPE" = "Darwin" ]; then
  if ! command -v brew >/dev/null 2>&1; then
    echo "Installing Homebrew..."
    # The Homebrew installer reads stdin twice: once for "Press RETURN to
    # continue" and again when sudo prompts for the password. Under `curl|bash`
    # stdin is the PIPE carrying our own script, so those reads drain the pipe
    # and the installer aborts mid-flight (and sudo can never prompt).
    #
    # The right fix is to give the installer the TERMINAL as stdin (`< /dev/tty`)
    # so it reads keystrokes from the keyboard — the RETURN confirm works AND
    # sudo can prompt for the admin password, without touching our pipe. We only
    # fall back to NONINTERACTIVE (no prompts, defaults) when there is genuinely
    # no terminal (real automation: CI, `tart exec`, etc.), where sudo must
    # already be passwordless or pre-authenticated.
    if [ "${DRY_RUN:-0}" = 1 ]; then
      echo "[dry-run] install Homebrew (interactive via /dev/tty, or NONINTERACTIVE if no tty)"
    else
      # Record the prefix first so a failed install rolls back (rm -rf /opt/homebrew).
      tx_brew_self
      brew_installer="$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
      if [ -r /dev/tty ]; then
        /bin/bash -c "$brew_installer" < /dev/tty
      else
        env -u INTERACTIVE NONINTERACTIVE=1 /bin/bash -c "$brew_installer"
      fi
      eval "$(/opt/homebrew/bin/brew shellenv)"
    fi
  fi

  # If brew install left the directory but no binary (the symptom of an
  # interrupted install), fail. The orchestrator's rollback will remove the
  # partial /opt/homebrew (recorded by tx_brew_self above) so the next run
  # starts clean — no manual `rm -rf` needed.
  if [ "${DRY_RUN:-0}" != 1 ] && [ ! -x /opt/homebrew/bin/brew ]; then
    echo "[01] ERROR: /opt/homebrew/bin/brew missing after install attempt." >&2
    exit 1
  fi

  # Record the formulae before installing so a later-step failure can uninstall
  # exactly what this run added.
  # coreutils: GNU userland. Provides `timeout` (BSD macOS lacks it), which the
  # Claude Code harness pushes scripts toward after it blocked foreground `sleep`.
  # 03-dotfiles symlinks gtimeout -> ~/.local/bin/timeout so the bare name works.
  # freeze lives in the charmbracelet tap (the core "freeze" name is an unrelated cask).
  BREW_PKGS="git gh neovim fzf zoxide eza bat ripgrep fd git-delta tlrc node usbutils coreutils yazi hexyl fastfetch sevenzip resvg exiftool glow charmbracelet/tap/freeze"
  # tlrc and tldr both ship a `tldr` binary; a legacy `tldr` install (older setups)
  # makes `brew install tlrc` abort with a conflict. Drop it first so tlrc wins.
  if [ "${DRY_RUN:-0}" != 1 ] && brew list --formula 2>/dev/null | grep -qx tldr; then
    run brew unlink tldr
    run brew uninstall tldr
  fi
  [ "${DRY_RUN:-0}" != 1 ] && tx_brew_install $BREW_PKGS
  # gum is NOT installed here: the UI uses our fork binary (table --width/
  # --border-row), fetched by ui_bootstrap_gum in install.sh. See lib/ui.sh.
  run brew install $BREW_PKGS
elif [ "$OS_TYPE" = "Linux" ]; then
  # On a clean apt-based image we may run as root (no sudo). Pick the right prefix.
  SUDO=""
  [ "$(id -u)" -ne 0 ] && command -v sudo >/dev/null 2>&1 && SUDO=sudo

  TX_SUDO="$SUDO"   # used by tx_apt_install's undo (apt-get remove)
  run $SUDO apt-get update -qq
  # Install in two passes so a missing package in one distro (e.g. trixie removed
  # `software-properties-common` from the default repo) doesn't drop the rest.
  # First pass: core tools that must be there. Second pass: nice-to-haves, best-effort.
  APT_CORE="zsh neovim fzf zoxide bat ripgrep fd-find git-delta nodejs npm curl git gh wget hexyl"
  [ "${DRY_RUN:-0}" != 1 ] && tx_apt_install $APT_CORE
  run $SUDO env DEBIAN_FRONTEND=noninteractive apt-get install -y $APT_CORE
  # Yazi is not packaged by every supported Debian/Ubuntu release. Install the
  # official architecture-specific .deb and verify GitHub's published digest.
  if ! command -v yazi >/dev/null 2>&1; then
    [ "${DRY_RUN:-0}" != 1 ] && tx_apt_install yazi
    run bash "${DOTFILES_DIR:?}/scripts/install-yazi.sh"
  fi
  # Fastfetch package availability also varies by distribution. Use its
  # verified official .deb when it is not already present.
  if ! command -v fastfetch >/dev/null 2>&1; then
    [ "${DRY_RUN:-0}" != 1 ] && tx_apt_install fastfetch
    run bash "${DOTFILES_DIR:?}/scripts/install-fastfetch.sh"
  fi
  # Best-effort extras; never abort if one is missing in this distro.
  for pkg in eza tealdeer 7zip resvg libimage-exiftool-perl software-properties-common glow; do
    if run $SUDO env DEBIAN_FRONTEND=noninteractive apt-get install -y "$pkg" 2>/dev/null; then
      [ "${DRY_RUN:-0}" != 1 ] && tx_apt_install "$pkg"
    else
      echo "  skip: $pkg not available in this distro"
    fi
  done
  run mkdir -p ~/.local/bin
  [ -n "$(command -v fdfind 2>/dev/null)" ] && run ln -sf "$(command -v fdfind)" ~/.local/bin/fd
  [ -n "$(command -v batcat 2>/dev/null)" ] && run ln -sf "$(command -v batcat)" ~/.local/bin/bat
else
  echo "Unsupported OS: $OS_TYPE"; exit 1
fi
echo "[01] done"
