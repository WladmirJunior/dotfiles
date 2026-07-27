#!/usr/bin/env bash
# Recoverable removal helpers shared by installer maintenance and rollback.

# Quarantine root: SETUP_TRASH_DIR wins outright; otherwise honor the shared
# agent quarantine root (AGENT_QUARANTINE_DIR) with ~/.cli-trash as fallback.
# The segment is "dotfiles-installer" because the installer runs on its own,
# outside any AI CLI.
setup_trash_dir() {
  if [ -z "${SETUP_TRASH_DIR:-}" ]; then
    SETUP_TRASH_DIR="${AGENT_QUARANTINE_DIR:-$HOME/.cli-trash}/dotfiles-installer/$(date +%s)-$$-dotfiles"
  fi
  mkdir -p "$SETUP_TRASH_DIR"
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

trash_path() {
  local path="$1" label dest
  label="${2:-$(basename "$1")}"
  [ -e "$path" ] || [ -L "$path" ] || return 0
  setup_trash_dir >/dev/null
  dest="$(setup_trash_destination "$label")"
  mv "$path" "$dest"
  SETUP_TRASH_LAST="$dest"
}

export -f setup_trash_dir setup_trash_destination trash_path 2>/dev/null || true
