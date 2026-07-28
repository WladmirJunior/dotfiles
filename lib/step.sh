#!/usr/bin/env bash
# Step metadata and execution contract shared by installer orchestrators.
#
# Exit-status contract: a step exits 0 on success. It may exit STEP_SKIPPED or
# STEP_DEPENDENCY_UNAVAILABLE to signal a NON-FATAL outcome: the orchestrator
# announces it and continues with the next step (no abort, no rollback); see
# step_status_label. Any other non-zero status (including STEP_AUTH_REQUIRED,
# which means a human must intervene) aborts the install and rolls back.

readonly STEP_OK=0
readonly STEP_SKIPPED=10
readonly STEP_DEPENDENCY_UNAVAILABLE=20
readonly STEP_AUTH_REQUIRED=30

# step_status_label RC: echo a human-readable label when RC is one of the
# continue-without-abort statuses above; fail (empty output) otherwise, in
# which case the caller must treat RC as fatal.
step_status_label() {
  case "$1" in
    "$STEP_SKIPPED") printf 'skipped\n' ;;
    "$STEP_DEPENDENCY_UNAVAILABLE") printf 'dependency unavailable\n' ;;
    *) return 1 ;;
  esac
}

step_title() {
  local value="${1#*-}"
  value="${value%.sh}"
  printf '%s\n' "${value//-/ }"
}

step_execute() {
  local step_path="$1"
  bash "$step_path" </dev/null
}

export STEP_OK STEP_SKIPPED STEP_DEPENDENCY_UNAVAILABLE STEP_AUTH_REQUIRED
export -f step_status_label step_title step_execute 2>/dev/null || true
