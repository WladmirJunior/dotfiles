#!/usr/bin/env bash

apt_package_installed() {
  dpkg-query -W -f='${db:Status-Abbrev}' "$1" 2>/dev/null | grep -q '^ii'
}

apt_install_required() {
  local pkg new_packages=""
  if [ "${DRY_RUN:-0}" != 1 ]; then
    for pkg in "$@"; do
      apt_package_installed "$pkg" || new_packages="${new_packages:+$new_packages }$pkg"
    done
    if [ -n "$new_packages" ] && command -v tx_apt_install >/dev/null 2>&1; then
      # shellcheck disable=SC2086
      tx_apt_install $new_packages
    fi
  fi
  # shellcheck disable=SC2086 # SUDO is empty or a command prefix.
  run ${SUDO:+$SUDO} env DEBIAN_FRONTEND=noninteractive apt-get install -y "$@"
}

apt_install_optional() {
  local pkg was_installed
  for pkg in "$@"; do
    was_installed=0
    apt_package_installed "$pkg" && was_installed=1
    # shellcheck disable=SC2086
    if run ${SUDO:+$SUDO} env DEBIAN_FRONTEND=noninteractive apt-get install -y "$pkg" 2>/dev/null; then
      if [ "${DRY_RUN:-0}" != 1 ] && [ "$was_installed" != 1 ] \
        && command -v tx_apt_install >/dev/null 2>&1; then
        tx_apt_install "$pkg"
      fi
    else
      echo "  skip: $pkg not available in this distro"
    fi
  done
}

export -f apt_package_installed apt_install_required apt_install_optional 2>/dev/null || true
