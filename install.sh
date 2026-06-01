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
PROFILE="${1:-desktop}"

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

PROFILE_FILE="$DOTFILES_DIR/profiles/$PROFILE"
if [ ! -f "$PROFILE_FILE" ]; then
  echo "Unknown profile '$PROFILE'. Available: $(ls "$DOTFILES_DIR/profiles" | tr '\n' ' ')"
  exit 1
fi

source "$DOTFILES_DIR/lib/detect.sh"
echo "dotfiles | profile: $PROFILE | OS: $OS_TYPE $ARCH | VM: $IS_VM | headless: $HEADLESS | tty: $INTERACTIVE"

while IFS= read -r step; do
  [ -z "$step" ] && continue
  case "$step" in \#*) continue ;; esac
  echo
  echo ">> $step"
  bash "$DOTFILES_DIR/steps/$step" || { echo "step $step failed (rc=$?), continuing"; }
done < "$PROFILE_FILE"

echo
echo "Done (profile: $PROFILE)."
[ "$OS_TYPE" = "Linux" ] && echo "Restart terminal to use zsh." || echo "Restart terminal."
