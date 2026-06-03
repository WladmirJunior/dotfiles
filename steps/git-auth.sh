#!/bin/bash
# Authenticate with GitHub so the private overlay repos (***REMOVED***,
# ***REMOVED***, etc.) can be cloned over HTTPS, and set gh up as git's
# credential helper. Uses the gh device flow — no token is written to a file.
# Idempotent: a no-op if already authenticated. Skipped when non-interactive
# (gh device flow needs a browser/code entry).
set -uo pipefail
[ -z "${OS_TYPE:-}" ] && source "${DOTFILES_DIR:-.}/lib/detect.sh"

echo "[git-auth] GitHub authentication..."

if ! command -v gh >/dev/null 2>&1; then
  echo "  gh not installed yet; skipping (run 01-packages first)"; exit 0
fi

# Already logged in?
if gh auth status >/dev/null 2>&1; then
  echo "  already authenticated with GitHub"
else
  if [ "${INTERACTIVE:-no}" != "yes" ]; then
    echo "  non-interactive shell; skipping gh auth login (run 'gh auth login' by hand)"
    exit 0
  fi
  echo "  launching gh device flow (follow the browser prompt)..."
  gh auth login --hostname github.com --git-protocol https --web || {
    echo "  gh auth login failed or was cancelled; private repos won't clone" >&2
    exit 0
  }
fi

# Make gh the git credential helper for HTTPS so clones/pulls of private repos
# just work. Safe to re-run.
gh auth setup-git 2>/dev/null && echo "  gh configured as git credential helper"

echo "[git-auth] done"
