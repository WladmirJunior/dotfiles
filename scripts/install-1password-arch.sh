#!/bin/bash
# Install the 1Password desktop app and CLI from the AUR on Arch Linux.
# The desktop package is maintained by 1Password and its source is signed with
# the vendor key documented at https://support.1password.com/install-linux/.
set -euo pipefail

[ "${PACKAGE_MANAGER:-}" = "pacman" ] || {
  echo "  1Password: Arch installer skipped (pacman not detected)"
  exit 0
}

if [ "${DRY_RUN:-0}" = 1 ]; then
  echo "[dry-run] install/update 1password and 1password-cli from the AUR"
  exit 0
fi

[ "$(id -u)" -ne 0 ] || {
  echo "  1Password: AUR packages must be built as a regular user, not root" >&2
  exit 1
}
command -v sudo >/dev/null 2>&1 || {
  echo "  1Password: sudo is required to install AUR dependencies" >&2
  exit 1
}

dependencies=(base-devel git curl gnupg)
missing_dependencies=()
for dependency in "${dependencies[@]}"; do
  pacman -Q "$dependency" >/dev/null 2>&1 || missing_dependencies+=("$dependency")
done
if [ "${#missing_dependencies[@]}" -gt 0 ]; then
  sudo pacman -S --needed --noconfirm "${missing_dependencies[@]}"
fi

key_url="https://downloads.1password.com/linux/keys/1password.asc"
key_fingerprint="3FEF9748469ADBE15DA7CA80AC2D62742012EA22"
aur_cache="${XDG_CACHE_HOME:-$HOME/.cache}/dotfiles/aur"
mkdir -p "$aur_cache"

# Import the vendor key only once. Reimporting an existing key prints warnings
# about third-party certifications whose signer keys are not in the local
# keyring; those warnings do not concern the verified 1Password source signature.
if ! gpg --batch --with-colons --list-keys "$key_fingerprint" 2>/dev/null \
    | awk -F: -v expected="$key_fingerprint" '$1 == "fpr" && $10 == expected { found=1 } END { exit !found }'; then
  key_file="$(mktemp)"
  trap 'rm -f "$key_file"' EXIT
  curl -fsSL "$key_url" -o "$key_file"
  actual_fingerprint="$(gpg --show-keys --with-colons "$key_file" |
    awk -F: '$1 == "fpr" { print $10; exit }')"
  [ "$actual_fingerprint" = "$key_fingerprint" ] || {
    echo "  1Password: signing-key fingerprint mismatch" >&2
    exit 1
  }
  gpg --batch --quiet --import-options import-minimal --import "$key_file"
fi

package_files=()
for package in 1password 1password-cli; do
  package_dir="$aur_cache/$package"
  if [ -d "$package_dir/.git" ]; then
    echo "  1Password: checking $package for updates..."
    git -C "$package_dir" pull --ff-only
  elif [ -e "$package_dir" ]; then
    echo "  1Password: cache path exists but is not an AUR clone: $package_dir" >&2
    echo "  Move or remove that path and re-run the installer." >&2
    exit 1
  else
    git clone --depth 1 "https://aur.archlinux.org/$package.git" "$package_dir"
  fi

  # Do not ask makepkg to reinstall an already-current artifact. `makepkg -si`
  # delegates to sudo once per package even when pacman ultimately has nothing
  # to do; comparing the AUR metadata first avoids both needless builds and
  # password prompts.
  srcinfo="$(cd "$package_dir" && makepkg --printsrcinfo)"
  aur_pkgver="$(awk -F' = ' '$1 ~ /^[[:space:]]*pkgver$/ { print $2; exit }' <<<"$srcinfo")"
  aur_pkgrel="$(awk -F' = ' '$1 ~ /^[[:space:]]*pkgrel$/ { print $2; exit }' <<<"$srcinfo")"
  aur_epoch="$(awk -F' = ' '$1 ~ /^[[:space:]]*epoch$/ { print $2; exit }' <<<"$srcinfo")"
  aur_version="${aur_epoch:+$aur_epoch:}$aur_pkgver-$aur_pkgrel"
  installed_version="$(pacman -Q "$package" 2>/dev/null | awk '{print $2}' || true)"
  if [ -n "$installed_version" ] && [ "$(vercmp "$installed_version" "$aur_version")" -ge 0 ]; then
    echo "  1Password: $package $installed_version is current"
    continue
  fi

  (
    cd "$package_dir"
    makepkg --cleanbuild --clean --noconfirm
  )
  while IFS= read -r package_file; do
    package_files+=("$package_file")
  done < <(cd "$package_dir" && makepkg --packagelist)
done

if [ "${#package_files[@]}" -gt 0 ]; then
  # Install every newly built package in one pacman transaction and therefore
  # one sudo invocation, instead of one prompt per AUR package.
  sudo pacman -U --needed --noconfirm "${package_files[@]}"
fi

echo "  1Password: app and CLI are up to date"
