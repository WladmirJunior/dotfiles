#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$SCRIPT_DIR/install-github-release.sh" \
  --repo fastfetch-cli/fastfetch \
  --label Fastfetch \
  --binary "${FASTFETCH_BIN:-fastfetch}" \
  --asset-amd64 fastfetch-linux-amd64.deb \
  --asset-arm64 fastfetch-linux-aarch64.deb \
  --api "${FASTFETCH_RELEASE_API:-https://api.github.com/repos/fastfetch-cli/fastfetch/releases/latest}"
