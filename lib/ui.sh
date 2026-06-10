#!/bin/bash
# =============================================================================
#  ui.sh — shared terminal UI toolkit for the dotfiles installers.
# =============================================================================
#  Built on Charm's `gum`. Sourced by install.sh (public) and, when present,
#  by the private/work overlays so all three share one look. Every helper
#  degrades to plain printf when gum is missing, so sourcing this never hard-
#  fails an install.
#
#  Public API:
#    banner "Title"            wide double-border section header
#    step "1/4" "Title"        numbered step header (a public-phase step)
#    task "Title"              un-numbered step header (a phase sub-task)
#    ok "msg"                  green success line
#    note "msg"                quiet indented line
#    spin "msg" -- cmd...      spinner over a command (cmd optional; omit -> sleep)
#    choose1 "Header" a b ...  single choice -> echoes the picked option
#    pick "Header" a b ...     multi choice  -> echoes comma-joined (or 'none')
#    confirm "Question"        yes/no -> exit status (yes = 0)
#    summary_table             reads "Key|Value" lines on stdin, renders a grid
#
#  Env toggles:  FAST=1 skip spinners   NO_COLOR=1 disable colors
# =============================================================================

# -----------------------------------------------------------------------------
#  THEME  — edit these to restyle the whole UI. Values are 256-color codes
#           (see `gum style` / 256-color charts). Names are semantic, not raw
#           colors, so a retheme is a one-line change here.
# -----------------------------------------------------------------------------
THEME_PRIMARY=51        # step titles, prompts, key accents
THEME_ACCENT=51         # interactive cursor / selection accent
THEME_SUCCESS=82        # ✓ done / success lines
THEME_BORDER=73         # banner & table borders (teal)
THEME_BORDER_MUTED=240  # quiet borders (step box)
THEME_LOG=240           # secondary / log lines under a step
THEME_VALUE=255         # plain values (e.g. summary table cells)
THEME_SPINNER=51        # loading spinner (gum spin)

LAYOUT_MARGIN=2         # left margin so nothing hugs the terminal edge
LAYOUT_MAXWIDTH=90      # cap the UI width on very wide terminals

# =============================================================================
#  GUM SOURCE  — single source of truth for which gum we run.
# -----------------------------------------------------------------------------
#  The table helper needs --width / --border-row, which upstream gum doesn't
#  expose yet (PR charmbracelet/gum#1084). Until that merges we run a fork built
#  from that PR, fetched as a prebuilt binary to a Santa-allowed path.
#
#  TO SWITCH TO UPSTREAM once the PR lands: set UI_GUM_USE_FORK=0 below. Nothing
#  else changes — ui_bootstrap_gum then just relies on stock gum (brew/apt), and
#  the table helper auto-detects whether --width is available.
# =============================================================================
UI_GUM_USE_FORK=1                                  # 1 = fork binary, 0 = stock gum
UI_GUM_REPO="WladmirJunior/gum"
UI_GUM_TAG="v0.17.0-borderrow"
UI_GUM_DIR="/opt/homebrew/var/gum-fork"            # Santa-allowed install path
UI_GUM_BIN="$UI_GUM_DIR/gum"

# ui_gum_asset: the release asset name for this platform, or "" if unsupported.
# The fork ships gum-<os>-<arch> binaries (darwin-arm64, linux-arm64).
ui_gum_asset() {
  case "$(uname)-$(uname -m)" in
    Darwin-arm64) echo "gum-darwin-arm64" ;;
    Linux-aarch64|Linux-arm64) echo "gum-linux-arm64" ;;
    *) echo "" ;;
  esac
}

# ui_ensure_gum: fetch the fork binary once for this platform. Best-effort — a
# failure just means the helpers use whatever `gum` is on PATH (no fork extras).
ui_ensure_gum() {
  [ "$UI_GUM_USE_FORK" = 1 ] || return 0
  [ -x "$UI_GUM_BIN" ] && return 0
  local asset; asset="$(ui_gum_asset)"; [ -n "$asset" ] || return 0
  command -v curl >/dev/null 2>&1 || return 0
  mkdir -p "$UI_GUM_DIR" 2>/dev/null || return 0
  local url="https://github.com/$UI_GUM_REPO/releases/download/$UI_GUM_TAG/$asset"
  if curl -fsSL "$url" -o "$UI_GUM_BIN" 2>/dev/null; then
    chmod +x "$UI_GUM_BIN" 2>/dev/null || true
  else
    rm -f "$UI_GUM_BIN" 2>/dev/null || true
  fi
}

