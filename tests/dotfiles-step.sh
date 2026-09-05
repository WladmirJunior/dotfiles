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

run_step() {  # run_step HOME_DIR GIT_INCLUDES GIT_CALLS TX_LOG [OS_TYPE]
  mkdir -p "$1"
  HOME="$1" \
  PATH="$TMP/bin:/usr/bin:/bin" \
  GIT_INCLUDES="$2" \
  GIT_CALLS="$3" \
  TX_LOG="$4" \
  SETUP_TRASH_ROOT="$TMP/trash-root" \
  DOTFILES_DIR="$ROOT" \
  OS_TYPE="${5:-Linux}" \
    bash "$ROOT/steps/03-dotfiles.sh" >/dev/null
}

# 1) No pre-existing include: the entry is added and its removal is recorded.
run_step "$TMP/home-a" "" "$TMP/git-a.calls" "$TMP/tx-a.jsonl"
grep -q "^config --global include.path $TMP/home-a/.gitconfig.delta$" "$TMP/git-a.calls"
grep -q 'git_include_path' "$TMP/tx-a.jsonl"
# ~/dev creation is journaled (tx_mkdir), not a raw mkdir rollback cannot see.
[ -d "$TMP/home-a/dev" ]
grep -q "mkdir:$TMP/home-a/dev" "$TMP/tx-a.jsonl"

# 1b) macOS run: the ~/Developer and ~/.local/bin/timeout symlinks are
# journaled through tx_symlink instead of raw ln -sfn.
cat > "$TMP/bin/gtimeout" <<'SH'
#!/bin/sh
exit 0
SH
chmod +x "$TMP/bin/gtimeout"
run_step "$TMP/home-mac" "" "$TMP/git-mac.calls" "$TMP/tx-mac.jsonl" Darwin
[ -L "$TMP/home-mac/Developer" ]
[ "$(readlink "$TMP/home-mac/Developer")" = "$TMP/home-mac/dev" ]
grep -q "symlink:$TMP/home-mac/Developer" "$TMP/tx-mac.jsonl"
# (target not pinned: a macOS host may resolve the homebrew gnubin path
# instead of the stubbed gtimeout; the journal entry is the contract here)
[ -L "$TMP/home-mac/.local/bin/timeout" ]
grep -q "symlink:$TMP/home-mac/.local/bin/timeout" "$TMP/tx-mac.jsonl"

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

# 4) ~/.zshenv: written as a real file (never a symlink into the repo, which a
# later `cat >` would write through), sourcing the repo copy and the local
# overlay. It is what gives non-interactive `ssh host cmd` a usable PATH.
[ -f "$TMP/home-a/.zshenv" ] || { echo "step 03 did not write ~/.zshenv" >&2; exit 1; }
[ -L "$TMP/home-a/.zshenv" ] && { echo "~/.zshenv must be a real file, not a symlink" >&2; exit 1; }
grep -qF "$ROOT/config/zsh/zshenv" "$TMP/home-a/.zshenv"
grep -qF '.zshenv.local' "$TMP/home-a/.zshenv"
grep -q "created:$TMP/home-a/.zshenv" "$TMP/tx-a.jsonl"

# 4b) A pre-existing ~/.zshenv is backed up through the transaction (restored on
# rollback), never blind-overwritten.
mkdir -p "$TMP/home-e"
printf 'export MINE=1\n' > "$TMP/home-e/.zshenv"
run_step "$TMP/home-e" "" "$TMP/git-e.calls" "$TMP/tx-e.jsonl"
grep -q 'write:.zshenv' "$TMP/tx-e.jsonl"
grep -qF "$ROOT/config/zsh/zshenv" "$TMP/home-e/.zshenv"

# 4c) Idempotent: a second run over an already-managed ~/.zshenv rewrites
# nothing and records no new backup.
run_step "$TMP/home-e" "" "$TMP/git-e2.calls" "$TMP/tx-e2.jsonl"
if grep -q 'write:.zshenv' "$TMP/tx-e2.jsonl" 2>/dev/null; then
  echo "step 03 rewrote an already-managed ~/.zshenv" >&2
  exit 1
fi

# 4d) The repo zshenv must not grow PATH when sourced repeatedly (nested
# shells source it again; an unguarded prepend would duplicate the entry).
dup="$(PATH=/opt/homebrew/bin:/usr/bin:/bin zsh -c '
  . '"$ROOT"'/config/zsh/zshenv; . '"$ROOT"'/config/zsh/zshenv
  print -r -- $PATH' 2>/dev/null | tr ':' '\n' | grep -c '^/opt/homebrew/bin$' || true)"
if [ -n "$dup" ] && [ "$dup" -gt 1 ]; then
  echo "config/zsh/zshenv duplicated /opt/homebrew/bin in PATH ($dup times)" >&2
  exit 1
fi

echo "Dotfiles step tests passed."
