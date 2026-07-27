#!/bin/bash
# Install essential CLI tools (brew on macOS, apt or pacman on Linux).
# Requires: DOTFILES_DIR in env.
set -uo pipefail
[ -z "${OS_TYPE:-}" ] && source "${DOTFILES_DIR:-.}/lib/detect.sh"
source "${DOTFILES_DIR:-.}/lib/ui.sh" 2>/dev/null || true
# Transaction helpers: record mutations so the orchestrator can roll back on
# failure. When the lib isn't sourced (step run standalone), the tx_* calls
# below are stubbed to no-ops so the step still works on its own.
[ -f "${DOTFILES_DIR:-.}/lib/transaction.sh" ] && source "${DOTFILES_DIR:-.}/lib/transaction.sh" 2>/dev/null || true
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
  BREW_PKGS="git gh neovim fzf zoxide eza bat ripgrep fd git-delta tlrc node usbutils coreutils yazi hexyl fastfetch sevenzip resvg exiftool glow vhs charmbracelet/tap/freeze charmbracelet/tap/wishlist tree-sitter-cli lua-language-server"
  # tlrc and tldr both ship a `tldr` binary; a legacy `tldr` install (older setups)
  # makes `brew install tlrc` abort with a conflict. Drop it first so tlrc wins.
  if [ "${DRY_RUN:-0}" != 1 ] && brew list --formula 2>/dev/null | grep -qx tldr; then
    run brew unlink tldr
    run brew uninstall tldr
  fi
  # gum is NOT installed here: the UI uses our fork binary (table --width/
  # --border-row), fetched by ui_bootstrap_gum in install.sh. See lib/ui.sh.
  if [ "${DRY_RUN:-0}" = 1 ]; then
    run brew install $BREW_PKGS
  else
    brew_missing=""; brew_upgrade=""
    brew_outdated="$(brew outdated --formula --quiet 2>/dev/null || true)"
    for pkg in $BREW_PKGS; do
      pkg_name="${pkg##*/}"
      if ! brew list --formula "$pkg_name" >/dev/null 2>&1; then
        brew_missing="${brew_missing:+$brew_missing }$pkg"
      elif grep -qx "$pkg_name" <<<"$brew_outdated"; then
        brew_upgrade="${brew_upgrade:+$brew_upgrade }$pkg"
      fi
    done
    brew_log_dir="${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/install"
    brew_log="$brew_log_dir/homebrew.log"
    mkdir -p "$brew_log_dir"
    if [ -n "$brew_missing" ]; then
      # shellcheck disable=SC2086
      tx_brew_install $brew_missing
      if command -v spin >/dev/null 2>&1; then
        # shellcheck disable=SC2086
        spin "Installing Homebrew packages · details in $brew_log" -- \
          bash -c 'log=$1; shift; brew install "$@" >>"$log" 2>&1' _ "$brew_log" $brew_missing
      else
        # shellcheck disable=SC2086
        brew install $brew_missing >>"$brew_log" 2>&1
      fi || { tail -n 30 "$brew_log" >&2; exit 1; }
      echo "  ✓ Homebrew packages installed"
    fi
    if [ -n "$brew_upgrade" ]; then
      if command -v spin >/dev/null 2>&1; then
        # shellcheck disable=SC2086
        spin "Updating Homebrew packages · details in $brew_log" -- \
          bash -c 'log=$1; shift; brew upgrade "$@" >>"$log" 2>&1' _ "$brew_log" $brew_upgrade
      else
        # shellcheck disable=SC2086
        brew upgrade $brew_upgrade >>"$brew_log" 2>&1
      fi || { tail -n 30 "$brew_log" >&2; exit 1; }
      echo "  ✓ Homebrew packages updated"
    fi
    [ -n "$brew_missing$brew_upgrade" ] || echo "  ✓ Homebrew packages are current"
  fi

  # Optional Neovim toolchain (LSP servers and formatters). The nvim config
  # enables each one only when its binary exists, so skipping any is safe.
  # Interactive multi-select; already-installed ones are filtered out. With no
  # TTY (CI, tart exec) `pick` degrades to 'none' and the step moves on.
  NVIM_OPT_PKGS="bash-language-server clojure-lsp/brew/clojure-lsp-native gopls shfmt jq"
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
        [ "${DRY_RUN:-0}" != 1 ] && tx_brew_install $picked_pkgs
        # shellcheck disable=SC2086
        run brew install $picked_pkgs
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
  # Parity with BREW_PKGS above, minus what Arch already ships in base: GNU
  # coreutils is a base dependency here (macOS needs brew for `timeout`), so it
  # is deliberately absent. wishlist/vhs/tree-sitter-cli/lua-language-server/
  # usbutils were macOS-only for a while purely because this list was never
  # updated alongside BREW_PKGS. `freeze` has no official Arch package (AUR
  # only) and stays out.
  PACMAN_CORE="zsh neovim fzf zoxide bat ripgrep fd git-delta nodejs npm curl git github-cli wget hexyl yazi fastfetch eza tealdeer 7zip resvg perl-image-exiftool glow pkgfile jq gum wishlist vhs tree-sitter-cli lua-language-server usbutils"
  if [ "${DRY_RUN:-0}" != 1 ]; then
    PACMAN_NEW=""
    for pkg in $PACMAN_CORE; do
      pacman -Q "$pkg" >/dev/null 2>&1 || PACMAN_NEW="$PACMAN_NEW $pkg"
    done
    # Rollback only packages introduced by this run, never pre-existing tools.
    [ -n "$PACMAN_NEW" ] && tx_pacman_install $PACMAN_NEW
  fi
  run $SUDO pacman -Syu --needed --noconfirm $PACMAN_CORE

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
  DNF_CORE="zsh neovim fzf zoxide bat ripgrep fd-find nodejs npm curl git gh wget jq"
  DNF_NEW=""
  for pkg in $DNF_CORE; do rpm -q "$pkg" >/dev/null 2>&1 || DNF_NEW="$DNF_NEW $pkg"; done
  [ "${DRY_RUN:-0}" = 1 ] || [ -z "$DNF_NEW" ] || tx_dnf_install $DNF_NEW
  run $SUDO dnf install -y -q $DNF_CORE

  # Tool availability varies between Fedora releases and RHEL-compatible
  # derivatives. Keep the base reliable and add parity tools independently.
  for pkg in git-delta hexyl yazi fastfetch eza tealdeer p7zip p7zip-plugins resvg perl-Image-ExifTool glow PackageKit-command-not-found; do
    if rpm -q "$pkg" >/dev/null 2>&1; then continue; fi
    if run $SUDO dnf install -y -q "$pkg" 2>/dev/null; then
      [ "${DRY_RUN:-0}" = 1 ] || tx_dnf_install "$pkg"
    else
      echo "  skip: $pkg not available in this Fedora-family release"
    fi
  done
  [ "${DRY_RUN:-0}" = 1 ] || ui_ensure_gum
else
  echo "Unsupported OS/distribution: $OS_TYPE (${DISTRO_ID:-unknown}); supported Linux families: Arch, Debian and Fedora." >&2
  exit 1
fi
echo "[01] done"
