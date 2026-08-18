#!/usr/bin/env bash
# Homebrew adapter shared by package and application steps.

brew_formula_name() {
  printf '%s\n' "${1##*/}"
}

brew_formula_installed() {
  brew list --formula "$(brew_formula_name "$1")" >/dev/null 2>&1
}

brew_cask_installed() {
  brew list --cask "$1" >/dev/null 2>&1
}

# brew_plan_formulae FORMULA...
# Results are exposed through BREW_MISSING and BREW_UPGRADE as space-separated
# package identifiers. Formula identifiers cannot contain spaces.
brew_plan_formulae() {
  local outdated pinned pkg name
  BREW_MISSING=""
  BREW_UPGRADE=""
  outdated="$(brew outdated --formula --quiet 2>/dev/null || true)"
  pinned="$(brew list --pinned 2>/dev/null || true)"
  for pkg in "$@"; do
    name="$(brew_formula_name "$pkg")"
    if ! brew_formula_installed "$pkg"; then
      BREW_MISSING="${BREW_MISSING:+$BREW_MISSING }$pkg"
    elif grep -qxF "$name" <<<"$outdated" && ! grep -qxF "$name" <<<"$pinned"; then
      BREW_UPGRADE="${BREW_UPGRADE:+$BREW_UPGRADE }$pkg"
    fi
  done
}

# brew_maintain_formulae LOG LABEL FORMULA...
brew_maintain_formulae() {
  local log="$1" label="$2"
  shift 2
  if [ "${DRY_RUN:-0}" = 1 ]; then
    run brew install "$@"
    return $?
  fi

  brew_plan_formulae "$@"
  if [ -n "$BREW_MISSING" ]; then
    # shellcheck disable=SC2086 # identifiers are intentionally word-split.
    command -v tx_brew_install >/dev/null 2>&1 && tx_brew_install $BREW_MISSING
    # shellcheck disable=SC2086
    run_logged "Installing $label" "$log" brew install $BREW_MISSING || return $?
  fi
  if [ -n "$BREW_UPGRADE" ]; then
    # shellcheck disable=SC2086
    run_logged "Updating $label" "$log" brew upgrade $BREW_UPGRADE || return $?
  fi
}

# brew_install_formulae LOG LABEL FORMULA...
brew_install_formulae() {
  local log="$1" label="$2" pkg missing=""
  shift 2
  for pkg in "$@"; do
    brew_formula_installed "$pkg" || missing="${missing:+$missing }$pkg"
  done
  [ -n "$missing" ] || return 0
  if [ "${DRY_RUN:-0}" != 1 ] && command -v tx_brew_install >/dev/null 2>&1; then
    # shellcheck disable=SC2086
    tx_brew_install $missing
  fi
  # shellcheck disable=SC2086
  run_logged "Installing $label" "$log" brew install $missing
}

# brew_install_casks LOG LABEL CASK...
brew_install_casks() {
  local log="$1" label="$2" cask missing=""
  shift 2
  for cask in "$@"; do
    brew_cask_installed "$cask" || missing="${missing:+$missing }$cask"
  done
  [ -n "$missing" ] || return 0
  if [ "${DRY_RUN:-0}" != 1 ] && command -v tx_brew_cask >/dev/null 2>&1; then
    # shellcheck disable=SC2086
    tx_brew_cask $missing
  fi
  # shellcheck disable=SC2086
  run_logged "Installing $label" "$log" brew install --cask $missing
}

brew_remove_formulae() {
  local log="$1" label="$2" pkg installed=""
  shift 2
  for pkg in "$@"; do
    brew_formula_installed "$pkg" && installed="${installed:+$installed }$pkg"
  done
  [ -n "$installed" ] || return 0
  # shellcheck disable=SC2086
  run_logged "Removing $label" "$log" brew uninstall $installed
}

brew_remove_casks() {
  local log="$1" label="$2" cask installed=""
  shift 2
  for cask in "$@"; do
    brew_cask_installed "$cask" && installed="${installed:+$installed }$cask"
  done
  [ -n "$installed" ] || return 0
  # shellcheck disable=SC2086
  run_logged "Removing $label" "$log" brew uninstall --cask $installed
}

export -f brew_formula_name brew_formula_installed brew_cask_installed \
  brew_plan_formulae brew_maintain_formulae brew_install_formulae \
  brew_install_casks brew_remove_formulae brew_remove_casks 2>/dev/null || true
