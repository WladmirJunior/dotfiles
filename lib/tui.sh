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
    [ "$cols" -gt 80 ] && cols=80

    local inner_width=$((cols - 4))
    [ "$inner_width" -lt 40 ] && inner_width=40

    local border
    border=$(printf '%*s' "$inner_width" '' | tr ' ' '─')

    # Move cursor to top-left and clear
    printf '\033[H\033[2J' >/dev/tty

    # 1. Header Box
    printf "${c_cyan}  ┌%s┐${c_reset}\n" "$border" >/dev/tty
    printf "${c_cyan}  │${c_bold}%*s%-*s${c_reset}${c_cyan}│${c_reset}\n" \
      $(( (inner_width - 25) / 2 )) "" $(( inner_width - (inner_width - 25) / 2 )) "DOTFILES ARCHINSTALL MENU" >/dev/tty
    printf "${c_cyan}  │${c_dim}%*s%-*s${c_reset}${c_cyan}│${c_reset}\n" \
      $(( (inner_width - 34) / 2 )) "" $(( inner_width - (inner_width - 34) / 2 )) "Full-Screen Configuration Interface" >/dev/tty
    printf "${c_cyan}  └%s┘${c_reset}\n" "$border" >/dev/tty

    # 2. System Status Badge
    local sys_desc="OS: $tui_os ($tui_arch)"
    if [ "$is_darwin" -eq 1 ]; then
      local mac_ver
      mac_ver="$(sw_vers -productVersion 2>/dev/null || echo "")"
      [ -n "$mac_ver" ] && sys_desc="$sys_desc • macOS $mac_ver"
    fi
    printf "  ${c_dim}%s • Standalone / Minimal Engine${c_reset}\n\n" "$sys_desc" >/dev/tty

    # 3. Build Menu Item List
    # We dynamically construct options depending on OS
    local -a item_keys=() item_labels=() item_descs=()

    # Option 1: Profile
    item_keys+=("profile")
    item_labels+=("Profile ........................ [ $tui_profile ]")
    case "$tui_profile" in
      minimal) item_descs+=("Essential CLI tools without Homebrew or Xcode CLT") ;;
      desktop) item_descs+=("Complete workstation setup with GUI apps & tools") ;;
      pentest) item_descs+=("CLI environment + security & penetration testing") ;;
    esac

    # macOS specific options
    if [ "$is_darwin" -eq 1 ]; then
      item_keys+=("kitty")
      if [ "$tui_kitty" -eq 1 ]; then
        item_labels+=("[*] Standalone Kitty Terminal .... (Enabled)")
        item_descs+=("Fast GPU terminal with Yazi image protocol support")
      else
        item_labels+=("[ ] Standalone Kitty Terminal .... (Disabled)")
        item_descs+=("Skip installing Kitty.app on this machine")
      fi

      item_keys+=("yabai")
      if [ "$tui_yabai" -eq 1 ]; then
        item_labels+=("[*] Standalone yabai Manager ..... (Enabled)")
        item_descs+=("Ultra-lightweight tiling window manager (~15MB RAM)")
      else
        item_labels+=("[ ] Standalone yabai Manager ..... (Disabled)")
        item_descs+=("Skip installing yabai binary and yabairc")
      fi
    fi

    # Dry-run
    item_keys+=("dryrun")
    if [ "$tui_dryrun" -eq 1 ]; then
      item_labels+=("[*] Dry-run Simulation .......... (Simulate only)")
      item_descs+=("Announce actions without modifying system state")
    else
      item_labels+=("[ ] Dry-run Simulation .......... (Disabled)")
      item_descs+=("Execute real changes and package installations")
    fi

    # Actions
    item_keys+=("install")
    item_labels+=("▶  Install / Apply Configuration")
    item_descs+=("Proceed with installation using selected parameters")

    item_keys+=("exit")
    item_labels+=("✖  Cancel / Exit Installer")
    item_descs+=("Exit cleanly without modifying the system")

    local count=${#item_keys[@]}

    # Ensure cursor in range
    [ "$tui_cursor" -ge "$count" ] && tui_cursor=$((count - 1))
    [ "$tui_cursor" -lt 0 ] && tui_cursor=0

    # 4. Render Menu Items
    local i
    for ((i=0; i<count; i++)); do
      # Separator before action buttons
      if [ "${item_keys[i]}" = "install" ]; then
        printf "  ${c_cyan}  %s${c_reset}\n" "$(printf '%*s' $((inner_width - 4)) '' | tr ' ' '─')" >/dev/tty
      fi

      local prefix="    "
      local num_str="$((i + 1)). "
      if [ "${item_keys[i]}" = "install" ] || [ "${item_keys[i]}" = "exit" ]; then
        num_str="   "
      fi

      if [ "$i" -eq "$tui_cursor" ]; then
        printf "  ${c_cyan}${c_bold}${c_rev} ▸ %s%-58s ${c_reset}\n" "$num_str" "${item_labels[i]}" >/dev/tty
        printf "      ${c_cyan}↳ %s${c_reset}\n" "${item_descs[i]}" >/dev/tty
      else
        printf "    %s%-58s\n" "$num_str" "${item_labels[i]}" >/dev/tty
      fi
    done

    # 5. Footer Bar
    printf "\n  ${c_cyan}├%s┤${c_reset}\n" "$border" >/dev/tty
    if [ "$is_darwin" -eq 1 ]; then
      printf "  ${c_dim} [↑/↓/j/k] Navigate  •  [Space/Enter] Toggle  •  [1-4] Jump  •  [i] Install  •  [q] Quit${c_reset}\n" >/dev/tty
    else
      printf "  ${c_dim} [↑/↓/j/k] Navigate  •  [Space/Enter] Toggle  •  [1-2] Jump  •  [i] Install  •  [q] Quit${c_reset}\n" >/dev/tty
    fi
  }

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
