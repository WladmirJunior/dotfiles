#!/bin/bash
# provision-vm.sh — clone a tart VM and provision it with the dotfiles, hands-off.
#
# "Create a VM + provision it" in one command, using `tart exec` (the macOS-VM
# equivalent of cloud-init: the cirruslabs base images ship a Guest Agent, so we
# run commands inside the guest from the host without SSH/keyboard/EDR).
#
# Usage:
#   scripts/provision-vm.sh [--from BASE] [--name NAME] [--profile P] [--dry-run] [--keep]
#
#   --from BASE     base image/VM to clone (default: ghcr.io/cirruslabs/macos-tahoe-base:latest)
#   --name NAME     name for the new VM (default: provision-test)
#   --profile P     dotfiles profile to install: desktop|minimal|pentest (default: minimal)
#   --dry-run       print what would happen, run nothing
#   --keep          leave the VM running at the end (default: stop it)
#
# Requires: tart (brew install cirruslabs/cli/tart). macOS host only.
set -uo pipefail

FROM="ghcr.io/cirruslabs/macos-tahoe-base:latest"
NAME="provision-test"
PROFILE="minimal"
DRY_RUN=0
KEEP=0
DOTFILES_URL="https://raw.githubusercontent.com/WladmirJunior/dotfiles/main/install.sh"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --from)     FROM="$2"; shift 2 ;;
    --name)     NAME="$2"; shift 2 ;;
    --profile)  PROFILE="$2"; shift 2 ;;
    --dry-run)  DRY_RUN=1; shift ;;
    --keep)     KEEP=1; shift ;;
    -h|--help)  sed -n '2,20p' "$0"; exit 0 ;;
    *)          echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

command -v tart >/dev/null 2>&1 || { echo "tart not found (brew install cirruslabs/cli/tart)"; exit 1; }

run() { if [ "$DRY_RUN" = 1 ]; then echo "[dry-run] $*"; else "$@"; fi; }

echo "==> Provisioning VM '$NAME' from '$FROM' (profile: $PROFILE)"

# 1. Clone the base into a fresh VM (idempotent: delete an old one first, to
#    quarantine not /dev/null — but tart has no trash, so we just delete the
#    throwaway VM; the base image is untouched).
if tart list 2>/dev/null | grep -q "[[:space:]]$NAME[[:space:]]"; then
  echo "==> '$NAME' exists; deleting the throwaway clone to start clean"
  run tart delete "$NAME"
fi
run tart clone "$FROM" "$NAME"

# 2. Boot it detached so the script keeps control. --no-graphics keeps it headless.
echo "==> Booting '$NAME' (detached)"
if [ "$DRY_RUN" = 1 ]; then
  echo "[dry-run] tart run --no-graphics $NAME &  (background)"
else
  tart run --no-graphics "$NAME" >/tmp/tart-$NAME.log 2>&1 &
  TART_PID=$!
fi

# 3. Wait for the Guest Agent to answer `tart exec` (up to ~120s).
echo "==> Waiting for guest agent..."
if [ "$DRY_RUN" = 1 ]; then
  echo "[dry-run] poll: tart exec $NAME whoami  until it responds"
else
  ready=0
  for _ in $(seq 1 60); do
    if tart exec "$NAME" whoami >/dev/null 2>&1; then ready=1; break; fi
    sleep 2
  done
  [ "$ready" = 1 ] || { echo "guest agent never came up; see /tmp/tart-$NAME.log"; exit 1; }
  echo "==> Guest agent ready (user: $(tart exec "$NAME" whoami 2>/dev/null))"
fi

# 4. Run the dotfiles installer inside the guest. We pipe the public installer in,
#    so the VM provisions exactly like a real machine. The profile is passed as an
#    arg; the auth phase skips gracefully without a tty.
echo "==> Running dotfiles install ($PROFILE) inside the guest..."
if [ "$DRY_RUN" = 1 ]; then
  echo "[dry-run] tart exec $NAME bash -lc 'curl -fsSL $DOTFILES_URL | bash -s -- $PROFILE'"
else
  tart exec "$NAME" bash -lc "curl -fsSL '$DOTFILES_URL' | bash -s -- '$PROFILE'" \
    || echo "WARN: install returned non-zero (see output above)"
fi

# 5. Verify with the installer's own --check inside the guest.
echo "==> Verifying inside the guest (install.sh --check)..."
if [ "$DRY_RUN" = 1 ]; then
  echo "[dry-run] tart exec $NAME bash -lc '~/.dotfiles/install.sh --check'"
else
  tart exec "$NAME" bash -lc '~/.dotfiles/install.sh --check' || echo "WARN: verification reported issues"
fi

# 6. Stop the VM unless --keep.
if [ "$KEEP" = 1 ]; then
  echo "==> Done. VM '$NAME' left running (--keep). Stop with: tart stop $NAME"
else
  echo "==> Stopping '$NAME'"
  run tart stop "$NAME" 2>/dev/null || true
fi
echo "==> provision-vm finished."
