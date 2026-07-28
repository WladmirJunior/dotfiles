#!/usr/bin/env bash
# Failure propagation: a mid-step mutation failure must make the step exit
# non-zero (set -e), not fall through to the trailing "done" echo. Also covers
# the step exit-status contract (lib/step.sh).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/home"

# apt-get: update succeeds, install fails (simulates a repo/package error).
cat > "$TMP/bin/apt-get" <<'SH'
#!/bin/sh
printf '%s\n' "$*" >> "$APT_CALLS"
for arg do
  [ "$arg" = install ] && exit 100
done
exit 0
SH

cat > "$TMP/bin/sudo" <<'SH'
#!/bin/sh
exec "$@"
SH

cat > "$TMP/bin/dpkg-query" <<'SH'
#!/bin/sh
exit 1
SH

for command_name in yazi fastfetch; do
  cat > "$TMP/bin/$command_name" <<'SH'
#!/bin/sh
exit 0
SH
done
chmod +x "$TMP/bin/"*

rc=0
HOME="$TMP/home" \
PATH="$TMP/bin:/usr/bin:/bin" \
APT_CALLS="$TMP/apt.calls" \
DOTFILES_DIR="$ROOT" \
TX_LOG="$TMP/tx.jsonl" \
OS_TYPE=Linux \
PACKAGE_MANAGER=apt \
  bash "$ROOT/steps/01-packages.sh" > "$TMP/step.out" 2>&1 || rc=$?

[ "$rc" -ne 0 ] || { echo "step 01 returned 0 despite a failed install" >&2; exit 1; }
if grep -q '\[01\] done' "$TMP/step.out"; then
  echo "step 01 reached its 'done' line after a failed mutation" >&2
  exit 1
fi

# Step exit-status contract: only SKIPPED / DEPENDENCY_UNAVAILABLE are
# continue-without-abort; everything else is fatal.
source "$ROOT/lib/step.sh"
[ "$(step_status_label "$STEP_SKIPPED")" = skipped ]
[ "$(step_status_label "$STEP_DEPENDENCY_UNAVAILABLE")" = 'dependency unavailable' ]
! step_status_label 1 >/dev/null
! step_status_label "$STEP_AUTH_REQUIRED" >/dev/null

echo "Step failure propagation tests passed."
