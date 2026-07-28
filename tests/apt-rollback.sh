#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/home"

cat > "$TMP/bin/apt-get" <<'SH'
#!/bin/sh
printf '%s\n' "$*" >> "$APT_CALLS"
SH

cat > "$TMP/bin/sudo" <<'SH'
#!/bin/sh
exec "$@"
SH

cat > "$TMP/bin/dpkg-query" <<'SH'
#!/bin/sh
for last_arg do :; done
case "$last_arg" in
  zsh|eza) printf 'ii \n' ;;
  *) exit 1 ;;
esac
SH

for command_name in yazi fastfetch; do
  cat > "$TMP/bin/$command_name" <<'SH'
#!/bin/sh
exit 0
SH
done
chmod +x "$TMP/bin/"*

HOME="$TMP/home" \
PATH="$TMP/bin:/usr/bin:/bin" \
APT_CALLS="$TMP/apt.calls" \
DOTFILES_DIR="$ROOT" \
TX_LOG="$TMP/tx.jsonl" \
OS_TYPE=Linux \
PACKAGE_MANAGER=apt \
  bash "$ROOT/steps/01-packages.sh"

grep -q 'apt_install:neovim' "$TMP/tx.jsonl"
grep -q 'apt_install:tealdeer' "$TMP/tx.jsonl"
if grep -q 'apt_install:zsh\|apt_install:eza' "$TMP/tx.jsonl"; then
  echo "rollback recorded a pre-existing apt package" >&2
  exit 1
fi

# ── apt-get update failure: fatal on first install, tolerated on maintenance ──
cat > "$TMP/bin/apt-get" <<'SH'
#!/bin/sh
case "$1" in update) exit 100 ;; esac
printf '%s\n' "$*" >> "$APT_CALLS"
SH
chmod +x "$TMP/bin/apt-get"

if HOME="$TMP/home" PATH="$TMP/bin:/usr/bin:/bin" APT_CALLS="$TMP/apt.calls" \
  DOTFILES_DIR="$ROOT" TX_LOG="$TMP/tx2.jsonl" OS_TYPE=Linux PACKAGE_MANAGER=apt \
  XDG_STATE_HOME="$TMP/state-first" \
  bash "$ROOT/steps/01-packages.sh" >/dev/null 2>&1; then
  echo "first install continued past a failed apt-get update" >&2
  exit 1
fi

mkdir -p "$TMP/state-maint/dotfiles"
printf 'public.base=complete\n' > "$TMP/state-maint/dotfiles/setup.state"
if ! HOME="$TMP/home" PATH="$TMP/bin:/usr/bin:/bin" APT_CALLS="$TMP/apt.calls" \
  DOTFILES_DIR="$ROOT" TX_LOG="$TMP/tx3.jsonl" OS_TYPE=Linux PACKAGE_MANAGER=apt \
  XDG_STATE_HOME="$TMP/state-maint" \
  bash "$ROOT/steps/01-packages.sh" >/dev/null 2>&1; then
  echo "maintenance re-run aborted on a failed apt index refresh" >&2
  exit 1
fi

echo "APT rollback safety test passed."
