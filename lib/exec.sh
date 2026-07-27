#!/usr/bin/env bash
# Shared command execution helpers for public and private installers.

run() {
  if [ "${DRY_RUN:-0}" = 1 ]; then
    printf '%s%s[dry-run]%s %s\n' "${PAD:-  }" "${c_info:-}" "${c_reset:-}" "$*"
    return 0
  fi
  "$@"
}

# run_logged LABEL LOG COMMAND...
# Keep successful output in LOG and show the last lines when COMMAND fails.
run_logged() {
  local label="$1" log="$2" rc
  shift 2
  mkdir -p "$(dirname "$log")"

  if [ "${DRY_RUN:-0}" = 1 ]; then
    run "$@"
    return $?
  fi

  if command -v spin >/dev/null 2>&1; then
    # shellcheck disable=SC2016 # expansion belongs to the child bash.
    spin "$label · details in $log" -- \
      bash -c 'log=$1; shift; "$@" >>"$log" 2>&1' _ "$log" "$@"
    rc=$?
  else
    "$@" >>"$log" 2>&1
    rc=$?
  fi

  if [ "$rc" -ne 0 ]; then
    printf '%s\n' "$label failed; last log lines:" >&2
    tail -n "${RUN_LOGGED_TAIL:-30}" "$log" >&2 2>/dev/null || true
  fi
  return "$rc"
}

export -f run run_logged 2>/dev/null || true
