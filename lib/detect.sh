#!/bin/bash
# Environment detection. Sourced by steps.
# Exports: OS_TYPE, ARCH, DISTRO_ID, DISTRO_FAMILY, PACKAGE_MANAGER,
#          IS_VM, IS_CONTAINER, HEADLESS, INTERACTIVE

OS_TYPE="$(uname)"
ARCH="$(uname -m)"
DISTRO_ID=""
DISTRO_FAMILY=""
PACKAGE_MANAGER=""

if [ "$OS_TYPE" = "Darwin" ]; then
  DISTRO_ID="macos"
  DISTRO_FAMILY="darwin"
  PACKAGE_MANAGER="brew"
elif [ "$OS_TYPE" = "Linux" ]; then
  # /etc/os-release is the stable distro interface. ID_LIKE lets derivatives
  # (EndeavourOS, CachyOS, Kali, Ubuntu, etc.) inherit the right package path.
  if [ -r /etc/os-release ]; then
    DISTRO_ID="$(. /etc/os-release; printf '%s' "${ID:-linux}")"
    _id_like="$(. /etc/os-release; printf '%s' "${ID_LIKE:-}")"
  else
    DISTRO_ID="linux"
    _id_like=""
  fi
  case " $DISTRO_ID $_id_like " in
    *" arch "*)   DISTRO_FAMILY="arch"; PACKAGE_MANAGER="pacman" ;;
    *" debian "*) DISTRO_FAMILY="debian"; PACKAGE_MANAGER="apt" ;;
    *)
      command -v pacman >/dev/null 2>&1 && { DISTRO_FAMILY="arch"; PACKAGE_MANAGER="pacman"; }
      if [ -z "$PACKAGE_MANAGER" ] && command -v apt-get >/dev/null 2>&1; then
        DISTRO_FAMILY="debian"; PACKAGE_MANAGER="apt"
      fi
      ;;
  esac
fi

IS_VM="no"
IS_CONTAINER="no"
if [ "$OS_TYPE" = "Darwin" ]; then
  MODEL_ID=$(system_profiler SPHardwareDataType 2>/dev/null | awk -F': ' '/Model Identifier/ {print $2}')
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

INTERACTIVE="no"
[ -t 0 ] && INTERACTIVE="yes"

export OS_TYPE ARCH DISTRO_ID DISTRO_FAMILY PACKAGE_MANAGER IS_VM IS_CONTAINER HEADLESS INTERACTIVE
