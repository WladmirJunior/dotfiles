#!/usr/bin/env bash
# Transaction log with rollback for the dotfiles installer.
#
# Every mutating action a step takes is recorded as one JSONL line holding the
# undo command (as an argv array). If the install aborts, the orchestrator
# replays those undo commands in reverse order to return the machine to its
# pre-install state. On full success the log is rotated to a `.last` file for
# debugging and the live log is cleared.
#
# WHY JSONL: append-only (atomic `>>` for small writes), survives a hard kill
# (each completed line is independently parseable), and the undo command stored
# as an argv array sidesteps all shell-quoting hazards (paths with spaces, etc).
#
# A step records intent with these helpers instead of running the raw command:
#   tx_brew_install <formula...>       # undo: brew uninstall <formula>
#   tx_brew_cask <cask...>             # undo: brew uninstall --cask <cask>
#   tx_apt_install <pkg...>            # undo: apt-get remove -y <pkg>
#   tx_pacman_install <pkg...>         # undo: pacman -Rns --noconfirm <pkg>
#   tx_dnf_install <pkg...>            # undo: dnf remove -y <pkg>
#   tx_git_clone <url> <dest>          # undo: move <dest> to recoverable trash
#   tx_created_path <path> [label]      # undo: move a new path to recoverable trash
#   tx_mkdir <dir>                     # undo: rmdir <dir>  (only if WE create it)
#   tx_symlink <src> <dst>             # undo: restore prior target / remove
#   tx_run "<op>" <undo-argv...> -- <do-argv...>   # generic escape hatch
#
# Disable rollback (e.g. debugging a half-finished state) with
# DOTFILES_NO_ROLLBACK=1; the log is still written, just not replayed.
# DOTFILES_INSTALLER_API identifies the public compatibility contract consumed
# by private overlays. Increment it only for an incompatible API change.

set -uo pipefail

DOTFILES_INSTALLER_API=1
export DOTFILES_INSTALLER_API

TX_LOG="${TX_LOG:-$HOME/.dotfiles-install.jsonl}"
TX_LAST="${TX_LAST:-$HOME/.dotfiles-install.last.jsonl}"
TX_LOCK_DIR="${TX_LOCK_DIR:-$TX_LOG.lock}"
TX_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$TX_LIB_DIR/trash.sh"

# tx_init: start a fresh transaction for this run.
# Returns 2 when another install holds the lock (caller must not proceed) and
# 1 when the journal path is unwritable. A leftover non-empty journal means the
# previous run never committed (crash, kill, or a rollback that itself failed):
# it is preserved as <TX_LOG>.abandoned-<epoch> with a loud warning, never
# silently truncated, so its undo entries can still be replayed by hand.
tx_init() {
  TX_SEQ=0
  # Single-writer lock: mkdir is atomic, and the PID stored inside identifies
  # the owner so the stale lock of a crashed run can be reclaimed safely.
  local lock_pid=""
  if mkdir "$TX_LOCK_DIR" 2>/dev/null; then
    printf '%s\n' "$$" > "$TX_LOCK_DIR/pid"
  else
    lock_pid="$(cat "$TX_LOCK_DIR/pid" 2>/dev/null || true)"
    if [ "$lock_pid" = "$$" ]; then
      :  # re-init from the same process; keep the lock we already own
    elif [ -n "$lock_pid" ] && kill -0 "$lock_pid" 2>/dev/null; then
      echo "tx: another install (pid $lock_pid) holds $TX_LOCK_DIR; refusing to start" >&2
      return 2
    else
      echo "tx: reclaiming stale lock $TX_LOCK_DIR (pid ${lock_pid:-unknown} is gone)"
      printf '%s\n' "$$" > "$TX_LOCK_DIR/pid"
    fi
  fi
  if [ -s "$TX_LOG" ]; then
    local abandoned
    abandoned="$TX_LOG.abandoned-$(date +%s)"
    if ! mv "$TX_LOG" "$abandoned" 2>/dev/null; then
      # mv can fail while the file itself is still readable (e.g. the parent
      # dir denies renames). Fall back to a copy; only a verified copy may
      # authorize truncation, otherwise keep the journal untouched and bail.
      if ! cp "$TX_LOG" "$abandoned" 2>/dev/null; then
        echo "tx: WARNING: found an uncommitted journal from an interrupted run." >&2
        echo "tx: could not preserve a copy of $TX_LOG; keeping it untouched." >&2
        echo "tx: inspect it and replay its undo entries manually, then remove it." >&2
        tx_release_lock
        return 1
      fi
    fi
    echo "tx: WARNING: found an uncommitted journal from an interrupted run." >&2
    echo "tx: preserved at $abandoned" >&2
    echo "tx: inspect it and replay its undo entries manually if that run left changes behind." >&2
  fi
  : > "$TX_LOG" 2>/dev/null || { echo "tx: cannot write $TX_LOG" >&2; tx_release_lock; return 1; }
}

