#!/usr/bin/env bash
# Small, non-secret checkpoint store shared by installer orchestrators.

DOTFILES_STATE_DIR="${DOTFILES_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles}"
DOTFILES_STATE_FILE="${DOTFILES_STATE_FILE:-$DOTFILES_STATE_DIR/setup.state}"

state_get() {
  local key="$1"
  [ -f "$DOTFILES_STATE_FILE" ] || return 1
  awk -F= -v wanted="$key" '$1 == wanted { sub(/^[^=]*=/, ""); value=$0; found=1 } END { if (found) print value; else exit 1 }' \
    "$DOTFILES_STATE_FILE"
}

state_set() {
  local key="$1" value="$2" tmp
  case "$key" in
    ''|*[!A-Za-z0-9._-]*) return 2 ;;
  esac
  case "$value" in
    *$'\n'*) return 2 ;;
  esac

  mkdir -p "$DOTFILES_STATE_DIR"
  tmp="$DOTFILES_STATE_FILE.tmp.$$"
  if [ -f "$DOTFILES_STATE_FILE" ]; then
    awk -F= -v unwanted="$key" '$1 != unwanted' "$DOTFILES_STATE_FILE" > "$tmp"
  else
    : > "$tmp"
  fi
  printf '%s=%s\n' "$key" "$value" >> "$tmp"
  mv "$tmp" "$DOTFILES_STATE_FILE"
}

state_unset() {
  local key="$1" tmp
  [ -f "$DOTFILES_STATE_FILE" ] || return 0
  tmp="$DOTFILES_STATE_FILE.tmp.$$"
  awk -F= -v unwanted="$key" '$1 != unwanted' "$DOTFILES_STATE_FILE" > "$tmp"
  mv "$tmp" "$DOTFILES_STATE_FILE"
}

state_is() {
  [ "$(state_get "$1" 2>/dev/null || true)" = "$2" ]
}

export DOTFILES_STATE_DIR DOTFILES_STATE_FILE
export -f state_get state_set state_unset state_is 2>/dev/null || true
