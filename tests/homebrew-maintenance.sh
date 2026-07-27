#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/dotfiles/lib" "$TMP/state"

cat > "$TMP/bin/brew" <<'SH'
#!/bin/sh
printf '%s\n' "$*" >> "$BREW_CALLS"
case "$1 $2 $3" in
  "outdated --formula --quiet") printf 'git\n' ;;
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
OS_TYPE=Darwin \
  bash "$ROOT/steps/01-packages.sh"

grep -qx 'install gh' "$TMP/brew.calls"
grep -qx 'upgrade git' "$TMP/brew.calls"
if grep -q '^install .*neovim' "$TMP/brew.calls"; then
  echo "installed an already-present formula" >&2
  exit 1
fi

echo "Homebrew maintenance test passed."
