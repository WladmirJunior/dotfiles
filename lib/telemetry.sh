#!/usr/bin/env bash
# Structured run telemetry for the installer.
#
# One JSONL line is appended per executed step, tagged "repo":"public" so the
# log shared with the private overlay can be split by producer:
#   {"timestamp":"2026-07-28T12:00:00Z","repo":"public","step":"01-packages.sh",
#    "rc":0,"duration_s":42,"mode":"install","os":"Linux"}
# Modes: install (first run), maintenance (base already complete), dry-run.
# --check never reaches the step loop, so it produces no lines. The log lives
# under XDG state so it survives re-clones of the repo.
#
# Telemetry is strictly best-effort: every failure path (no encoder, read-only
# state dir, full disk) returns 0 so it can NEVER fail or abort an install.
# JSON encoding uses jq when present, else a pure-shell encoder.

TELEMETRY_LOG="${DOTFILES_TELEMETRY_LOG:-${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/runs.jsonl}"

_telemetry_have_jq() { command -v jq >/dev/null 2>&1; }

# _telemetry_json_str S: S as a JSON string literal (control characters dropped).
_telemetry_json_str() {
  local s
  s="$(printf '%s' "$1" | tr -d '\000-\037')"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  printf '"%s"' "$s"
}

# telemetry_record_step STEP RC DURATION_S MODE OS
telemetry_record_step() {
  local step="$1" rc="$2" duration="$3" mode="$4" os="$5" ts line
  # rc and duration_s are emitted as JSON numbers; drop the record rather than
  # write a corrupt line when either is not a plain integer.
  case "$rc" in ''|*[!0-9]*) return 0 ;; esac
  case "$duration" in ''|*[!0-9]*) return 0 ;; esac
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)" || return 0
  if _telemetry_have_jq; then
    line="$(jq -cn \
      --arg ts "$ts" --arg step "$step" --arg mode "$mode" --arg os "$os" \
      --argjson rc "$rc" --argjson duration "$duration" \
      '{timestamp:$ts,repo:"public",step:$step,rc:$rc,duration_s:$duration,mode:$mode,os:$os}' \
      2>/dev/null)" || return 0
  else
    # No python fallback: on macOS without the CLT /usr/bin/python3 is a stub
    # that pops the install dialog.
    line="{\"timestamp\":$(_telemetry_json_str "$ts"),\"repo\":\"public\",\"step\":$(_telemetry_json_str "$step"),\"rc\":$rc,\"duration_s\":$duration,\"mode\":$(_telemetry_json_str "$mode"),\"os\":$(_telemetry_json_str "$os")}"
  fi
  [ -n "$line" ] || return 0
  mkdir -p "$(dirname "$TELEMETRY_LOG")" 2>/dev/null || return 0
  { printf '%s\n' "$line" >> "$TELEMETRY_LOG"; } 2>/dev/null || return 0
  return 0
}

export TELEMETRY_LOG
export -f _telemetry_have_jq _telemetry_json_str telemetry_record_step 2>/dev/null || true
