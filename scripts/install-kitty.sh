#!/bin/bash
# Install the official Kitty terminal on macOS without Homebrew.
# Downloads the verified release DMG, verifies SHA-256 and bundle ID,
# stages into /Applications (or ~/Applications), and links the config.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="${DOTFILES_DIR:-$(cd "$SCRIPT_DIR/.." && pwd)}"
DOTFILES_PRIVATE_DIR="${DOTFILES_PRIVATE_DIR:-$HOME/.dotfiles-private}"

APPLICATIONS_DIR="${APPLICATIONS_DIR:-/Applications}"
DEST="$APPLICATIONS_DIR/kitty.app"
EXPECTED_BUNDLE_ID="net.kovidgoyal.kitty"

SW_VERS_BIN="${SW_VERS_BIN:-sw_vers}"
MACOS_VER="$($SW_VERS_BIN -productVersion 2>/dev/null || echo "11.0")"
MACOS_MAJ="${MACOS_VER%%.*}"

# Kitty 0.46.0+ bumped LSMinimumSystemVersion to macOS 12 (Monterey).
# For macOS 11 (Big Sur), the latest functional release is v0.45.0.
if [ "$MACOS_MAJ" -lt 12 ]; then
  DEFAULT_KITTY_VERSION="0.45.0"
  DEFAULT_KITTY_SHA="c0e2afb7580fcf1f4cad410d525068c9d082679c3106a743962610fade4d7381"
else
  DEFAULT_KITTY_VERSION="0.48.2"
  DEFAULT_KITTY_SHA="f804f58ee4b69c76f84eb3281e140748269a63f3f4a816015a8dec2a06d2b195"
fi

VERSION="${KITTY_VERSION:-$DEFAULT_KITTY_VERSION}"
EXPECTED_SHA="${KITTY_SHA256:-$DEFAULT_KITTY_SHA}"
DOWNLOAD_URL="${KITTY_DOWNLOAD_URL:-https://github.com/kovidgoyal/kitty/releases/download/v${VERSION}/kitty-${VERSION}.dmg}"

CURL_BIN="${CURL_BIN:-curl}"
HDIUTIL_BIN="${HDIUTIL_BIN:-hdiutil}"
DITTO_BIN="${DITTO_BIN:-/usr/bin/ditto}"
XATTR_BIN="${XATTR_BIN:-/usr/bin/xattr}"
PLISTBUDDY_BIN="${PLISTBUDDY_BIN:-/usr/libexec/PlistBuddy}"
SHASUM_BIN="${SHASUM_BIN:-shasum}"
UNAME_BIN="${UNAME_BIN:-uname}"

[ "$($UNAME_BIN -s)" = "Darwin" ] || { echo "  Kitty: macOS only, skipping"; exit 0; }

# If /Applications is not writable, fall back to ~/Applications
if [ ! -w "$APPLICATIONS_DIR" ] && [ ! -d "$DEST" ]; then
  APPLICATIONS_DIR="$HOME/Applications"
  DEST="$APPLICATIONS_DIR/kitty.app"
  mkdir -p "$APPLICATIONS_DIR"
fi

# Link configuration file if available
link_kitty_config() {
  local kitty_src=""
  if [ -d "$DOTFILES_PRIVATE_DIR/config/kitty" ]; then
    kitty_src="$DOTFILES_PRIVATE_DIR/config/kitty"
  elif [ -d "$DOTFILES_DIR/config/kitty" ]; then
    kitty_src="$DOTFILES_DIR/config/kitty"
  fi

  if [ -n "$kitty_src" ]; then
    mkdir -p "$HOME/.config/kitty"
    [ -f "$kitty_src/kitty.conf" ] && ln -sfn "$kitty_src/kitty.conf" "$HOME/.config/kitty/kitty.conf"
    [ -f "$kitty_src/colors.conf" ] && ln -sfn "$kitty_src/colors.conf" "$HOME/.config/kitty/colors.conf"
    echo "  ✓ Kitty: config linked ($kitty_src -> $HOME/.config/kitty)"
  fi
}

install_kitty_font() {
  local font_dir="$HOME/Library/Fonts"
  if [ -f "$font_dir/TerminessNerdFont-Regular.ttf" ]; then
    return 0
  fi
  if [ "${DRY_RUN:-0}" = 1 ]; then
    echo "  [dry-run] download Terminess Nerd Font -> $font_dir"
    return 0
  fi

  echo "  Kitty: downloading Terminess Nerd Font..."
  local tmp_font
  tmp_font="$(mktemp -d -t "dotfiles-font.XXXXXX")"
  local font_url="https://github.com/ryanoasis/nerd-fonts/releases/download/v3.3.0/Terminus.tar.xz"
  if "$CURL_BIN" -fsSL --retry 3 --max-time 120 -o "$tmp_font/Terminus.tar.xz" "$font_url"; then
    tar -xf "$tmp_font/Terminus.tar.xz" -C "$tmp_font" 2>/dev/null || true
    mkdir -p "$font_dir"
    cp "$tmp_font"/TerminessNerdFont*.ttf "$font_dir/" 2>/dev/null || true
    echo "  ✓ Terminess Nerd Font: installed ($font_dir)"
  else
    echo "  warning: failed to download Terminess Nerd Font; continuing" >&2
  fi
  rm -rf "$tmp_font"
}

