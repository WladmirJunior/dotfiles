#!/usr/bin/env bash
# Rollback honesty, abandoned-journal preservation, install lock and
# quarantine retention (transaction.sh + trash.sh).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
HELPER_PID=""
cleanup() {
  [ -n "$HELPER_PID" ] && kill "$HELPER_PID" 2>/dev/null || true
  rm -rf "$TMP"
}
trap cleanup EXIT

TX_LOG="$TMP/tx.jsonl"
TX_LAST="$TMP/tx.last.jsonl"
SETUP_TRASH_DIR="$TMP/trash"
SETUP_TRASH_ROOT="$TMP/trash-root"
source "$ROOT/lib/transaction.sh"

# ── Rollback reports failed undos and returns non-zero ───────────────────────
tx_init
tx_run "bad:undo" rmdir "$TMP/does-not-exist" -- true    # this undo must fail
tx_run "good:undo" touch "$TMP/undone-marker" -- true    # this one must run
if tx_rollback > "$TMP/rollback.out" 2>&1; then
  echo "tx_rollback claimed success despite a failed undo" >&2
  exit 1
fi
[ "$TX_ROLLBACK_FAILED" = 1 ]
grep -q '1 failed undo' "$TMP/rollback.out"
grep -q 'bad:undo' "$TMP/rollback.out"
[ -e "$TMP/undone-marker" ]        # the good undo still ran
[ -s "$TX_LOG" ]                   # journal kept as evidence on partial restore

# ── tx_init preserves an uncommitted journal instead of truncating it ─────────
tx_init > "$TMP/init.out" 2> "$TMP/init.err"
grep -q 'uncommitted journal' "$TMP/init.err"
compgen -G "$TX_LOG.abandoned-*" >/dev/null
[ ! -s "$TX_LOG" ]

# ── tx_init: journal move fails -> copy fallback preserves, then truncates ────
(
  mkdir -p "$TMP/mvfail/stubbin"
  printf '#!/bin/sh\nexit 1\n' > "$TMP/mvfail/stubbin/mv"
  chmod +x "$TMP/mvfail/stubbin/mv"
  TX_LOG="$TMP/mvfail/tx.jsonl"
  TX_LOCK_DIR="$TX_LOG.lock"
  printf '{"op":"copied","undo":["true"]}\n' > "$TX_LOG"
  PATH="$TMP/mvfail/stubbin:$PATH"
  tx_init 2> "$TMP/mvfail/init.err"
  grep -q 'preserved at' "$TMP/mvfail/init.err"
  compgen -G "$TX_LOG.abandoned-*" >/dev/null
  grep -q '"op":"copied"' "$TX_LOG".abandoned-*
  [ ! -s "$TX_LOG" ]   # truncated only because the copy succeeded
)

# ── tx_init: journal not preservable at all -> kept untouched, init refuses ───
(
  mkdir -p "$TMP/rodir"
  TX_LOG="$TMP/rodir/tx.jsonl"
  TX_LOCK_DIR="$TMP/ro.lock"   # lock lives outside the read-only dir
  printf '{"op":"keep","undo":["true"]}\n' > "$TX_LOG"
  chmod 555 "$TMP/rodir"       # rename and copy-into both fail; file stays writable
  rc=0; tx_init 2> "$TMP/ro-init.err" || rc=$?
  chmod 755 "$TMP/rodir"
  [ "$rc" -eq 1 ]
  grep -q 'keeping' "$TMP/ro-init.err"
  grep -q '"op":"keep"' "$TX_LOG"   # journal intact: NOT truncated
  [ ! -d "$TX_LOCK_DIR" ]           # lock released on refusal
)

# ── Clean rollback still succeeds and rotates the journal ─────────────────────
tx_run "noop" true -- true
tx_rollback >/dev/null
[ ! -e "$TX_LOG" ]
[ -f "$TX_LOG.rolledback" ]

# ── Lock: an active concurrent install is refused (rc 2) ─────────────────────
sleep 60 & HELPER_PID=$!
mkdir "$TX_LOG.lock"
printf '%s\n' "$HELPER_PID" > "$TX_LOG.lock/pid"
rc=0; tx_init 2> "$TMP/lock.err" || rc=$?
[ "$rc" -eq 2 ]
grep -q 'another install' "$TMP/lock.err"

# ── Lock: a stale lock (dead pid) is reclaimed ────────────────────────────────
kill "$HELPER_PID" 2>/dev/null || true
wait "$HELPER_PID" 2>/dev/null || true
HELPER_PID=""
tx_init > "$TMP/stale.out"
grep -q 'reclaiming stale lock' "$TMP/stale.out"
grep -qx "$$" "$TX_LOG.lock/pid"

# ── Quarantine: manifest records origin -> destination ────────────────────────
printf 'junk\n' > "$TMP/junk-file"
trash_path "$TMP/junk-file"
grep -q "^$TMP/junk-file -> $SETUP_TRASH_DIR/junk-file" "$SETUP_TRASH_DIR/MANIFEST"

# ── Quarantine: every recording helper writes its manifest line at record time ─
tx_created_path "$TMP/mf-created"
grep -q "^$TMP/mf-created -> " "$SETUP_TRASH_DIR/MANIFEST"

tx_git_clone "https://example.invalid/repo.git" "$TMP/mf-clone"
grep -q "^$TMP/mf-clone -> " "$SETUP_TRASH_DIR/MANIFEST"

HOMEBREW_PREFIX="$TMP/mf-brew-prefix" tx_brew_self
grep -q "^$TMP/mf-brew-prefix -> " "$SETUP_TRASH_DIR/MANIFEST"

printf 'old\n' > "$TMP/mf-backed"
tx_backup_path "test:backup" "$TMP/mf-backed" "$TMP/mf-backed.bak"
grep -q "^$TMP/mf-backed -> " "$SETUP_TRASH_DIR/MANIFEST"
[ -f "$TMP/mf-backed.bak" ]

tx_symlink "$TMP/mf-target" "$TMP/mf-link"   # dst absent -> new-link branch
grep -q "^$TMP/mf-link -> " "$SETUP_TRASH_DIR/MANIFEST"

# ── Quarantine: tx_commit prunes only expired per-run dirs ────────────────────
old_epoch=$(( $(date +%s) - 100 * 86400 ))
old_dir="$SETUP_TRASH_ROOT/dotfiles-installer/$old_epoch-1-dotfiles"
fresh_dir="$SETUP_TRASH_ROOT/dotfiles-installer/$(date +%s)-2-dotfiles"
odd_dir="$SETUP_TRASH_ROOT/dotfiles-installer/keep-me"
outside_dir="$SETUP_TRASH_ROOT/other-tool/$old_epoch-9-dotfiles"
mkdir -p "$old_dir" "$fresh_dir" "$odd_dir" "$outside_dir"
touch "$old_dir/file"

DRY_RUN=1 setup_trash_prune
[ -d "$old_dir" ]                  # dry-run never prunes

tx_commit > "$TMP/commit.out"
[ ! -e "$old_dir" ]
grep -q 'pruned quarantine' "$TMP/commit.out"
[ -d "$fresh_dir" ]
[ -d "$odd_dir" ]                  # non-epoch names are untouched
[ -d "$outside_dir" ]              # nothing outside dotfiles-installer/
[ ! -d "$TX_LOG.lock" ]            # commit released the install lock

echo "Transaction safety tests passed."
