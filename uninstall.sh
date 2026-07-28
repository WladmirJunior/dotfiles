#!/bin/bash
# Dotfiles uninstaller: reverses everything the public steps (01-04) install.
# Usage:
#   ./uninstall.sh                 remove configs, symlinks and packages
#   ./uninstall.sh --keep-packages remove configs/symlinks only (fast re-test)
#   ./uninstall.sh --dry-run       announce every action without executing it
#
# Scope: ONLY what the public repo installs. Private overlays, 1Password/GitHub
# auth wiring (~/.zshrc.local, ~/.ssh/config) and Homebrew itself are untouched.
# Package lists are DERIVED from config/packages.tsv (the same catalog the
# installer reads) minus an explicit keep-list, so install and uninstall cannot
# drift apart. Nothing is deleted: every removed file/dir is parked in the
# shared installer quarantine (lib/trash.sh) and can be brought back with
# scripts/trash-tool.sh restore.
set -uo pipefail

DOTFILES_DIR="$( cd "$( dirname "${BASH_SOURCE[0]:-/dev/null}" )" 2>/dev/null && pwd )"
D="${DOTFILES_DIR:?cannot resolve script dir}"

# Reuse the repo UI when available; degrade to plain echoes standalone.
[ -f "$D/lib/detect.sh" ] && source "$D/lib/detect.sh"
source "$D/lib/ui.sh" 2>/dev/null || true
source "$D/lib/trash.sh" 2>/dev/null || true
source "$D/lib/packages/catalog.sh" 2>/dev/null || true
command -v note   >/dev/null 2>&1 || note()   { echo "  $*"; }
command -v banner >/dev/null 2>&1 || banner() { echo "== $* =="; }
command -v task   >/dev/null 2>&1 || task()   { echo "-- $* --"; }
OS_TYPE="${OS_TYPE:-$(uname)}"

DRY_RUN=0; KEEP_PKGS=0
for arg in "$@"; do
  case "$arg" in
    --dry-run|-n)     DRY_RUN=1 ;;
    --keep-packages)  KEEP_PKGS=1 ;;
    *) echo "Unknown flag: $arg" >&2; exit 2 ;;
  esac
done

run() { [ "$DRY_RUN" = 1 ] && { echo "[dry-run] $*"; return 0; }; "$@"; }

# trash_rm PATH [LABEL]: recoverable removal into the shared quarantine (never
# rm). Falls back to a plain backup dir if lib/trash.sh could not be sourced.
trash_rm() {
  [ -e "$1" ] || [ -L "$1" ] || return 0
  if [ "$DRY_RUN" = 1 ]; then echo "[dry-run] quarantine $1"; return 0; fi
  if command -v trash_path >/dev/null 2>&1; then
    trash_path "$1" "${2:-}" && note "quarantined: $1 -> ${SETUP_TRASH_LAST:-?}"
  else
    local fallback
    fallback="$HOME/.dotfiles-uninstall-backup/$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$fallback"
    mv "$1" "$fallback/$(basename "$1")" && note "backed up: $1 -> $fallback/"
  fi
}
unlink_if() {  # unlink_if LINK EXPECTED_TARGET_FRAGMENT: remove only OUR symlink
  [ -L "$1" ] || return 0
  case "$(readlink "$1")" in
    *"$2"*) run unlink "$1" && note "unlinked: $1" ;;
    *)      note "kept: $1 (points elsewhere, not ours)" ;;
  esac
}

# Keep-list, by catalog capability. These almost always predate the dotfiles or
# are base-system dependencies; removing them would break the machine far
# beyond what this repo installed:
#   shell (zsh: the login shell), git (other tools depend on it),
#   http-client (curl), downloader (wget), node-runtime (node/nodejs/npm:
#   global tooling outside this repo may rely on it).
UNINSTALL_KEEP_CAPABILITIES="shell git http-client downloader node-runtime"

