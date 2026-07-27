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
[ "$pacman_core" = '7zip bat curl eza fastfetch fd fzf git git-delta github-cli glow gum hexyl jq neovim nodejs npm perl-image-exiftool pkgfile resvg ripgrep tealdeer wget yazi zoxide zsh' ] || {
  echo "unexpected Pacman catalog order: $pacman_core" >&2
  exit 1
}
[ "$dnf_core" = 'bat curl fd-find fzf gh git jq neovim nodejs npm ripgrep wget zoxide zsh' ] || {
  echo "unexpected DNF catalog order: $dnf_core" >&2
  exit 1
}

echo "Package catalog tests passed."
