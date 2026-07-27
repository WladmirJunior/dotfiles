#!/usr/bin/env bash
# Plan / preview mode for the dotfiles installer.
#
# `--plan` runs steps with DRY_RUN=1 PLAN_MODE=1 and captures every announced
# change (file writes, package installs, symlinks). At the end it shows a
# compact, color-coded summary so you can review before re-running for real.
#
# Steps opt in to plan-aware output by calling these helpers instead of doing
# the change directly:
#   plan_file_change   "$dst" "$rendered_or_new_content"
#   plan_pkg_install   brew "ripgrep" "jq"
#   plan_pkg_install   cask "ghostty"
#   plan_symlink       "$src" "$dst"
#   plan_dir_create    "$path"
#
# When PLAN_MODE=0 (default) they fall through to real execution. When
# PLAN_MODE=1 they record the intent into PLAN_LOG and stay no-op.

set -uo pipefail

# Records: one line per planned change. Format: "CATEGORY|ACTION|DETAIL".
# CATEGORY in: file, pkg, link, dir
# ACTION   in: create, update, replace, install (pkg), skip (no change)
PLAN_LOG="${PLAN_LOG:-${TMPDIR:-/tmp}/dotfiles-plan-$$.log}"
: > "$PLAN_LOG"
export PLAN_LOG

plan_record() {
  # category | action | detail
  printf '%s\n' "$1|$2|$3" >> "$PLAN_LOG"
}

# plan_file_change DST CONTENT
# CONTENT is the new content as a string. Compares with existing dst.
plan_file_change() {
  local dst="$1" new="$2"
  local action
  if [ ! -f "$dst" ]; then
    action="create"
  elif [ "$(cat "$dst")" = "$new" ]; then
    action="skip"
  else
    action="update"
  fi
  plan_record file "$action" "$dst"
  if [ "${PLAN_MODE:-0}" = "0" ]; then
    mkdir -p "$(dirname "$dst")"
    if [ "$action" != "skip" ]; then
      [ -f "$dst" ] && cp "$dst" "$dst.bak"
      printf '%s' "$new" > "$dst"
    fi
  fi
}

# plan_pkg_install TYPE PKG [PKG...]
# TYPE: brew | cask | apt | pacman | npm | pip
plan_pkg_install() {
  local type="$1"; shift
  local pkg
  for pkg in "$@"; do
    local installed=0
    case "$type" in
      brew)
        command -v brew >/dev/null 2>&1 && brew list --formula --versions "$pkg" >/dev/null 2>&1 && installed=1
        ;;
      cask)
        command -v brew >/dev/null 2>&1 && brew list --cask --versions "$pkg" >/dev/null 2>&1 && installed=1
        ;;
      apt)
        dpkg -s "$pkg" >/dev/null 2>&1 && installed=1
        ;;
      pacman)
        command -v pacman >/dev/null 2>&1 && pacman -Q "$pkg" >/dev/null 2>&1 && installed=1
        ;;
      npm)
        command -v npm >/dev/null 2>&1 && npm list -g --depth=0 "$pkg" >/dev/null 2>&1 && installed=1
        ;;
      pip)
        command -v pip3 >/dev/null 2>&1 && pip3 show "$pkg" >/dev/null 2>&1 && installed=1
        ;;
    esac
    if [ "$installed" = 1 ]; then
      plan_record pkg "skip" "$type:$pkg"
    else
      plan_record pkg "install" "$type:$pkg"
      if [ "${PLAN_MODE:-0}" = "0" ]; then
        case "$type" in
          brew) brew install "$pkg" ;;
          cask) brew install --cask "$pkg" ;;
          apt)  sudo apt-get install -y "$pkg" ;;
          pacman) sudo pacman -S --needed --noconfirm "$pkg" ;;
          npm)  npm install -g "$pkg" ;;
          pip)  pip3 install --user "$pkg" ;;
        esac
      fi
    fi
  done
}

