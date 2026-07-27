#!/bin/bash
# Dotfiles uninstaller: reverses everything the public steps (01-04) install.
# Usage:
#   ./uninstall.sh                 remove configs, symlinks and packages
#   ./uninstall.sh --keep-packages remove configs/symlinks only (fast re-test)
#   ./uninstall.sh --dry-run       announce every action without executing it
#
# Scope: ONLY what the public repo installs. Private overlays, 1Password/GitHub
# auth wiring (~/.zshrc.local, ~/.ssh/config) and Homebrew itself are untouched.
# Files with local edits are backed up to ~/.dotfiles-uninstall-backup/<ts>/
# before removal; symlinks and cloned plugin repos are just removed (regenerable).
set -uo pipefail

DOTFILES_DIR="$( cd "$( dirname "${BASH_SOURCE[0]:-/dev/null}" )" 2>/dev/null && pwd )"
D="${DOTFILES_DIR:?cannot resolve script dir}"

# Reuse the repo UI when available; degrade to plain echoes standalone.
[ -f "$D/lib/detect.sh" ] && source "$D/lib/detect.sh"
source "$D/lib/ui.sh" 2>/dev/null || true
command -v note   >/dev/null 2>&1 || note()   { echo "  $*"; }
command -v ok     >/dev/null 2>&1 || ok()     { echo "OK $*"; }
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

BACKUP_DIR="$HOME/.dotfiles-uninstall-backup/$(date +%Y%m%d-%H%M%S)"
backup_rm() {  # backup_rm FILE: move a real file to the backup dir (never lost)
  [ -e "$1" ] || return 0
  if [ "$DRY_RUN" = 1 ]; then echo "[dry-run] backup+remove $1"; return 0; fi
  mkdir -p "$BACKUP_DIR"
  mv "$1" "$BACKUP_DIR/$(basename "$1")" && note "backed up: $1 -> $BACKUP_DIR/"
}
unlink_if() {  # unlink_if LINK EXPECTED_TARGET_FRAGMENT: remove only OUR symlink
  [ -L "$1" ] || return 0
  case "$(readlink "$1")" in
    *"$2"*) run unlink "$1" && note "unlinked: $1" ;;
    *)      note "kept: $1 (points elsewhere, not ours)" ;;
  esac
}

banner "Uninstall · public dotfiles"

# -- 03-dotfiles: configs and symlinks -----------------------------------------
task "configs & symlinks"

# ~/.zshrc: only remove the thin file this repo writes (marker check), never a
# user-authored zshrc.
if [ -f "$HOME/.zshrc" ] && grep -qF '# Managed by dotfiles.' "$HOME/.zshrc" 2>/dev/null; then
  backup_rm "$HOME/.zshrc"
elif [ -e "$HOME/.zshrc" ]; then
  note "kept: ~/.zshrc (not the dotfiles thin file)"
fi

unlink_if "$HOME/.config/nvim/init.lua" "$D/config/nvim/init.lua"
unlink_if "$HOME/.config/yazi/init.lua" "$D/config/yazi/init.lua"
unlink_if "$HOME/.config/yazi/package.toml" "$D/config/yazi/package.toml"
unlink_if "$HOME/.config/yazi/yazi.toml" "$D/config/yazi/yazi.toml"
if [ -d "$HOME/.config/yazi/plugins/git.yazi" ]; then
  run rm -rf "$HOME/.config/yazi/plugins/git.yazi" \
    && note "removed: Yazi git plugin"
fi

# git delta config: drop the include.path entry, then the copied file.
DELTA="$HOME/.gitconfig.delta"
if git config --global --get-all include.path 2>/dev/null | grep -qF "$DELTA"; then
  run git config --global --unset include.path "$DELTA" && note "gitconfig: include.path removed"
fi
backup_rm "$DELTA"

unlink_if "$HOME/.local/bin/timeout" "coreutils"
unlink_if "$HOME/Developer" "$HOME/dev"

# -- 02-shell: fzf integration and cloned zsh plugins ---------------------------
task "shell (fzf, zsh plugins)"
backup_rm "$HOME/.fzf.zsh"
if [ -d "$HOME/.config/zsh-plugins" ]; then
  # Plain clones of public repos, nothing local to lose: remove outright.
  run rm -rf "$HOME/.config/zsh-plugins" && note "removed: ~/.config/zsh-plugins"
