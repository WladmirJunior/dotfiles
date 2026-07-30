#!/usr/bin/env bash
# Recoverable removal helpers shared by installer maintenance and rollback.

# Quarantine root: SETUP_TRASH_ROOT wins, then the shared agent quarantine root
# (AGENT_QUARANTINE_DIR), with ~/.shell-trash as fallback. The per-run dir lives
# under the "dotfiles-installer" segment because the installer runs on its own,
# outside any AI CLI. SETUP_TRASH_DIR overrides the per-run dir outright.
SETUP_TRASH_ROOT="${SETUP_TRASH_ROOT:-${AGENT_QUARANTINE_DIR:-$HOME/.shell-trash}}"

# setup_trash_dir: resolve (and print) this run's quarantine dir WITHOUT
# creating it. The dir appears on disk only when something is actually moved
# into it (setup_trash_mv / setup_trash_manifest); a fully successful install
# that parked nothing leaves no empty per-run dir behind.
setup_trash_dir() {
  if [ -z "${SETUP_TRASH_DIR:-}" ]; then
    SETUP_TRASH_DIR="$SETUP_TRASH_ROOT/dotfiles-installer/$(date +%s)-$$-dotfiles"
  fi
  printf '%s\n' "$SETUP_TRASH_DIR"
}

setup_trash_destination() {
  local label="${1:-item}" dest suffix=0
  case "$label" in
    ''|.|..) label=item ;;
  esac
  label="${label//\//_}"
  setup_trash_dir >/dev/null
  dest="$SETUP_TRASH_DIR/$label"
  while [ -e "$dest" ] || [ -L "$dest" ]; do
    suffix=$((suffix + 1))
    dest="$SETUP_TRASH_DIR/$label.$suffix"
  done
  printf '%s\n' "$dest"
}

# setup_trash_manifest ORIGIN DEST: record one quarantine move so a person can
# map every parked file back to where it came from ("origin -> destination").
# Call it only for moves that actually happened: a manifest line for an item
# that never reached the quarantine sends trash-tool restore chasing ghosts.
setup_trash_manifest() {
  setup_trash_dir >/dev/null
  mkdir -p "$SETUP_TRASH_DIR" 2>/dev/null || true
  printf '%s -> %s\n' "$1" "$2" >> "$SETUP_TRASH_DIR/MANIFEST" 2>/dev/null || true
}

# setup_trash_mv SRC DEST [MANIFEST_ORIGIN]: the single quarantine move
# primitive. Moves SRC to DEST and writes the manifest line next to DEST in
# the same act, so the manifest can never claim a move that did not happen.
# MANIFEST_ORIGIN (default SRC) is the path a restore should map the item back
# to; commit-time backup parking passes the original path, not the temporary
# backup name. Also used as a recorded undo/cleanup command (see
# lib/transaction.sh): it is exported and runs in the same shell during
# rollback/commit, keeping deferred moves and their manifest line together.
setup_trash_mv() {
  local src="$1" dest="$2" origin="${3:-$1}"
  mkdir -p "$(dirname "$dest")" 2>/dev/null
  mv "$src" "$dest" || return 1
  printf '%s -> %s\n' "$origin" "$dest" >> "$(dirname "$dest")/MANIFEST" 2>/dev/null || true
}

trash_path() {
  local path="$1" label dest
  label="${2:-$(basename "$1")}"
  [ -e "$path" ] || [ -L "$path" ] || return 0
  setup_trash_dir >/dev/null
  dest="$(setup_trash_destination "$label")"
  setup_trash_mv "$path" "$dest"
  SETUP_TRASH_LAST="$dest"
}

# setup_trash_prune: retention for the quarantine. Deletes per-run quarantine
# dirs older than SETUP_TRASH_RETENTION_DAYS (default 60), and ONLY under
# <SETUP_TRASH_ROOT>/dotfiles-installer where dir names start with their
# creation epoch ("<epoch>-<pid>-dotfiles"); anything not matching that shape
# is left alone, and nothing outside that segment is ever touched. No-op in
# dry-run. Called from tx_commit so retention only runs on successful installs.
setup_trash_prune() {
  [ "${DRY_RUN:-0}" = 1 ] && return 0
  local root="$SETUP_TRASH_ROOT/dotfiles-installer"
  [ -d "$root" ] || return 0
  local days="${SETUP_TRASH_RETENTION_DAYS:-60}" now cutoff dir name epoch
  now="$(date +%s)"
  cutoff=$((now - days * 86400))
  for dir in "$root"/*/; do
    [ -d "$dir" ] || continue
    name="$(basename "$dir")"
    epoch="${name%%-*}"
    case "$epoch" in ''|*[!0-9]*) continue ;; esac
    [ "$epoch" -lt "$cutoff" ] || continue
    [ "${dir%/}" != "${SETUP_TRASH_DIR:-}" ] || continue   # never the live dir
    rm -rf -- "$dir"
    echo "trash: pruned quarantine older than ${days}d: ${dir%/}"
  done
  return 0
}

export SETUP_TRASH_ROOT
export -f setup_trash_dir setup_trash_destination setup_trash_manifest \
  setup_trash_mv trash_path setup_trash_prune 2>/dev/null || true
