#!/usr/bin/env bash
# Shared end-of-run report for the public installer and nested overlays.

setup_report_init() {
  local owner="$1"
  if [ -z "${DOTFILES_REPORT_FILE:-}" ]; then
    DOTFILES_REPORT_FILE="$(mktemp "${TMPDIR:-/tmp}/dotfiles-setup-report.XXXXXX")" || return 1
    DOTFILES_REPORT_OWNER="$owner"
    export DOTFILES_REPORT_FILE DOTFILES_REPORT_OWNER
  fi
}

setup_report_add() {
  local scope="$1" component="$2" result="$3" detail="${4:-}"
  [ -n "${DOTFILES_REPORT_FILE:-}" ] || return 0
  detail="${detail//$'\n'/ }"
  detail="${detail//|//}"
  printf '%s|%s|%s|%s\n' "$scope" "$component" "$result" "$detail" \
    >> "$DOTFILES_REPORT_FILE" 2>/dev/null || true
}

setup_report_count() {
  local file="${1:-}"
  [ -f "$file" ] || { echo 0; return 0; }
  wc -l < "$file" | tr -d ' '
}

setup_report_change_labels() {
  local before="$1" after="$2" count line labels="" shown=0 op
  [ -f "${TX_LOG:-}" ] || return 0
  count=$((after - before))
  [ "$count" -gt 0 ] || return 0
  while IFS= read -r line; do
    if command -v jq >/dev/null 2>&1; then
      op="$(printf '%s\n' "$line" | jq -r '.op // empty' 2>/dev/null || true)"
    else
      op="$(printf '%s\n' "$line" | sed -n 's/.*"op"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
    fi
    [ -n "$op" ] || continue
    shown=$((shown + 1))
    if [ "$shown" -le 4 ]; then labels="${labels:+$labels, }$op"; fi
  done < <(tail -n "$count" "$TX_LOG")
  if [ "$shown" -gt 4 ]; then labels="$labels, +$((shown - 4)) more"; fi
  printf '%s\n' "$labels"
}

setup_report_step() {
  local scope="$1" component="$2" rc="$3" before="$4" after="$5" detail="${6:-}"
  if [ "$rc" -ne 0 ]; then
    setup_report_add "$scope" "$component" failed "${detail:-exit $rc}"
  elif [ "$after" -gt "$before" ]; then
    local labels
    labels="$(setup_report_change_labels "$before" "$after")"
    setup_report_add "$scope" "$component" changed \
      "${labels:-$((after - before)) recorded change(s)}${detail:+, $detail}"
  else
    setup_report_add "$scope" "$component" unchanged "${detail:-already current}"
  fi
}

setup_report_print() {
  [ -s "${DOTFILES_REPORT_FILE:-}" ] || return 0
  banner "Summary · changes and failures" 2>/dev/null || echo "== Summary · changes and failures =="
  if command -v summary_table >/dev/null 2>&1; then
    summary_table 'Scope,Component,Result,Details' '10,24,12,42' < "$DOTFILES_REPORT_FILE"
  elif command -v column >/dev/null 2>&1; then
    { echo 'Scope|Component|Result|Details'; cat "$DOTFILES_REPORT_FILE"; } | column -t -s '|'
  else
    echo 'Scope|Component|Result|Details'
    cat "$DOTFILES_REPORT_FILE"
  fi
}

setup_report_finish() {
  local owner="$1"
  [ "${DOTFILES_REPORT_OWNER:-}" = "$owner" ] || return 0
  setup_report_print
  rm -f "$DOTFILES_REPORT_FILE"
  unset DOTFILES_REPORT_FILE DOTFILES_REPORT_OWNER
}

export -f setup_report_init setup_report_add setup_report_count setup_report_change_labels setup_report_step \
  setup_report_print setup_report_finish 2>/dev/null || true
