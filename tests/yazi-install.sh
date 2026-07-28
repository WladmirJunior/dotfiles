#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin"

# Portable SHA-256: GNU sha256sum on Linux, shasum on stock macOS.
sha256_hex() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$@"
  else shasum -a 256 "$@"; fi
}

printf 'yazi test package' > "$TMP/reference.deb"
TEST_SHA="$(sha256_hex "$TMP/reference.deb" | awk '{print $1}')"
export TEST_SHA

cat > "$TMP/bin/uname" <<'SH'
#!/bin/sh
case "$1" in
  -s) echo Linux ;;
  -m) echo x86_64 ;;
esac
SH

cat > "$TMP/bin/curl" <<'SH'
#!/bin/sh
printf '%s\n' "$*" >> "$CURL_LOG"
output=""
while [ "$#" -gt 0 ]; do
  if [ "$1" = "-o" ]; then output="$2"; shift 2; continue; fi
  shift
done
if [ -n "$output" ]; then
  printf 'yazi test package' > "$output"
else
  printf '{"tag_name":"v9.9.9","assets":[{"name":"yazi-x86_64-unknown-linux-gnu.deb","digest":"sha256:%s","browser_download_url":"https://github.com/sxyazi/yazi/releases/download/v9.9.9/yazi-x86_64-unknown-linux-gnu.deb"}]}\n' "$TEST_SHA"
fi
SH

cat > "$TMP/bin/sha256sum" <<'SH'
#!/bin/sh
# Delegate to the system digest tool by absolute path (a bare `sha256sum`
# would recurse into this stub); shasum covers stock macOS.
if [ -x /usr/bin/sha256sum ]; then exec /usr/bin/sha256sum "$1"; fi
if [ -x /bin/sha256sum ]; then exec /bin/sha256sum "$1"; fi
exec /usr/bin/shasum -a 256 "$1"
SH

cat > "$TMP/bin/apt-get" <<'SH'
#!/bin/sh
printf '%s\n' "$*" >> "$APT_LOG"
SH

chmod +x "$TMP/bin/"*

PATH="$TMP/bin:/usr/bin:/bin" \
CURL_LOG="$TMP/curl.log" \
APT_LOG="$TMP/apt.log" \
CURL_BIN="$TMP/bin/curl" \
SHASUM_BIN="$TMP/bin/sha256sum" \
APT_GET_BIN="$TMP/bin/apt-get" \
UNAME_BIN="$TMP/bin/uname" \
YAZI_BIN="$TMP/bin/yazi-test-not-installed" \
SUDO_BIN="" \
  "$ROOT/scripts/install-yazi.sh"

grep -q 'api.github.com/repos/sxyazi/yazi/releases/latest' "$TMP/curl.log"
grep -q 'github.com/sxyazi/yazi/releases/download/v9.9.9/' "$TMP/curl.log"
grep -Eq '^install -y .*/yazi-x86_64-unknown-linux-gnu\.deb$' "$TMP/apt.log"

cat > "$TMP/bin/yazi" <<'SH'
#!/bin/sh
exit 0
SH
chmod +x "$TMP/bin/yazi"
curl_calls="$(wc -l < "$TMP/curl.log" | tr -d ' ')"
PATH="$TMP/bin:/usr/bin:/bin" \
CURL_LOG="$TMP/curl.log" \
CURL_BIN="$TMP/bin/curl" \
UNAME_BIN="$TMP/bin/uname" \
YAZI_BIN="$TMP/bin/yazi" \
  "$ROOT/scripts/install-yazi.sh"
[ "$(wc -l < "$TMP/curl.log" | tr -d ' ')" = "$curl_calls" ]

echo "Yazi installer test passed."
