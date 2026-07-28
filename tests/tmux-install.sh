#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin"

cat > "$TMP/bin/brew" <<'SH'
#!/bin/sh
exit 0
SH
chmod +x "$TMP/bin/brew"

output="$(
  HOME="$TMP/home" \
  PATH="$TMP/bin:/usr/bin:/bin" \
  DOTFILES_DIR="$ROOT" \
  OS_TYPE=Darwin \
  DRY_RUN=1 \
  WANT_TMUX=yes \
    bash "$ROOT/steps/01-packages.sh"
)"

grep -Fq '[dry-run] brew install tmux' <<<"$output"

# ── A declined interactive choice is persisted and later runs stop re-asking ──
# Restricted PATH (no system dirs) so the host's tmux never leaks in; only the
# tools the Darwin branch needs are exposed. Without gum the tmux pick resolves
# to "declined", which must land in the state store; the second run must skip
# the prompt because of that state, announcing why.
mkdir -p "$TMP/sbin"
for tool in awk basename bash cat date dirname grep mkdir mv paste rm sed tr wc; do
  ln -s "$(command -v "$tool")" "$TMP/sbin/$tool"
done
ln -s "$TMP/bin/brew" "$TMP/sbin/brew"

run_step_real() {
  HOME="$TMP/home" \
  PATH="$TMP/sbin" \
  XDG_STATE_HOME="$TMP/state" \
  DOTFILES_DIR="$ROOT" \
  OS_TYPE=Darwin \
  TX_LOG="$TMP/tx.jsonl" \
  SETUP_TRASH_ROOT="$TMP/trash-root" \
    bash "$ROOT/steps/01-packages.sh"
}

run_step_real > "$TMP/first.out"
grep -q '^packages.tmux=declined$' "$TMP/state/dotfiles/setup.state" || {
  echo "declined tmux choice was not persisted:" >&2
  cat "$TMP/first.out" >&2
  exit 1
}

run_step_real > "$TMP/second.out"
grep -Fq 'tmux: previously declined' "$TMP/second.out" || {
  echo "second run did not honor the persisted declined choice:" >&2
  cat "$TMP/second.out" >&2
  exit 1
}

# An explicit WANT_TMUX=yes still overrides the persisted refusal.
out_override="$(WANT_TMUX=yes DRY_RUN=1 HOME="$TMP/home" PATH="$TMP/sbin" \
  XDG_STATE_HOME="$TMP/state" DOTFILES_DIR="$ROOT" OS_TYPE=Darwin \
  bash "$ROOT/steps/01-packages.sh")"
grep -Fq '[dry-run] brew install tmux' <<<"$out_override"

echo "Optional tmux install test passed."
