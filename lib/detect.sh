#!/bin/bash
# Environment detection. Sourced by steps.
# Exports: OS_TYPE, ARCH, DISTRO_ID, DISTRO_FAMILY, PACKAGE_MANAGER,
#          IS_VM, IS_CONTAINER, HEADLESS, INTERACTIVE

OS_TYPE="${OS_TYPE:-$(uname)}"
ARCH="${ARCH:-$(uname -m)}"
case "$ARCH" in
  x86_64|amd64) ARCH="x86_64" ;;
  arm64|aarch64) ARCH="arm64" ;;
esac
DISTRO_ID=""
DISTRO_FAMILY=""
PACKAGE_MANAGER=""
MACOS_VERSION=""
MACOS_MAJOR=""

if [ "$OS_TYPE" = "Darwin" ]; then
  DISTRO_ID="macos"
  DISTRO_FAMILY="darwin"
  MACOS_VERSION="${MACOS_VERSION:-$(sw_vers -productVersion 2>/dev/null || echo "")}"
  MACOS_MAJOR="${MACOS_MAJOR:-$(echo "$MACOS_VERSION" | cut -d. -f1)}"
  PACKAGE_MANAGER="brew"
elif [ "$OS_TYPE" = "Linux" ]; then
  # /etc/os-release is the stable distro interface. ID_LIKE lets derivatives
  # (EndeavourOS, CachyOS, Kali, Ubuntu, etc.) inherit the right package path.
  OS_RELEASE_FILE="${OS_RELEASE_FILE:-/etc/os-release}"
  if [ -r "$OS_RELEASE_FILE" ]; then
    DISTRO_ID="$(. "$OS_RELEASE_FILE"; printf '%s' "${ID:-linux}")"
    _id_like="$(. "$OS_RELEASE_FILE"; printf '%s' "${ID_LIKE:-}")"
  else
    DISTRO_ID="linux"
    _id_like=""
  fi
  case " $DISTRO_ID $_id_like " in
    *" arch "*)   DISTRO_FAMILY="arch"; PACKAGE_MANAGER="pacman" ;;
    *" debian "*) DISTRO_FAMILY="debian"; PACKAGE_MANAGER="apt" ;;
    *" fedora "*|*" rhel "*|*" centos "*) DISTRO_FAMILY="fedora"; PACKAGE_MANAGER="dnf" ;;
    *)
      command -v pacman >/dev/null 2>&1 && { DISTRO_FAMILY="arch"; PACKAGE_MANAGER="pacman"; }
      if [ -z "$PACKAGE_MANAGER" ] && command -v apt-get >/dev/null 2>&1; then
        DISTRO_FAMILY="debian"; PACKAGE_MANAGER="apt"
      fi
      if [ -z "$PACKAGE_MANAGER" ] && command -v dnf >/dev/null 2>&1; then
        DISTRO_FAMILY="fedora"; PACKAGE_MANAGER="dnf"
      fi
      ;;
  esac
fi

IS_VM="no"
IS_CONTAINER="no"
if [ "$OS_TYPE" = "Darwin" ]; then
  _sp_bin="$(command -v system_profiler 2>/dev/null || true)"
  [ -z "$_sp_bin" ] && [ -x /usr/sbin/system_profiler ] && _sp_bin=/usr/sbin/system_profiler
  if [ -n "$_sp_bin" ]; then
    MODEL_ID=$("$_sp_bin" SPHardwareDataType 2>/dev/null | awk -F': ' '/Model Identifier/ {print $2}')
  else
    MODEL_ID=""
  fi
  # VirtualMac*: Apple Virtualization.framework (tart, UTM, VirtualBuddy on Apple Silicon).
  case "$MODEL_ID" in
    VirtualMachine*|VirtualMac*|VMware*|Parallels*) IS_VM="yes" ;;
  esac
elif [ "$OS_TYPE" = "Linux" ]; then
  if command -v systemd-detect-virt >/dev/null 2>&1; then
    # Containers and hardware VMs are distinct. The unqualified command reports
    # both, which used to classify containers such as distrobox/toolbox as VMs.
    systemd-detect-virt --vm --quiet 2>/dev/null && IS_VM="yes"
    systemd-detect-virt --container --quiet 2>/dev/null && IS_CONTAINER="yes"
  elif grep -q "hypervisor" /proc/cpuinfo 2>/dev/null; then
    IS_VM="yes"
  fi
fi

HEADLESS="no"
if [ "$OS_TYPE" = "Linux" ]; then
  if [ -z "${DISPLAY:-}" ] && [ -z "${WAYLAND_DISPLAY:-}" ]; then
    HEADLESS="yes"
  fi
fi

git_usable() {
  command -v git >/dev/null 2>&1 || return 1
  if [ "${OS_TYPE:-$(uname)}" = "Darwin" ]; then
    local git_path
    git_path="$(command -v git 2>/dev/null || true)"
    if [ "$git_path" = "/usr/bin/git" ]; then
      xcode-select -p >/dev/null 2>&1 || return 1
    fi
  fi
  return 0
}

detect_native_tools() {
  local missing=0
  for t in curl tar unzip sh; do
    if ! command -v "$t" >/dev/null 2>&1; then
      missing=$((missing + 1))
    fi
  done
  return "$missing"
}

export OS_TYPE ARCH DISTRO_ID DISTRO_FAMILY PACKAGE_MANAGER MACOS_VERSION MACOS_MAJOR IS_VM IS_CONTAINER HEADLESS INTERACTIVE
export -f git_usable detect_native_tools 2>/dev/null || true
