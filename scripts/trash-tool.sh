#!/usr/bin/env bash
# Quarantine tooling for the dotfiles installer.
#
# The installer never deletes user data: rollback and replacements park items
# under <SETUP_TRASH_ROOT>/dotfiles-installer/<epoch>-<pid>-dotfiles, each dir
# carrying a MANIFEST of "origin -> stored" moves. This tool inspects and
# reverses those moves. It is scoped to the dotfiles-installer segment only;
# other quarantine segments (AI CLIs, etc.) are never touched.
#
# Usage:
#   trash-tool.sh list           per-run dirs with size, age and manifest info
#   trash-tool.sh restore <dir>  move MANIFEST items back to their origins;
#                                an origin that exists again is skipped with a
#                                warning (nothing is ever overwritten)
set -uo pipefail

TOOL_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Single source of truth for SETUP_TRASH_ROOT resolution.
source "$TOOL_ROOT/lib/trash.sh"

TRASH_BASE="$SETUP_TRASH_ROOT/dotfiles-installer"

usage() {
  sed -n 's/^# \{0,1\}//p' "${BASH_SOURCE[0]}" | sed -n '/^Usage:/,/overwritten)$/p'
  echo "Quarantine root: $TRASH_BASE"
}

trash_list() {
  [ -d "$TRASH_BASE" ] || { echo "quarantine is empty: $TRASH_BASE"; return 0; }
  local dir name epoch age size entries now found=0
  now="$(date +%s)"
  for dir in "$TRASH_BASE"/*/; do
    [ -d "$dir" ] || continue
    found=1
    name="$(basename "$dir")"
    size="$(du -sh "$dir" 2>/dev/null | cut -f1)"
    # Per-run dirs are named <epoch>-<pid>-dotfiles; age comes from that epoch.
    epoch="${name%%-*}"
    case "$epoch" in
      ''|*[!0-9]*) age="?" ;;
      *) age="$(( (now - epoch) / 86400 ))d" ;;
    esac
    if [ -f "$dir/MANIFEST" ]; then
      entries="$(wc -l < "$dir/MANIFEST" | tr -d ' ') item(s)"
    else
      entries="no manifest"
    fi
    printf '%s\t%s\t%s\t%s\n' "$name" "${size:-?}" "$age" "$entries"
  done
  [ "$found" = 1 ] || echo "quarantine is empty: $TRASH_BASE"
  return 0
}

trash_restore() {
  local arg="$1" name dir
  name="$(basename "$arg")"
  case "$name" in
    ''|.|..) echo "restore: invalid quarantine dir name: $arg" >&2; return 2 ;;
  esac
  dir="$TRASH_BASE/$name"
  # Accept a bare dir name or a path, but only when it resolves INSIDE the
  # dotfiles-installer segment; anything else is not ours to restore.
  if [ "$arg" != "$name" ] && [ "$(cd "$arg" 2>/dev/null && pwd)" != "$dir" ]; then
    echo "restore: $arg is not under $TRASH_BASE" >&2
    return 2
  fi
  [ -d "$dir" ] || { echo "restore: no quarantine dir: $dir" >&2; return 2; }
  [ -f "$dir/MANIFEST" ] || {
    echo "restore: $dir has no MANIFEST; inspect and restore it by hand" >&2
    return 2
  }
  local line origin stored restored=0 skipped=0 failed=0
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    # MANIFEST lines read "origin -> stored". Split on the LAST " -> ", then
    # validate BOTH sides: a tampered manifest (or a filename containing the
    # separator, which mis-splits) must never move anything outside this
    # quarantine dir or to a relative destination.
    origin="${line% -> *}"
    stored="${line##* -> }"
    { [ -n "$origin" ] && [ -n "$stored" ] && [ "$origin" != "$line" ]; } || continue
    case "$stored" in
      "$dir"/*) ;;
      *) echo "  skip (stored path outside this quarantine dir): $stored" >&2
         skipped=$((skipped + 1)); continue ;;
    esac
    case "$origin" in
      /*) ;;
      *) echo "  skip (relative origin): $origin" >&2
         skipped=$((skipped + 1)); continue ;;
    esac
    if [ ! -e "$stored" ] && [ ! -L "$stored" ]; then
      echo "  gone (already restored?): $stored"
      continue
    fi
    if [ -e "$origin" ] || [ -L "$origin" ]; then
      echo "  skip (already exists): $origin"
      skipped=$((skipped + 1))
      continue
    fi
    if mkdir -p "$(dirname "$origin")" 2>/dev/null && mv "$stored" "$origin" 2>/dev/null; then
      echo "  restored: $origin"
      restored=$((restored + 1))
    else
      echo "  FAILED to restore: $origin" >&2
      failed=$((failed + 1))
    fi
  done < "$dir/MANIFEST"
  echo "restore: $restored restored, $skipped skipped, $failed failed ($dir)"
  [ "$failed" -eq 0 ] || return 1
  return 0
}

case "${1:-}" in
  list)
    trash_list
    ;;
  restore)
    [ -n "${2:-}" ] || { usage >&2; exit 2; }
    trash_restore "$2"
    ;;
  -h|--help|help)
    usage
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac
