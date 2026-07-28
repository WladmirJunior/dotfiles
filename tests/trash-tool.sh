#!/usr/bin/env bash
# scripts/trash-tool.sh: quarantine tooling scoped to the installer's own
# <root>/dotfiles-installer segment. `list` shows each per-run dir with size,
# age and manifest entries; `restore <dir>` moves MANIFEST items back to their
# original paths, skipping (never overwriting) paths that exist again.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

export SETUP_TRASH_ROOT="$TMP/trash-root"
BASE="$SETUP_TRASH_ROOT/dotfiles-installer"

# One quarantine dir with a manifest: a restorable item (origin gone) and a
# conflicting one (origin exists again).
RUN1="$BASE/1700000000-123-dotfiles"
mkdir -p "$RUN1/clone-repo" "$TMP/home"
printf 'hello\n' > "$RUN1/replaced-zshrc"
printf 'x\n' > "$RUN1/clone-repo/f"
ORIG_GONE="$TMP/home/.zshrc"       # does not exist -> must be restored
ORIG_KEPT="$TMP/home/repo"         # exists -> must be skipped, item kept
mkdir -p "$ORIG_KEPT"
{
  printf '%s -> %s\n' "$ORIG_GONE" "$RUN1/replaced-zshrc"
  printf '%s -> %s\n' "$ORIG_KEPT" "$RUN1/clone-repo"
} > "$RUN1/MANIFEST"

# A second quarantine dir without a manifest (older runs / manual moves).
RUN2="$BASE/1800000000-9-dotfiles"
mkdir -p "$RUN2"
printf 'y\n' > "$RUN2/orphan"

# ── list: every per-run dir with size, age and manifest summary ──────────────
bash "$ROOT/scripts/trash-tool.sh" list > "$TMP/list.out"
grep -q '1700000000-123-dotfiles' "$TMP/list.out"
grep -q '1800000000-9-dotfiles' "$TMP/list.out"
grep -q '2 item(s)' "$TMP/list.out"
grep -q 'no manifest' "$TMP/list.out"

# ── restore: origin gone -> moved back; origin present -> skip with warning ──
bash "$ROOT/scripts/trash-tool.sh" restore 1700000000-123-dotfiles > "$TMP/restore.out"
[ -f "$ORIG_GONE" ]
grep -q hello "$ORIG_GONE"
[ ! -e "$RUN1/replaced-zshrc" ]
grep -q "skip (already exists): $ORIG_KEPT" "$TMP/restore.out"
[ -d "$RUN1/clone-repo" ]   # the conflicting item stays parked in quarantine
grep -q '1 restored, 1 skipped, 0 failed' "$TMP/restore.out"

# Re-running the same restore is safe: nothing to do, nothing clobbered.
bash "$ROOT/scripts/trash-tool.sh" restore "$RUN1" > "$TMP/restore2.out"
grep -q '0 restored, 1 skipped, 0 failed' "$TMP/restore2.out"
grep -q hello "$ORIG_GONE"

# ── only the dotfiles-installer segment is restorable ────────────────────────
mkdir -p "$TMP/elsewhere/dirx"
rc=0; bash "$ROOT/scripts/trash-tool.sh" restore "$TMP/elsewhere/dirx" \
  > "$TMP/outside.out" 2>&1 || rc=$?
[ "$rc" -eq 2 ] || { echo "restore outside the quarantine was not refused" >&2; exit 1; }
[ -d "$TMP/elsewhere/dirx" ]

# ── a dir without MANIFEST cannot be auto-restored ───────────────────────────
rc=0; bash "$ROOT/scripts/trash-tool.sh" restore 1800000000-9-dotfiles \
  > "$TMP/nomanifest.out" 2>&1 || rc=$?
[ "$rc" -eq 2 ]
[ -f "$RUN2/orphan" ]   # nothing was moved

echo "Trash tool tests passed."
