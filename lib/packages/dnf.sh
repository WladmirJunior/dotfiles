#!/usr/bin/env bash

dnf_package_installed() {
  rpm -q "$1" >/dev/null 2>&1
}

dnf_install_required() {
  local pkg new_packages=""
  if [ "${DRY_RUN:-0}" != 1 ]; then
    for pkg in "$@"; do
      dnf_package_installed "$pkg" || new_packages="${new_packages:+$new_packages }$pkg"
    done
    if [ -n "$new_packages" ] && command -v tx_dnf_install >/dev/null 2>&1; then
      # shellcheck disable=SC2086
      tx_dnf_install $new_packages
    fi
  fi
  # shellcheck disable=SC2086 # SUDO is empty or a command prefix.
  run ${SUDO:+$SUDO} dnf install -y -q "$@"
}

dnf_install_optional() {
  local pkg
  for pkg in "$@"; do
    dnf_package_installed "$pkg" && continue
    # shellcheck disable=SC2086
    if run ${SUDO:+$SUDO} dnf install -y -q "$pkg" 2>/dev/null; then
      if [ "${DRY_RUN:-0}" != 1 ] && command -v tx_dnf_install >/dev/null 2>&1; then
        tx_dnf_install "$pkg"
      fi
    else
      echo "  skip: $pkg not available in this Fedora-family release"
    fi
  done
}

export -f dnf_package_installed dnf_install_required dnf_install_optional 2>/dev/null || true