# plan_symlink SRC DST
plan_symlink() {
  local src="$1" dst="$2"
  local action
  if [ -L "$dst" ] && [ "$(readlink "$dst")" = "$src" ]; then
    action="skip"
  elif [ -e "$dst" ]; then
    action="replace"
  else
    action="create"
  fi
  plan_record link "$action" "$dst -> $src"
  if [ "${PLAN_MODE:-0}" = "0" ] && [ "$action" != "skip" ]; then
    mkdir -p "$(dirname "$dst")"
    [ -e "$dst" ] && [ ! -L "$dst" ] && cp -r "$dst" "$dst.bak"
    ln -sfn "$src" "$dst"
  fi
}

plan_dir_create() {
  local path="$1"
  if [ -d "$path" ]; then
    plan_record dir "skip" "$path"
  else
    plan_record dir "create" "$path"
    [ "${PLAN_MODE:-0}" = "0" ] && mkdir -p "$path"
  fi
}

# plan_summary: print the captured plan as a categorized summary.
# Output respects NO_COLOR.
plan_summary() {
  if [ ! -s "$PLAN_LOG" ]; then
    echo "  (no changes planned)"
    return 0
  fi

  local C_CREATE="" C_UPDATE="" C_REPLACE="" C_INSTALL="" C_SKIP="" C_RESET=""
  if [ -z "${NO_COLOR:-}" ] && [ -t 1 ]; then
    C_CREATE=$'\033[32m'    # green
    C_UPDATE=$'\033[33m'    # yellow
    C_REPLACE=$'\033[35m'   # magenta
    C_INSTALL=$'\033[36m'   # cyan
    C_SKIP=$'\033[90m'      # gray
    C_RESET=$'\033[0m'
  fi

  local total=0 creates=0 updates=0 replaces=0 installs=0 skips=0
  while IFS='|' read -r cat action detail; do
    total=$((total + 1))
    case "$action" in
      create)  creates=$((creates + 1)) ;;
      update)  updates=$((updates + 1)) ;;
      replace) replaces=$((replaces + 1)) ;;
      install) installs=$((installs + 1)) ;;
      skip)    skips=$((skips + 1)) ;;
    esac
  done < "$PLAN_LOG"

  printf '\n  Summary: '
  printf '%screate %d%s  ' "$C_CREATE" "$creates" "$C_RESET"
  printf '%supdate %d%s  ' "$C_UPDATE" "$updates" "$C_RESET"
  printf '%sreplace %d%s  ' "$C_REPLACE" "$replaces" "$C_RESET"
  printf '%sinstall %d%s  ' "$C_INSTALL" "$installs" "$C_RESET"
  printf '%sskip %d%s\n\n' "$C_SKIP" "$skips" "$C_RESET"

  local cat action detail color symbol
  while IFS='|' read -r cat action detail; do
    case "$action" in
      create)  color="$C_CREATE";  symbol="+" ;;
      update)  color="$C_UPDATE";  symbol="~" ;;
      replace) color="$C_REPLACE"; symbol="!" ;;
      install) color="$C_INSTALL"; symbol="+" ;;
      skip)    color="$C_SKIP";    symbol="=" ;;
      *)       color="";           symbol="?" ;;
    esac
    # Skip "skip" entries by default; show with PLAN_SHOW_SKIP=1
    if [ "$action" = "skip" ] && [ "${PLAN_SHOW_SKIP:-0}" = "0" ]; then
      continue
    fi
    printf '  %s%s %-7s %-7s%s %s\n' "$color" "$symbol" "$cat" "$action" "$C_RESET" "$detail"
  done < "$PLAN_LOG"
}

# plan_reset: clear the log (call at start of install.sh)
plan_reset() {
  : > "$PLAN_LOG"
}

# plan_cleanup: remove the log file (call at end of install.sh)
plan_cleanup() {
  rm -f "$PLAN_LOG"
}

export -f plan_record plan_file_change plan_pkg_install plan_symlink plan_dir_create plan_summary plan_reset plan_cleanup
