#!/usr/bin/env bash
# Tests for Kitty themes and shaders ported from Ghostty
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# 1. Verify existence of all 4 themes and shaders
for theme in retro ghost green amber; do
  [ -f "$ROOT/config/kitty/themes/${theme}.conf" ] || { echo "FAIL: missing theme $theme" >&2; exit 1; }
done

for shader in bloom-h bloom-v crt in-game-crt in-game-crt-chroma retro-terminal; do
  [ -f "$ROOT/config/kitty/shaders/${shader}.glsl" ] || { echo "FAIL: missing shader $shader" >&2; exit 1; }
done

# 2. Test kitty-theme CLI
export XDG_CONFIG_HOME="$TMP/config"
mkdir -p "$XDG_CONFIG_HOME/kitty/themes"
cp "$ROOT/config/kitty/themes/"* "$XDG_CONFIG_HOME/kitty/themes/"

list_out="$("$ROOT/scripts/kitty-theme" list)"
for t in retro ghost green amber; do
  echo "$list_out" | grep -q "^$t$" || { echo "FAIL: $t not in kitty-theme list" >&2; exit 1; }
done

# Apply retro
"$ROOT/scripts/kitty-theme" apply retro
curr="$("$ROOT/scripts/kitty-theme" current)"
[ "$curr" = "retro" ] || { echo "FAIL: expected current theme to be retro, got $curr" >&2; exit 1; }
grep -q "include themes/retro.conf" "$XDG_CONFIG_HOME/kitty/theme.conf"

# Apply ghost
"$ROOT/scripts/kitty-theme" apply ghost
curr="$("$ROOT/scripts/kitty-theme" current)"
[ "$curr" = "ghost" ] || { echo "FAIL: expected current theme to be ghost, got $curr" >&2; exit 1; }
grep -q "include themes/ghost.conf" "$XDG_CONFIG_HOME/kitty/theme.conf"

# Invalid theme fails
set +e
"$ROOT/scripts/kitty-theme" apply nonexistent 2>/dev/null
rc=$?
set -e
[ "$rc" -ne 0 ] || { echo "FAIL: invalid theme did not return error" >&2; exit 1; }

# 3. Test link_kitty_config and install_kitty_font in install-kitty.sh
HOME="$TMP/home"
mkdir -p "$HOME/Applications" "$HOME/.local/bin"
# Mock already installed kitty.app
mkdir -p "$HOME/Applications/kitty.app/Contents/MacOS"
touch "$HOME/Applications/kitty.app/Contents/MacOS/kitty"
touch "$HOME/Applications/kitty.app/Contents/MacOS/kitten"

DOTFILES_DIR="$ROOT" \
DOTFILES_PRIVATE_DIR="$TMP/nonexistent" \
APPLICATIONS_DIR="$HOME/Applications" \
HOME="$TMP/home" \
DRY_RUN=1 \
  bash "$ROOT/scripts/install-kitty.sh"

[ -L "$TMP/home/.config/kitty/kitty.conf" ]
[ -L "$TMP/home/.config/kitty/themes" ]
[ -L "$TMP/home/.config/kitty/shaders" ]
[ -L "$TMP/home/.local/bin/kitty-theme" ]

echo "Kitty themes and shaders tests passed."
