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
TX_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$TX_LIB_DIR/trash.sh"

# tx_init: start a fresh transaction log for this run.
tx_init() {
  TX_SEQ=0
  : > "$TX_LOG" 2>/dev/null || { echo "tx: cannot write $TX_LOG" >&2; return 1; }
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
  _tx_record "brew_self:$prefix" mv "$prefix" "$trash_dest"
}
tx_git_clone() {  # url dest
  local trash_dest
  setup_trash_dir >/dev/null
  _tx_seq
  trash_dest="$(setup_trash_destination "clone-$(basename "$2")-$TX_SEQ")"
  _tx_record "git_clone:$2" mv "$2" "$trash_dest"
}
tx_created_path() {  # path [label]
  local path="$1" label trash_dest
  label="${2:-created-$(basename "$1")}"
  if [ -e "$path" ] || [ -L "$path" ]; then return 0; fi
  setup_trash_dir >/dev/null
  _tx_seq
  trash_dest="$(setup_trash_destination "$label-$TX_SEQ")"
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
    _tx_record "symlink:$dst" mv "$trash_dest" "$dst"
  else
    local new_link_trash
    setup_trash_dir >/dev/null
    _tx_seq
    new_link_trash="$(setup_trash_destination "link-$(basename "$dst")-$TX_SEQ")"
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
  _tx_record_backup "$op" "$backup" "$cleanup_dest" mv "$backup" "$path"
  mv "$path" "$backup"
}

# ── Rollback ──────────────────────────────────────────────────────────────────

# _tx_exec_undo LINE: parse one JSONL line and run its .undo argv. Best-effort.
# Tokens are decoded from base64 (jq @base64, newline-separated) so spaces and
# shell metacharacters in paths survive without a NUL delimiter.
_tx_exec_undo() {
  local line="$1"
  [ -z "$line" ] && return 0
  if _tx_have_jq; then
    local op; op=$(printf '%s' "$line" | jq -r '.op // "?"' 2>/dev/null) || return 0
    local argv=() b64
    while IFS= read -r b64; do
      [ -z "$b64" ] && continue
      argv+=("$(printf '%s' "$b64" | base64 -d 2>/dev/null)")
    done < <(printf '%s' "$line" | jq -r '.undo[]? | @base64' 2>/dev/null)
    [ "${#argv[@]}" -eq 0 ] && return 0
    echo "  undo: $op -> ${argv[*]}"
    "${argv[@]}" >/dev/null 2>&1 || echo "    (undo failed, skipping)"
  else
    # python fallback. NOTE: no heredoc here — a heredoc inside a function that
    # gets `export -f`'d is re-serialized by bash and corrupts (the trailing
    # `|| true` ends up after the PY terminator -> syntax error in child shells
    # that inherit the exported function). Use `python3 -c` with the program as
    # a single-quoted arg instead, which survives export -f intact.
    LINE="$line" python3 -c 'import json,os,subprocess,sys
try:
    d=json.loads(os.environ["LINE"])
except Exception:
    sys.exit(0)
u=d.get("undo") or []
if u:
    print("  undo: %s -> %s" % (d.get("op","?")," ".join(u)))
    subprocess.run(u,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)' || true
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

# tx_rollback: replay every recorded undo in reverse order. Best-effort — a
# failing undo is logged and skipped so one bad entry doesn't strand the rest.
tx_rollback() {
  [ -s "$TX_LOG" ] || { echo "tx: nothing to roll back"; return 0; }
  if [ "${DOTFILES_NO_ROLLBACK:-0}" = 1 ]; then
    echo "tx: DOTFILES_NO_ROLLBACK=1 — leaving $TX_LOG in place, not undoing"
    return 0
  fi
  echo "tx: rolling back $(wc -l < "$TX_LOG" | tr -d ' ') recorded action(s)..."
  local tac
  if command -v tac >/dev/null 2>&1; then tac="tac"; else tac="tail -r"; fi
  local line
  while IFS= read -r line; do
    _tx_exec_undo "$line"
  done < <($tac "$TX_LOG")
  echo "tx: rollback complete."
}

# tx_commit: call on full success. Rotate the live log to .last and clear it.
tx_commit() {
  if [ -s "$TX_LOG" ]; then
    local line
    while IFS= read -r line; do _tx_exec_cleanup "$line"; done < "$TX_LOG"
  fi
  [ -f "$TX_LOG" ] && mv "$TX_LOG" "$TX_LAST" 2>/dev/null || true
}

export -f tx_init _tx_seq _tx_have_jq _tx_record _tx_record_backup tx_brew_install tx_brew_cask \
  tx_apt_install tx_pacman_install tx_dnf_install tx_brew_self tx_git_clone tx_created_path \
  tx_mkdir tx_symlink tx_run \
  tx_backup_path _tx_exec_undo _tx_exec_cleanup tx_rollback tx_commit 2>/dev/null || true
