#!/bin/bash
# Dotfiles installer — orchestrator.
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/WladmirJunior/dotfiles/main/install.sh | bash
#   curl -fsSL .../install.sh | bash -s -- minimal
#   curl -fsSL .../install.sh | bash -s -- pentest
#   ./install.sh [desktop|minimal|pentest]
#
# Profiles in profiles/. Steps in steps/. Detection in lib/detect.sh.
set -uo pipefail

REPO_URL="https://github.com/WladmirJunior/dotfiles.git"
CLONE_DIR="$HOME/.dotfiles"
# Profile may be given explicitly ($1). If omitted, we pick a default AFTER
# detection (headless hosts default to minimal — no GUI apps to install).
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

# Resolve the profile. An explicit arg always wins. With no arg, the detected
# environment chooses the default: a headless host (no display) gets `minimal`
# (GUI apps would be pointless); anything with a display gets `desktop`.
if [ -n "$PROFILE_ARG" ]; then
  PROFILE="$PROFILE_ARG"
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

echo "dotfiles | profile: $PROFILE | OS: $OS_TYPE $ARCH | VM: $IS_VM | headless: $HEADLESS | tty: $INTERACTIVE"

# Read the profile on a dedicated FD (3), not stdin. Under `curl | bash` stdin is
# the pipe carrying the rest of this script; a step that consumes stdin (e.g. brew)
# would otherwise eat the loop's input and skip the remaining steps. Steps still
# inherit the real stdin (FD 0), so interactive ones like git-auth keep working.
while IFS= read -r step <&3; do
  [ -z "$step" ] && continue
  case "$step" in \#*) continue ;; esac
  echo
  echo ">> $step"
  bash "$DOTFILES_DIR/steps/$step" || { echo "step $step failed (rc=$?), continuing"; }
done 3< "$PROFILE_FILE"

echo
echo "Done (profile: $PROFILE)."
[ "$OS_TYPE" = "Linux" ] && echo "Restart terminal to use zsh." || echo "Restart terminal."
