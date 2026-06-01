#!/bin/bash
# Environment detection. Sourced by steps.
# Exports: OS_TYPE, ARCH, IS_VM, HEADLESS, INTERACTIVE

OS_TYPE="$(uname)"
ARCH="$(uname -m)"

IS_VM="no"
if [ "$OS_TYPE" = "Darwin" ]; then
  MODEL_ID=$(system_profiler SPHardwareDataType 2>/dev/null | awk -F': ' '/Model Identifier/ {print $2}')
  case "$MODEL_ID" in
    VirtualMachine*|VMware*|Parallels*) IS_VM="yes" ;;
  esac
elif [ "$OS_TYPE" = "Linux" ]; then
  if command -v systemd-detect-virt >/dev/null 2>&1; then
    [ "$(systemd-detect-virt 2>/dev/null || echo none)" != "none" ] && IS_VM="yes"
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

export OS_TYPE ARCH IS_VM HEADLESS INTERACTIVE
