#!/usr/bin/env bash
# ./install.sh --status is a headless, read-only drift report: for the current
# OS it compares the package catalog against what is actually installed, per
# manager. It takes no install lock, starts no transaction, runs no steps, and
# needs no TTY. Exit code: 0 = no drift, 1 = missing packages.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/home"

# Pin the platform: fake uname (the suite also runs on macOS CI) and a fake
# os-release, so detection always lands on the mocked Linux manager.
cat > "$TMP/bin/uname" <<'SH'
#!/bin/sh
[ "${1:-}" = -m ] && { echo x86_64; exit 0; }
echo Linux
SH
# pacman mock: only zsh is installed, unless PACMAN_ALL_INSTALLED is set.
cat > "$TMP/bin/pacman" <<'SH'
#!/bin/sh
if [ "$1" = -Q ]; then
  [ -n "${PACMAN_ALL_INSTALLED:-}" ] && exit 0
  [ "$2" = zsh ]; exit $?
fi
exit 0
SH
# dpkg-query mock (apt adapter): only zsh reports the installed "ii" status.
cat > "$TMP/bin/dpkg-query" <<'SH'
#!/bin/sh
for last; do :; done
[ "$last" = zsh ] && { printf 'ii '; exit 0; }
exit 1
SH
chmod +x "$TMP/bin/"*

printf 'ID=arch\n' > "$TMP/os-release-arch"
printf 'ID=debian\n' > "$TMP/os-release-debian"

# Minimal catalog: one installed core package, one missing, plus best-effort
# rows (none for pacman, so that scope must not be reported there).
{
  printf 'scope\tcapability\tbrew\tapt\tpacman\tdnf\n'
  printf 'core\tshell\t-\tzsh\tzsh\tzsh\n'
  printf 'core\teditor\tneovim\tneovim\tneovim\tneovim\n'
  printf 'best-effort\tmarkdown\t-\tglow\t-\tglow\n'
} > "$TMP/catalog.tsv"

run_status() {  # run_status NAME OS_RELEASE_FILE [EXTRA_ENV...]
  local name="$1" os_release="$2" rc=0
  shift 2
  env -i \
    HOME="$TMP/home" \
    PATH="$TMP/bin:/usr/bin:/bin" \
    OS_RELEASE_FILE="$os_release" \
    PACKAGE_CATALOG_FILE="$TMP/catalog.tsv" \
    TX_LOG="$TMP/tx-$name.jsonl" \
    TX_LOCK_DIR="$TMP/tx-$name.jsonl.lock" \
    XDG_STATE_HOME="$TMP/state-$name" \
    "$@" \
    bash "$ROOT/install.sh" --status > "$TMP/$name.out" 2>&1 || rc=$?
  return "$rc"
}

# ── pacman: drift → exit 1, compact missing/ok lines, no best-effort noise ───
rc=0; run_status pacman-drift "$TMP/os-release-arch" || rc=$?
[ "$rc" -eq 1 ] || { echo "expected exit 1 on drift, got $rc" >&2; cat "$TMP/pacman-drift.out" >&2; exit 1; }
grep -q 'core missing: neovim' "$TMP/pacman-drift.out"
grep -q 'core ok: 1 package' "$TMP/pacman-drift.out"
if grep -q 'best-effort' "$TMP/pacman-drift.out"; then
  echo "reported a scope the catalog does not populate for pacman" >&2
  exit 1
fi
# Read-only contract: no lock taken, no transaction journal created.
[ ! -d "$TMP/tx-pacman-drift.jsonl.lock" ]
[ ! -e "$TMP/tx-pacman-drift.jsonl" ]

# ── pacman: everything installed → exit 0, no missing line ───────────────────
run_status pacman-ok "$TMP/os-release-arch" PACMAN_ALL_INSTALLED=1 || {
  echo "expected exit 0 when nothing is missing" >&2
  cat "$TMP/pacman-ok.out" >&2
  exit 1
}
grep -q 'core ok: 2 packages' "$TMP/pacman-ok.out"
if grep -q 'missing:' "$TMP/pacman-ok.out"; then
  echo "reported missing packages although everything is installed" >&2
  exit 1
fi

# ── apt: same report through the dpkg-query mock, best-effort included ───────
rc=0; run_status apt-drift "$TMP/os-release-debian" || rc=$?
[ "$rc" -eq 1 ]
grep -q 'core missing: neovim' "$TMP/apt-drift.out"
grep -q 'best-effort missing: glow' "$TMP/apt-drift.out"

echo "Install --status tests passed."
