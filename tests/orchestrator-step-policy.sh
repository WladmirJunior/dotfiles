#!/usr/bin/env bash
# Orchestrator step-policy table: a failing step declared optional is warned,
# recorded and the install continues; anything not declared optional (including
# steps missing from the table) stays fail-closed and aborts the install.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Fake repo at $HOME/.dotfiles so install.sh keeps it in place (no relocation)
# and runs the fake profile below with the real lib/ code.
FAKE_HOME="$TMP/home"
REPO="$FAKE_HOME/.dotfiles"
mkdir -p "$TMP/bin" "$REPO/steps" "$REPO/profiles" "$FAKE_HOME/.ssh"
ln -s "$ROOT/lib" "$REPO/lib"
ln -s "$ROOT/install.sh" "$REPO/install.sh"

printf '10-pass.sh\n20-optfail.sh\n30-marker.sh\n' > "$REPO/profiles/policytest"
printf '#!/bin/sh\nexit 0\n' > "$REPO/steps/10-pass.sh"
printf '#!/bin/sh\necho "boom" >&2\nexit 1\n' > "$REPO/steps/20-optfail.sh"
printf '#!/bin/sh\ntouch "$MARKER"\n' > "$REPO/steps/30-marker.sh"

# sudo stub (Linux hosts): install.sh authenticates sudo before the loop.
printf '#!/bin/sh\nexit 0\n' > "$TMP/bin/sudo"
# curl stub: fail every fetch so nothing ever reaches the network.
printf '#!/bin/sh\nexit 1\n' > "$TMP/bin/curl"
chmod +x "$TMP/bin/"* "$REPO/steps/"*

# Pre-seed a gum stub at the fork path: ui_bootstrap_gum then never downloads,
# and `gum confirm` answering "no" keeps the post-install auth phase inert.
mkdir -p "$TMP/data/gum-fork"
printf '#!/bin/sh\n[ "$1" = confirm ] && exit 1\nexit 0\n' > "$TMP/data/gum-fork/gum"
chmod +x "$TMP/data/gum-fork/gum"

run_install() {  # run_install NAME POLICY_TABLE(optional)
  local name="$1" policy_table="${2:-}" rc=0
  HOME="$FAKE_HOME" \
  PATH="$TMP/bin:/usr/bin:/bin" \
  XDG_DATA_HOME="$TMP/data" \
  XDG_STATE_HOME="$TMP/state-$name" \
  TX_LOG="$TMP/tx-$name.jsonl" \
  TX_LOCK_DIR="$TMP/tx-$name.jsonl.lock" \
  SETUP_TRASH_ROOT="$TMP/trash-root" \
  MARKER="$TMP/marker-$name" \
  STEP_POLICY_TABLE="$policy_table" \
    bash "$REPO/install.sh" policytest > "$TMP/$name.out" 2>&1 || rc=$?
  return "$rc"
}

# ── Declared optional: warn, record, keep going, exit 0 ──────────────────────
run_install optional '20-optfail.sh optional' || {
  echo "install aborted although the failing step is declared optional" >&2
  cat "$TMP/optional.out" >&2
  exit 1
}
grep -q 'optional step 20-optfail.sh failed (rc=1); continuing' "$TMP/optional.out"
grep -q 'optional step(s) failed: 20-optfail.sh' "$TMP/optional.out"
[ -e "$TMP/marker-optional" ] || {
  echo "steps after the failed optional step did not run" >&2
  exit 1
}

# ── Telemetry: one JSONL line per executed step ──────────────────────────────
TELEM="$TMP/state-optional/dotfiles/runs.jsonl"
[ -f "$TELEM" ] || { echo "no telemetry log written" >&2; exit 1; }
[ "$(wc -l < "$TELEM" | tr -d ' ')" -eq 3 ] || {
  echo "expected 3 telemetry lines (one per executed step)" >&2
  cat "$TELEM" >&2
  exit 1
}
grep -q '"step":"10-pass.sh","rc":0' "$TELEM"
grep -q '"step":"20-optfail.sh","rc":1' "$TELEM"
grep -q '"step":"30-marker.sh","rc":0' "$TELEM"
# Producer tag: every public line carries repo:"public" (parity with the
# private overlay's repo:"private") so the shared log can be split.
[ "$(grep -c '"repo":"public"' "$TELEM")" -eq 3 ]
grep -q '"timestamp":"' "$TELEM"
grep -q '"duration_s":' "$TELEM"
grep -q '"mode":"install"' "$TELEM"
grep -q '"os":"' "$TELEM"

# ── Not in the table: fail-closed default, abort + no later steps ────────────
rc=0; run_install default '' || rc=$?
[ "$rc" -ne 0 ] || {
  echo "install continued past a failing step not declared optional" >&2
  cat "$TMP/default.out" >&2
  exit 1
}
grep -q 'step 20-optfail.sh failed (rc=1)' "$TMP/default.out"
grep -q 'aborting install' "$TMP/default.out"
if [ -e "$TMP/marker-default" ]; then
  echo "a step ran after the aborting failure" >&2
  exit 1
fi

# The aborting failure is still recorded; steps that never ran are not.
TELEM_DEFAULT="$TMP/state-default/dotfiles/runs.jsonl"
grep -q '"step":"20-optfail.sh","rc":1' "$TELEM_DEFAULT"
if grep -q '"step":"30-marker.sh"' "$TELEM_DEFAULT"; then
  echo "telemetry recorded a step that never ran" >&2
  exit 1
fi

# ── Explicitly required behaves like the default ─────────────────────────────
rc=0; run_install required '20-optfail.sh required' || rc=$?
[ "$rc" -ne 0 ]
grep -q 'aborting install' "$TMP/required.out"

# ── Telemetry: a completed base install re-runs in maintenance mode ──────────
mkdir -p "$TMP/state-maint/dotfiles"
printf 'public.base=complete\n' > "$TMP/state-maint/dotfiles/setup.state"
run_install maint '20-optfail.sh optional'
grep -q '"mode":"maintenance"' "$TMP/state-maint/dotfiles/runs.jsonl"

# ── Telemetry is best-effort: an unwritable log never fails the install ──────
mkdir -p "$TMP/state-broken/dotfiles/runs.jsonl"   # a DIRECTORY at the log path
run_install broken '20-optfail.sh optional' || {
  echo "telemetry append failure aborted the install" >&2
  cat "$TMP/broken.out" >&2
  exit 1
}
[ -e "$TMP/marker-broken" ] || {
  echo "steps stopped running after a telemetry append failure" >&2
  exit 1
}
# ...and the failure is silent: no raw bash redirection error leaks to output.
if grep -q 'runs.jsonl' "$TMP/broken.out"; then
  echo "telemetry append failure leaked a raw error into install output" >&2
  exit 1
fi

echo "Orchestrator step-policy tests passed."
