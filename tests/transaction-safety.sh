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

# ── Quarantine: manifest records origin -> destination at the real move ───────
printf 'junk\n' > "$TMP/junk-file"
trash_path "$TMP/junk-file"
grep -q "^$TMP/junk-file -> $SETUP_TRASH_DIR/junk-file" "$SETUP_TRASH_DIR/MANIFEST"

# tx_symlink over an existing file parks it NOW: manifest line at record time.
printf 'old\n' > "$TMP/mf-replaced"
tx_symlink "$TMP/mf-target" "$TMP/mf-replaced"
grep -q "^$TMP/mf-replaced -> " "$SETUP_TRASH_DIR/MANIFEST"

# ── Deferred recorders: no dir, no manifest line until the move really runs ───
# A successful install (commit, no rollback) must leave no ghost entries that
# point trash-tool at items which never reached the quarantine.
(
  SETUP_TRASH_DIR="$TMP/trash-commit"
  TX_LOG="$TMP/tx-commit.jsonl"
  TX_LOCK_DIR="$TX_LOG.lock"
  tx_init
  tx_created_path "$TMP/cm-created"
  printf 'made\n' > "$TMP/cm-created"
  tx_git_clone "https://example.invalid/repo.git" "$TMP/cm-clone"
  mkdir -p "$TMP/cm-clone"
  HOMEBREW_PREFIX="$TMP/cm-brew-prefix" tx_brew_self
  tx_symlink "$TMP/cm-target" "$TMP/cm-link"   # dst absent -> new-link branch
  [ ! -e "$SETUP_TRASH_DIR" ]   # recording alone creates nothing on disk
  tx_commit >/dev/null
  [ ! -e "$SETUP_TRASH_DIR" ]   # committed install: no quarantine dir at all
  [ -f "$TMP/cm-created" ]      # ...and the installed items stayed in place
  [ -L "$TMP/cm-link" ]
)

# ── Deferred recorders on rollback: items land in trash WITH manifest lines ───
(
  SETUP_TRASH_DIR="$TMP/trash-rb"
  TX_LOG="$TMP/tx-rb.jsonl"
  TX_LOCK_DIR="$TX_LOG.lock"
  tx_init
  tx_created_path "$TMP/rb-created"
  printf 'made\n' > "$TMP/rb-created"
  tx_symlink "$TMP/rb-target" "$TMP/rb-link"
  tx_rollback >/dev/null
  [ ! -e "$TMP/rb-created" ]    # undone: moved to quarantine
  [ ! -L "$TMP/rb-link" ]
  grep -q "^$TMP/rb-created -> " "$SETUP_TRASH_DIR/MANIFEST"
  grep -q "^$TMP/rb-link -> " "$SETUP_TRASH_DIR/MANIFEST"
)

# ── tx_backup_path: backup parked (manifest mapped to the ORIGINAL path) only
#    at commit; a rollback restores it and writes no manifest line ────────────
(
  SETUP_TRASH_DIR="$TMP/trash-bk"
  TX_LOG="$TMP/tx-bk.jsonl"
  TX_LOCK_DIR="$TX_LOG.lock"
  tx_init
  printf 'old\n' > "$TMP/bk-file"
  tx_backup_path "test:backup" "$TMP/bk-file" "$TMP/bk-file.bak"
  [ -f "$TMP/bk-file.bak" ]
  [ ! -e "$SETUP_TRASH_DIR" ]   # nothing parked yet
  tx_commit >/dev/null
  [ ! -e "$TMP/bk-file.bak" ]   # backup left $HOME for the quarantine
  grep -q "^$TMP/bk-file -> $SETUP_TRASH_DIR/backup-bk-file-1$" "$SETUP_TRASH_DIR/MANIFEST"
  grep -q '^old$' "$SETUP_TRASH_DIR/backup-bk-file-1"
)
(
  SETUP_TRASH_DIR="$TMP/trash-bk-rb"
  TX_LOG="$TMP/tx-bk-rb.jsonl"
  TX_LOCK_DIR="$TX_LOG.lock"
  tx_init
  printf 'old\n' > "$TMP/bk-rb-file"
  tx_backup_path "test:backup" "$TMP/bk-rb-file" "$TMP/bk-rb-file.bak"
  tx_rollback >/dev/null
  grep -q '^old$' "$TMP/bk-rb-file"   # restored in place
  [ ! -e "$SETUP_TRASH_DIR" ]         # nothing went to quarantine, no manifest
)

# ── python fallback (no jq): deferred undo and commit cleanup still run the
#    exported setup_trash_mv in-shell (a subprocess could not exec a function) ─
if command -v python3 >/dev/null 2>&1; then
  (
    _tx_have_jq() { return 1; }
    SETUP_TRASH_DIR="$TMP/trash-nojq"
    TX_LOG="$TMP/tx-nojq.jsonl"
    TX_LOCK_DIR="$TX_LOG.lock"
    tx_init
    printf 'old\n' > "$TMP/nj-file"
    tx_backup_path "test:backup" "$TMP/nj-file" "$TMP/nj-file.bak"
    tx_commit >/dev/null
    [ ! -e "$TMP/nj-file.bak" ]
    grep -q "^$TMP/nj-file -> " "$SETUP_TRASH_DIR/MANIFEST"
  )
  (
    _tx_have_jq() { return 1; }
    SETUP_TRASH_DIR="$TMP/trash-nojq-rb"
    TX_LOG="$TMP/tx-nojq-rb.jsonl"
    TX_LOCK_DIR="$TX_LOG.lock"
    tx_init
    tx_created_path "$TMP/njr-created"
    printf 'made\n' > "$TMP/njr-created"
    tx_rollback >/dev/null
    [ ! -e "$TMP/njr-created" ]
    grep -q "^$TMP/njr-created -> " "$SETUP_TRASH_DIR/MANIFEST"
  )
fi

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