# uninstall_packages MANAGER: core + best-effort catalog packages for MANAGER
# minus the keep-list, space-separated in catalog order. Empty/failure output
# means "catalog unavailable": the caller must skip package removal rather
# than guess at a hardcoded list.
uninstall_packages() {
  local manager="$1" keep="" cap scope pkg out=""
  command -v package_catalog >/dev/null 2>&1 || return 1
  for cap in $UNINSTALL_KEEP_CAPABILITIES; do
    keep="$keep $(package_for "$cap" "$manager" 2>/dev/null || true)"
  done
  for scope in core best-effort; do
    # shellcheck disable=SC2046 # catalog identifiers are word-split on purpose.
    for pkg in $(package_catalog "$scope" "$manager" 2>/dev/null); do
      case " $keep " in *" $pkg "*) continue ;; esac
      case " $out "  in *" $pkg "*) continue ;; esac
      out="${out:+$out }$pkg"
    done
  done
  [ -n "$out" ] || return 1
  printf '%s\n' "$out"
}

banner "Uninstall · public dotfiles"

# -- 03-dotfiles: configs and symlinks -----------------------------------------
task "configs & symlinks"

# ~/.zshrc: only remove the thin file this repo writes (marker check), never a
# user-authored zshrc.
if [ -f "$HOME/.zshrc" ] && grep -qF '# Managed by dotfiles.' "$HOME/.zshrc" 2>/dev/null; then
  trash_rm "$HOME/.zshrc" zshrc
elif [ -e "$HOME/.zshrc" ]; then
  note "kept: ~/.zshrc (not the dotfiles thin file)"
fi

unlink_if "$HOME/.config/nvim/init.lua" "$D/config/nvim/init.lua"
unlink_if "$HOME/.config/yazi/init.lua" "$D/config/yazi/init.lua"
unlink_if "$HOME/.config/yazi/package.toml" "$D/config/yazi/package.toml"
unlink_if "$HOME/.config/yazi/yazi.toml" "$D/config/yazi/yazi.toml"
if [ -d "$HOME/.config/yazi/plugins/git.yazi" ]; then
  trash_rm "$HOME/.config/yazi/plugins/git.yazi" yazi-plugin-git \
    && note "removed: Yazi git plugin"
fi

# git delta config: drop the include.path entry, then the copied file.
DELTA="$HOME/.gitconfig.delta"
if git config --global --get-all include.path 2>/dev/null | grep -qF "$DELTA"; then
  run git config --global --unset include.path "$DELTA" && note "gitconfig: include.path removed"
fi
trash_rm "$DELTA" gitconfig-delta

unlink_if "$HOME/.local/bin/timeout" "coreutils"
unlink_if "$HOME/Developer" "$HOME/dev"

# -- 02-shell: fzf integration and cloned zsh plugins ---------------------------
task "shell (fzf, zsh plugins)"
trash_rm "$HOME/.fzf.zsh" fzf-zsh
if [ -d "$HOME/.config/zsh-plugins" ]; then
  # Plain clones of public repos, regenerable; still quarantined, not deleted.
  trash_rm "$HOME/.config/zsh-plugins" zsh-plugins \
    && note "removed: ~/.config/zsh-plugins"
fi

# -- installer runtime artifacts (gum fork, transaction log) --------------------
task "installer artifacts"
[ -d "$HOME/.local/share/gum-fork" ] && trash_rm "$HOME/.local/share/gum-fork" gum-fork \
  && note "removed: gum fork binary"
[ -f "$HOME/.dotfiles-install.jsonl" ] && trash_rm "$HOME/.dotfiles-install.jsonl" tx-journal \
  && note "removed: transaction log"

# -- 01-packages + 04-apps: packages --------------------------------------------
# Lists come from config/packages.tsv (see uninstall_packages above). One by
# one where the manager allows it, best-effort: a package that is a dependency
# of something outside this repo just fails and stays.
if [ "$KEEP_PKGS" = 1 ]; then
  note "skipping packages (--keep-packages)"
