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
#
# Flags:
#   --dry-run, -n   announce every state-changing action without executing it
#   --plan, -p      same as --dry-run but show a categorized summary at the end
#                   (create/update/install/skip counts + per-item list)
#   --check         run only the post-install verification (no steps)
set -uo pipefail

REPO_URL="https://github.com/WladmirJunior/dotfiles.git"
CLONE_DIR="$HOME/.dotfiles"

# Parse flags (any order) and keep the first non-flag arg as the profile.
DRY_RUN=0; CHECK_ONLY=0; PLAN_MODE=0; PROFILE_ARG=""
for arg in "$@"; do
  case "$arg" in
    --dry-run|-n) DRY_RUN=1 ;;
    --plan|-p)    DRY_RUN=1; PLAN_MODE=1 ;;
    --check)      CHECK_ONLY=1 ;;
    -*)           echo "Unknown flag: $arg" >&2; exit 2 ;;
    *)            [ -z "$PROFILE_ARG" ] && PROFILE_ARG="$arg" ;;
  esac
done
export DRY_RUN PLAN_MODE

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
[ -f "$DOTFILES_DIR/lib/template.sh" ] && source "$DOTFILES_DIR/lib/template.sh"
[ -f "$DOTFILES_DIR/lib/plan.sh" ]     && source "$DOTFILES_DIR/lib/plan.sh"
[ "$PLAN_MODE" = 1 ] && plan_reset

# verify_install: post-install health check. Symlinks resolve, core tools on PATH.
# Run as the final step of a normal install, or standalone via `--check`.
verify_install() {
  banner "Verify · post-install health check"
  verify_cmd git; verify_cmd zsh
  command -v nvim >/dev/null 2>&1 && verify_cmd nvim
  verify_path "$HOME/.zshrc"
  [ -e "$HOME/.config/nvim/init.lua" ] && verify_link "$HOME/.config/nvim/init.lua"
  [ -e "$HOME/.config/ghostty/config" ] && verify_link "$HOME/.config/ghostty/config"
  if [ "$VERIFY_FAILS" -eq 0 ]; then ok "all checks passed"
  else note "$VERIFY_FAILS check(s) failed — see FAIL lines above"; fi
  return "$VERIFY_FAILS"
}

# --check: verification only, no install steps.
if [ "$CHECK_ONLY" = 1 ]; then
  verify_install; exit $?
fi

# Announce dry-run / plan mode up front so the user knows nothing will be changed.
if [ "$PLAN_MODE" = 1 ]; then
  info "PLAN: capturing planned changes; nothing will be executed."
elif [ "$DRY_RUN" = 1 ]; then
  info "DRY-RUN: actions are announced, not executed."
fi

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
    'pentest · CLI + security tools')"
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
# the pipe carrying the rest of this script; a step that consumes stdin (e.g. brew
# installing a cask) would otherwise drain it and bash would hit EOF after the
# loop, skipping the closing banner. Each step runs with stdin from /dev/null so it
# can't touch the pipe; interactive steps read /dev/tty directly, not stdin.
STEP_N=0
while IFS= read -r step <&3; do
  [ -z "$step" ] && continue
  case "$step" in \#*) continue ;; esac
  STEP_N=$((STEP_N + 1))
  brew_env   # pick up a brew that an earlier step (01-packages) may have installed
  step "$STEP_N/$STEP_TOTAL" "$(step_title "$step")"
  bash "$DOTFILES_DIR/steps/$step" </dev/null || note "step $step failed (rc=$?), continuing"
done 3< "$PROFILE_FILE"

ok "Public setup done (profile: $PROFILE)."

# Plan mode: emit the summary of recorded changes and exit before private overlays.
if [ "$PLAN_MODE" = 1 ]; then
  banner "Plan summary"
  plan_summary
  plan_cleanup
  exit 0
fi

# Verify what the steps just applied (skipped in dry-run: nothing was changed).
[ "$DRY_RUN" = 1 ] || verify_install || note "verification reported issues (see above)"

# -----------------------------------------------------------------------------
#  Connect & authenticate (opt-in) — wire up the 1Password SSH agent + GitHub CLI
#  so private overlays can be fetched. Generic: only ever names 1Password/GitHub,
#  never any private repo. macOS only (1Password app + op CLI).
# -----------------------------------------------------------------------------
OP_SOCK="$HOME/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"
ZLOCAL="$HOME/.zshrc.local"   # machine-local overlay sourced by the thin ~/.zshrc

# append_once FILE MARKER LINE: add LINE to FILE only if MARKER not already there.
append_once() {
  local f="$1" marker="$2" line="$3"
  mkdir -p "$(dirname "$f")"; touch "$f"
  grep -qF "$marker" "$f" 2>/dev/null || printf '%s\n' "$line" >> "$f"
}

