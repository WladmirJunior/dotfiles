#!/usr/bin/env bash
# tx_init failures other than the lock (rc 2) are fail-closed: an install that
# cannot write its transaction journal must abort before running any step,
# because it would otherwise run with rollback silently disabled.
# DOTFILES_NO_TX=1 is the explicit opt-out.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'chmod -R u+w "$TMP" 2>/dev/null; rm -rf "$TMP"' EXIT

# Fake repo at $HOME/.dotfiles so install.sh keeps it in place (no relocation)
# and runs the fake profile below with the real lib/ code.
FAKE_HOME="$TMP/home"
REPO="$FAKE_HOME/.dotfiles"
mkdir -p "$TMP/bin" "$REPO/steps" "$REPO/profiles" "$FAKE_HOME"
ln -s "$ROOT/lib" "$REPO/lib"
ln -s "$ROOT/install.sh" "$REPO/install.sh"

printf '10-marker.sh\n' > "$REPO/profiles/txtest"
printf '#!/bin/sh\ntouch "$MARKER"\n' > "$REPO/steps/10-marker.sh"

# sudo stub (Linux hosts): install.sh authenticates sudo before the loop.
printf '#!/bin/sh\nexit 0\n' > "$TMP/bin/sudo"
# curl stub: fail every fetch so nothing ever reaches the network.
printf '#!/bin/sh\nexit 1\n' > "$TMP/bin/curl"
chmod +x "$TMP/bin/"* "$REPO/steps/"*

# Pre-seed a gum stub at the fork path: ui_bootstrap_gum then never downloads,
# and `gum confirm` answering "no" keeps the post-install auth phase inert.
mkdir -p "$TMP/data/gum-fork"
printf '#!/bin/sh\n[ "$1" = confirm ] && exit 1\nexit 0\n' > "$TMP/data/gum-fork/gum"
chmod +x "$TMP/data/gum-fork/gum"

# An unwritable journal path makes tx_init return 1.
mkdir -p "$TMP/rodir"
chmod 555 "$TMP/rodir"

run_install() {  # run_install NAME [EXTRA_ENV...]
  local name="$1" rc=0
  shift
  HOME="$FAKE_HOME" \
  PATH="$TMP/bin:/usr/bin:/bin" \
  XDG_DATA_HOME="$TMP/data" \
  XDG_STATE_HOME="$TMP/state-$name" \
  TX_LOG="$TMP/rodir/tx.jsonl" \
  TX_LOCK_DIR="$TMP/tx-$name.lock" \
  SETUP_TRASH_ROOT="$TMP/trash-root" \
  MARKER="$TMP/marker-$name" \
  env "$@" bash "$REPO/install.sh" txtest > "$TMP/$name.out" 2>&1 || rc=$?
  return "$rc"
}

# ── Unwritable journal (tx_init rc 1): abort before any step ─────────────────
rc=0; run_install failclosed || rc=$?
[ "$rc" -ne 0 ] || {
  echo "install proceeded although the transaction journal is unwritable" >&2
  cat "$TMP/failclosed.out" >&2
  exit 1
}
grep -q 'rollback would be silently disabled' "$TMP/failclosed.out"
grep -q 'DOTFILES_NO_TX=1' "$TMP/failclosed.out"
if [ -e "$TMP/marker-failclosed" ]; then
  echo "a step ran despite the fail-closed transaction abort" >&2
  exit 1
fi

# ── Explicit opt-out: DOTFILES_NO_TX=1 proceeds without a journal ────────────
run_install optout DOTFILES_NO_TX=1 || {
  echo "DOTFILES_NO_TX=1 did not bypass the transaction requirement" >&2
  cat "$TMP/optout.out" >&2
  exit 1
}
grep -q 'WITHOUT rollback protection' "$TMP/optout.out"
[ -e "$TMP/marker-optout" ] || {
  echo "steps did not run under DOTFILES_NO_TX=1" >&2
  exit 1
}
[ ! -e "$TMP/rodir/tx.jsonl" ]   # no journal was ever created

echo "Transaction fail-closed tests passed."