# Skip if already installed and not updating
if [ -d "$DEST" ] && [ "${DOTFILES_UPDATE:-0}" != 1 ]; then
  echo "  Kitty: already installed ($DEST)"
  link_kitty_config
  install_kitty_font
  mkdir -p "$HOME/.local/bin"
  [ -f "$DEST/Contents/MacOS/kitty" ] && ln -sfn "$DEST/Contents/MacOS/kitty" "$HOME/.local/bin/kitty"
  [ -f "$DEST/Contents/MacOS/kitten" ] && ln -sfn "$DEST/Contents/MacOS/kitten" "$HOME/.local/bin/kitten"
  exit 0
fi

if [ "${DRY_RUN:-0}" = 1 ]; then
  echo "[dry-run] install Kitty $VERSION DMG -> $DEST"
  exit 0
fi

for cmd in "$CURL_BIN" "$HDIUTIL_BIN" "$DITTO_BIN" "$XATTR_BIN" "$SHASUM_BIN"; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "  Kitty: required command not found: $cmd" >&2
    exit 1
  fi
done

tmp_dir="$(mktemp -d -t kitty-install.XXXXXX)"
dmg="$tmp_dir/kitty.dmg"
mountpoint="$tmp_dir/mnt"
stage="$tmp_dir/kitty.app"
mounted=0

cleanup() {
  local rc=$?
  if [ "$mounted" -eq 1 ]; then
    "$HDIUTIL_BIN" detach "$mountpoint" -quiet 2>/dev/null || true
  fi
  rm -rf "$tmp_dir"
  exit "$rc"
}
trap cleanup EXIT INT TERM

echo "  Kitty: downloading $VERSION official DMG..."
if ! "$CURL_BIN" -fL --retry 3 --max-time 180 -o "$dmg" "$DOWNLOAD_URL"; then
  echo "  Kitty: download failed from $DOWNLOAD_URL" >&2
  exit 1
fi

actual_sha="$($SHASUM_BIN -a 256 "$dmg" | awk '{print $1}')"
if [ "$actual_sha" != "$EXPECTED_SHA" ]; then
  echo "  Kitty: SHA-256 mismatch (expected $EXPECTED_SHA, got $actual_sha)" >&2
  exit 1
fi

mkdir -p "$mountpoint"
if ! "$HDIUTIL_BIN" attach "$dmg" -nobrowse -readonly -mountpoint "$mountpoint" >/dev/null; then
  echo "  Kitty: failed to attach disk image" >&2
  exit 1
fi
mounted=1

source_app="$mountpoint/kitty.app"
if [ ! -d "$source_app" ]; then
  echo "  Kitty: kitty.app missing from DMG" >&2
  exit 1
fi

if [ -x "$PLISTBUDDY_BIN" ] && [ -f "$source_app/Contents/Info.plist" ]; then
  bundle_id="$($PLISTBUDDY_BIN -c 'Print :CFBundleIdentifier' "$source_app/Contents/Info.plist" 2>/dev/null || true)"
  if [ -n "$bundle_id" ] && [ "$bundle_id" != "$EXPECTED_BUNDLE_ID" ]; then
    echo "  Kitty: unexpected bundle ID: $bundle_id" >&2
    exit 1
  fi
fi

mkdir -p "$APPLICATIONS_DIR"
"$DITTO_BIN" "$source_app" "$stage"
"$XATTR_BIN" -dr com.apple.quarantine "$stage" 2>/dev/null || true

# Detach before moving into place
"$HDIUTIL_BIN" detach "$mountpoint" -quiet 2>/dev/null || true
mounted=0

# Move staged app into place
if [ -d "$DEST" ]; then
  rm -rf "$DEST"
fi
mv "$stage" "$DEST"

# Link config
link_kitty_config
install_kitty_font

# Link CLI helpers into ~/.local/bin
mkdir -p "$HOME/.local/bin"
[ -f "$DEST/Contents/MacOS/kitty" ] && ln -sfn "$DEST/Contents/MacOS/kitty" "$HOME/.local/bin/kitty"
[ -f "$DEST/Contents/MacOS/kitten" ] && ln -sfn "$DEST/Contents/MacOS/kitten" "$HOME/.local/bin/kitten"

echo "  ✓ Kitty: installed ($VERSION -> $DEST)"
