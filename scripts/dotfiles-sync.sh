#!/usr/bin/env bash
# dotfiles-sync — interactive helper to commit + push + pull the synchronized
# set of repos across corp ↔ personal Macs.
#
# Repos synced (from reference_dotfiles_sync_set):
#   ~/.dotfiles          (public)
#   ~/.***REMOVED***  (private)
#   ~/.***REMOVED***       (Nubank-only, work mac only)
#   ~/dev/sonus          (voice stack)
#
# Modes:
#   dotfiles-sync          interactive: detect changes, prompt to commit, push all
#   dotfiles-sync --pull   pull-only on every repo (use on the receiving mac)
#   dotfiles-sync --status read-only status of every repo
#   dotfiles-sync --dry    show actions but don't run git
#
# Conflicts: this script never resolves conflicts. If `git pull --ff-only` fails,
# it stops on that repo and tells you. Resolution is manual on whichever side
# has the divergent commits.

set -uo pipefail

DRY=0
MODE="interactive"
for arg in "$@"; do
  case "$arg" in
    --pull)   MODE="pull" ;;
    --status) MODE="status" ;;
    --dry|-n) DRY=1 ;;
    -h|--help)
      sed -n '2,25p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "Unknown arg: $arg" >&2
      exit 2
      ;;
  esac
done

# Try to use the public ui.sh if present, else fall back to plain echo.
DOTFILES_DIR="$HOME/.dotfiles"
if [ -f "$DOTFILES_DIR/lib/ui.sh" ]; then
  # shellcheck disable=SC1091
  source "$DOTFILES_DIR/lib/ui.sh" 2>/dev/null || true
fi
command -v banner >/dev/null 2>&1 || banner() { printf '\n=== %s ===\n' "$*"; }
command -v ok     >/dev/null 2>&1 || ok()     { printf '✓ %s\n' "$*"; }
command -v note   >/dev/null 2>&1 || note()   { printf '  %s\n' "$*"; }
command -v info   >/dev/null 2>&1 || info()   { printf 'i %s\n' "$*"; }
command -v task   >/dev/null 2>&1 || task()   { printf '\n→ %s\n' "$*"; }

# Detect if this is the work mac. Only on work mac we touch ***REMOVED***.
IS_WORK_MAC=0
if [ -d "/Library/Application Support/JAMF" ] \
  || [ -f "/Library/LaunchDaemons/com.zscaler.tunnel.plist" ] \
  || [[ "$(hostname -s 2>/dev/null)" == *nubank* ]] \
  || [[ "$(hostname -s 2>/dev/null)" == wladmir-* ]]; then
  IS_WORK_MAC=1
fi

REPOS=(
  "$HOME/.dotfiles"
  "$HOME/.***REMOVED***"
)
[ "$IS_WORK_MAC" = 1 ] && REPOS+=("$HOME/.***REMOVED***")
REPOS+=("$HOME/dev/sonus")

run() {
  if [ "$DRY" = 1 ]; then
    echo "  [dry] $*"
  else
    "$@"
  fi
}

confirm_yn() {
  local prompt="$1"
  read -r -p "$prompt (y/N) " ans
  case "$ans" in
    y|Y|yes|YES) return 0 ;;
    *)           return 1 ;;
  esac
}

repo_status() {
  local repo="$1"
  [ -d "$repo/.git" ] || { echo "  (no repo)"; return 1; }
  local name; name="$(basename "$repo")"
  local branch; branch=$(git -C "$repo" rev-parse --abbrev-ref HEAD 2>/dev/null)
  local ahead behind
  git -C "$repo" fetch --quiet 2>/dev/null || true
  ahead=$(git -C "$repo"  rev-list --count "@{u}..HEAD" 2>/dev/null || echo 0)
  behind=$(git -C "$repo" rev-list --count "HEAD..@{u}" 2>/dev/null || echo 0)
  local dirty="clean"
  if [ -n "$(git -C "$repo" status --porcelain 2>/dev/null)" ]; then
    dirty="dirty"
  fi
  printf '  %-22s branch=%s ahead=%s behind=%s %s\n' "$name" "$branch" "$ahead" "$behind" "$dirty"
}

do_status() {
  banner "dotfiles-sync · status"
  for repo in "${REPOS[@]}"; do
    [ -d "$repo" ] || { printf '  %-22s (missing on disk)\n' "$(basename "$repo")"; continue; }
    repo_status "$repo"
  done
}

do_pull() {
  banner "dotfiles-sync · pull"
  local fail=0
  for repo in "${REPOS[@]}"; do
    [ -d "$repo/.git" ] || continue
    task "$(basename "$repo")"
    if [ -n "$(git -C "$repo" status --porcelain 2>/dev/null)" ]; then
      note "skipped: working tree dirty"
      fail=$((fail + 1))
      continue
    fi
    if run git -C "$repo" pull --ff-only --quiet; then
      ok "fast-forwarded"
    else
      note "pull --ff-only failed (diverged or no upstream)"
      fail=$((fail + 1))
    fi
  done
  [ "$fail" -gt 0 ] && note "$fail repo(s) need manual attention"
  return "$fail"
}

do_interactive() {
  banner "dotfiles-sync · interactive"

  # Phase 1: pull first to minimize merge conflicts
  task "Pull (fast-forward only) before committing"
  for repo in "${REPOS[@]}"; do
    [ -d "$repo/.git" ] || continue
    local name; name="$(basename "$repo")"
    if [ -n "$(git -C "$repo" status --porcelain 2>/dev/null)" ]; then
      note "$name: skipped (dirty)"
      continue
    fi
    if run git -C "$repo" pull --ff-only --quiet 2>/dev/null; then
      note "$name: up to date"
    else
      note "$name: pull skipped (no upstream or diverged)"
    fi
  done

  # Phase 2: per-repo commit prompt
  for repo in "${REPOS[@]}"; do
    [ -d "$repo/.git" ] || continue
    local name; name="$(basename "$repo")"
    local changes; changes=$(git -C "$repo" status --porcelain 2>/dev/null)
    if [ -z "$changes" ]; then
      continue
    fi
    task "$name has uncommitted changes"
    echo "$changes" | head -20 | sed 's/^/    /'
    local count; count=$(echo "$changes" | wc -l | tr -d ' ')
    [ "$count" -gt 20 ] && note "(showing first 20 of $count files)"

    if confirm_yn "Commit and push $name?"; then
      read -r -p "Commit message: " msg
      [ -z "$msg" ] && { note "skipped (empty message)"; continue; }
      run git -C "$repo" add -A
      run git -C "$repo" commit -m "$msg"
      run git -C "$repo" push
      ok "$name pushed"
    else
      note "$name: skipped"
    fi
  done

  do_status
}

case "$MODE" in
  status)      do_status ;;
  pull)        do_pull ;;
  interactive) do_interactive ;;
esac
