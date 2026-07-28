#!/usr/bin/env bash
# --plan is a plain compatibility alias for --dry-run: same announcement, no
# separate plan machinery, no fabricated end-of-run summary, and no plan log
# left behind in TMPDIR (the old lib/plan.sh leaked dotfiles-plan-$$.log on
# every execution, even non-plan ones).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/home" "$TMP/tmpdir"

rc=0
HOME="$TMP/home" \
TMPDIR="$TMP/tmpdir" \
XDG_STATE_HOME="$TMP/state" \
TX_LOG="$TMP/tx.jsonl" \
TX_LOCK_DIR="$TMP/tx.jsonl.lock" \
SETUP_TRASH_ROOT="$TMP/trash-root" \
  bash "$ROOT/install.sh" --plan minimal > "$TMP/plan.out" 2>&1 || rc=$?
[ "$rc" -eq 0 ] || { echo "--plan run failed (rc=$rc):" >&2; cat "$TMP/plan.out" >&2; exit 1; }

grep -q 'DRY-RUN: actions are announced, not executed' "$TMP/plan.out"

# The dead plan summary claimed "(no changes planned)" right after announcing
# mutations; the alias must not emit any summary at all.
if grep -qi 'plan summary\|no changes planned' "$TMP/plan.out"; then
  echo "--plan still emits the dead plan summary" >&2
  exit 1
fi

# No unconditional plan log litter in TMPDIR.
if compgen -G "$TMP/tmpdir/dotfiles-plan-*" >/dev/null; then
  echo "leftover plan log in TMPDIR" >&2
  exit 1
fi

# A dry run must not mutate the sandbox HOME (spot checks on step outputs).
[ ! -e "$TMP/home/.zshrc" ]
[ ! -e "$TMP/home/.config/zsh-plugins" ]

echo "Plan alias tests passed."
