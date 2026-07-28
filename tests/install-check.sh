#!/usr/bin/env bash
# install.sh --check is verification-only: it must not start a transaction, so
# it never takes the install lock nor moves an abandoned journal aside.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/home"

# A leftover uncommitted journal from an interrupted run: --check must not
# treat it as abandoned (that is the real installer's job).
TX_LOG="$TMP/tx.jsonl"
printf '{"op":"leftover","undo":["true"]}\n' > "$TX_LOG"

# rc is ignored: verification may legitimately fail in this bare HOME; the
# contract under test is the absence of transaction side effects.
HOME="$TMP/home" \
TX_LOG="$TX_LOG" \
TX_LOCK_DIR="$TX_LOG.lock" \
SETUP_TRASH_ROOT="$TMP/trash-root" \
  bash "$ROOT/install.sh" --check > "$TMP/check.out" 2>&1 || true

grep -q '"op":"leftover"' "$TX_LOG"   # journal untouched (not truncated/moved)
if compgen -G "$TX_LOG.abandoned-*" >/dev/null; then
  echo "--check moved the abandoned journal aside" >&2
  exit 1
fi
if [ -d "$TX_LOG.lock" ]; then
  echo "--check took the install lock" >&2
  exit 1
fi
grep -qi 'health check' "$TMP/check.out"   # verification itself did run

echo "Install --check tests passed."
