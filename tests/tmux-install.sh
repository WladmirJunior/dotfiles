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

# ── Silent defaults never persist; only a real interactive decline does ──────
# Restricted PATH (no system dirs) so the host's tmux never leaks in; only the
# tools the Darwin branch needs are exposed. Without gum (or without a TTY)
# the pick resolves to its default silently: that must NOT be recorded as a
# user decision, so every future interactive run still gets the question.
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
if grep -q '^packages.tmux=' "$TMP/state/dotfiles/setup.state" 2>/dev/null; then
  echo "a silent (no-gum) default was persisted as a user decision:" >&2
  cat "$TMP/first.out" >&2
  exit 1
fi

# A REAL interactive decline (gum present, TTY attached) is persisted and the
# next run skips the question, announcing why. Needs a pty: GNU script only.
if script --version 2>/dev/null | grep -q util-linux; then
  # Fake gum: `choose` prints nothing = everything deselected = decline.
  printf '#!/bin/sh\ncase "$1" in choose) exit 0 ;; esac\nexit 0\n' > "$TMP/sbin/gum"
  chmod +x "$TMP/sbin/gum"
  cat > "$TMP/interactive.sh" <<SH
#!/bin/bash
HOME="$TMP/home" PATH="$TMP/sbin" XDG_STATE_HOME="$TMP/state" \
  DOTFILES_DIR="$ROOT" OS_TYPE=Darwin TX_LOG="$TMP/tx.jsonl" \
  SETUP_TRASH_ROOT="$TMP/trash-root" \
  bash "$ROOT/steps/01-packages.sh"
SH
  chmod +x "$TMP/interactive.sh"
  script -qec "$TMP/interactive.sh" /dev/null > "$TMP/first-tty.out"
  grep -q '^packages.tmux=declined$' "$TMP/state/dotfiles/setup.state" || {
    echo "an interactive decline was not persisted:" >&2
    cat "$TMP/first-tty.out" >&2
    exit 1
  }
  rm -f "$TMP/sbin/gum"
  run_step_real > "$TMP/second.out"
  grep -Fq 'tmux: previously declined' "$TMP/second.out" || {
    echo "second run did not honor the persisted declined choice:" >&2
    cat "$TMP/second.out" >&2
    exit 1
  }
fi

# An explicit WANT_TMUX=yes still overrides the persisted refusal.
out_override="$(WANT_TMUX=yes DRY_RUN=1 HOME="$TMP/home" PATH="$TMP/sbin" \
  XDG_STATE_HOME="$TMP/state" DOTFILES_DIR="$ROOT" OS_TYPE=Darwin \
  bash "$ROOT/steps/01-packages.sh")"
grep -Fq '[dry-run] brew install tmux' <<<"$out_override"

echo "Optional tmux install test passed."