if [ "$OS_TYPE" = "Darwin" ] && confirm "Authenticate with 1Password now?"; then
  banner "Connect & authenticate · 1Password, GitHub, SSH"

  task "1Password · install & connect (one time)"
  # 1Password 8 ships via the brew cask from the official site (the App Store only
  # has the legacy v7). Installed here, not in the base setup, so a machine that
  # opts out of auth never pulls the 198MB cask.
  if [ ! -d "/Applications/1Password.app" ]; then
    spin "installing 1Password" -- brew install --cask 1password </dev/null \
      || note "1Password install failed — install it manually"
  fi
  # open by path, not by name: LaunchServices may not have indexed the just-moved
  # app yet, so `open -a "1Password"` can fail right after install.
  open /Applications/1Password.app 2>/dev/null || note "open 1Password manually"
  note "In the 1Password app:"
  note "1. Sign in to your 1Password account"
  note "2. Settings > Developer > enable \"Use the SSH agent\""
  note "3. Settings > Developer > enable \"Integrate with 1Password CLI\""
  note "   (if a \"Set Up SSH Agent\" popup offers to edit ~/.ssh/config, just"
  note "    close it — this script writes that config for you)"
  confirm "Done? Continue" || true

  task "SSH agent · 1Password"
  export SSH_AUTH_SOCK="$OP_SOCK"
  append_once "$ZLOCAL" "2BUA8C4S2C.com.1password/t/agent.sock" \
    'export SSH_AUTH_SOCK="$HOME/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"'
  # ~/.ssh/config IdentityAgent so GUI apps (not just the shell) use the agent.
  # Match on the agent-socket fragment (not the exact line) so we don't duplicate
  # a block 1Password may have written itself via its "Edit Automatically" popup.
  append_once "$HOME/.ssh/config" "2BUA8C4S2C.com.1password/t/agent.sock" \
    "$(printf 'Host *\n  IdentityAgent "%s"' "$OP_SOCK")"
  chmod 600 "$HOME/.ssh/config" 2>/dev/null || true
  ok "SSH uses the 1Password agent (Touch ID per use)"

  task "GitHub CLI · 1Password shell plugin"
  # The op CLI is a separate cask from the desktop app; install it if missing.
  if ! command -v op >/dev/null 2>&1; then
    spin "installing 1Password CLI" -- brew install --cask 1password-cli </dev/null || true
    brew_env
  fi
  if command -v op >/dev/null 2>&1; then
    op plugin init gh </dev/tty || note "op plugin init gh did not complete"
    # op prints a manual "echo source ... >> ~/.zshrc" hint — we've already wired
    # the source into ~/.zshrc.local, so that hint can be ignored.
    append_once "$ZLOCAL" 'op/plugins.sh' \
      '[ -f "$HOME/.config/op/plugins.sh" ] && source "$HOME/.config/op/plugins.sh"'
    rm -f "$HOME/.config/gh/hosts.yml" 2>/dev/null || true   # no on-disk gh creds
    ok "gh plugin wired into ~/.zshrc.local (ignore op's echo hint above)"
  else
    note "1Password CLI unavailable — run 'op plugin init gh' after installing it"
  fi

  banner "Next · private overlays"
  # The bootstrap script lives in the 1Password Secure Note (no private repo names
  # in this public repo). We can run it right here: SSH_AUTH_SOCK is already
  # exported and the op gh plugin is sourced into this session below — so there's
  # nothing to reload first.
  BOOTSTRAP='op://Personal/dotfiles-bootstrap/bootstrap_script'
  if command -v op >/dev/null 2>&1 && confirm "Apply private overlays now?"; then
    # Load the op gh plugin alias into THIS session so the bootstrap's gh calls
    # authenticate via 1Password without a shell reload.
    [ -f "$HOME/.config/op/plugins.sh" ] && source "$HOME/.config/op/plugins.sh"
    note "fetching bootstrap from 1Password and applying overlays..."
    if ! op read "$BOOTSTRAP" 2>/dev/null | bash; then
      note "bootstrap did not complete — run it manually:"
      info "op read \"$BOOTSTRAP\" | bash"
    fi
  else
    note "Apply your private overlays later with:"
    info "op read \"$BOOTSTRAP\" | bash"
    note "(reload the shell first if gh isn't authenticated yet: exec zsh)"
  fi
else
  [ "$OS_TYPE" = "Darwin" ] && info "Skipped authentication. Run it later from the 1Password handoff."
  [ "$OS_TYPE" = "Linux" ] && info "Restart your terminal to use zsh."
  [ "$OS_TYPE" = "Darwin" ] && info "Reload your shell to pick up the new config:  exec zsh"
fi
