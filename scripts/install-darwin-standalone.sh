#!/usr/bin/env bash
# Install essential standalone CLI binaries for macOS (Intel x86_64 and Apple Silicon arm64)
# without Homebrew, MacPorts, Nix, or Xcode Command Line Tools.
#
# Reads pinned versions, URLs, and checksums from config/packages-darwin-binaries.tsv.
# All binaries are placed in ~/.local/bin; versioned runtime support files in ~/.local/share.
# Idempotent, verified by SHA-256, transactional undo-aware, and recoverable.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="${DOTFILES_DIR:-$(cd "$SCRIPT_DIR/.." && pwd)}"

# Load detection and transaction helpers
source "$DOTFILES_DIR/lib/detect.sh" 2>/dev/null || true
source "$DOTFILES_DIR/lib/trash.sh" 2>/dev/null || true
source "$DOTFILES_DIR/lib/state.sh" 2>/dev/null || true
source "$DOTFILES_DIR/lib/transaction.sh" 2>/dev/null || true

for fn in tx_created_path tx_mkdir tx_symlink tx_run; do
  command -v "$fn" >/dev/null 2>&1 || eval "$fn() { :; }"
done
command -v state_is  >/dev/null 2>&1 || state_is() { return 1; }
command -v state_set >/dev/null 2>&1 || state_set() { :; }
command -v trash_path >/dev/null 2>&1 || trash_path() {
  local p="$1"
  if [ -e "$p" ] || [ -L "$p" ]; then
    local trash="${SETUP_TRASH_ROOT:-$HOME/.shell-trash}/$(date +%s)-$$-$(basename "$p")"
    mkdir -p "$(dirname "$trash")" 2>/dev/null || true
    mv "$p" "$trash" 2>/dev/null || rm -f "$p"
  fi
}

# 1. Verify OS
[ "${OS_TYPE:-$(uname)}" = "Darwin" ] || {
  echo "Darwin standalone installer called on non-Darwin OS: ${OS_TYPE:-unknown}" >&2
  exit 1
}

# 2. Check architecture
CURRENT_ARCH="${ARCH:-$(uname -m)}"
case "$CURRENT_ARCH" in
  x86_64|amd64) TARGET_ARCH="x86_64" ;;
  arm64|aarch64) TARGET_ARCH="arm64" ;;
  *)
    echo "ERROR: Unsupported macOS architecture: $CURRENT_ARCH" >&2
    exit 1
    ;;
esac

# 3. Detect macOS version
MACOS_VER="${MACOS_VERSION:-$(sw_vers -productVersion 2>/dev/null || echo "")}"
MACOS_MAJ="${MACOS_MAJOR:-$(echo "$MACOS_VER" | cut -d. -f1)}"
if [ -z "$MACOS_MAJ" ]; then
  MACOS_MAJ="11"
fi

# 4. Verify native system tools
CURL_BIN="${CURL_BIN:-$(command -v curl 2>/dev/null || echo "/usr/bin/curl")}"
TAR_BIN="${TAR_BIN:-$(command -v tar 2>/dev/null || echo "/usr/bin/tar")}"
UNZIP_BIN="${UNZIP_BIN:-$(command -v unzip 2>/dev/null || echo "/usr/bin/unzip")}"

for tool_path in "$CURL_BIN" "$TAR_BIN"; do
  if [ -z "$tool_path" ] || [ ! -x "$tool_path" ]; then
    echo "ERROR: Native tool missing: $tool_path" >&2
    exit 1
  fi
done

sha256_calc() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    echo "ERROR: Neither shasum nor sha256sum available" >&2
    return 1
  fi
}

MANIFEST="${PACKAGES_DARWIN_MANIFEST:-$DOTFILES_DIR/config/packages-darwin-binaries.tsv}"
[ -f "$MANIFEST" ] || {
  echo "ERROR: Standalone manifest not found: $MANIFEST" >&2
  exit 1
}

LOCAL_BIN="$HOME/.local/bin"
LOCAL_SHARE="$HOME/.local/share"
if [ "${DRY_RUN:-0}" = 1 ]; then
  mkdir -p "$LOCAL_BIN" "$LOCAL_SHARE" 2>/dev/null || true
else
  tx_mkdir "$LOCAL_BIN"
  tx_mkdir "$LOCAL_SHARE"
fi

# Compare macOS versions: returns 0 if host >= required, 1 if host < required
macos_version_ge() {
  local host="$1" required="$2"
  awk -v h="$host" -v r="$required" 'BEGIN { exit (h + 0 >= r + 0) ? 0 : 1 }'
}

echo "  Installing standalone binaries for macOS ($TARGET_ARCH, macOS $MACOS_VER)..."