elif [ "$OS_TYPE" = "Darwin" ]; then
  task "brew packages"
  # Snapshot the lists first: `brew list | grep -q` under pipefail dies with
  # SIGPIPE (141) when grep exits early, silently skipping installed packages.
  BREW_INSTALLED="$(brew list --formula 2>/dev/null)"
  BREW_CASKS="$(brew list --cask 2>/dev/null)"
  BREW_PKGS="$(uninstall_packages brew)" || BREW_PKGS=""
  if [ -z "$BREW_PKGS" ]; then
    note "package catalog unavailable; skipping package removal"
  else
    for pkg in $BREW_PKGS; do
      # brew list prints short names; catalog ids may be tap-qualified.
      grep -qx "${pkg##*/}" <<<"$BREW_INSTALLED" || continue
      if run brew uninstall "$pkg" 2>/dev/null; then
        note "uninstalled: $pkg"
      else
        note "kept: $pkg (dependency of another formula)"
      fi
    done
  fi
  if grep -qx "font-jetbrains-mono" <<<"$BREW_CASKS"; then
    run brew uninstall --cask font-jetbrains-mono && note "uninstalled: font-jetbrains-mono"
  fi
  run brew autoremove 2>/dev/null || true
elif [ "$OS_TYPE" = "Linux" ] && [ "${PACKAGE_MANAGER:-}" = "apt" ]; then
  task "apt packages"
  SUDO=""; [ "$(id -u)" -ne 0 ] && command -v sudo >/dev/null 2>&1 && SUDO=sudo
  APT_PKGS="$(uninstall_packages apt)" || APT_PKGS=""
  if [ -z "$APT_PKGS" ]; then
    note "package catalog unavailable; skipping package removal"
  else
    # shellcheck disable=SC2086
    run $SUDO apt-get remove -y $APT_PKGS 2>/dev/null || note "some apt packages kept"
    run $SUDO apt-get autoremove -y 2>/dev/null || true
  fi
elif [ "$OS_TYPE" = "Linux" ] && [ "${PACKAGE_MANAGER:-}" = "pacman" ]; then
  task "pacman packages"
  SUDO=""; [ "$(id -u)" -ne 0 ] && command -v sudo >/dev/null 2>&1 && SUDO=sudo
  PACMAN_PKGS="$(uninstall_packages pacman)" || PACMAN_PKGS=""
  if [ -z "$PACMAN_PKGS" ]; then
    note "package catalog unavailable; skipping package removal"
  else
    # shellcheck disable=SC2086
    run $SUDO pacman -Rns --noconfirm $PACMAN_PKGS 2>/dev/null || note "some pacman packages kept"
  fi
elif [ "$OS_TYPE" = "Linux" ] && [ "${PACKAGE_MANAGER:-}" = "dnf" ]; then
  task "dnf packages"
  SUDO=""; [ "$(id -u)" -eq 0 ] || SUDO=sudo
  DNF_PKGS="$(uninstall_packages dnf)" || DNF_PKGS=""
  if [ -z "$DNF_PKGS" ]; then
    note "package catalog unavailable; skipping package removal"
  else
    # shellcheck disable=SC2086
    run $SUDO dnf remove -y $DNF_PKGS 2>/dev/null || note "some dnf packages kept"
  fi
fi

# -- 04-apps: Touch ID for sudo (needs sudo, best-effort) -----------------------
task "Touch ID for sudo"
if [ -f /etc/pam.d/sudo_local ] && grep -q "pam_tid" /etc/pam.d/sudo_local 2>/dev/null; then
  if [ "$DRY_RUN" = 1 ]; then
    echo "[dry-run] sudo rm /etc/pam.d/sudo_local"
  elif sudo -n true 2>/dev/null; then
    sudo rm -f /etc/pam.d/sudo_local && note "removed: /etc/pam.d/sudo_local"
  else
    note "needs sudo, remove manually:  sudo rm /etc/pam.d/sudo_local"
  fi
fi

banner "Done"
if [ -n "${SETUP_TRASH_DIR:-}" ] && [ -d "${SETUP_TRASH_DIR:-}" ]; then
  note "quarantined items: $SETUP_TRASH_DIR"
  note "restore any of them with:  scripts/trash-tool.sh restore $(basename "$SETUP_TRASH_DIR")"
fi
note "NOT touched: Homebrew itself, ~/.zshrc.local, ~/.ssh/config, private overlays."
note "Re-install with:  ./install.sh"
exit 0