# tx_release_lock: drop the install lock, but only if this process owns it.
tx_release_lock() {
  [ -d "$TX_LOCK_DIR" ] || return 0
  local lock_pid
  lock_pid="$(cat "$TX_LOCK_DIR/pid" 2>/dev/null || true)"
  if [ -z "$lock_pid" ] || [ "$lock_pid" = "$$" ]; then
    rm -f "$TX_LOCK_DIR/pid" 2>/dev/null || true
    rmdir "$TX_LOCK_DIR" 2>/dev/null || true
  fi
  return 0
}

# _tx_seq: bump TX_SEQ, a per-transaction monotonic suffix for trash
# destinations computed at record time. $RANDOM can repeat within one run and
# make two undo entries share a destination; a counter cannot. Must be called
# directly (not in a command substitution) so the increment sticks.
_tx_seq() { TX_SEQ=$((${TX_SEQ:-0} + 1)); }

_tx_have_jq() { command -v jq >/dev/null 2>&1; }

# _tx_record OP UNDO_ARGV...: append one JSONL entry. OP is a human label; the
# rest is the undo command as separate argv tokens. Uses jq when present, else a
# small python encoder (both available before/after step 01 on every target).
_tx_record() {
  local op="$1"; shift
  if _tx_have_jq; then
    local args_json
    args_json=$(printf '%s\n' "$@" | jq -R . | jq -cs .)
    printf '{"op":%s,"undo":%s}\n' "$(printf '%s' "$op" | jq -R .)" "$args_json" >> "$TX_LOG"
  else
    # python fallback, via `-c` (no heredoc — see _tx_exec_undo note: heredocs
    # inside export -f'd functions corrupt in child shells).
    OP="$op" python3 -c 'import json,os,sys
print(json.dumps({"op":os.environ["OP"],"undo":sys.argv[1:]},ensure_ascii=False))' "$@" >> "$TX_LOG"
  fi
}

# _tx_record_backup OP BACKUP UNDO_ARGV...: record an undo that consumes a
# temporary backup on rollback and removes that backup only after commit.
_tx_record_backup() {
  local op="$1" backup="$2" cleanup_dest="$3"; shift 3
  if _tx_have_jq; then
    local args_json cleanup_json
    args_json=$(printf '%s\n' "$@" | jq -R . | jq -cs .)
    cleanup_json=$(printf '%s\n' mv "$backup" "$cleanup_dest" | jq -R . | jq -cs .)
    printf '{"op":%s,"undo":%s,"cleanup":%s}\n' \
      "$(printf '%s' "$op" | jq -R .)" "$args_json" "$cleanup_json" >> "$TX_LOG"
  else
    OP="$op" BACKUP="$backup" CLEANUP_DEST="$cleanup_dest" python3 -c 'import json,os,sys
print(json.dumps({"op":os.environ["OP"],"undo":sys.argv[1:],"cleanup":["mv",os.environ["BACKUP"],os.environ["CLEANUP_DEST"]]},ensure_ascii=False))' \
      "$@" >> "$TX_LOG"
  fi
}

