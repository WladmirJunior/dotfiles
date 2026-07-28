#!/usr/bin/env bash
# lib/ui.sh choose1 without gum: a plain numbered menu that actually asks.
# With a TTY: options listed on stderr (stdout carries only the pick), the
# /dev/tty answer selects by number, an empty answer defaults to the first
# option. Without a usable TTY the first option is used silently, but the
# default pick is announced instead of pretending the user chose it.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Child under test: ui.sh with gum forced off, so choose1 takes the fallback.
cat > "$TMP/child.sh" <<SH
#!/usr/bin/env bash
set -u
NO_COLOR=1
source "$ROOT/lib/ui.sh"
have_gum() { return 1; }
choose1 "Pick one" alpha beta gamma > "$TMP/choice.out" 2> "$TMP/choice.err"
SH
chmod +x "$TMP/child.sh"

# ── TTY branch (GNU script provides a pty; skipped where unavailable) ────────
if script --version 2>/dev/null | grep -q util-linux; then
  # Answer "2" -> second option.
  printf '2\n' | script -qec "$TMP/child.sh" /dev/null >/dev/null
  [ "$(cat "$TMP/choice.out")" = beta ] || {
    echo "numbered answer 2 did not pick the second option:" >&2
    cat "$TMP/choice.out" >&2
    exit 1
  }
  grep -q '1) alpha' "$TMP/choice.err"   # the menu was actually shown
  grep -q '3) gamma' "$TMP/choice.err"

  # Empty answer -> first option (the announced default).
  printf '\n' | script -qec "$TMP/child.sh" /dev/null >/dev/null
  [ "$(cat "$TMP/choice.out")" = alpha ]

  # Out-of-range / non-numeric answers fall back to the first option.
  printf '9\n' | script -qec "$TMP/child.sh" /dev/null >/dev/null
  [ "$(cat "$TMP/choice.out")" = alpha ]
  printf 'zz\n' | script -qec "$TMP/child.sh" /dev/null >/dev/null
  [ "$(cat "$TMP/choice.out")" = alpha ]
fi

# ── No usable TTY: default to the first option and say so ────────────────────
if command -v setsid >/dev/null 2>&1; then
  setsid "$TMP/child.sh" < /dev/null
  [ "$(cat "$TMP/choice.out")" = alpha ]
  grep -q 'no TTY: defaulting to "alpha"' "$TMP/choice.err" || {
    echo "silent no-TTY default was not announced:" >&2
    cat "$TMP/choice.err" >&2
    exit 1
  }
fi

echo "choose1 fallback tests passed."
