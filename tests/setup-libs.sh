#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

source "$ROOT/lib/exec.sh"
DRY_RUN=1 run touch "$TMP/dry-run-created"
[ ! -e "$TMP/dry-run-created" ]
DRY_RUN=0 run_logged "logged command" "$TMP/command.log" sh -c 'printf success'
grep -qx success "$TMP/command.log"

DOTFILES_STATE_DIR="$TMP/state"
DOTFILES_STATE_FILE="$DOTFILES_STATE_DIR/setup.state"
source "$ROOT/lib/state.sh"
state_set public.base complete
state_set private.base pending
state_is public.base complete
[ "$(state_get private.base)" = pending ]
state_unset private.base
! state_get private.base >/dev/null

TX_LOG="$TMP/tx.jsonl"
TX_LAST="$TMP/tx.last.jsonl"
source "$ROOT/lib/transaction.sh"
[ "$DOTFILES_INSTALLER_API" = 1 ]
printf 'original\n' > "$TMP/config"
tx_init
tx_backup_path "backup:test" "$TMP/config" "$TMP/config.backup"
printf 'replacement\n' > "$TMP/config"
tx_rollback >/dev/null
grep -qx original "$TMP/config"

printf 'original\n' > "$TMP/config"
tx_init
tx_backup_path "backup:test" "$TMP/config" "$TMP/config.backup"
printf 'replacement\n' > "$TMP/config"
tx_commit
[ ! -e "$TMP/config.backup" ]
grep -qx replacement "$TMP/config"

source "$ROOT/lib/setup/selection.sh"
component_installed() {
  case "$1" in app-a|app-c) return 0 ;; *) return 1 ;; esac
}
pick() {
  printf '%s\n' "$PICK_SELECTED" > "$TMP/preselected"
  printf 'App A,App B\n'
}
SELECTION_FORCE_PROMPT=1
maintenance_select component_installed WANT_APPS REMOVE_APPS "Applications" \
  'app-a|App A' 'app-b|App B' 'app-c|App C'
[ "$WANT_APPS" = app-b ]
[ "$REMOVE_APPS" = app-c ]
[ "$(cat "$TMP/preselected")" = 'App A,App C' ]

echo "Shared setup library tests passed."
