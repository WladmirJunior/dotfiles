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

  tui_draw() {
    local cols lines
    cols=$(tput cols 2>/dev/null || echo 80)
    lines=$(tput lines 2>/dev/null || echo 24)
    [ "$cols" -lt 50 ] && cols=50
    [ "$lines" -lt 18 ] && lines=18

    # Proportional width: expand across terminal width with a 2-char margin
    local inner_width=$((cols - 4))
    [ "$inner_width" -lt 46 ] && inner_width=46

    local border
    border=$(printf '%*s' "$inner_width" '' | tr ' ' '─')

    # Move cursor to top-left and clear
    printf '\033[H\033[2J' >/dev/tty

    local rendered_lines=0

    # 1. Header Box
    printf "${c_cyan}  ┌%s┐${c_reset}\n" "$border" >/dev/tty; ((rendered_lines++))
    printf "${c_cyan}  │${c_bold}%*s%-*s${c_reset}${c_cyan}│${c_reset}\n" \
      $(( (inner_width - 25) / 2 )) "" $(( inner_width - (inner_width - 25) / 2 )) "DOTFILES ARCHINSTALL MENU" >/dev/tty; ((rendered_lines++))
    printf "${c_cyan}  │${c_dim}%*s%-*s${c_reset}${c_cyan}│${c_reset}\n" \
      $(( (inner_width - 36) / 2 )) "" $(( inner_width - (inner_width - 36) / 2 )) "Full-Screen Configuration Interface" >/dev/tty; ((rendered_lines++))

    local sys_desc="OS: $tui_os ($tui_arch)"
    if [ "$is_darwin" -eq 1 ]; then
      local mac_ver
      mac_ver="$(sw_vers -productVersion 2>/dev/null || echo "")"
      [ -n "$mac_ver" ] && sys_desc="$sys_desc • macOS $mac_ver"
    fi
    sys_desc="$sys_desc • Standalone / Minimal Engine"
    local sys_len=${#sys_desc}
    [ "$sys_len" -ge "$inner_width" ] && sys_desc="${sys_desc:0:$((inner_width - 4))}..."
    printf "${c_cyan}  │${c_dim}%*s%-*s${c_reset}${c_cyan}│${c_reset}\n" \
      $(( (inner_width - ${#sys_desc}) / 2 )) "" $(( inner_width - (inner_width - ${#sys_desc}) / 2 )) "$sys_desc" >/dev/tty; ((rendered_lines++))
    printf "${c_cyan}  └%s┘${c_reset}\n" "$border" >/dev/tty; ((rendered_lines++))

    printf "\n" >/dev/tty; ((rendered_lines++))

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

    # 3. Render Menu Items with dynamic dot-leaders spanning the full width
    local content_width=$((inner_width - 4))
    local i
    for ((i=0; i<count; i++)); do
      if [ "${item_keys[i]}" = "install" ]; then
        printf "  ${c_cyan}  %s${c_reset}\n" "$(printf '%*s' "$content_width" '' | tr ' ' '─')" >/dev/tty; ((rendered_lines++))
      fi

      local lbl="${item_labels[i]}"
      local val="${item_vals[i]}"

      if [ -n "$val" ]; then
        local label_len=${#lbl}
        local val_len=${#val}
        local dots_len=$(( content_width - label_len - val_len - 6 ))
        [ "$dots_len" -lt 2 ] && dots_len=2
        local dots=$(printf '%*s' "$dots_len" '' | tr ' ' '.')

        if [ "$i" -eq "$tui_cursor" ]; then
          local line_str=$(printf "▸ %s %s %s" "$lbl" "$dots" "$val")
          printf "    ${c_cyan}${c_bold}${c_rev} %-*s ${c_reset}\n" "$((content_width - 2))" "$line_str" >/dev/tty; ((rendered_lines++))
        else
          printf "      %s ${c_dim}%s${c_reset} %s\n" "$lbl" "$dots" "$val" >/dev/tty; ((rendered_lines++))
        fi
      else
        # Action buttons
        if [ "$i" -eq "$tui_cursor" ]; then
          printf "    ${c_cyan}${c_bold}${c_rev} ▸ %-*s ${c_reset}\n" "$((content_width - 4))" "$lbl" >/dev/tty; ((rendered_lines++))
        else
          printf "        %s\n" "$lbl" >/dev/tty; ((rendered_lines++))
        fi
      fi
    done

    # 4. Dynamic Vertical Padding down to the footer/help area
    # Help box (3 lines) + Footer separator & text (2 lines) = 5 lines at bottom
    local bottom_lines=6
    local pad_lines=$(( lines - rendered_lines - bottom_lines ))
    [ "$pad_lines" -lt 1 ] && pad_lines=1
    for ((p=0; p<pad_lines; p++)); do
      printf "\n" >/dev/tty; ((rendered_lines++))
    done

    # 5. Contextual Help Box (Fixed position above footer)
    local active_desc="${item_descs[tui_cursor]}"
    local help_border_fill=$(( inner_width - 10 ))
    [ "$help_border_fill" -lt 2 ] && help_border_fill=2
    local help_border=$(printf '%*s' "$help_border_fill" '' | tr ' ' '─')

    printf "  ${c_cyan}┌─ Help ─%s┐${c_reset}\n" "$help_border" >/dev/tty; ((rendered_lines++))
    printf "  ${c_cyan}│${c_reset}  ${c_dim}ℹ %-*s${c_reset}${c_cyan}│${c_reset}\n" "$((inner_width - 5))" "$active_desc" >/dev/tty; ((rendered_lines++))
    printf "  ${c_cyan}└%s┘${c_reset}\n" "$border" >/dev/tty; ((rendered_lines++))

    # 6. Footer Bar
    local footer_text
    if [ "$inner_width" -ge 86 ]; then
      footer_text="[↑/↓/j/k] Navigate  •  [Space/Enter] Toggle  •  [1-${dry_num}] Jump  •  [i] Install  •  [q] Quit"
    else
      footer_text="[↑/↓] Move • [Space] Toggle • [1-${dry_num}] Jump • [i] Install • [q] Quit"
    fi
    printf "  ${c_cyan}  %s${c_reset}\n" "$border" >/dev/tty; ((rendered_lines++))
    printf "    ${c_dim}%s${c_reset}\n" "$footer_text" >/dev/tty; ((rendered_lines++))
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
