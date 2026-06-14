#!/bin/bash
# =============================================================================
#  theme.sh — single source of truth for the semantic color palette.
# =============================================================================
#  The whole environment (gum-based installer UI, interactive shell helpers,
#  and ideally the terminal itself) reads its colors from here. Names are
#  semantic (attention/warning/error), not raw colors, so a retheme is a
#  one-line change and every consumer follows. Semantic colors like "error red"
#  are STABLE — they do not change when the terminal theme changes.
#
#  Two representations of each color, because consumers differ:
#    THEME_<NAME>      256-color code   — for gum (`gum style --foreground N`)
#    THEME_<NAME>_HEX  #rrggbb          — for truecolor escapes / terminal config
#
#  Sourced by lib/ui.sh (gum) and the zsh overlays (interactive helpers).
#  Pure assignments only — no commands, free to source in an interactive shell.
# =============================================================================

# ── Semantic palette ────────────────────────────────────────────────────────
# 256-color codes are the originals from the installer UI (unchanged). The
# CRITICAL hex is anchored to the "Xcode WWDC" red (#bb383a) the user picked —
# a soft brick red — so destructive prompts use that exact tone regardless of
# the terminal theme. Only WARNING/CRITICAL/PATH carry a HEX (the ones shell
# helpers render); the rest are gum-only and keep their 256 codes.
THEME_PRIMARY=51        # step titles, prompts, key accents
THEME_ACCENT=51         # interactive cursor / selection accent
THEME_SUCCESS=107;       THEME_SUCCESS_HEX="#94c66e"   # ✓ done / success (soft olive green, Xcode WWDC)
THEME_WARNING=214;       THEME_WARNING_HEX="#e9b143"   # ⚠ warnings / recoverable-destructive (amber)
THEME_CRITICAL=131;      THEME_CRITICAL_HEX="#bb383a"  # ✗ errors / destructive confirm (soft brick red, Xcode WWDC)
THEME_PATH=33;           THEME_PATH_HEX="#268bd2"      # filesystem paths (blue)
THEME_BORDER=73         # banner & table borders (teal)
THEME_BORDER_MUTED=240  # quiet borders (step box)
THEME_LOG=240           # secondary / log lines under a step
THEME_VALUE=255         # plain values (e.g. summary table cells)
THEME_MUTED=240         # muted markers / hints
THEME_SPINNER=51        # loading spinner (gum spin)

# ── Truecolor escape helper (for shell helpers that want exact hex) ──────────
# theme_fg "#bb383a"  → prints the 24-bit foreground SGR escape for that hex.
# Used by interactive helpers; gum consumers use the 256-color codes above.
theme_fg() {
  local hex="${1#\#}"
  printf '\033[38;2;%d;%d;%dm' "0x${hex:0:2}" "0x${hex:2:2}" "0x${hex:4:2}"
}
