#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin"

printf 'fastfetch test package' > "$TMP/reference.deb"
TEST_SHA="$(/usr/bin/shasum -a 256 "$TMP/reference.deb" | awk '{print $1}')"
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
  printf 'fastfetch test package' > "$output"
else
  printf '{"tag_name":"9.9.9","assets":[{"name":"fastfetch-linux-amd64.deb","digest":"sha256:%s","browser_download_url":"https://github.com/fastfetch-cli/fastfetch/releases/download/9.9.9/fastfetch-linux-amd64.deb"}]}\n' "$TEST_SHA"
fi
SH

cat > "$TMP/bin/sha256sum" <<'SH'
#!/bin/sh
/usr/bin/shasum -a 256 "$1"
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
SUDO_BIN="" \
  "$ROOT/scripts/install-fastfetch.sh"

grep -q 'api.github.com/repos/fastfetch-cli/fastfetch/releases/latest' "$TMP/curl.log"
grep -q 'github.com/fastfetch-cli/fastfetch/releases/download/9.9.9/' "$TMP/curl.log"
grep -Eq '^install -y .*/fastfetch-linux-amd64\.deb$' "$TMP/apt.log"

cat > "$TMP/bin/fastfetch" <<'SH'
#!/bin/sh
exit 0
SH
chmod +x "$TMP/bin/fastfetch"
curl_calls="$(wc -l < "$TMP/curl.log" | tr -d ' ')"
PATH="$TMP/bin:/usr/bin:/bin" \
CURL_LOG="$TMP/curl.log" \
CURL_BIN="$TMP/bin/curl" \
UNAME_BIN="$TMP/bin/uname" \
  "$ROOT/scripts/install-fastfetch.sh"
[ "$(wc -l < "$TMP/curl.log" | tr -d ' ')" = "$curl_calls" ]

echo "Fastfetch installer test passed."
