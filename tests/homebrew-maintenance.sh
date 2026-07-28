#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/state" "$TMP/home" "$TMP/dotfiles/lib/packages" "$TMP/dotfiles/config"
ln -s "$ROOT/lib/transaction.sh" "$TMP/dotfiles/lib/transaction.sh"
ln -s "$ROOT/lib/exec.sh" "$TMP/dotfiles/lib/exec.sh"
ln -s "$ROOT/lib/packages/brew.sh" "$TMP/dotfiles/lib/packages/brew.sh"
ln -s "$ROOT/lib/packages/catalog.sh" "$TMP/dotfiles/lib/packages/catalog.sh"
ln -s "$ROOT/config/packages.tsv" "$TMP/dotfiles/config/packages.tsv"

cat > "$TMP/bin/brew" <<'SH'
#!/bin/sh
printf '%s\n' "$*" >> "$BREW_CALLS"
case "$1 $2 $3" in
  "outdated --formula --quiet") printf 'git\n' ;;
  "list --formula ") printf 'tldr\n' ;;   # bare listing: a legacy tldr install
  "list --formula gh") exit 1 ;;
  "list --formula "*) exit 0 ;;
esac
exit 0
SH
chmod +x "$TMP/bin/brew"

HOME="$TMP/home" \
PATH="$TMP/bin:/usr/bin:/bin" \
XDG_STATE_HOME="$TMP/state" \
BREW_CALLS="$TMP/brew.calls" \
DOTFILES_DIR="$TMP/dotfiles" \
TX_LOG="$TMP/tx.jsonl" \
OS_TYPE=Darwin \
  bash "$ROOT/steps/01-packages.sh"

grep -qx 'install gh' "$TMP/brew.calls"
grep -qx 'upgrade git' "$TMP/brew.calls"
if grep -q '^install .*neovim' "$TMP/brew.calls"; then
  echo "installed an already-present formula" >&2
  exit 1
fi
grep -q 'brew_install:gh' "$TMP/tx.jsonl"
if grep -q 'brew_install:git\|brew_install:neovim' "$TMP/tx.jsonl"; then
  echo "rollback recorded a pre-existing formula" >&2
  exit 1
fi

# The pre-existing legacy tldr is removed, but only AFTER recording its
# reinstall as the undo, so rollback restores it.
grep -qx 'unlink tldr' "$TMP/brew.calls"
grep -qx 'uninstall tldr' "$TMP/brew.calls"
grep -q 'brew_replace:tldr' "$TMP/tx.jsonl"

echo "Homebrew maintenance test passed."
