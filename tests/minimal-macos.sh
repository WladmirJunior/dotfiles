#!/bin/bash
# Tests for minimal profile on macOS Intel (x86_64) and Apple Silicon (arm64):
# - Ensures brew is never called.
# - Ensures xcode-select --install is never called.
# - Validates x86_64 artifact selection and arm64 rejection on Intel.
# - Validates arm64 artifact selection and x86_64 rejection on Apple Silicon.
# - Validates macOS version compatibility check (minos vs MACOS_MAJOR).
# - Validates checksum mismatch rejection and cleanup.
# - Validates idempotent re-run without re-downloading.
# - Validates 01-packages.sh, 02-shell.sh, and 03-dotfiles.sh under minimal profile.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/bin" "$TMP/home/.local/bin" "$TMP/home/.local/share" "$TMP/state" "$TMP/dotfiles/config" "$TMP/dotfiles/lib" "$TMP/dotfiles/scripts"

# Copy needed libs and scripts
cp -R "$ROOT/config" "$TMP/dotfiles/"
cp "$ROOT"/lib/*.sh "$TMP/dotfiles/lib/"
cp -R "$ROOT/lib/packages" "$TMP/dotfiles/lib/"
cp "$ROOT/scripts/install-darwin-standalone.sh" "$TMP/dotfiles/scripts/"
cp "$ROOT/steps/"*.sh "$TMP/dotfiles/steps/" 2>/dev/null || true
mkdir -p "$TMP/dotfiles/steps"
cp "$ROOT/steps/01-packages.sh" "$TMP/dotfiles/steps/"
cp "$ROOT/steps/02-shell.sh" "$TMP/dotfiles/steps/"
cp "$ROOT/steps/03-dotfiles.sh" "$TMP/dotfiles/steps/"

# Mock brew to fail if called
cat > "$TMP/bin/brew" <<'SH'
#!/bin/sh
echo "FAIL: brew called with: $*" >> "$BREW_LOG"
exit 99
SH

# Mock xcode-select to fail if --install is passed
cat > "$TMP/bin/xcode-select" <<'SH'
#!/bin/sh
printf '%s\n' "$*" >> "$XCODE_SELECT_LOG"
for arg in "$@"; do
  if [ "$arg" = "--install" ]; then
    echo "FAIL: xcode-select --install called" >&2
    exit 98
  fi
done
case "$1" in
  -p)
    if [ "${MOCK_CLT_INSTALLED:-0}" = 1 ]; then
      echo "/Library/Developer/CommandLineTools"
      exit 0
    else
      echo "xcode-select: error: unable to get active developer directory" >&2
      exit 2
    fi
    ;;
esac
exit 0
SH

# Mock sw_vers
cat > "$TMP/bin/sw_vers" <<'SH'
#!/bin/sh
if [ "$1" = "-productVersion" ]; then
  echo "${MOCK_MACOS_VERSION:-11.6.8}"
fi
SH

chmod +x "$TMP/bin/"*

# Generate a small mock manifest with real tarballs created locally to test full cycle
# Create mock x86_64 and arm64 tarballs
TAR_SRC="$TMP/src_tool"
mkdir -p "$TAR_SRC/bin"
echo '#!/bin/sh' > "$TAR_SRC/bin/mocktool"
echo 'echo mocktool-x86_64' >> "$TAR_SRC/bin/mocktool"
chmod +x "$TAR_SRC/bin/mocktool"
tar -czf "$TMP/mocktool-x86_64.tar.gz" -C "$TAR_SRC" bin

echo '#!/bin/sh' > "$TAR_SRC/bin/mocktool"
echo 'echo mocktool-arm64' >> "$TAR_SRC/bin/mocktool"
tar -czf "$TMP/mocktool-arm64.tar.gz" -C "$TAR_SRC" bin

SHA_X86="$(shasum -a 256 "$TMP/mocktool-x86_64.tar.gz" | awk '{print $1}')"
SHA_ARM="$(shasum -a 256 "$TMP/mocktool-arm64.tar.gz" | awk '{print $1}')"

cat > "$TMP/dotfiles/config/test-manifest.tsv" <<EOF
tool	version	minos	type	bin	share	url_x86_64	sha256_x86_64	url_arm64	sha256_arm64
mocktool	1.0.0	11.0	tar.gz	bin/mocktool	yes	https://example.com/mocktool-x86_64.tar.gz	$SHA_X86	https://example.com/mocktool-arm64.tar.gz	$SHA_ARM
EOF

export MOCK_X86_FILE="$TMP/mocktool-x86_64.tar.gz"
export MOCK_ARM_FILE="$TMP/mocktool-arm64.tar.gz"

# Mock curl that intercepts downloads and serves our local mock files
cat > "$TMP/bin/curl" <<'SH'
#!/bin/sh
if [ -n "${CURL_LOG:-}" ]; then
  printf '%s\n' "$*" >> "$CURL_LOG"
fi
out=""
url=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    -o) out="$2"; shift 2 ;;
    https://example.com/mocktool-x86_64.tar.gz) url="x86_64"; shift ;;
    https://example.com/mocktool-arm64.tar.gz) url="arm64"; shift ;;
    *) shift ;;
  esac
done
if [ -n "$out" ]; then
  if [ "$url" = "x86_64" ]; then
    cp "$MOCK_X86_FILE" "$out"
  elif [ "$url" = "arm64" ]; then
    cp "$MOCK_ARM_FILE" "$out"
  else
    exit 1
  fi
fi
exit 0
SH
chmod +x "$TMP/bin/curl"

# -----------------------------------------------------------------------------
# Test 1: macOS Intel x86_64 minimal install
# -----------------------------------------------------------------------------
BREW_LOG="$TMP/brew.log"
XCODE_SELECT_LOG="$TMP/xcode-select.log"
CURL_LOG="$TMP/curl.log"
export BREW_LOG XCODE_SELECT_LOG CURL_LOG
: > "$BREW_LOG"
: > "$XCODE_SELECT_LOG"
: > "$CURL_LOG"

HOME="$TMP/home" \
PATH="$TMP/bin:/usr/bin:/bin" \
XDG_STATE_HOME="$TMP/state" \
DOTFILES_DIR="$TMP/dotfiles" \
PACKAGES_DARWIN_MANIFEST="$TMP/dotfiles/config/test-manifest.tsv" \
OS_TYPE="Darwin" \
ARCH="x86_64" \
MOCK_MACOS_VERSION="11.6.8" \
MOCK_CLT_INSTALLED=0 \
PROFILE="minimal" \
  bash "$TMP/dotfiles/scripts/install-darwin-standalone.sh"

# Assertions for Test 1:
# - brew was NEVER called
[ ! -s "$BREW_LOG" ] || { echo "FAIL: brew was called!" >&2; exit 1; }
# - xcode-select --install was NEVER called
! grep -q -- '--install' "$XCODE_SELECT_LOG" || { echo "FAIL: xcode-select --install was called!" >&2; exit 1; }
# - Correct x86_64 asset was downloaded
grep -q 'mocktool-x86_64.tar.gz' "$CURL_LOG"
! grep -q 'mocktool-arm64.tar.gz' "$CURL_LOG" || { echo "FAIL: arm64 asset downloaded on x86_64!" >&2; exit 1; }
# - Binary installed and working
[ -x "$TMP/home/.local/bin/mocktool" ]
output="$("$TMP/home/.local/bin/mocktool")"
[ "$output" = "mocktool-x86_64" ] || { echo "FAIL: unexpected binary output: $output" >&2; exit 1; }

# -----------------------------------------------------------------------------
# Test 2: Idempotency (re-run performs zero downloads)
# -----------------------------------------------------------------------------
curl_count_before="$(wc -l < "$CURL_LOG" | tr -d ' ')"

HOME="$TMP/home" \
PATH="$TMP/bin:/usr/bin:/bin" \
XDG_STATE_HOME="$TMP/state" \
DOTFILES_DIR="$TMP/dotfiles" \
PACKAGES_DARWIN_MANIFEST="$TMP/dotfiles/config/test-manifest.tsv" \
OS_TYPE="Darwin" \
ARCH="x86_64" \
MOCK_MACOS_VERSION="11.6.8" \
MOCK_CLT_INSTALLED=0 \
PROFILE="minimal" \
  bash "$TMP/dotfiles/scripts/install-darwin-standalone.sh"

curl_count_after="$(wc -l < "$CURL_LOG" | tr -d ' ')"
[ "$curl_count_before" = "$curl_count_after" ] || { echo "FAIL: re-run was not idempotent (downloaded again)" >&2; exit 1; }

# -----------------------------------------------------------------------------
# Test 3: Apple Silicon (arm64) downloads arm64 asset and rejects x86_64
# -----------------------------------------------------------------------------
TMP_ARM="$TMP/arm_home"
mkdir -p "$TMP_ARM/.local/bin" "$TMP_ARM/.local/share"
: > "$CURL_LOG"

HOME="$TMP_ARM" \
PATH="$TMP/bin:/usr/bin:/bin" \
XDG_STATE_HOME="$TMP/state_arm" \
DOTFILES_DIR="$TMP/dotfiles" \
PACKAGES_DARWIN_MANIFEST="$TMP/dotfiles/config/test-manifest.tsv" \
OS_TYPE="Darwin" \
ARCH="arm64" \
MOCK_MACOS_VERSION="12.4" \
MOCK_CLT_INSTALLED=0 \
PROFILE="minimal" \
  bash "$TMP/dotfiles/scripts/install-darwin-standalone.sh"

grep -q 'mocktool-arm64.tar.gz' "$CURL_LOG"
! grep -q 'mocktool-x86_64.tar.gz' "$CURL_LOG" || { echo "FAIL: x86_64 asset downloaded on arm64!" >&2; exit 1; }
arm_output="$("$TMP_ARM/.local/bin/mocktool")"
[ "$arm_output" = "mocktool-arm64" ] || { echo "FAIL: unexpected arm64 output: $arm_output" >&2; exit 1; }

# -----------------------------------------------------------------------------
# Test 4: macOS version compatibility (minos > host skips the binary)
# -----------------------------------------------------------------------------
cat > "$TMP/dotfiles/config/minos-manifest.tsv" <<EOF
tool	version	minos	type	bin	share	url_x86_64	sha256_x86_64	url_arm64	sha256_arm64
mocktool	1.0.0	14.0	tar.gz	bin/mocktool	yes	https://example.com/mocktool-x86_64.tar.gz	$SHA_X86	https://example.com/mocktool-arm64.tar.gz	$SHA_ARM
EOF

TMP_OLD_MAC="$TMP/old_mac_home"
mkdir -p "$TMP_OLD_MAC/.local/bin"
out_old_mac=$(
HOME="$TMP_OLD_MAC" \
PATH="$TMP/bin:/usr/bin:/bin" \
XDG_STATE_HOME="$TMP/state_old" \
DOTFILES_DIR="$TMP/dotfiles" \
PACKAGES_DARWIN_MANIFEST="$TMP/dotfiles/config/minos-manifest.tsv" \
OS_TYPE="Darwin" \
ARCH="x86_64" \
MOCK_MACOS_VERSION="11.0.0" \
MOCK_CLT_INSTALLED=0 \
PROFILE="minimal" \
  bash "$TMP/dotfiles/scripts/install-darwin-standalone.sh" 2>&1
)
echo "$out_old_mac" | grep -q 'requires macOS >= 14.0'
[ ! -e "$TMP_OLD_MAC/.local/bin/mocktool" ] || { echo "FAIL: binary installed despite OS version incompatibility" >&2; exit 1; }

# -----------------------------------------------------------------------------
# Test 5: Checksum mismatch rejection
# -----------------------------------------------------------------------------
cat > "$TMP/dotfiles/config/bad-sha-manifest.tsv" <<EOF
tool	version	minos	type	bin	share	url_x86_64	sha256_x86_64	url_arm64	sha256_arm64
mocktool	1.0.0	11.0	tar.gz	bin/mocktool	yes	https://example.com/mocktool-x86_64.tar.gz	0000000000000000000000000000000000000000000000000000000000000000	https://example.com/mocktool-arm64.tar.gz	$SHA_ARM
EOF

TMP_BAD="$TMP/bad_sha_home"
mkdir -p "$TMP_BAD/.local/bin"
set +e
bad_out=$(
HOME="$TMP_BAD" \
PATH="$TMP/bin:/usr/bin:/bin" \
XDG_STATE_HOME="$TMP/state_bad" \
DOTFILES_DIR="$TMP/dotfiles" \
PACKAGES_DARWIN_MANIFEST="$TMP/dotfiles/config/bad-sha-manifest.tsv" \
OS_TYPE="Darwin" \
ARCH="x86_64" \
MOCK_MACOS_VERSION="11.6.8" \
MOCK_CLT_INSTALLED=0 \
PROFILE="minimal" \
  bash "$TMP/dotfiles/scripts/install-darwin-standalone.sh" 2>&1
)
bad_rc=$?
set -e
[ "$bad_rc" -ne 0 ]
echo "$bad_out" | grep -q 'SHA-256 mismatch'
[ ! -e "$TMP_BAD/.local/bin/mocktool" ]

# -----------------------------------------------------------------------------
# Test 6: 01-packages.sh under minimal profile on Darwin never calls brew
# -----------------------------------------------------------------------------
: > "$BREW_LOG"
cat > "$TMP/bin/fzf" <<'SH'
#!/bin/sh
if [ "$1" = "--zsh" ]; then
  echo "# fzf zsh integration"
  exit 0
fi
exit 0
SH
chmod +x "$TMP/bin/fzf"

HOME="$TMP/home" \
PATH="$TMP/bin:/usr/bin:/bin" \
XDG_STATE_HOME="$TMP/state" \
DOTFILES_DIR="$TMP/dotfiles" \
PACKAGES_DARWIN_MANIFEST="$TMP/dotfiles/config/test-manifest.tsv" \
OS_TYPE="Darwin" \
ARCH="x86_64" \
MOCK_MACOS_VERSION="11.6.8" \
PROFILE="minimal" \
DRY_RUN=1 \
  bash "$TMP/dotfiles/steps/01-packages.sh"

[ ! -s "$BREW_LOG" ] || { echo "FAIL: 01-packages.sh called brew under minimal profile!" >&2; exit 1; }

# -----------------------------------------------------------------------------
# Test 7: 02-shell.sh under minimal profile uses fzf --zsh and never calls brew
# -----------------------------------------------------------------------------
: > "$BREW_LOG"
HOME="$TMP/home" \
PATH="$TMP/bin:/usr/bin:/bin" \
XDG_STATE_HOME="$TMP/state" \
DOTFILES_DIR="$TMP/dotfiles" \
OS_TYPE="Darwin" \
ARCH="x86_64" \
MOCK_MACOS_VERSION="11.6.8" \
PROFILE="minimal" \
DRY_RUN=0 \
  bash "$TMP/dotfiles/steps/02-shell.sh"

[ ! -s "$BREW_LOG" ] || { echo "FAIL: 02-shell.sh called brew under minimal profile!" >&2; exit 1; }
[ -f "$TMP/home/.fzf.zsh" ]
grep -q 'fzf zsh integration' "$TMP/home/.fzf.zsh"

# -----------------------------------------------------------------------------
# Test 8: 03-dotfiles.sh does not fail without /opt/homebrew
# -----------------------------------------------------------------------------
HOME="$TMP/home" \
PATH="$TMP/bin:/usr/bin:/bin" \
XDG_STATE_HOME="$TMP/state" \
DOTFILES_DIR="$TMP/dotfiles" \
OS_TYPE="Darwin" \
ARCH="x86_64" \
MOCK_MACOS_VERSION="11.6.8" \
PROFILE="minimal" \
DRY_RUN=0 \
  bash "$TMP/dotfiles/steps/03-dotfiles.sh"

[ -f "$TMP/home/.zshrc" ]
[ -f "$TMP/home/.zshenv" ]

echo "Minimal macOS Intel tests passed."
