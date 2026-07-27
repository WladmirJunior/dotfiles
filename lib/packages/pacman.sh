#!/usr/bin/env bash

pacman_package_installed() {
  pacman -Q "$1" >/dev/null 2>&1
}

pacman_install_required() {
  local pkg new_packages=""
  if [ "${DRY_RUN:-0}" != 1 ]; then
    for pkg in "$@"; do
      pacman_package_installed "$pkg" || new_packages="${new_packages:+$new_packages }$pkg"
    done
    if [ -n "$new_packages" ] && command -v tx_pacman_install >/dev/null 2>&1; then
      # shellcheck disable=SC2086
      tx_pacman_install $new_packages
    fi
  fi
  # shellcheck disable=SC2086 # SUDO is empty or a command prefix.
  run ${SUDO:+$SUDO} pacman -Syu --needed --noconfirm "$@"
}

export -f pacman_package_installed pacman_install_required 2>/dev/null || true
