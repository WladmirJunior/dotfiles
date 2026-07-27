#!/bin/bash
# Install the latest official Yazi .deb on Linux, verified against the SHA-256
# digest published with the GitHub Release asset.
set -euo pipefail

RELEASE_API="${YAZI_RELEASE_API:-https://api.github.com/repos/sxyazi/yazi/releases/latest}"
CURL_BIN="${CURL_BIN:-curl}"
PYTHON_BIN="${PYTHON_BIN:-python3}"
SHASUM_BIN="${SHASUM_BIN:-sha256sum}"
APT_GET_BIN="${APT_GET_BIN:-apt-get}"
UNAME_BIN="${UNAME_BIN:-uname}"
YAZI_BIN="${YAZI_BIN:-yazi}"

[ "$($UNAME_BIN -s)" = "Linux" ] || { echo "  Yazi: Linux installer skipped"; exit 0; }
if [ -x "$YAZI_BIN" ] || command -v "$YAZI_BIN" >/dev/null 2>&1; then
  echo "  Yazi: already installed"
  exit 0
fi

if [ "${DRY_RUN:-0}" = 1 ]; then
  echo "[dry-run] install latest verified Yazi release from $RELEASE_API"
  exit 0
fi

case "$($UNAME_BIN -m)" in
  arm64|aarch64) asset_name='yazi-aarch64-unknown-linux-gnu.deb' ;;
  x86_64|amd64)  asset_name='yazi-x86_64-unknown-linux-gnu.deb' ;;
  *) echo "  Yazi: unsupported architecture: $($UNAME_BIN -m)" >&2; exit 1 ;;
esac

for command in "$CURL_BIN" "$PYTHON_BIN" "$SHASUM_BIN" "$APT_GET_BIN"; do
  [ -x "$command" ] || command -v "$command" >/dev/null 2>&1 || {
    echo "  Yazi: required command not found: $command" >&2
    exit 1
  }
done

# An explicitly provided empty SUDO_BIN is useful for root and test harnesses.
if [ -z "${SUDO_BIN+x}" ]; then
  SUDO_BIN=""
  if [ "$(id -u)" -ne 0 ]; then
    command -v sudo >/dev/null 2>&1 || {
      echo "  Yazi: sudo is required for package installation" >&2
      exit 1
    }
    SUDO_BIN=sudo
  fi
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
deb="$tmp/$asset_name"

release_json="$($CURL_BIN -fsSL --max-time 30 "$RELEASE_API")"
asset_info="$(YAZI_RELEASE_JSON="$release_json" YAZI_ASSET_NAME="$asset_name" \
  "$PYTHON_BIN" -c 'import json, os
release = json.loads(os.environ["YAZI_RELEASE_JSON"])
name = os.environ["YAZI_ASSET_NAME"]
matches = [a for a in release.get("assets", []) if a.get("name") == name]
if len(matches) != 1:
    raise SystemExit(f"expected one {name} asset, found {len(matches)}")
asset = matches[0]
digest = asset.get("digest") or ""
if not digest.startswith("sha256:"):
    raise SystemExit("release asset has no SHA-256 digest")
print("|".join((asset["browser_download_url"], digest.removeprefix("sha256:"), release["tag_name"])))')"
IFS='|' read -r download_url expected_sha version <<EOF
$asset_info
EOF

case "$download_url" in
  https://github.com/sxyazi/yazi/releases/download/*) ;;
  *) echo "  Yazi: unexpected download URL: $download_url" >&2; exit 1 ;;
esac

echo "  Yazi: downloading $version official package..."
"$CURL_BIN" -fL --retry 3 --max-time 180 -o "$deb" "$download_url"
actual_sha="$($SHASUM_BIN "$deb" | awk '{print $1}')"
[ "$actual_sha" = "$expected_sha" ] || {
  echo "  Yazi: SHA-256 mismatch" >&2
  exit 1
}

if [ -n "$SUDO_BIN" ]; then
  "$SUDO_BIN" "$APT_GET_BIN" install -y "$deb"
else
  "$APT_GET_BIN" install -y "$deb"
fi
echo "  Yazi: installed ($version)"
