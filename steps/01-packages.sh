#!/bin/bash
# Install essential CLI tools (Homebrew on macOS; APT, Pacman or DNF on Linux).
# Requires: DOTFILES_DIR in env.
set -uo pipefail
[ -z "${OS_TYPE:-}" ] && source "${DOTFILES_DIR:-.}/lib/detect.sh"
source "${DOTFILES_DIR:-.}/lib/exec.sh" 2>/dev/null || true
source "${DOTFILES_DIR:-.}/lib/ui.sh" 2>/dev/null || true
# Transaction helpers: record mutations so the orchestrator can roll back on
# failure. When the lib isn't sourced (step run standalone), the tx_* calls
# below are stubbed to no-ops so the step still works on its own.
[ -f "${DOTFILES_DIR:-.}/lib/transaction.sh" ] && source "${DOTFILES_DIR:-.}/lib/transaction.sh" 2>/dev/null || true
[ -f "${DOTFILES_DIR:-.}/lib/packages/catalog.sh" ] && source "${DOTFILES_DIR:-.}/lib/packages/catalog.sh" 2>/dev/null || true
[ -f "${DOTFILES_DIR:-.}/lib/packages/brew.sh" ] && source "${DOTFILES_DIR:-.}/lib/packages/brew.sh" 2>/dev/null || true
[ -f "${DOTFILES_DIR:-.}/lib/packages/apt.sh" ] && source "${DOTFILES_DIR:-.}/lib/packages/apt.sh" 2>/dev/null || true
[ -f "${DOTFILES_DIR:-.}/lib/packages/pacman.sh" ] && source "${DOTFILES_DIR:-.}/lib/packages/pacman.sh" 2>/dev/null || true
[ -f "${DOTFILES_DIR:-.}/lib/packages/dnf.sh" ] && source "${DOTFILES_DIR:-.}/lib/packages/dnf.sh" 2>/dev/null || true
for fn in tx_brew_install tx_brew_cask tx_apt_install tx_pacman_install tx_dnf_install tx_brew_self; do
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
  if [ "${DRY_RUN:-0}" != 1 ] && ! command -v brew >/dev/null 2>&1; then
    echo "[01] ERROR: brew missing after install attempt." >&2
    exit 1
  fi

  # Install only missing formulae and upgrade only managed formulae that are
  # outdated. This keeps repeat runs quiet and ensures rollback records only
  # packages introduced by the current run.
  # coreutils: GNU userland. Provides `timeout` (BSD macOS lacks it), which the
  # Claude Code harness pushes scripts toward after it blocked foreground `sleep`.
  # 03-dotfiles symlinks gtimeout -> ~/.local/bin/timeout so the bare name works.
  # freeze lives in the charmbracelet tap (the core "freeze" name is an unrelated cask).
  BREW_PKGS="$(package_catalog core brew)"
  # tlrc and tldr both ship a `tldr` binary; a legacy `tldr` install (older setups)
  # makes `brew install tlrc` abort with a conflict. Drop it first so tlrc wins.
  if [ "${DRY_RUN:-0}" != 1 ] && brew list --formula 2>/dev/null | grep -qx tldr; then
    run brew unlink tldr
    run brew uninstall tldr
  fi
  # gum is NOT installed here: the UI uses our fork binary (table --width/
  # --border-row), fetched by ui_bootstrap_gum in install.sh. See lib/ui.sh.
  brew_log="${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/install/homebrew.log"
  # shellcheck disable=SC2086
  brew_maintain_formulae "$brew_log" "Homebrew packages" $BREW_PKGS || exit $?
  if [ "${DRY_RUN:-0}" != 1 ]; then
    [ -n "$BREW_MISSING" ] && echo "  ✓ Homebrew packages installed"
    [ -n "$BREW_UPGRADE" ] && echo "  ✓ Homebrew packages updated"
    [ -n "$BREW_MISSING$BREW_UPGRADE" ] || echo "  ✓ Homebrew packages are current"
  fi

  # Optional Neovim toolchain (LSP servers and formatters). The nvim config
  # enables each one only when its binary exists, so skipping any is safe.
  # Interactive multi-select; already-installed ones are filtered out. With no
  # TTY (CI, tart exec) `pick` degrades to 'none' and the step moves on.
  NVIM_OPT_PKGS="$(package_catalog nvim-optional brew)"
  if [ "${DRY_RUN:-0}" != 1 ] && command -v pick >/dev/null 2>&1; then
    nvim_opt_missing=""
    for pkg in $NVIM_OPT_PKGS; do
      command -v "$(basename "$pkg" | sed 's/-native$//')" >/dev/null 2>&1 \
        || nvim_opt_missing="$nvim_opt_missing $pkg"
    done
    if [ -n "$nvim_opt_missing" ]; then
      # shellcheck disable=SC2086
      PICK_SELECTED="$(echo $nvim_opt_missing | tr ' ' ',')"
      # shellcheck disable=SC2086
      picked=$(pick "Optional Neovim LSPs/formatters" $nvim_opt_missing)
      if [ "$picked" != none ] && [ -n "$picked" ]; then
        picked_pkgs="$(echo "$picked" | tr ',' ' ')"
        # shellcheck disable=SC2086
        brew_install_formulae "$brew_log" "optional Neovim tools" $picked_pkgs
      fi
    fi
  fi
