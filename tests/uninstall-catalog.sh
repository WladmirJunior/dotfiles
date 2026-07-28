#!/usr/bin/env bash
# uninstall.sh parity with config/packages.tsv: the removal list is derived
# from the same catalog the installer reads (core + best-effort for the
# detected manager) minus the explicit keep-list, and removed files are parked
# in the shared quarantine (trash-tool restorable), not rm'd or ad-hoc backed up.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/home"

# Pin the platform: fake uname + os-release so detection lands on the mocked
# Linux manager even on macOS runners.
cat > "$TMP/bin/uname" <<'SH'
#!/bin/sh
[ "${1:-}" = -m ] && { echo x86_64; exit 0; }
echo Linux
SH
chmod +x "$TMP/bin/uname"
printf 'ID=arch\n' > "$TMP/os-release-arch"
printf 'ID=debian\n' > "$TMP/os-release-debian"

# Keep-list mirror (capability -> package names across managers). Must match
# UNINSTALL_KEEP_CAPABILITIES in uninstall.sh: shell git http-client
# downloader node-runtime apt-repositories command-not-found:dnf.
KEEP="zsh git curl wget node nodejs npm software-properties-common"
KEEP_DNF="PackageKit-command-not-found"

# expected_removals MANAGER: catalog core+best-effort minus keep, one per line.
expected_removals() {
  local manager="$1" scope pkg out="" keep="$KEEP"
  [ "$manager" = dnf ] && keep="$KEEP $KEEP_DNF"
  for scope in core best-effort; do
    for pkg in $(DOTFILES_DIR="$ROOT" bash -c \
      'source "$1/lib/packages/catalog.sh"; package_catalog "$2" "$3"' _ "$ROOT" "$scope" "$manager"); do
      case " $keep " in *" $pkg "*) continue ;; esac
      case " $out "  in *" $pkg "*) continue ;; esac
      out="${out:+$out }$pkg"
    done
  done
  printf '%s\n' "$out" | tr ' ' '\n' | sort
}

run_uninstall_dry() {  # NAME OS_RELEASE
  HOME="$TMP/home" \
  PATH="$TMP/bin:/usr/bin:/bin" \
  OS_RELEASE_FILE="$2" \
  SETUP_TRASH_ROOT="$TMP/trash-root" \
    bash "$ROOT/uninstall.sh" --dry-run > "$TMP/$1.out" 2>&1
}

# ── pacman: announced removal set == catalog-derived set ─────────────────────
run_uninstall_dry pacman "$TMP/os-release-arch"
actual="$(sed -n 's/.*pacman -Rns --noconfirm //p' "$TMP/pacman.out" | tr ' ' '\n' | sort)"
[ -n "$actual" ] || { echo "no pacman removal announced:" >&2; cat "$TMP/pacman.out" >&2; exit 1; }
expected="$(expected_removals pacman)"
[ "$actual" = "$expected" ] || {
  echo "pacman uninstall list drifted from the catalog:" >&2
  diff <(printf '%s\n' "$expected") <(printf '%s\n' "$actual") >&2 || true
  exit 1
}
# The keep-list must never be scheduled for removal.
for kept in zsh git curl; do
  if printf '%s\n' "$actual" | grep -qx "$kept"; then
    echo "keep-list package scheduled for removal: $kept" >&2
    exit 1
  fi
done

# ── apt: same contract through the debian detection path ─────────────────────
run_uninstall_dry apt "$TMP/os-release-debian"
actual_apt="$(sed -n 's/.*apt-get remove -y //p' "$TMP/apt.out" | tr ' ' '\n' | sort)"
[ -n "$actual_apt" ]
[ "$actual_apt" = "$(expected_removals apt)" ] || {
  echo "apt uninstall list drifted from the catalog" >&2
  exit 1
}

# ── files go to the shared quarantine, restorable, no ad-hoc backup dir ──────
HOME2="$TMP/home2"
mkdir -p "$HOME2/.config/zsh-plugins/fzf-tab"
printf '# Managed by dotfiles. thin\n' > "$HOME2/.zshrc"
printf 'fzf\n' > "$HOME2/.fzf.zsh"
HOME="$HOME2" \
PATH="$TMP/bin:/usr/bin:/bin" \
OS_RELEASE_FILE="$TMP/os-release-arch" \
SETUP_TRASH_ROOT="$TMP/trash-root2" \
  bash "$ROOT/uninstall.sh" --keep-packages > "$TMP/files.out" 2>&1

[ ! -e "$HOME2/.zshrc" ]
[ ! -e "$HOME2/.fzf.zsh" ]
[ ! -e "$HOME2/.config/zsh-plugins" ]
[ ! -d "$HOME2/.dotfiles-uninstall-backup" ]   # no ad-hoc backup dir
qdir="$(compgen -G "$TMP/trash-root2/dotfiles-installer/*" | head -n1)"
[ -n "$qdir" ] || { echo "no quarantine dir created" >&2; exit 1; }
grep -q "^$HOME2/.zshrc -> " "$qdir/MANIFEST"
grep -q "^$HOME2/.fzf.zsh -> " "$qdir/MANIFEST"
grep -q "^$HOME2/.config/zsh-plugins -> " "$qdir/MANIFEST"
grep -q '^fzf$' "$qdir/fzf-zsh"   # content parked intact
grep -q 'quarantined items:' "$TMP/files.out"

echo "Uninstall catalog parity tests passed."
