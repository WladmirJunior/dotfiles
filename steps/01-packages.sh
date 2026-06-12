#!/bin/bash
# Install essential CLI tools (brew on Mac, apt on Linux).
# Requires: DOTFILES_DIR in env.
set -uo pipefail
[ -z "${OS_TYPE:-}" ] && source "${DOTFILES_DIR:-.}/lib/detect.sh"
source "${DOTFILES_DIR:-.}/lib/ui.sh" 2>/dev/null || true
command -v run >/dev/null 2>&1 || run() { [ "${DRY_RUN:-0}" = 1 ] && { echo "[dry-run] $*"; return 0; }; "$@"; }

echo "[01] CLI packages..."

if [ "$OS_TYPE" = "Darwin" ]; then
  if ! command -v brew >/dev/null 2>&1; then
    echo "Installing Homebrew..."
    # Force NONINTERACTIVE: the brew installer otherwise tries to call
    # `read` on stdin to confirm, but under `curl|bash` stdin is the pipe
    # carrying our own script — the read drains the pipe and the installer
    # aborts mid-flight, leaving /opt/homebrew/ created but no `brew`
    # binary. NONINTERACTIVE=1 skips the prompt and uses defaults.
    # Also unset INTERACTIVE in case the user's profile exported it
    # (the brew installer treats $INTERACTIVE=1 as a hard override that
    # overrides our detected non-tty stdin).
    if [ "${DRY_RUN:-0}" = 1 ]; then
      echo "[dry-run] NONINTERACTIVE=1 unset INTERACTIVE  /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
    else
      env -u INTERACTIVE NONINTERACTIVE=1 /bin/bash -c \
        "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
      eval "$(/opt/homebrew/bin/brew shellenv)"
    fi
  fi

  # If brew install left the directory but no binary (the symptom of an
  # interrupted install), bail loudly so the user knows to re-run instead of
  # silently failing every subsequent step that wants `brew`.
  if [ "${DRY_RUN:-0}" != 1 ] && [ ! -x /opt/homebrew/bin/brew ]; then
    echo "[01] ERROR: /opt/homebrew/bin/brew missing after install attempt." >&2
    echo "[01] Re-run from a fresh terminal:  rm -rf /opt/homebrew && curl -fsSL https://raw.githubusercontent.com/WladmirJunior/dotfiles/main/install.sh | bash -s -- desktop" >&2
    exit 1
  fi

  # gum is NOT installed here: the UI uses our fork binary (table --width/
  # --border-row), fetched by ui_bootstrap_gum in install.sh. See lib/ui.sh.
  run brew install git gh neovim fzf zoxide eza bat ripgrep fd git-delta tlrc node usbutils
elif [ "$OS_TYPE" = "Linux" ]; then
  # On a clean apt-based image we may run as root (no sudo). Pick the right prefix.
  SUDO=""
  [ "$(id -u)" -ne 0 ] && command -v sudo >/dev/null 2>&1 && SUDO=sudo

  run $SUDO apt-get update -qq
  # Install in two passes so a missing package in one distro (e.g. trixie removed
  # `software-properties-common` from the default repo) doesn't drop the rest.
  # First pass: core tools that must be there. Second pass: nice-to-haves, best-effort.
  run $SUDO env DEBIAN_FRONTEND=noninteractive apt-get install -y \
    zsh neovim fzf zoxide bat ripgrep fd-find git-delta nodejs npm curl git gh wget
  # Best-effort extras; never abort if one is missing in this distro.
  for pkg in eza tealdeer software-properties-common; do
    run $SUDO env DEBIAN_FRONTEND=noninteractive apt-get install -y "$pkg" 2>/dev/null \
      || echo "  skip: $pkg not available in this distro"
  done
  run mkdir -p ~/.local/bin
  [ -n "$(command -v fdfind 2>/dev/null)" ] && run ln -sf "$(command -v fdfind)" ~/.local/bin/fd
  [ -n "$(command -v batcat 2>/dev/null)" ] && run ln -sf "$(command -v batcat)" ~/.local/bin/bat
else
  echo "Unsupported OS: $OS_TYPE"; exit 1
fi
echo "[01] done"