# Process each entry in the declarative manifest
# Header: tool version minos type bin share url_x86_64 sha256_x86_64 url_arm64 sha256_arm64
while IFS=$'\t' read -r tool version minos pkg_type bin_list share_flag url_x86 sha_x86 url_arm sha_arm; do
  [ "$tool" = "tool" ] && continue
  [ -z "$tool" ] && continue

  # Verify minimum macOS version
  if ! macos_version_ge "$MACOS_MAJ" "$minos"; then
    echo "  $tool: skipped (requires macOS >= $minos; host is macOS $MACOS_VER)"
    continue
  fi

  # Resolve architecture asset
  if [ "$TARGET_ARCH" = "x86_64" ]; then
    download_url="$url_x86"
    expected_sha="$sha_x86"
  else
    download_url="$url_arm"
    expected_sha="$sha_arm"
  fi

  if [ -z "$download_url" ] || [ "$download_url" = "-" ] || [ -z "$expected_sha" ] || [ "$expected_sha" = "-" ]; then
    echo "  $tool: no $TARGET_ARCH release available; skipping"
    continue
  fi

  # Check if all binaries for this tool are already installed and at expected version
  already_installed=1
  IFS=',' read -ra bins <<< "$bin_list"
  for b in "${bins[@]}"; do
    b_name="$(basename "$b")"
    if [ ! -x "$LOCAL_BIN/$b_name" ]; then
      already_installed=0
      break
    fi
  done

  if [ "$already_installed" -eq 1 ] && state_is "standalone.$tool" "$version"; then
    echo "  $tool: already installed ($version)"
    continue
  fi

  if [ "${DRY_RUN:-0}" = 1 ]; then
    echo "  [dry-run] download $tool $version ($TARGET_ARCH) -> $LOCAL_BIN"
    continue
  fi

  # Prepare temporary download workspace
  tmp_dir="$(mktemp -d -t "dotfiles-${tool}.XXXXXX")"
  archive_name="$(basename "${download_url%%\?*}")"
  download_file="$tmp_dir/$archive_name"

  echo "  downloading $tool $version ($TARGET_ARCH)..."
  if ! "$CURL_BIN" -fsSL --retry 3 --max-time 180 -o "$download_file" "$download_url"; then
    echo "ERROR: Failed to download $tool from $download_url" >&2
    rm -rf "$tmp_dir"
    exit 1
  fi

  actual_sha="$(sha256_calc "$download_file")"
  if [ "$actual_sha" != "$expected_sha" ]; then
    echo "ERROR: SHA-256 mismatch for $tool ($archive_name)" >&2
    echo "  expected: $expected_sha" >&2
    echo "  actual:   $actual_sha" >&2
    rm -rf "$tmp_dir"
    exit 1
  fi

  # Unpack archive
  extract_dir="$tmp_dir/extracted"
  mkdir -p "$extract_dir"
  case "$pkg_type" in
    tar.gz|tgz)
      "$TAR_BIN" -xzf "$download_file" -C "$extract_dir"
      ;;
    zip)
      [ -x "$UNZIP_BIN" ] || { echo "ERROR: unzip required for $tool" >&2; rm -rf "$tmp_dir"; exit 1; }
      "$UNZIP_BIN" -q "$download_file" -d "$extract_dir"
      ;;
    binary)
      chmod +x "$download_file"
      cp "$download_file" "$extract_dir/$(basename "$bin_list")"
      ;;
    *)
      echo "ERROR: Unknown package type '$pkg_type' for $tool" >&2
      rm -rf "$tmp_dir"
      exit 1
      ;;
  esac

  # If tool distributes supporting files (share/lib), park in ~/.local/share/<tool>-<version>
  if [ "$share_flag" = "yes" ]; then
    tool_share_dir="$LOCAL_SHARE/$tool-$version"
    # Locate top extracted directory (GitHub tarballs/zips often have a root folder)
    content_dir="$extract_dir"
    subdirs=("$extract_dir"/*)
    if [ "${#subdirs[@]}" -eq 1 ] && [ -d "${subdirs[0]}" ]; then
      content_dir="${subdirs[0]}"
    fi

    # Quarantine any previous version of tool share dir
    if [ -d "$tool_share_dir" ]; then
      trash_path "$tool_share_dir"
    fi

    tx_mkdir "$tool_share_dir"
    cp -R "$content_dir"/* "$tool_share_dir/"

    # Symlink binaries into ~/.local/bin
    for b in "${bins[@]}"; do
      b_name="$(basename "$b")"
      src_bin="$tool_share_dir/$b"
      [ -f "$src_bin" ] || src_bin="$tool_share_dir/bin/$b_name"
      [ -f "$src_bin" ] || src_bin="$(find "$tool_share_dir" -name "$b_name" -type f -perm +111 2>/dev/null | head -n 1 || true)"
      if [ -z "$src_bin" ] || [ ! -f "$src_bin" ]; then
        echo "ERROR: Could not find binary '$b_name' inside extracted $tool" >&2
        rm -rf "$tmp_dir"
        exit 1
      fi
      chmod +x "$src_bin"
      target_link="$LOCAL_BIN/$b_name"
      if [ -e "$target_link" ] || [ -L "$target_link" ]; then
        trash_path "$target_link"
      fi
      tx_symlink "$src_bin" "$target_link"
    done
  else
    # Single or standalone binaries
    for b in "${bins[@]}"; do
      b_name="$(basename "$b")"
      found_bin="$(find "$extract_dir" -name "$b_name" -type f 2>/dev/null | head -n 1 || true)"
      if [ -z "$found_bin" ] || [ ! -f "$found_bin" ]; then
        echo "ERROR: Binary '$b_name' not found in $tool archive" >&2
        rm -rf "$tmp_dir"
        exit 1
      fi
      chmod +x "$found_bin"
      target_bin="$LOCAL_BIN/$b_name"
      if [ -e "$target_bin" ] || [ -L "$target_bin" ]; then
        trash_path "$target_bin"
      fi
      tx_created_path "$target_bin"
      mv "$found_bin" "$target_bin"
    done
  fi

  rm -rf "$tmp_dir"
  state_set "standalone.$tool" "$version"
  echo "  ✓ $tool: installed ($version)"
done < "$MANIFEST"

# 5. Git Availability Check
if command -v git_usable >/dev/null 2>&1 && git_usable; then
  echo "  ✓ git: available ($(command -v git))"
else
  echo "  ! git: no functional Git found on macOS without Command Line Tools."
  echo "    No official standalone x86_64 binary release exists for macOS without Homebrew or CLT."
  echo "    To use Git, install Xcode Command Line Tools manually via 'xcode-select --install'"
  echo "    or place a verified Git binary in ~/.local/bin/git."
fi

echo "  Standalone packages configured."