# ── Recording helpers ─────────────────────────────────────────────────────────

tx_brew_install() {
  local f
  for f in "$@"; do _tx_record "brew_install:$f" brew uninstall --ignore-dependencies "$f"; done
}
tx_brew_cask() {
  local c
  for c in "$@"; do _tx_record "brew_cask:$c" brew uninstall --cask "$c"; done
}
tx_apt_install() {
  local p
  for p in "$@"; do _tx_record "apt_install:$p" "${TX_SUDO:-env}" apt-get remove -y "$p"; done
}
tx_pacman_install() {
  local p
  for p in "$@"; do
    _tx_record "pacman_install:$p" "${TX_SUDO:-env}" pacman -Rns --noconfirm "$p"
  done
}
tx_dnf_install() {
  local p
  for p in "$@"; do _tx_record "dnf_install:$p" "${TX_SUDO:-env}" dnf remove -y "$p"; done
}
# tx_brew_self: record a new Homebrew prefix for recoverable rollback. An
# existing prefix is never moved because it may contain unrelated user files.
tx_brew_self() {
  local prefix="${HOMEBREW_PREFIX:-}"
  if [ -z "$prefix" ]; then
    # Default prefix depends on OS and architecture, not architecture alone
    # (Linux aarch64 is not /opt/homebrew).
    case "$(uname -s):$(uname -m)" in
      Darwin:arm64) prefix=/opt/homebrew ;;
      Darwin:*) prefix=/usr/local ;;
      *) prefix=/home/linuxbrew/.linuxbrew ;;
    esac
  fi
  [ -e "$prefix" ] && return 0
  local trash_dest
  setup_trash_dir >/dev/null
  _tx_seq
  trash_dest="$(setup_trash_destination "homebrew-prefix-$TX_SEQ")"
  setup_trash_manifest "$prefix" "$trash_dest"
  _tx_record "brew_self:$prefix" mv "$prefix" "$trash_dest"
}
tx_git_clone() {  # url dest
  local trash_dest
  setup_trash_dir >/dev/null
  _tx_seq
  trash_dest="$(setup_trash_destination "clone-$(basename "$2")-$TX_SEQ")"
  setup_trash_manifest "$2" "$trash_dest"
  _tx_record "git_clone:$2" mv "$2" "$trash_dest"
}
tx_created_path() {  # path [label]
  local path="$1" label trash_dest
  label="${2:-created-$(basename "$1")}"
  if [ -e "$path" ] || [ -L "$path" ]; then return 0; fi
  setup_trash_dir >/dev/null
  _tx_seq
  trash_dest="$(setup_trash_destination "$label-$TX_SEQ")"
  setup_trash_manifest "$path" "$trash_dest"
  _tx_record "created:$path" mv "$path" "$trash_dest"
}
tx_mkdir() {  # dir — only record if we actually create it
  local d="$1"
  [ -d "$d" ] && return 0
  mkdir -p "$d" && _tx_record "mkdir:$d" rmdir "$d"
}
tx_symlink() {  # src dst
  local src="$1" dst="$2"
  if [ -L "$dst" ]; then
    local prev; prev=$(readlink "$dst")
    _tx_record "symlink:$dst" ln -sfn "$prev" "$dst"
  elif [ -e "$dst" ]; then
    local trash_dest
    setup_trash_dir >/dev/null
    _tx_seq
    trash_dest="$(setup_trash_destination "replaced-$(basename "$dst")-$TX_SEQ")"
    mv "$dst" "$trash_dest"
    setup_trash_manifest "$dst" "$trash_dest"
    _tx_record "symlink:$dst" mv "$trash_dest" "$dst"
  else
    local new_link_trash
    setup_trash_dir >/dev/null
    _tx_seq
    new_link_trash="$(setup_trash_destination "link-$(basename "$dst")-$TX_SEQ")"
    setup_trash_manifest "$dst" "$new_link_trash"
    _tx_record "symlink:$dst" mv "$dst" "$new_link_trash"
  fi
  ln -sfn "$src" "$dst"
}

