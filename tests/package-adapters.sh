#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/home"

cat > "$TMP/bin/pacman" <<'SH'
#!/bin/sh
if [ "$1" = -Q ]; then [ "$2" = zsh ]; exit $?; fi
printf '%s\n' "$*" >> "$PACMAN_CALLS"
SH
cat > "$TMP/bin/rpm" <<'SH'
#!/bin/sh
[ "$1" = -q ] && [ "$2" = zsh ]
SH
cat > "$TMP/bin/dnf" <<'SH'
#!/bin/sh
printf '%s\n' "$*" >> "$DNF_CALLS"
SH
chmod +x "$TMP/bin/"*

HOME="$TMP/home"
PATH="$TMP/bin:/usr/bin:/bin"
PACMAN_CALLS="$TMP/pacman.calls"
DNF_CALLS="$TMP/dnf.calls"
export HOME PATH PACMAN_CALLS DNF_CALLS
DRY_RUN=0
SUDO=""
TX_SUDO=""
TX_LOG="$TMP/tx.jsonl"
TX_LAST="$TMP/tx.last.jsonl"

source "$ROOT/lib/exec.sh"
source "$ROOT/lib/transaction.sh"
source "$ROOT/lib/packages/pacman.sh"
source "$ROOT/lib/packages/dnf.sh"

tx_init
pacman_install_required zsh neovim
grep -q 'pacman_install:neovim' "$TX_LOG"
! grep -q 'pacman_install:zsh' "$TX_LOG"
grep -qx -- '-Syu --needed --noconfirm zsh neovim' "$PACMAN_CALLS"

tx_init
dnf_install_required zsh neovim
grep -q 'dnf_install:neovim' "$TX_LOG"
! grep -q 'dnf_install:zsh' "$TX_LOG"
grep -qx 'install -y -q zsh neovim' "$DNF_CALLS"

echo "Package adapter tests passed."
