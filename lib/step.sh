#!/usr/bin/env bash
# Step metadata and execution contract shared by installer orchestrators.

readonly STEP_OK=0
readonly STEP_SKIPPED=10
readonly STEP_DEPENDENCY_UNAVAILABLE=20
readonly STEP_AUTH_REQUIRED=30

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
export -f step_title step_execute 2>/dev/null || true