# tx_run "op" <undo argv...> -- <do argv...>
# Record an arbitrary undo, then execute the real command. The undo is recorded
# BEFORE the action runs so a crash mid-action is still covered.
tx_run() {
  local op="$1"; shift
  local undo=()
  while [ "$#" -gt 0 ] && [ "$1" != "--" ]; do undo+=("$1"); shift; done
  [ "${1:-}" = "--" ] && shift
  _tx_record "$op" "${undo[@]}"
  "$@"
}

# tx_backup_path OP PATH BACKUP: move PATH aside while retaining enough state
# for rollback. After commit the prior value is kept in recoverable trash.
tx_backup_path() {
  local op="$1" path="$2" backup="$3" cleanup_dest
  setup_trash_dir >/dev/null
  _tx_seq
  cleanup_dest="$(setup_trash_destination "backup-$(basename "$path")-$TX_SEQ")"
  setup_trash_manifest "$path" "$cleanup_dest"
  _tx_record_backup "$op" "$backup" "$cleanup_dest" mv "$backup" "$path"
  mv "$path" "$backup"
}

# ── Rollback ──────────────────────────────────────────────────────────────────

# _tx_exec_undo LINE: parse one JSONL line and run its .undo argv. Tokens are
# decoded from base64 (newline-separated) so spaces and shell metacharacters in
# paths survive without a NUL delimiter. Sets TX_UNDO_LAST_OP to the entry's op
# label and returns non-zero when the undo command itself failed, so
# tx_rollback can report an honest summary instead of unconditional success.
_tx_exec_undo() {
  local line="$1"
  TX_UNDO_LAST_OP="?"
  [ -z "$line" ] && return 0
  local decoded=() b64
  if _tx_have_jq; then
    # First emitted token is the op label, the rest is the undo argv.
    while IFS= read -r b64; do
      [ -z "$b64" ] && continue
      decoded+=("$(printf '%s' "$b64" | base64 -d 2>/dev/null)")
    done < <(printf '%s' "$line" | jq -r '([.op // "?"] + (.undo // [])) | .[] | @base64' 2>/dev/null)
  else
    # python fallback. NOTE: no heredoc here: a heredoc inside a function that
    # gets `export -f`'d is re-serialized by bash and corrupts (the trailing
    # `|| true` ends up after the PY terminator -> syntax error in child shells
    # that inherit the exported function). Use `python3 -c` with the program as
    # a single-quoted arg instead, which survives export -f intact.
    while IFS= read -r b64; do
      [ -z "$b64" ] && continue
      decoded+=("$(printf '%s' "$b64" | base64 -d 2>/dev/null)")
    done < <(LINE="$line" python3 -c 'import base64,json,os
try:
    d=json.loads(os.environ["LINE"])
except Exception:
    raise SystemExit(0)
for t in [str(d.get("op") or "?")] + [str(u) for u in (d.get("undo") or [])]:
    print(base64.b64encode(t.encode()).decode())' 2>/dev/null)
  fi
  [ "${#decoded[@]}" -ge 1 ] || return 0
  TX_UNDO_LAST_OP="${decoded[0]}"
  [ "${#decoded[@]}" -ge 2 ] || return 0
  local argv=("${decoded[@]:1}")
  echo "  undo: $TX_UNDO_LAST_OP -> ${argv[*]}"
  if ! "${argv[@]}" >/dev/null 2>&1; then
    echo "    (undo FAILED: $TX_UNDO_LAST_OP)"
    return 1
  fi
}

_tx_exec_cleanup() {
  local line="$1"
  [ -z "$line" ] && return 0
  if _tx_have_jq; then
    local argv=() b64
    while IFS= read -r b64; do
      [ -z "$b64" ] && continue
      argv+=("$(printf '%s' "$b64" | base64 -d 2>/dev/null)")
    done < <(printf '%s' "$line" | jq -r '.cleanup[]? | @base64' 2>/dev/null)
    [ "${#argv[@]}" -eq 0 ] || "${argv[@]}" >/dev/null 2>&1 \
      || echo "tx: commit cleanup failed: ${argv[*]}" >&2
  else
    LINE="$line" python3 -c 'import json,os,subprocess
try:
    cleanup=json.loads(os.environ["LINE"]).get("cleanup") or []
except Exception:
    cleanup=[]
if cleanup:
    subprocess.run(cleanup,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)' || true
  fi
}

# tx_rollback: replay every recorded undo in reverse order. A failing undo is
# logged and skipped so one bad entry doesn't strand the rest, but every
# failure is counted (TX_ROLLBACK_FAILED), listed at the end, and reflected in
# the exit status: non-zero means the machine was only PARTIALLY restored. In
# that case the journal is kept in place as evidence (the next tx_init moves it
# aside as abandoned); on a fully clean rollback it rotates to .rolledback.
tx_rollback() {
  TX_ROLLBACK_FAILED=0
  [ -s "$TX_LOG" ] || { echo "tx: nothing to roll back"; tx_release_lock; return 0; }
  if [ "${DOTFILES_NO_ROLLBACK:-0}" = 1 ]; then
    echo "tx: DOTFILES_NO_ROLLBACK=1: leaving $TX_LOG in place, not undoing"
    tx_release_lock
    return 0
  fi
  echo "tx: rolling back $(wc -l < "$TX_LOG" | tr -d ' ') recorded action(s)..."
  local tac
  if command -v tac >/dev/null 2>&1; then tac="tac"; else tac="tail -r"; fi
  local line failed_ops=""
  while IFS= read -r line; do
    if ! _tx_exec_undo "$line"; then
      TX_ROLLBACK_FAILED=$((TX_ROLLBACK_FAILED + 1))
      failed_ops="${failed_ops:+$failed_ops, }${TX_UNDO_LAST_OP:-?}"
    fi
  done < <($tac "$TX_LOG")
  if [ "$TX_ROLLBACK_FAILED" -gt 0 ]; then
    echo "tx: rollback finished with $TX_ROLLBACK_FAILED failed undo(s): $failed_ops" >&2
    echo "tx: journal kept at $TX_LOG; the failed items may need manual cleanup." >&2
    tx_release_lock
    return 1
  fi
  # Fully undone: rotate the journal aside so the next tx_init does not treat
  # this (already reverted) run as an abandoned one.
  mv "$TX_LOG" "$TX_LOG.rolledback" 2>/dev/null || true
  echo "tx: rollback complete."
  tx_release_lock
}

# tx_commit: call on full success. Run recorded cleanups, rotate the live log
# to .last, prune expired quarantine dirs and release the install lock.
tx_commit() {
  if [ -s "$TX_LOG" ]; then
    local line
    while IFS= read -r line; do _tx_exec_cleanup "$line"; done < "$TX_LOG"
  fi
  if [ -f "$TX_LOG" ]; then mv "$TX_LOG" "$TX_LAST" 2>/dev/null || true; fi
  command -v setup_trash_prune >/dev/null 2>&1 && setup_trash_prune
  tx_release_lock
}

export -f tx_init tx_release_lock _tx_seq _tx_have_jq _tx_record _tx_record_backup \
  tx_brew_install tx_brew_cask \
  tx_apt_install tx_pacman_install tx_dnf_install tx_brew_self tx_git_clone tx_created_path \
  tx_mkdir tx_symlink tx_run \
  tx_backup_path _tx_exec_undo _tx_exec_cleanup tx_rollback tx_commit 2>/dev/null || true
