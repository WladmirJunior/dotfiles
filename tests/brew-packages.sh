#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/lib/packages/brew.sh"

brew() {
  case "$1:$2" in
    outdated:--formula)
      printf '%s\n' gh node fzf
      ;;
    list:--pinned)
      printf '%s\n' node
      ;;
    list:--formula)
      return 0
      ;;
    *)
      echo "unexpected brew invocation: $*" >&2
      return 1
      ;;
  esac
}

brew_plan_formulae gh node fzf

[ -z "$BREW_MISSING" ] || {
  echo "unexpected missing formulae: $BREW_MISSING" >&2
  exit 1
}
[ "$BREW_UPGRADE" = 'gh fzf' ] || {
  echo "pinned formula entered upgrade plan: $BREW_UPGRADE" >&2
  exit 1
}

echo "Homebrew package planning tests passed."
