#!/bin/bash
# Install Hammerspoon on macOS without Homebrew and wire the yabai hotkey layer.
# Downloads the official release zip, verifies SHA-256, bundle ID and code
# signature, stages into /Applications (or ~/Applications) and links the config.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="${DOTFILES_DIR:-$(cd "$SCRIPT_DIR/.." && pwd)}"

command -v tx_created_path >/dev/null 2>&1 || tx_created_path() { :; }
command -v tx_run >/dev/null 2>&1 || tx_run() {
  while [ "$#" -gt 0 ] && [ "$1" != "--" ]; do shift; done
  shift
  "$@"
}

APPLICATIONS_DIR="${APPLICATIONS_DIR:-/Applications}"
DEST="$APPLICATIONS_DIR/Hammerspoon.app"
EXPECTED_BUNDLE_ID="org.hammerspoon.Hammerspoon"

SW_VERS_BIN="${SW_VERS_BIN:-sw_vers}"
MACOS_VER="$($SW_VERS_BIN -productVersion 2>/dev/null || echo "11.0")"
MACOS_MAJ="${MACOS_VER%%.*}"

# LSMinimumSystemVersion: 1.1.x needs macOS 13, 1.0.0 needs 12, 0.9.100 needs 11.
if [ "$MACOS_MAJ" -ge 13 ]; then
  DEFAULT_VERSION="1.1.1"
  DEFAULT_SHA="11bb1c90faf5427f37c7bd4fe7eab9774ae43e1d5cb020c5b3088dac32849efa"
elif [ "$MACOS_MAJ" -ge 12 ]; then
  DEFAULT_VERSION="1.0.0"
  DEFAULT_SHA="5db702b55da47dc306e8f5948d91ef85bebd315ddfa29428322a0af7ed7e6a7e"
else
  DEFAULT_VERSION="0.9.100"
  DEFAULT_SHA="6dcfc807c7cec692caf3b18c36cc1ea3af6b9f42699b4df277734408e4e07399"
fi
VERSION="${HAMMERSPOON_VERSION:-$DEFAULT_VERSION}"
EXPECTED_SHA="${HAMMERSPOON_SHA256:-$DEFAULT_SHA}"
DOWNLOAD_URL="${HAMMERSPOON_DOWNLOAD_URL:-https://github.com/Hammerspoon/hammerspoon/releases/download/${VERSION}/Hammerspoon-${VERSION}.zip}"

CURL_BIN="${CURL_BIN:-curl}"
DITTO_BIN="${DITTO_BIN:-/usr/bin/ditto}"
XATTR_BIN="${XATTR_BIN:-/usr/bin/xattr}"
PLISTBUDDY_BIN="${PLISTBUDDY_BIN:-/usr/libexec/PlistBuddy}"
CODESIGN_BIN="${CODESIGN_BIN:-/usr/bin/codesign}"
SHASUM_BIN="${SHASUM_BIN:-shasum}"
UNAME_BIN="${UNAME_BIN:-uname}"

[ "$($UNAME_BIN -s)" = "Darwin" ] || { echo "  Hammerspoon: macOS only, skipping"; exit 0; }

if [ ! -w "$APPLICATIONS_DIR" ] && [ ! -d "$DEST" ]; then
  APPLICATIONS_DIR="$HOME/Applications"
  DEST="$APPLICATIONS_DIR/Hammerspoon.app"
  mkdir -p "$APPLICATIONS_DIR"
fi

# link_config: ~/.hammerspoon/yabai.lua always; init.lua only when it is absent
# or already ours, so a private overlay's init.lua is never replaced.
link_config() {
  local src="$DOTFILES_DIR/config/hammerspoon" dir="$HOME/.hammerspoon" init
  [ -d "$src" ] || return 0
  if [ "${DRY_RUN:-0}" = 1 ]; then
    echo "  [dry-run] link $src/{init,yabai}.lua -> $dir"
    return 0
  fi
  mkdir -p "$dir"
  if [ ! -e "$dir/yabai.lua" ] && [ ! -L "$dir/yabai.lua" ]; then
    tx_created_path "$dir/yabai.lua"
  fi
  ln -sfn "$src/yabai.lua" "$dir/yabai.lua"
  init="$dir/init.lua"
  if [ ! -e "$init" ] && [ ! -L "$init" ]; then
    tx_created_path "$init"
    ln -sfn "$src/init.lua" "$init"
  elif [ "$(readlink "$init" 2>/dev/null || true)" != "$src/init.lua" ]; then
    echo "  Hammerspoon: keeping existing $init; add require('yabai') to it for the yabai hotkeys"
  fi
}

