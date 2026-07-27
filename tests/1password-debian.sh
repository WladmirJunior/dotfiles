#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
bash -n "$ROOT/install.sh" "$ROOT/scripts/install-1password-debian.sh"
grep -qF 'downloads.1password.com/linux/debian/amd64' "$ROOT/scripts/install-1password-debian.sh"
grep -qF '1password 1password-cli' "$ROOT/scripts/install-1password-debian.sh"
grep -qF '[ "$PACKAGE_MANAGER" = "apt" ]' "$ROOT/install.sh"
echo 'Debian 1Password support test passed.'
