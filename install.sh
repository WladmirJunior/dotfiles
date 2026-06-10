#!/bin/bash
# Dotfiles installer — orchestrator.
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/WladmirJunior/dotfiles/main/install.sh | bash
#   curl -fsSL .../install.sh | bash -s -- minimal
#   curl -fsSL .../install.sh | bash -s -- pentest
#   ./install.sh [desktop|minimal|pentest]
#
# With no profile arg on an interactive terminal you're asked to pick one.
# Profiles in profiles/. Steps in steps/. Detection in lib/detect.sh. UI in lib/ui.sh.
set -uo pipefail

REPO_URL="https://github.com/WladmirJunior/dotfiles.git"
CLONE_DIR="$HOME/.dotfiles"
# Profile may be given explicitly ($1). If omitted, we pick one AFTER detection:
# interactively if there's a tty, else by environment (headless -> minimal).
PROFILE_ARG="${1:-}"

SELF_DIR="$( cd "$( dirname "${BASH_SOURCE[0]:-/dev/null}" )" 2>/dev/null && pwd )"
if [ -n "$SELF_DIR" ] && [ -d "$SELF_DIR/steps" ] && [ -d "$SELF_DIR/profiles" ]; then
  DOTFILES_DIR="$SELF_DIR"
else
  echo "Cloning repo to $CLONE_DIR..."
  if [ -d "$CLONE_DIR/.git" ]; then
    git -C "$CLONE_DIR" pull --ff-only 2>/dev/null || true
  else
    git clone --depth 1 "$REPO_URL" "$CLONE_DIR"
  fi
  DOTFILES_DIR="$CLONE_DIR"
fi
export DOTFILES_DIR

source "$DOTFILES_DIR/lib/detect.sh"
source "$DOTFILES_DIR/lib/ui.sh"

# Put Homebrew on PATH for every step. 01-packages may have just installed it, or
# it may already exist (CI images, re-runs) — either way its shellenv isn't in the
# orchestrator's env, so later steps (02-shell, 04-apps) would hit
# `brew: command not found`. Re-evaluated before each step (see the loop) so a
# brew installed by 01 is visible to 02+.
brew_env() {
  [ "$OS_TYPE" = "Darwin" ] || return 0
  for brew_bin in /opt/homebrew/bin/brew /usr/local/bin/brew; do
    [ -x "$brew_bin" ] && eval "$("$brew_bin" shellenv)" && return 0
  done
}
brew_env

# Fetch the gum fork before the first prompt/banner so the UI renders richly even
# on a clean machine. Single source of truth for the gum binary lives in lib/ui.sh.
ui_bootstrap_gum

# Welcome banner.
if have_gum; then
  "$GUM" style --border double --border-foreground $THEME_BORDER --padding "1 3" \
    --margin "1 0 0 $LAYOUT_MARGIN" --align center --width "$(cwidth)" \
    "$("$GUM" style --foreground $THEME_PRIMARY --bold 'Welcome to the dotfiles setup')" \
    "Bootstrapping this machine · apps, shell, dotfiles" || true
fi

# Resolve the profile. An explicit arg always wins. With no arg: ask interactively
# when a real terminal is reachable, else fall back by environment (headless ->
# minimal). We test /dev/tty rather than FD 0 because under `curl | bash` stdin is
# the script pipe, not the keyboard — but /dev/tty still reaches the terminal.
if [ -n "$PROFILE_ARG" ]; then
  PROFILE="$PROFILE_ARG"
elif [ -r /dev/tty ] && [ "$HEADLESS" != "yes" ]; then
  task "Choose what to install"
  PROFILE="$(choose1 'Profile' \
    'desktop · full GUI setup' \
    'minimal · CLI only' \
    'pentest · CLI + security tools' < /dev/tty)"
  PROFILE="${PROFILE%% *}"   # keep the first word (desktop/minimal/pentest)
  PROFILE="${PROFILE:-desktop}"
  note "→ $PROFILE"
elif [ "$HEADLESS" = "yes" ]; then
  PROFILE="minimal"
  echo "No profile given and host is headless -> defaulting to 'minimal'."
else
  PROFILE="desktop"
fi

PROFILE_FILE="$DOTFILES_DIR/profiles/$PROFILE"
if [ ! -f "$PROFILE_FILE" ]; then
  echo "Unknown profile '$PROFILE'. Available: $(ls "$DOTFILES_DIR/profiles" | tr '\n' ' ')"
  exit 1
fi

note "profile: $PROFILE · OS: $OS_TYPE $ARCH · VM: $IS_VM · headless: $HEADLESS"

# Count the real steps in the profile up front so headers can read "Step N/total".
STEP_TOTAL=$(grep -cvE '^\s*(#|$)' "$PROFILE_FILE")

banner "Base setup · public dotfiles"

# step_title 01-packages.sh -> "packages" : strip NN- prefix and .sh, spaces for dashes.
step_title() { local s="${1#*-}"; s="${s%.sh}"; echo "${s//-/ }"; }

# Read the profile on a dedicated FD (3), not stdin. Under `curl | bash` stdin is
# the pipe carrying the rest of this script; a step that consumes stdin (e.g. brew)
# would otherwise eat the loop's input and skip the remaining steps. Steps still
# inherit the real stdin (FD 0), so interactive ones keep working.
STEP_N=0
while IFS= read -r step <&3; do
  [ -z "$step" ] && continue
  case "$step" in \#*) continue ;; esac
  STEP_N=$((STEP_N + 1))
  brew_env   # pick up a brew that an earlier step (01-packages) may have installed
  step "$STEP_N/$STEP_TOTAL" "$(step_title "$step")"
  bash "$DOTFILES_DIR/steps/$step" || note "step $step failed (rc=$?), continuing"
done 3< "$PROFILE_FILE"

ok "Public setup done (profile: $PROFILE)."
[ "$OS_TYPE" = "Linux" ] && note "Restart terminal to use zsh." || note "Restart terminal."

banner "Next · private overlays"
note "Authenticate first, then apply any private overlays:"
note "gh auth login --git-protocol https --web"