# enable_desktop_hotkeys: Mission Control "Switch to Desktop 1..9" on Ctrl+1..9
# (symbolic hotkeys 118-126). Without yabai's scripting addition this is the
# only way to switch spaces, and yabai.lua sends these shortcuts. Also keep
# spaces in a fixed order so a number always names the same desktop.
enable_desktop_hotkeys() {
  if [ "${DRY_RUN:-0}" = 1 ]; then
    echo "  [dry-run] enable Mission Control Ctrl+1..9 and fixed space order"
    return 0
  fi
  local keycodes=(18 19 20 21 23 22 26 28 25) i id changed=0
  local plist="$HOME/Library/Preferences/com.apple.symbolichotkeys.plist"
  for i in 0 1 2 3 4 5 6 7 8; do
    id=$((118 + i))
    [ "$($PLISTBUDDY_BIN -c "Print :AppleSymbolicHotKeys:$id:enabled" "$plist" 2>/dev/null)" = true ] && continue
    changed=1
    tx_run "symbolichotkey:$id" defaults write com.apple.symbolichotkeys AppleSymbolicHotKeys -dict-add "$id" \
      "<dict><key>enabled</key><false/><key>value</key><dict><key>parameters</key><array><integer>65535</integer><integer>${keycodes[i]}</integer><integer>262144</integer></array><key>type</key><string>standard</string></dict></dict>" \
      -- defaults write com.apple.symbolichotkeys AppleSymbolicHotKeys -dict-add "$id" \
      "<dict><key>enabled</key><true/><key>value</key><dict><key>parameters</key><array><integer>65535</integer><integer>${keycodes[i]}</integer><integer>262144</integer></array><key>type</key><string>standard</string></dict></dict>"
  done
  if [ "$changed" = 1 ]; then
    /System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings -u 2>/dev/null || true
  fi

  if [ "$(defaults read com.apple.dock mru-spaces 2>/dev/null || echo 1)" != 0 ]; then
    tx_run "dock:mru-spaces" defaults delete com.apple.dock mru-spaces \
      -- defaults write com.apple.dock mru-spaces -bool false
    killall Dock 2>/dev/null || true
  fi
}

launch() {
  [ "${DRY_RUN:-0}" = 1 ] && return 0
  open -a "$DEST" 2>/dev/null || true
  echo "  Hammerspoon: grant it Accessibility in System Preferences > Security & Privacy > Privacy"
}

if [ -d "$DEST" ] && [ "${DOTFILES_UPDATE:-0}" != 1 ]; then
  echo "  Hammerspoon: already installed ($DEST)"
  link_config
  enable_desktop_hotkeys
  launch
  exit 0
fi

if [ "${DRY_RUN:-0}" = 1 ]; then
  echo "[dry-run] install Hammerspoon $VERSION -> $DEST"
  link_config
  enable_desktop_hotkeys
  exit 0
fi

tmp_dir="$(mktemp -d -t hammerspoon-install.XXXXXX)"
trap 'rm -rf "$tmp_dir"' EXIT INT TERM
zip="$tmp_dir/Hammerspoon.zip"

echo "  Hammerspoon: downloading $VERSION..."
if ! "$CURL_BIN" -fL --retry 3 --max-time 180 -o "$zip" "$DOWNLOAD_URL"; then
  echo "  Hammerspoon: download failed from $DOWNLOAD_URL" >&2
  exit 1
fi

actual_sha="$($SHASUM_BIN -a 256 "$zip" | awk '{print $1}')"
if [ "$actual_sha" != "$EXPECTED_SHA" ]; then
  echo "  Hammerspoon: SHA-256 mismatch (expected $EXPECTED_SHA, got $actual_sha)" >&2
  exit 1
fi

"$DITTO_BIN" -x -k "$zip" "$tmp_dir/unzipped"
stage="$tmp_dir/unzipped/Hammerspoon.app"
[ -d "$stage" ] || { echo "  Hammerspoon: Hammerspoon.app missing from zip" >&2; exit 1; }

bundle_id="$($PLISTBUDDY_BIN -c 'Print :CFBundleIdentifier' "$stage/Contents/Info.plist" 2>/dev/null || true)"
if [ "$bundle_id" != "$EXPECTED_BUNDLE_ID" ]; then
  echo "  Hammerspoon: unexpected bundle ID: ${bundle_id:-none}" >&2
  exit 1
fi
if ! "$CODESIGN_BIN" --verify --deep --strict "$stage" 2>/dev/null; then
  echo "  Hammerspoon: code signature verification failed" >&2
  exit 1
fi
"$XATTR_BIN" -dr com.apple.quarantine "$stage" 2>/dev/null || true

mkdir -p "$APPLICATIONS_DIR"
tx_created_path "$DEST" hammerspoon-app
mv "$stage" "$DEST"
echo "  ✓ Hammerspoon: installed ($VERSION -> $DEST)"

link_config
enable_desktop_hotkeys
launch
