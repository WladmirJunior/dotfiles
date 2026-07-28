#!/usr/bin/env bash
# Structured run telemetry for the installer.
#
# One JSONL line is appended per executed step:
#   {"timestamp":"2026-07-28T12:00:00Z","step":"01-packages.sh","rc":0,
#    "duration_s":42,"mode":"install","os":"Linux"}
# Modes: install (first run), maintenance (base already complete), dry-run,
# check. The log lives under XDG state so it survives re-clones of the repo.
#
# Telemetry is strictly best-effort: every failure path (no encoder, read-only
# state dir, full disk) returns 0 so it can NEVER fail or abort an install.
# JSON encoding follows the jq-or-python pattern of lib/transaction.sh; python
# uses `-c` (no heredoc) so the function survives `export -f` intact.

TELEMETRY_LOG="${DOTFILES_TELEMETRY_LOG:-${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/runs.jsonl}"

_telemetry_have_jq() { command -v jq >/dev/null 2>&1; }

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
      '{timestamp:$ts,step:$step,rc:$rc,duration_s:$duration,mode:$mode,os:$os}' \
      2>/dev/null)" || return 0
  elif command -v python3 >/dev/null 2>&1; then
    line="$(TS="$ts" STEP="$step" RC="$rc" DURATION="$duration" MODE="$mode" OS="$os" \
      python3 -c 'import json,os
e=os.environ
print(json.dumps({"timestamp":e["TS"],"step":e["STEP"],"rc":int(e["RC"]),"duration_s":int(e["DURATION"]),"mode":e["MODE"],"os":e["OS"]},ensure_ascii=False))' \
      2>/dev/null)" || return 0
  else
    return 0
  fi
  [ -n "$line" ] || return 0
  mkdir -p "$(dirname "$TELEMETRY_LOG")" 2>/dev/null || return 0
  printf '%s\n' "$line" >> "$TELEMETRY_LOG" 2>/dev/null || return 0
  return 0
}

export TELEMETRY_LOG
export -f _telemetry_have_jq telemetry_record_step 2>/dev/null || true
