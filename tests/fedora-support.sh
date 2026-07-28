#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
bash -n "$ROOT/install.sh" "$ROOT/steps/01-packages.sh" \
  "$ROOT/scripts/install-1password-fedora.sh"
grep -qF 'PACKAGE_MANAGER="dnf"' "$ROOT/lib/detect.sh"
grep -qF 'dnf install -y -q' "$ROOT/lib/packages/dnf.sh"
grep -qF 'downloads.1password.com/linux/rpm/stable' "$ROOT/scripts/install-1password-fedora.sh"
grep -qF 'tx_dnf_install' "$ROOT/lib/transaction.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
printf 'ID=nobara\nID_LIKE="fedora rhel"\n' >"$TMP/os-release"
# detect.sh trusts uname, so on a macOS runner the os-release fixture would be
# ignored; stub uname to exercise the Linux detection branch everywhere.
mkdir -p "$TMP/bin"
printf '#!/bin/sh\ncase "${1:-}" in -m) echo x86_64 ;; *) echo Linux ;; esac\n' > "$TMP/bin/uname"
chmod +x "$TMP/bin/uname"
detected="$(OS_RELEASE_FILE="$TMP/os-release" PATH="$TMP/bin:$PATH" \
  bash -c 'source "$1/lib/detect.sh"; printf "%s:%s:%s" "$DISTRO_ID" "$DISTRO_FAMILY" "$PACKAGE_MANAGER"' _ "$ROOT")"
[ "$detected" = 'nobara:fedora:dnf' ]
echo 'Fedora public support test passed.'
