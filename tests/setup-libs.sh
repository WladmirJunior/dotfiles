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
SETUP_TRASH_ROOT="$TMP/trash-root"   # keep tx_commit's prune away from the real quarantine
source "$ROOT/lib/transaction.sh"
[ "$DOTFILES_INSTALLER_API" = 1 ]
SETUP_TRASH_DIR="$TMP/trash"
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
compgen -G "$TMP/trash/backup-config-*" >/dev/null

tx_init
mkdir "$TMP/new-clone"
printf 'partial\n' > "$TMP/new-clone/file"
tx_git_clone example.invalid/repo "$TMP/new-clone"
tx_rollback >/dev/null
[ ! -e "$TMP/new-clone" ]
compgen -G "$TMP/trash/clone-new-clone-*/file" >/dev/null

tx_init
tx_created_path "$TMP/generated"
mkdir "$TMP/generated"
printf 'generated\n' > "$TMP/generated/file"
tx_rollback >/dev/null
[ ! -e "$TMP/generated" ]
compgen -G "$TMP/trash/created-generated-*/file" >/dev/null

tx_init
tx_symlink "$TMP/config" "$TMP/new-link"
[ -L "$TMP/new-link" ]
tx_rollback >/dev/null
[ ! -e "$TMP/new-link" ]
compgen -G "$TMP/trash/link-new-link-*" >/dev/null

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

source "$ROOT/lib/setup/report.sh"
DOTFILES_REPORT_FILE="$TMP/report"
DOTFILES_REPORT_OWNER=test
setup_report_add public packages unchanged 'already current'
setup_report_step private apps 0 1 3
setup_report_step nu certs 1 3 3 'certificate setup failed'
grep -qx 'public|packages|unchanged|already current' "$TMP/report"
grep -qx 'private|apps|changed|2 recorded change(s)' "$TMP/report"
grep -qx 'nu|certs|failed|certificate setup failed' "$TMP/report"

echo "Shared setup library tests passed."