elif [ "$OS_TYPE" = "Linux" ] && [ "${PACKAGE_MANAGER:-}" = "apt" ]; then
  # On a clean apt-based image we may run as root (no sudo). Pick the right prefix.
  SUDO=""
  [ "$(id -u)" -ne 0 ] && command -v sudo >/dev/null 2>&1 && SUDO=sudo

  TX_SUDO="$SUDO"   # used by tx_apt_install's undo (apt-get remove)
  run $SUDO apt-get update -qq
  # Install in two passes so a missing package in one distro (e.g. trixie removed
  # `software-properties-common` from the default repo) doesn't drop the rest.
  # First pass: core tools that must be there. Second pass: nice-to-haves, best-effort.
  APT_CORE="$(package_catalog core apt)"
  # shellcheck disable=SC2086
  apt_install_required $APT_CORE
  # Yazi is not packaged by every supported Debian/Ubuntu release. Install the
  # official architecture-specific .deb and verify GitHub's published digest.
  if ! command -v yazi >/dev/null 2>&1; then
    [ "${DRY_RUN:-0}" = 1 ] || apt_package_installed yazi || tx_apt_install yazi
    run bash "${DOTFILES_DIR:?}/scripts/install-yazi.sh"
  fi
  # Fastfetch package availability also varies by distribution. Use its
  # verified official .deb when it is not already present.
  if ! command -v fastfetch >/dev/null 2>&1; then
    [ "${DRY_RUN:-0}" = 1 ] || apt_package_installed fastfetch || tx_apt_install fastfetch
    run bash "${DOTFILES_DIR:?}/scripts/install-fastfetch.sh"
  fi
  # Best-effort extras; never abort if one is missing in this distro.
  APT_OPTIONAL="$(package_catalog best-effort apt)"
  # shellcheck disable=SC2086
  apt_install_optional $APT_OPTIONAL
  run mkdir -p ~/.local/bin
  [ -n "$(command -v fdfind 2>/dev/null)" ] && run ln -sf "$(command -v fdfind)" ~/.local/bin/fd
  [ -n "$(command -v batcat 2>/dev/null)" ] && run ln -sf "$(command -v batcat)" ~/.local/bin/bat
elif [ "$OS_TYPE" = "Linux" ] && [ "${PACKAGE_MANAGER:-}" = "pacman" ]; then
  SUDO=""
  if [ "$(id -u)" -ne 0 ]; then
    command -v sudo >/dev/null 2>&1 || {
      echo "[01] ERROR: sudo is required when installing as a non-root user." >&2
      exit 1
    }
    SUDO=sudo
  fi
  TX_SUDO="$SUDO"

  # Arch forbids partial upgrades: -Syu refreshes databases and upgrades the
  # system before resolving this package set. --needed keeps re-runs idempotent.
  PACMAN_CORE="$(package_catalog core pacman)"
  # shellcheck disable=SC2086
  pacman_install_required $PACMAN_CORE

  # Prefer the custom border-row fork over the stock package.
  [ "${DRY_RUN:-0}" = 1 ] || ui_ensure_gum

  # Populate pkgfile's command database for the zsh command-not-found hook.
  # Some third-party repositories (for example arch-mact2) do not publish a
  # usable .files index. pkgfile then exits non-zero even though the official
  # core/extra databases were updated successfully, so validate the resulting
  # database instead of treating that aggregate exit status as authoritative.
  if ! run $SUDO pkgfile --update; then
    if [ "${DRY_RUN:-0}" != 1 ] && pkgfile --binaries zsh >/dev/null 2>&1; then
      echo "  pkgfile: official database ready (an optional repository has no file index)"
    else
      echo "  warning: pkgfile database is unavailable; run 'sudo pkgfile --update' later"
    fi
  fi
elif [ "$OS_TYPE" = "Linux" ] && [ "${PACKAGE_MANAGER:-}" = "dnf" ]; then
  SUDO=""; [ "$(id -u)" -eq 0 ] || SUDO=sudo
  TX_SUDO="$SUDO"
  DNF_CORE="$(package_catalog core dnf)"
  # shellcheck disable=SC2086
  dnf_install_required $DNF_CORE

  # Tool availability varies between Fedora releases and RHEL-compatible
  # derivatives. Keep the base reliable and add parity tools independently.
  DNF_OPTIONAL="$(package_catalog best-effort dnf)"
  # shellcheck disable=SC2086
  dnf_install_optional $DNF_OPTIONAL
  [ "${DRY_RUN:-0}" = 1 ] || ui_ensure_gum
else
  echo "Unsupported OS/distribution: $OS_TYPE (${DISTRO_ID:-unknown}); supported Linux families: Arch, Debian and Fedora." >&2
  exit 1
fi
echo "[01] done"
