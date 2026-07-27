#!/usr/bin/env bash
# Install one verified .deb asset from the latest GitHub release.
set -euo pipefail

repo="" label="" binary="" asset_amd64="" asset_arm64="" release_api=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --repo) repo="$2"; shift 2 ;;
    --label) label="$2"; shift 2 ;;
    --binary) binary="$2"; shift 2 ;;
    --asset-amd64) asset_amd64="$2"; shift 2 ;;
    --asset-arm64) asset_arm64="$2"; shift 2 ;;
    --api) release_api="$2"; shift 2 ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
done

[ -n "$repo" ] && [ -n "$label" ] && [ -n "$binary" ] \
  && [ -n "$asset_amd64" ] && [ -n "$asset_arm64" ] || {
  echo "Usage: $0 --repo OWNER/REPO --label NAME --binary COMMAND --asset-amd64 FILE --asset-arm64 FILE [--api URL]" >&2
  exit 2
}
case "$repo" in */*) ;; *) echo "$label: invalid GitHub repository: $repo" >&2; exit 2 ;; esac
case "$repo" in
  *[!A-Za-z0-9._/-]*) echo "$label: invalid GitHub repository: $repo" >&2; exit 2 ;;
esac
repo_owner="${repo%%/*}"
repo_name="${repo#*/}"
[ -n "$repo_owner" ] && [ -n "$repo_name" ] && [ "$repo_name" != "$repo" ] \
  && [[ "$repo_name" != */* ]] || {
  echo "$label: invalid GitHub repository: $repo" >&2
  exit 2
}
case "$asset_amd64:$asset_arm64" in
  *'/'*|*'..'*) echo "$label: release assets must be plain file names" >&2; exit 2 ;;
esac
release_api="${release_api:-https://api.github.com/repos/$repo/releases/latest}"

CURL_BIN="${CURL_BIN:-curl}"
PYTHON_BIN="${PYTHON_BIN:-python3}"
SHASUM_BIN="${SHASUM_BIN:-sha256sum}"
APT_GET_BIN="${APT_GET_BIN:-apt-get}"
UNAME_BIN="${UNAME_BIN:-uname}"

[ "$($UNAME_BIN -s)" = Linux ] || { echo "  $label: Linux installer skipped"; exit 0; }
if [ -x "$binary" ] || command -v "$binary" >/dev/null 2>&1; then
  echo "  $label: already installed"
  exit 0
fi

if [ "${DRY_RUN:-0}" = 1 ]; then
  echo "[dry-run] install latest verified $label release from $release_api"
  exit 0
fi

case "$($UNAME_BIN -m)" in
  arm64|aarch64) asset_name="$asset_arm64" ;;
  x86_64|amd64) asset_name="$asset_amd64" ;;
  *) echo "  $label: unsupported architecture: $($UNAME_BIN -m)" >&2; exit 1 ;;
esac

for required_command in "$CURL_BIN" "$PYTHON_BIN" "$SHASUM_BIN" "$APT_GET_BIN"; do
  [ -x "$required_command" ] || command -v "$required_command" >/dev/null 2>&1 || {
    echo "  $label: required command not found: $required_command" >&2
    exit 1
  }
done

if [ -z "${SUDO_BIN+x}" ]; then
  SUDO_BIN=""
  if [ "$(id -u)" -ne 0 ]; then
    command -v sudo >/dev/null 2>&1 || {
      echo "  $label: sudo is required for package installation" >&2
      exit 1
    }
    SUDO_BIN=sudo
  fi
fi

release_tmp="$(mktemp -d)"
trap 'rm -rf "$release_tmp"' EXIT
package="$release_tmp/$asset_name"

release_json="$($CURL_BIN -fsSL --max-time 30 "$release_api")"
asset_info="$(RELEASE_JSON="$release_json" RELEASE_ASSET_NAME="$asset_name" \
  "$PYTHON_BIN" -c 'import json, os
release = json.loads(os.environ["RELEASE_JSON"])
name = os.environ["RELEASE_ASSET_NAME"]
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
  "https://github.com/$repo/releases/download/"*) ;;
  *) echo "  $label: unexpected download URL: $download_url" >&2; exit 1 ;;
esac

echo "  $label: downloading $version official package..."
"$CURL_BIN" -fL --retry 3 --max-time 180 -o "$package" "$download_url"
actual_sha="$($SHASUM_BIN "$package" | awk '{print $1}')"
[ "$actual_sha" = "$expected_sha" ] || {
  echo "  $label: SHA-256 mismatch" >&2
  exit 1
}

if [ -n "$SUDO_BIN" ]; then
  "$SUDO_BIN" "$APT_GET_BIN" install -y "$package"
else
  "$APT_GET_BIN" install -y "$package"
fi
echo "  $label: installed ($version)"
