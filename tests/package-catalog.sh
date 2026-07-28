#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOTFILES_DIR="$ROOT"
source "$ROOT/lib/packages/catalog.sh"

[ "$(package_for github-cli brew core)" = gh ]
[ "$(package_for github-cli pacman core)" = github-cli ]
[ "$(package_for metadata apt best-effort)" = libimage-exiftool-perl ]
[ "$(package_for metadata dnf best-effort)" = perl-Image-ExifTool ]
[ "$(package_for node-runtime apt core)" = 'nodejs npm' ]

sorted_packages() { tr ' ' '\n' | sed '/^$/d' | sort | paste -sd ' ' -; }
brew_core="$(package_catalog core brew | sorted_packages)"
apt_core="$(package_catalog core apt | sorted_packages)"
pacman_core="$(package_catalog core pacman | sorted_packages)"
dnf_core="$(package_catalog core dnf | sorted_packages)"

[ "$brew_core" = 'bat charmbracelet/tap/freeze charmbracelet/tap/wishlist coreutils exiftool eza fastfetch fd fzf gh git git-delta glow hexyl lua-language-server neovim node resvg ripgrep sevenzip tlrc tree-sitter-cli usbutils vhs yazi zoxide' ] || {
  echo "unexpected Homebrew catalog order: $brew_core" >&2
  exit 1
}
[ "$apt_core" = 'bat curl fd-find fzf gh git git-delta hexyl neovim nodejs npm ripgrep wget zoxide zsh' ] || {
  echo "unexpected APT catalog order: $apt_core" >&2
  exit 1
}
[ "$pacman_core" = '7zip bat curl eza fastfetch fd fzf git git-delta github-cli glow gum hexyl jq lua-language-server neovim nodejs npm perl-image-exiftool pkgfile resvg ripgrep tealdeer tree-sitter-cli usbutils vhs wget wishlist yazi zoxide zsh' ] || {
  echo "unexpected Pacman catalog order: $pacman_core" >&2
  exit 1
}
[ "$dnf_core" = 'bat curl fd-find fzf gh git jq neovim nodejs npm ripgrep wget zoxide zsh' ] || {
  echo "unexpected DNF catalog order: $dnf_core" >&2
  exit 1
}

# ── Schema validation: a malformed catalog must abort with the line number ────
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
TSV_HEADER='scope	capability	brew	apt	pacman	dnf'

# expect_invalid FILE FRAGMENT: both lookup entry points must fail closed and
# name the offending line.
expect_invalid() {
  local file="$1" fragment="$2" out rc
  rc=0; out="$( (PACKAGE_CATALOG_FILE="$file" package_catalog core apt) 2>&1 )" || rc=$?
  [ "$rc" -ne 0 ] || { echo "package_catalog accepted malformed catalog $file" >&2; exit 1; }
  grep -qF "$fragment" <<<"$out" || {
    echo "missing '$fragment' in error for $file: $out" >&2; exit 1
  }
  rc=0; out="$( (PACKAGE_CATALOG_FILE="$file" package_for shell apt) 2>&1 )" || rc=$?
  [ "$rc" -ne 0 ] || { echo "package_for accepted malformed catalog $file" >&2; exit 1; }
}

printf '%s\ncore\tshell\t-\tzsh\tzsh\tzsh\ncore\teditor\tneovim\tneovim\tneovim\n' "$TSV_HEADER" \
  > "$TMP/short-row.tsv"
expect_invalid "$TMP/short-row.tsv" 'line 3: expected 6 tab-separated columns, found 5'

printf '%s\ncoreish\tshell\t-\tzsh\tzsh\tzsh\n' "$TSV_HEADER" > "$TMP/bad-scope.tsv"
expect_invalid "$TMP/bad-scope.tsv" 'line 2: unknown scope "coreish"'

printf '%s\ncore\tshell\t-\tzsh\tzsh\tzsh\ncore\tshell\t-\tbash\tbash\tbash\n' "$TSV_HEADER" \
  > "$TMP/dup.tsv"
expect_invalid "$TMP/dup.tsv" 'line 3: duplicate capability "shell" in scope "core"'

printf '%s\ncore\t-\t-\tzsh\tzsh\tzsh\n' "$TSV_HEADER" > "$TMP/no-capability.tsv"
expect_invalid "$TMP/no-capability.tsv" 'line 2: missing capability'

printf '%s\ncore\tshell\t-\t\tzsh\tzsh\n' "$TSV_HEADER" > "$TMP/empty-cell.tsv"
expect_invalid "$TMP/empty-cell.tsv" 'line 2: empty package column 4'

# The same capability in DIFFERENT scopes is legitimate (core on one distro,
# best-effort on another); only a same-scope duplicate is an error.
printf '%s\ncore\tshell\t-\tzsh\tzsh\tzsh\nbest-effort\tshell\t-\tzsh\t-\tzsh\n' "$TSV_HEADER" \
  > "$TMP/cross-scope.tsv"
[ "$(PACKAGE_CATALOG_FILE="$TMP/cross-scope.tsv" package_for shell apt best-effort)" = zsh ]

# Sourcing the library over a malformed catalog fails at load, before any lookup.
if PACKAGE_CATALOG_FILE="$TMP/bad-scope.tsv" \
  bash -c 'source "$1/lib/packages/catalog.sh" && echo reached' _ "$ROOT" 2>"$TMP/load.err"; then
  echo "sourcing catalog.sh succeeded despite a malformed catalog" >&2
  exit 1
fi
grep -qF 'line 2: unknown scope "coreish"' "$TMP/load.err"

echo "Package catalog tests passed."