fi

# -- installer runtime artifacts (gum fork, transaction log) --------------------
task "installer artifacts"
[ -d "$HOME/.local/share/gum-fork" ] && run rm -rf "$HOME/.local/share/gum-fork" && note "removed: gum fork binary"
[ -f "$HOME/.dotfiles-install.jsonl" ] && run rm -f "$HOME/.dotfiles-install.jsonl" && note "removed: transaction log"

# -- 01-packages + 04-apps: packages --------------------------------------------
if [ "$KEEP_PKGS" = 1 ]; then
  note "skipping packages (--keep-packages)"
elif [ "$OS_TYPE" = "Darwin" ]; then
  task "brew packages"
  # Same list as 01-packages. Uninstall one by one, best-effort: a formula that
  # is a dependency of something outside this repo just fails and stays.
  # Snapshot the lists first: `brew list | grep -q` under pipefail dies with
  # SIGPIPE (141) when grep exits early, silently skipping installed packages.
  BREW_INSTALLED="$(brew list --formula 2>/dev/null)"
  BREW_CASKS="$(brew list --cask 2>/dev/null)"
  BREW_PKGS="git gh neovim fzf zoxide eza bat ripgrep fd git-delta tlrc node usbutils coreutils yazi hexyl fastfetch sevenzip resvg exiftool"
  for pkg in $BREW_PKGS; do
    grep -qx "$pkg" <<<"$BREW_INSTALLED" || continue
    run brew uninstall "$pkg" 2>/dev/null && note "uninstalled: $pkg" \
      || note "kept: $pkg (dependency of another formula)"
  done
  if grep -qx "font-jetbrains-mono" <<<"$BREW_CASKS"; then
    run brew uninstall --cask font-jetbrains-mono && note "uninstalled: font-jetbrains-mono"
  fi
  run brew autoremove 2>/dev/null || true
elif [ "$OS_TYPE" = "Linux" ] && [ "${PACKAGE_MANAGER:-}" = "apt" ]; then
  task "apt packages"
  SUDO=""; [ "$(id -u)" -ne 0 ] && command -v sudo >/dev/null 2>&1 && SUDO=sudo
  APT_PKGS="neovim fzf zoxide bat ripgrep fd-find git-delta eza tealdeer yazi hexyl fastfetch 7zip resvg libimage-exiftool-perl"
  # zsh/git/curl/nodejs stay: likely predate the dotfiles or are system deps.
  run $SUDO apt-get remove -y $APT_PKGS 2>/dev/null || note "some apt packages kept"
  run $SUDO apt-get autoremove -y 2>/dev/null || true
elif [ "$OS_TYPE" = "Linux" ] && [ "${PACKAGE_MANAGER:-}" = "pacman" ]; then
  task "pacman packages"
  SUDO=""; [ "$(id -u)" -ne 0 ] && command -v sudo >/dev/null 2>&1 && SUDO=sudo
  PACMAN_PKGS="neovim fzf zoxide bat ripgrep fd git-delta eza tealdeer yazi hexyl fastfetch 7zip resvg perl-image-exiftool glow pkgfile jq gum"
  # zsh/git/curl/nodejs stay: likely predate the dotfiles or are system deps.
  run $SUDO pacman -Rns --noconfirm $PACMAN_PKGS 2>/dev/null || note "some pacman packages kept"
elif [ "$OS_TYPE" = "Linux" ] && [ "${PACKAGE_MANAGER:-}" = "dnf" ]; then
  task "dnf packages"
  SUDO=""; [ "$(id -u)" -eq 0 ] || SUDO=sudo
  DNF_PKGS="neovim fzf zoxide bat ripgrep fd-find git-delta eza tealdeer yazi hexyl fastfetch p7zip p7zip-plugins resvg perl-Image-ExifTool glow"
  run $SUDO dnf remove -y $DNF_PKGS 2>/dev/null || note "some dnf packages kept"
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
[ -d "$BACKUP_DIR" ] && note "backups: $BACKUP_DIR"
note "NOT touched: Homebrew itself, ~/.zshrc.local, ~/.ssh/config, private overlays."
note "Re-install with:  ./install.sh"
exit 0