# ui_bootstrap_gum: make gum available before the first UI prompt. Sourced before
# any step runs, so on a clean machine the early banner/prompt would otherwise
# render in the plain-printf fallback. With the fork enabled this just fetches the
# fork binary; with the fork disabled it leaves stock gum (installed by step 01)
# to the helpers. Best-effort; everything degrades gracefully if it fails.
ui_bootstrap_gum() {
  ui_ensure_gum
}

# -----------------------------------------------------------------------------
#  RUNTIME  — derived state: color escapes (for plain printf), gum binary.
# -----------------------------------------------------------------------------
PAD="$(printf '%*s' "$LAYOUT_MARGIN" '')"   # left-margin spaces
# shellcheck disable=SC2034  # c_dim/c_bold are part of the shared color API
# c_log is a mid grey (250), not bright-black (90) — the latter vanishes on the
# dark terminal backgrounds these installers run in. c_info is a soft cyan for
# closing messages the user needs to actually read.
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  c_primary=$'\033[36m'; c_success=$'\033[32m'; c_log=$'\033[38;5;250m'
  c_info=$'\033[38;5;45m'
  c_bold=$'\033[1m'; c_dim=$'\033[2m'; c_reset=$'\033[0m'
else
  c_primary=; c_success=; c_log=; c_info=; c_bold=; c_dim=; c_reset=
fi

# Resolve which gum binary to use, preferring the fork at UI_GUM_BIN. Done lazily
# on every have_gum() call (not once at source time) because ui_bootstrap_gum may
# fetch the fork AFTER this file is sourced — the next helper call then picks it
# up automatically. GUM defaults to plain `gum`.
GUM=gum
have_gum() {
  if [ -x "$UI_GUM_BIN" ]; then GUM="$UI_GUM_BIN"
  elif command -v gum >/dev/null 2>&1; then GUM=gum
  else return 1; fi
  return 0
}
gum_has_width() { "$GUM" table --help 2>&1 | grep -q -- '--width'; }   # fork only

# Inner content width = (capped) terminal width minus the left+right margins.
cwidth() { local w; w=$(tput cols 2>/dev/null || echo 80)
           [ "$w" -gt "$LAYOUT_MAXWIDTH" ] && w=$LAYOUT_MAXWIDTH
           echo $(( w - LAYOUT_MARGIN * 2 )); }

# -----------------------------------------------------------------------------
#  UI HELPERS  — three visual levels, all left-margined by LAYOUT_MARGIN:
#    banner  wide double-border box, centered     → a major section
#    step    small rounded box, left-aligned      → a step header (lighter)
#    note/ok plain indented lines under a step
# -----------------------------------------------------------------------------
banner() {
  if have_gum; then "$GUM" style --foreground $THEME_BORDER --bold --border double \
      --border-foreground $THEME_BORDER --padding "0 2" --margin "1 0 0 $LAYOUT_MARGIN" \
      --align center --width "$(cwidth)" "$1"
  else printf '\n%s== %s ==%s\n' "$c_bold" "$1" "$c_reset"; fi
}
step() {  # step "1/4" "Title"  → numbered step (public phase: "Step 1/4 · ...")
  _stepbox "Step $1 · $2"
}
task() {  # task "Title"  → un-numbered step inside a non-public phase (no "Step N")
  _stepbox "$1"
}
_stepbox() {  # shared rounded box for step()/task()
  if have_gum; then "$GUM" style --foreground $THEME_PRIMARY --bold --border rounded \
      --border-foreground $THEME_BORDER_MUTED --padding "0 2" --margin "1 0 0 $LAYOUT_MARGIN" \
      "▸ $1"
  else printf '\n%s▸ %s%s\n' "$c_bold$c_primary" "$1" "$c_reset"; fi
}
ok()   { if have_gum; then printf '%s' "$PAD"; "$GUM" style --foreground $THEME_SUCCESS "✓ $1"
         else printf '%s%s✓ %s%s\n' "$PAD" "$c_success" "$1" "$c_reset"; fi; }
