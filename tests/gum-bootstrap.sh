#!/usr/bin/env bash
# ui_ensure_gum: dry-run must not download, and an asset failing its pinned
# SHA-256 must never become executable (fallback UI instead).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin"

# curl mock: records the call and writes controllable content to the -o target.
cat > "$TMP/bin/curl" <<'SH'
#!/bin/sh
printf '%s\n' "$*" >> "$CURL_CALLS"
out=""
prev=""
for arg do
  [ "$prev" = -o ] && out="$arg"
  prev="$arg"
done
[ -n "$out" ] && printf '%s' "$CURL_BODY" > "$out"
exit 0
SH
chmod +x "$TMP/bin/curl"

export CURL_CALLS="$TMP/curl.calls"
: > "$CURL_CALLS"

run_ensure_gum() {
  # Subshell per scenario so DRY_RUN/UI_GUM_* state never leaks between cases.
  (
    PATH="$TMP/bin:/usr/bin:/bin"
    NO_COLOR=1
    export PATH NO_COLOR CURL_BODY XDG_DATA_HOME
    # shellcheck disable=SC1091
    source "$ROOT/lib/ui.sh"
    ui_ensure_gum
  )
}

# 1) DRY_RUN=1: announce, no download, no binary.
XDG_DATA_HOME="$TMP/data-dry"
CURL_BODY="anything"
out="$(DRY_RUN=1 run_ensure_gum)"
grep -q '\[dry-run\] fetch gum fork' <<<"$out"
[ ! -s "$CURL_CALLS" ] || { echo "dry-run still downloaded gum" >&2; exit 1; }
[ ! -e "$TMP/data-dry/gum-fork/gum" ]

# 2) Checksum mismatch: download is discarded, nothing executable is installed.
XDG_DATA_HOME="$TMP/data-bad"
CURL_BODY="not the real gum binary"
DRY_RUN=0 run_ensure_gum 2> "$TMP/mismatch.err"
grep -q 'SHA-256 mismatch' "$TMP/mismatch.err"
grep -q 'releases/download/' "$CURL_CALLS"
[ ! -e "$TMP/data-bad/gum-fork/gum" ]
if compgen -G "$TMP/data-bad/gum-fork/gum.download.*" >/dev/null; then
  echo "mismatched download was left behind" >&2; exit 1
fi

# 3) Checksum match (pin overridden to this body's digest): binary installed.
XDG_DATA_HOME="$TMP/data-good"
CURL_BODY="pretend gum binary"
# Portable digest: GNU sha256sum on Linux, shasum on stock macOS.
if command -v sha256sum >/dev/null 2>&1; then
  expected="$(printf '%s' "$CURL_BODY" | sha256sum | awk '{print $1}')"
else
  expected="$(printf '%s' "$CURL_BODY" | shasum -a 256 | awk '{print $1}')"
fi
UI_GUM_SHA256="$expected" DRY_RUN=0 run_ensure_gum
[ -x "$TMP/data-good/gum-fork/gum" ]

echo "Gum bootstrap tests passed."
