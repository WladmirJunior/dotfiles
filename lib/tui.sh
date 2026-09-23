#!/usr/bin/env bash
# =============================================================================
#  lib/tui.sh — Archinstall-style full-screen TUI for dotfiles installer.
# =============================================================================
#  Pure Bash 3.2+ and ANSI VT100 escapes. Zero external dependencies (no gum,
#  no dialog, no python).
#
#  Usage:
#    source "$DOTFILES_DIR/lib/tui.sh"
#    tui_launch   # returns 0 to proceed with install, 1 to cancel
# =============================================================================

tui_launch() {
  # Must be interactive with a reachable terminal
  [ -r /dev/tty ] || return 1
  [ -t 1 ] || [ -t 2 ] || return 1

  local saved_stty
  saved_stty="$(stty -g 2>/dev/null || true)"

  # State
  local tui_profile="${PROFILE:-minimal}"
  local tui_kitty="${INSTALL_KITTY:-1}"
  local tui_yabai="${INSTALL_YABAI:-1}"
  local tui_dryrun="${DRY_RUN:-0}"
  local tui_cursor=0
  local tui_os="${OS_TYPE:-$(uname)}"
  local tui_arch="${ARCH:-$(uname -m)}"
  local tui_result=1

  # Colors & Styles
  local c_cyan=$'\033[36m'
  local c_green=$'\033[32m'
  local c_yellow=$'\033[33m'
  local c_magenta=$'\033[35m'
  local c_bold=$'\033[1m'
  local c_dim=$'\033[2m'
  local c_rev=$'\033[7m'
  local c_reset=$'\033[0m'

  # Switch to alternate screen buffer and hide cursor
  printf '\033[?1049h\033[?25l' >/dev/tty

  tui_cleanup() {
    printf '\033[?25h\033[?1049l' >/dev/tty 2>/dev/null || true
    if [ -n "$saved_stty" ]; then
      stty "$saved_stty" 2>/dev/null || true
    fi
  }
  trap tui_cleanup EXIT INT TERM

  local is_darwin=0
  [ "$tui_os" = "Darwin" ] && is_darwin=1

  # Cycle through profiles
  cycle_profile() {
    case "$tui_profile" in
      minimal) tui_profile="desktop" ;;
      desktop) tui_profile="pentest" ;;
      pentest) tui_profile="minimal" ;;
      *)       tui_profile="minimal" ;;
    esac
  }

  # Box drawing and padding count display characters, not bytes: bash's
  # printf pads "%-*s" by bytes, which shortens every row holding ▸, •, ℹ or ─
  # and breaks the right border. ${#var} counts characters under a UTF-8 locale.
  case "${LC_ALL:-${LC_CTYPE:-${LANG:-}}}" in
    *UTF-8*|*utf-8*|*UTF8*|*utf8*) ;;
    *) if [ "$is_darwin" -eq 1 ]; then local LC_ALL=en_US.UTF-8; else local LC_ALL=C.UTF-8; fi ;;
  esac

  # tui_size: set cols/lines from the controlling terminal. `tput` inside $(...)
  # sees a pipe on stdout and, under `curl | bash`, falls back to 80x24.
  tui_size() {
    local sz
    sz="$(stty size 2>/dev/null </dev/tty || true)"
    lines="${DOTFILES_TERM_LINES:-${sz% *}}"
    cols="${DOTFILES_TERM_COLS:-${sz#* }}"
    case "$lines" in ''|0|*[!0-9]*) lines=$(tput lines 2>/dev/null || echo 24) ;; esac
    case "$cols" in ''|0|*[!0-9]*) cols=$(tput cols 2>/dev/null || echo 80) ;; esac
  }

  # tui_rep CHAR N: CHAR repeated N times (locale-independent, unlike tr).
  tui_rep() {
    local r=""
    [ "$2" -gt 0 ] && { r="$(printf '%*s' "$2" '')"; r="${r// /$1}"; }
    printf '%s' "$r"
  }

  # tui_fit TEXT WIDTH: TEXT truncated with … or right-padded to exactly WIDTH.
  tui_fit() {
    local t="$1" w="$2"
    if [ "${#t}" -gt "$w" ]; then
      t="${t:0:$((w - 1))}…"
    fi
    printf '%s%s' "$t" "$(tui_rep ' ' $((w - ${#t})))"
  }

  # tui_center TEXT WIDTH
  tui_center() {
    local t="$1" w="$2" left
    [ "${#t}" -gt "$w" ] && t="${t:0:$((w - 1))}…"
    left=$(( (w - ${#t}) / 2 ))
    tui_fit "$(tui_rep ' ' "$left")$t" "$w"
  }

  tui_draw() {
    local cols lines
    tui_size
    [ "$cols" -lt 50 ] && cols=50
    [ "$lines" -lt 18 ] && lines=18

    # W: width inside the box borders. Rows are 2 + 1 + W + 1 = cols - 2 wide,
    # leaving a 2-column margin on both sides.
    local W=$((cols - 6))
    local hr; hr="$(tui_rep '─' "$W")"
    local frame="" nl=$'\n' rendered_lines=0

    # 1. Header Box
    local sys_desc="OS: $tui_os ($tui_arch)"
    if [ "$is_darwin" -eq 1 ]; then
      local mac_ver
      mac_ver="$(sw_vers -productVersion 2>/dev/null || echo "")"
      [ -n "$mac_ver" ] && sys_desc="$sys_desc • macOS $mac_ver"
    fi
    sys_desc="$sys_desc • Standalone / Minimal Engine"

    frame+="  ${c_cyan}┌${hr}┐${c_reset}${nl}"
    frame+="  ${c_cyan}│${c_bold}$(tui_center "DOTFILES ARCHINSTALL MENU" "$W")${c_reset}${c_cyan}│${c_reset}${nl}"
    frame+="  ${c_cyan}│${c_reset}${c_dim}$(tui_center "Full-Screen Configuration Interface" "$W")${c_reset}${c_cyan}│${c_reset}${nl}"
    frame+="  ${c_cyan}│${c_reset}${c_dim}$(tui_center "$sys_desc" "$W")${c_reset}${c_cyan}│${c_reset}${nl}"
    frame+="  ${c_cyan}└${hr}┘${c_reset}${nl}${nl}"
    rendered_lines=6

    # 2. Build Menu Item List
    local -a item_keys=() item_labels=() item_vals=() item_descs=()

    # Option 1: Profile
    item_keys+=("profile")
    item_labels+=("1. Profile")
    item_vals+=("[ $tui_profile ]")
    case "$tui_profile" in
      minimal) item_descs+=("Essential CLI tools without Homebrew or Xcode CLT") ;;
      desktop) item_descs+=("Complete workstation setup with GUI apps & tools") ;;
      pentest) item_descs+=("CLI environment + security & penetration testing") ;;
    esac

    # macOS specific options
    if [ "$is_darwin" -eq 1 ]; then
      item_keys+=("kitty")
      if [ "$tui_kitty" -eq 1 ]; then
        item_labels+=("2. [*] Standalone Kitty Terminal")
        item_vals+=("(Enabled)")
        item_descs+=("Fast GPU terminal with native Yazi image protocol support")
      else
        item_labels+=("2. [ ] Standalone Kitty Terminal")
        item_vals+=("(Disabled)")
        item_descs+=("Skip installing Kitty.app on this machine")
      fi

      item_keys+=("yabai")
      if [ "$tui_yabai" -eq 1 ]; then
        item_labels+=("3. [*] Standalone yabai Manager")
        item_vals+=("(Enabled)")
        item_descs+=("Ultra-lightweight tiling window manager (~15MB RAM)")
      else
        item_labels+=("3. [ ] Standalone yabai Manager")
        item_vals+=("(Disabled)")
        item_descs+=("Skip installing yabai binary and yabairc")
      fi
    fi

    # Dry-run
    item_keys+=("dryrun")
    local dry_num=2
    [ "$is_darwin" -eq 1 ] && dry_num=4
    if [ "$tui_dryrun" -eq 1 ]; then
      item_labels+=("${dry_num}. [*] Dry-run Simulation")
      item_vals+=("(Simulate only)")
      item_descs+=("Announce actions without modifying system state")
    else
      item_labels+=("${dry_num}. [ ] Dry-run Simulation")
      item_vals+=("(Disabled)")
      item_descs+=("Execute real changes and package installations")
    fi

    # Actions
    item_keys+=("install")
    item_labels+=("▶  Install / Apply Configuration")
    item_vals+=("")
    item_descs+=("Proceed with installation using selected parameters")

    item_keys+=("exit")
    item_labels+=("✖  Cancel / Exit Installer")
    item_vals+=("")
    item_descs+=("Exit cleanly without modifying the system")

    local count=${#item_keys[@]}

    # Ensure cursor in range
    [ "$tui_cursor" -ge "$count" ] && tui_cursor=$((count - 1))
    [ "$tui_cursor" -lt 0 ] && tui_cursor=0

    # 3. Menu rows span the box's outer width (W + 2), dot leaders fill the gap.
    local RW=$((W + 2)) i row marker dots_len
    for ((i=0; i<count; i++)); do
      if [ "${item_keys[i]}" = "install" ]; then
        frame+="   ${c_cyan}${hr}${c_reset}${nl}"; rendered_lines=$((rendered_lines + 1))
      fi
      marker="   "
      [ "$i" -eq "$tui_cursor" ] && marker=" ▸ "
      if [ -n "${item_vals[i]}" ]; then
        # The value always stays visible; a narrow terminal shortens the label.
        local lbl_w=$(( RW - 3 - ${#item_vals[i]} - 5 ))
        local lbl="${item_labels[i]}"
        [ "${#lbl}" -gt "$lbl_w" ] && lbl="$(tui_fit "$lbl" "$lbl_w")"
        dots_len=$(( RW - 3 - ${#lbl} - ${#item_vals[i]} - 3 ))
        row="$(tui_fit "${marker}${lbl} $(tui_rep '.' "$dots_len") ${item_vals[i]}" "$RW")"
      else
        row="$(tui_fit "${marker}${item_labels[i]}" "$RW")"
      fi
      if [ "$i" -eq "$tui_cursor" ]; then
        frame+="  ${c_cyan}${c_bold}${c_rev}${row}${c_reset}${nl}"
      else
        frame+="  ${row}${nl}"
      fi
      rendered_lines=$((rendered_lines + 1))
    done

    # 4. Pad down so help box + footer (5 rows) end on the terminal's last row.
    local pad_lines=$(( lines - rendered_lines - 5 ))
    [ "$pad_lines" -lt 0 ] && pad_lines=0
    local p; for ((p=0; p<pad_lines; p++)); do frame+="$nl"; done

    # 5. Contextual Help Box
    frame+="  ${c_cyan}┌─ Help $(tui_rep '─' $((W - 7)))┐${c_reset}${nl}"
    frame+="  ${c_cyan}│${c_reset}${c_dim}$(tui_fit " ℹ ${item_descs[tui_cursor]}" "$W")${c_reset}${c_cyan}│${c_reset}${nl}"
    frame+="  ${c_cyan}└${hr}┘${c_reset}${nl}"

    # 6. Footer Bar (no newline after the last row, so the screen never scrolls)
    local footer_text
    if [ "$W" -ge 86 ]; then
      footer_text="[↑/↓/j/k] Navigate  •  [Space/Enter] Toggle  •  [1-${dry_num}] Jump  •  [i] Install  •  [q] Quit"
    else
      footer_text="[↑/↓] Move • [Space] Toggle • [1-${dry_num}] Jump • [i] Install • [q] Quit"
    fi
    frame+="   ${c_cyan}${hr}${c_reset}${nl}"
    frame+="  ${c_dim}$(tui_fit " $footer_text" "$RW")${c_reset}"

    printf '\033[H\033[2J%s' "$frame" >/dev/tty
  }

  # Redraw automatically on terminal resize (SIGWINCH)
  trap tui_draw WINCH

  # Interactive input loop
  while true; do
    tui_draw

    local key="" rest=""
    IFS= read -rsn1 key </dev/tty || break

    if [ "$key" = $'\x1b' ]; then
      # Read escape sequence with 1-second timeout (Bash 3.2 compliant)
      read -rsn2 -t 1 rest </dev/tty || rest=""
      case "$rest" in
        '[A'|'OA') key="UP" ;;
        '[B'|'OB') key="DOWN" ;;
        '[C'|'OC') key="RIGHT" ;;
        '[D'|'OD') key="LEFT" ;;
        *)         key="ESC" ;;
      esac
    fi

    # Total items count
    local count=4
    [ "$is_darwin" -eq 1 ] && count=6

    case "$key" in
      UP|k|K)
        tui_cursor=$(( (tui_cursor - 1 + count) % count ))
        ;;
      DOWN|j|J)
        tui_cursor=$(( (tui_cursor + 1) % count ))
        ;;
      ' '|'')
        # Space or Enter: toggle or action
        if [ "$is_darwin" -eq 1 ]; then
          case "$tui_cursor" in
            0) cycle_profile ;;
            1) tui_kitty=$(( 1 - tui_kitty )) ;;
            2) tui_yabai=$(( 1 - tui_yabai )) ;;
            3) tui_dryrun=$(( 1 - tui_dryrun )) ;;
            4) tui_result=0; break ;; # Install
            5) tui_result=1; break ;; # Exit
          esac
        else
          case "$tui_cursor" in
            0) cycle_profile ;;
            1) tui_dryrun=$(( 1 - tui_dryrun )) ;;
            2) tui_result=0; break ;; # Install
            3) tui_result=1; break ;; # Exit
          esac
        fi
        ;;
      1)
        tui_cursor=0
        cycle_profile
        ;;
      2)
        tui_cursor=1
        if [ "$is_darwin" -eq 1 ]; then tui_kitty=$(( 1 - tui_kitty )); else tui_dryrun=$(( 1 - tui_dryrun )); fi
        ;;
      3)
        tui_cursor=2
        if [ "$is_darwin" -eq 1 ]; then tui_yabai=$(( 1 - tui_yabai )); else tui_result=0; break; fi
        ;;
      4)
        tui_cursor=3
        if [ "$is_darwin" -eq 1 ]; then tui_dryrun=$(( 1 - tui_dryrun )); else tui_result=1; break; fi
        ;;
      5)
        if [ "$is_darwin" -eq 1 ]; then tui_cursor=4; tui_result=0; break; fi
        ;;
      6)
        if [ "$is_darwin" -eq 1 ]; then tui_cursor=5; tui_result=1; break; fi
        ;;
      i|I)
        tui_result=0
        break
        ;;
      q|Q|ESC)
        tui_result=1
        break
        ;;
    esac
  done

  trap - WINCH
  tui_cleanup
  trap - EXIT INT TERM

  if [ "$tui_result" -eq 0 ]; then
    PROFILE="$tui_profile"
    INSTALL_KITTY="$tui_kitty"
    INSTALL_YABAI="$tui_yabai"
    DRY_RUN="$tui_dryrun"
    export PROFILE INSTALL_KITTY INSTALL_YABAI DRY_RUN
    return 0
  else
    echo "Installer aborted by user."
    return 1
  fi
}