note() { printf '%s%s   %s%s\n' "$PAD" "$c_log" "$1" "$c_reset"; }
# info: a closing/next-step message the user must read (brighter than note()).
info() { printf '%s%s   %s%s\n' "$PAD" "$c_info" "$1" "$c_reset"; }

# spin "title" [-- cmd args...]  — run cmd under a spinner (or sleep if no cmd).
# FAST=1 or no gum → just print the title and run the cmd plainly.
spin() {
  local title="$1"; shift
  [ "${1:-}" = "--" ] && shift
  if have_gum && [ "${FAST:-0}" != 1 ]; then
    if [ "$#" -gt 0 ]; then
      "$GUM" spin --spinner dot --spinner.foreground=$THEME_SPINNER \
        --title "$title" --title.foreground=$THEME_LOG -- "$@"
    else
      "$GUM" spin --spinner dot --spinner.foreground=$THEME_SPINNER \
        --title "$title" --title.foreground=$THEME_LOG -- sleep 0.4
    fi
  else
    note "$title"; [ "$#" -gt 0 ] && "$@"
  fi
}

# -----------------------------------------------------------------------------
#  PROMPT HELPERS  — gum choose/confirm have no --margin, so we left-pad the
#                    header, cursor and item prefixes to line up with the UI.
#                    Fall back to the first option / plain read with no gum.
#  All read from /dev/tty so they work under `curl | bash`, where stdin is the
#  script pipe (gum would otherwise get no keyboard and return immediately).
# -----------------------------------------------------------------------------
choose1() {  # choose1 "Header" opt...  → single choice (echoes the picked option)
  local h="$1"; shift
  if have_gum; then "$GUM" choose --header="${PAD}$h  (↑↓ move · enter select)" \
      --cursor="${PAD}> " --cursor.foreground=$THEME_ACCENT --header.foreground=$THEME_PRIMARY "$@" </dev/tty
  else echo "$1"; fi
}
pick() {  # pick "Header" opt...  → multi choice ([ ]/[x]); comma-joined or 'none'
  local h="$1"; shift
  if have_gum; then
    local out; out=$("$GUM" choose --no-limit --header="${PAD}$h  (space select · enter confirm)" \
      --cursor="${PAD}> " --cursor.foreground=$THEME_ACCENT --header.foreground=$THEME_PRIMARY \
      --selected.foreground=$THEME_SUCCESS \
      --cursor-prefix="${PAD}[ ] " --unselected-prefix="${PAD}[ ] " --selected-prefix="${PAD}[x] " "$@" </dev/tty)
    [ -z "$out" ] && { echo none; return; }; echo "$out" | paste -sd, -
  else echo none; fi
}
confirm() {  # confirm "Question"  → exit status (yes=0)
  local q="$1"
  if have_gum; then "$GUM" confirm "$q" --padding "0 0 0 $LAYOUT_MARGIN" \
      --prompt.foreground=$THEME_PRIMARY --selected.background=$THEME_BORDER --selected.foreground=232 </dev/tty
  else printf '%s%s [y/N] ' "$PAD" "$q"; read -r a </dev/tty 2>/dev/null; [ "$a" = y ]; fi
}

# summary_table  — reads "Component|Selection" lines on stdin, renders a grid.
# With the fork: per-row dividers (--border-row) and a fixed width matching the
# header box (--width; +2 offsets gum's column-split rounding), styling neutralized
# so the first data row isn't treated as a header. Without the fork: a plain gum
# table. Without gum at all: column(1).
summary_table() {
  if have_gum && gum_has_width; then
    "$GUM" table -p --separator="|" --border double --border-row \
      --border.foreground=$THEME_BORDER --selected.foreground=$THEME_VALUE --selected.bold=false \
      --columns "Component,Selection" --width "$(( $(cwidth) + 2 ))"
  elif have_gum; then
    "$GUM" table -p --separator="|" --border double --border.foreground=$THEME_BORDER \
      --columns "Component,Selection" --widths 22,40
  else column -t -s'|'; fi
  return 0
}
