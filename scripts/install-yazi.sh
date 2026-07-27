#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$SCRIPT_DIR/install-github-release.sh" \
  --repo sxyazi/yazi \
  --label Yazi \
  --binary "${YAZI_BIN:-yazi}" \
  --asset-amd64 yazi-x86_64-unknown-linux-gnu.deb \
  --asset-arm64 yazi-aarch64-unknown-linux-gnu.deb \
  --api "${YAZI_RELEASE_API:-https://api.github.com/repos/sxyazi/yazi/releases/latest}"
