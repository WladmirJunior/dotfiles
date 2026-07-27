#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin"

cat > "$TMP/bin/brew" <<'SH'
#!/bin/sh
exit 0
SH
chmod +x "$TMP/bin/brew"

output="$(
  HOME="$TMP/home" \
  PATH="$TMP/bin:/usr/bin:/bin" \
  DOTFILES_DIR="$ROOT" \
  OS_TYPE=Darwin \
  DRY_RUN=1 \
  WANT_TMUX=yes \
    bash "$ROOT/steps/01-packages.sh"
)"

grep -Fq '[dry-run] brew install tmux' <<<"$output"
echo "Optional tmux install test passed."
