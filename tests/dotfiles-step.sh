#!/usr/bin/env bash
# steps/03-dotfiles.sh: the git include.path undo is recorded only when this
# run actually adds the entry; a pre-existing entry gets no --unset undo.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin"

# git mock: --get-all include.path prints GIT_INCLUDES (or fails when empty);
# every call is recorded for assertions.
cat > "$TMP/bin/git" <<'SH'
#!/bin/sh
printf '%s\n' "$*" >> "$GIT_CALLS"
case "$*" in
  "config --global --get-all include.path")
    [ -n "$GIT_INCLUDES" ] || exit 1
    printf '%s\n' "$GIT_INCLUDES"
    ;;
esac
exit 0
SH
# ya stub: keep the yazi plugin install inert even when the host has yazi.
cat > "$TMP/bin/ya" <<'SH'
#!/bin/sh
exit 0
SH
chmod +x "$TMP/bin/git" "$TMP/bin/ya"

run_step() {  # run_step HOME_DIR GIT_INCLUDES GIT_CALLS TX_LOG
  mkdir -p "$1"
  HOME="$1" \
  PATH="$TMP/bin:/usr/bin:/bin" \
  GIT_INCLUDES="$2" \
  GIT_CALLS="$3" \
  TX_LOG="$4" \
  SETUP_TRASH_ROOT="$TMP/trash-root" \
  DOTFILES_DIR="$ROOT" \
  OS_TYPE=Linux \
    bash "$ROOT/steps/03-dotfiles.sh" >/dev/null
}

# 1) No pre-existing include: the entry is added and its removal is recorded.
run_step "$TMP/home-a" "" "$TMP/git-a.calls" "$TMP/tx-a.jsonl"
grep -q "^config --global include.path $TMP/home-a/.gitconfig.delta$" "$TMP/git-a.calls"
grep -q 'git_include_path' "$TMP/tx-a.jsonl"

# 2) Entry already present before the run: no re-set, and NO --unset undo that
# would strip the user's pre-existing config on rollback.
run_step "$TMP/home-b" "$TMP/home-b/.gitconfig.delta" "$TMP/git-b.calls" "$TMP/tx-b.jsonl"
if grep -q "^config --global include.path " "$TMP/git-b.calls"; then
  echo "step 03 re-set a pre-existing include.path" >&2
  exit 1
fi
if grep -q 'git_include_path' "$TMP/tx-b.jsonl" 2>/dev/null; then
  echo "step 03 recorded an unset undo for a pre-existing include.path" >&2
  exit 1
fi

# 3) The yazi plugin is cosmetic: a failing `ya pkg install` must warn and let
# the step complete instead of aborting it under set -e.
cat > "$TMP/bin/ya" <<'SH'
#!/bin/sh
exit 1
SH
chmod +x "$TMP/bin/ya"
run_step "$TMP/home-c" "" "$TMP/git-c.calls" "$TMP/tx-c.jsonl" 2> "$TMP/step-c.err" \
  || { echo "step 03 aborted on a failed yazi plugin install" >&2; exit 1; }
grep -q 'yazi plugin install failed; continuing' "$TMP/step-c.err"

# 3b) Same tolerance on the refresh path (plugin dir already present).
mkdir -p "$TMP/home-d/.config/yazi/plugins/git.yazi"
run_step "$TMP/home-d" "" "$TMP/git-d.calls" "$TMP/tx-d.jsonl" 2> "$TMP/step-d.err" \
  || { echo "step 03 aborted on a failed yazi plugin refresh" >&2; exit 1; }
grep -q 'yazi plugin install failed; continuing' "$TMP/step-d.err"

echo "Dotfiles step tests passed."
