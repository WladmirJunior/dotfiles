#!/bin/bash
# provision-kali-vm.sh — boot a fresh Kali Linux ARM tart VM, cloud-init it,
# install the dotfiles `pentest` profile, and report PASS/FAIL.
#
# WHY A SIBLING SCRIPT (not a --kali flag on provision-vm.sh):
#   provision-vm.sh provisions *macOS* guests purely through the tart Guest Agent
#   (`tart exec`) — no cloud-init, no seed disk. The Kali path is a different
#   provisioning model: a Linux guest driven by a cloud-init NoCloud seed (cidata
#   ISO) on first boot. Bolting that onto provision-vm.sh would interleave two
#   unrelated flows (ISO build, seed attach, cloud-init wait) behind one entry
#   point. Keeping them separate keeps each readable. They share the same ideas
#   (auto-bridged net on the work Mac, local-image cache, `tart exec` to drive
#   the install) but not the same code path.
#
# APPROACH (Debian ARM base + Kali repo, seeded by cloud-init):
#   tart has no real Kali ARM OCI image (checked ghcr.io/cirruslabs: debian
#   exists, kali does not). So we clone the cirruslabs Debian ARM base
#   (~0.6 GB, ships cloud-init + tart-guest-agent) and the cloud-init seed
#   (config/cloud-init/user-data.kali) converts it to Kali on first boot:
#   adds the Kali apt repo + signing key and installs `kali-linux-headless`.
#   Then THIS script drives the dotfiles `pentest` install via `tart exec`
#   (Guest Agent — no SSH, so no EDR alert on the corporate Mac; see
#   memory feedback_never_sshpass_edr) and parses `install.sh --check`.
#
# Usage:
#   scripts/provision-kali-vm.sh [--name NAME] [--from BASE] [--ssh-key FILE]
#                                [--net MODE] [--dry-run] [--keep]
#
#   --name NAME     name for the new VM (default: kali-test)
#   --from BASE     Linux base image/VM to clone
#                   (default: ghcr.io/cirruslabs/debian:latest)
#   --ssh-key FILE  optional public key to inject into the seed. Omit it: the
#                   install is driven via the Guest Agent, so no key is needed.
#                   NEVER pass a private key; NEVER use sshpass (EDR alert).
#   --net MODE      networking: shared | bridged=IFACE | softnet | none.
#                   Auto-detected: on the corporate Mac (Zscaler always-on)
#                   defaults to bridged=en0, because shared NAT silently has no
#                   route out under Zscaler (memory reference_tart_zscaler_bridged).
#   --dry-run       print what would happen, run nothing
#   --keep          leave the VM running at the end (default: stop it)
#
# Requires: tart, hdiutil (built into macOS). Apple Silicon host only.
set -uo pipefail

NAME="kali-test"
FROM="ghcr.io/cirruslabs/debian:latest"
SSH_KEY_FILE=""
NET=""
DRY_RUN=0
KEEP=0
DOTFILES_URL="https://raw.githubusercontent.com/WladmirJunior/dotfiles/main/install.sh"
SEED_SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/config/cloud-init/user-data.kali"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --name)     NAME="$2"; shift 2 ;;
    --from)     FROM="$2"; shift 2 ;;
    --ssh-key)  SSH_KEY_FILE="$2"; shift 2 ;;
    --net)      NET="$2"; shift 2 ;;
    --dry-run)  DRY_RUN=1; shift ;;
    --keep)     KEEP=1; shift ;;
    -h|--help)  sed -n '2,49p' "$0"; exit 0 ;;
    *)          echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

command -v tart    >/dev/null 2>&1 || { echo "tart not found (brew install cirruslabs/cli/tart)"; exit 1; }
command -v hdiutil >/dev/null 2>&1 || { echo "hdiutil not found (macOS only)"; exit 1; }
[ -f "$SEED_SRC" ] || { echo "seed template not found: $SEED_SRC"; exit 1; }

run() { if [ "$DRY_RUN" = 1 ]; then echo "[dry-run] $*"; else "$@"; fi; }

# --- Networking: default shared NAT; export IS_WORK_MAC=1 for bridged on en0. --
if [ -z "$NET" ]; then
  if [ "${IS_WORK_MAC:-0}" = 1 ]; then
    NET="bridged=en0"
  else
    NET="shared"
  fi
fi
case "$NET" in
  shared)    TART_NET_FLAGS=() ;;
  bridged=*) TART_NET_FLAGS=(--net-bridged="${NET#bridged=}") ;;
  softnet)   TART_NET_FLAGS=(--net-softnet) ;;
  none)      TART_NET_FLAGS=() ;;
  *)         echo "Unknown --net mode: $NET (use: shared, bridged=IFACE, softnet, none)" >&2; exit 2 ;;
esac
echo "==> Networking: $NET"

# --- Prefer a locally-cached base over re-pulling from the registry. -----------
if [[ "$FROM" == *":"* ]] || [[ "$FROM" == *"/"* ]]; then
  CAND="${FROM##*/}"; CAND="${CAND%:*}"   # ghcr.io/cirruslabs/debian:latest -> debian
  if tart list 2>/dev/null | awk '$1=="local"{print $2}' | grep -qx "$CAND"; then
    echo "==> using local image '$CAND' instead of '$FROM' (skips re-pull)"
    FROM="$CAND"
  fi
fi

# --- Build the cidata seed image from user-data.kali. --------------------------
# A NoCloud seed is a filesystem labelled `cidata` holding `user-data` +
# `meta-data`. cloud-init reads ISO9660 OR vfat. We build a small FAT image,
# NOT an ISO: `hdiutil makehybrid` (the documented ISO path) is blocked by the
# corporate Mac's MDM/TCC ("Operation not permitted"), but `hdiutil create
# -fs MS-DOS` + auto-mount copy is allowed and needs no sudo/kext prompt. The
# `-layout NONE` image is a raw disk tart attaches read-only.
# We template the SSH key (only when --ssh-key) and stamp a unique instance-id
# so cloud-init treats every boot as first boot.
SEED_DIR="$(mktemp -d "$HOME/.cache/kali-seed.XXXXXX")"
SEED_IMG="$SEED_DIR/cidata.img.dmg"   # hdiutil create appends .dmg
SEED_MNT=""
cleanup_seed() {
  [ -n "$SEED_MNT" ] && hdiutil detach "$SEED_MNT" >/dev/null 2>&1
  rm -rf "$SEED_DIR" 2>/dev/null || true
}
trap cleanup_seed EXIT

if [ -n "$SSH_KEY_FILE" ]; then
  [ -f "$SSH_KEY_FILE" ] || { echo "ssh key file not found: $SSH_KEY_FILE"; exit 1; }
  case "$SSH_KEY_FILE" in
    *.pub) : ;;
    *) echo "refusing non-.pub key '$SSH_KEY_FILE' — pass a PUBLIC key only" >&2; exit 1 ;;
  esac
  SSH_KEY_VALUE="$(tr -d '\n' < "$SSH_KEY_FILE")"
else
  SSH_KEY_VALUE=""
fi

echo "==> Building cidata seed (FAT image) from $(basename "$SEED_SRC")"
if [ "$DRY_RUN" = 1 ]; then
  echo "[dry-run] template user-data (ssh key: ${SSH_KEY_FILE:-none}) + meta-data -> FAT img $SEED_IMG"
else
  USERDATA="$SEED_DIR/user-data"
  if [ -n "$SSH_KEY_VALUE" ]; then
    # Keep the SSH_KEY_BLOCK lines, substitute the key in.
    sed "s#{{SSH_AUTHORIZED_KEY}}#${SSH_KEY_VALUE}#" "$SEED_SRC" > "$USERDATA"
  else
    # No key: strip the whole SSH_KEY_BLOCK so cloud-init sees no ssh key field
    # at all (rather than a dangling null), then drop the marker comments.
    grep -v '# SSH_KEY_BLOCK' "$SEED_SRC" > "$USERDATA"
  fi
  printf 'instance-id: kali-%s\nlocal-hostname: kali-devvm\n' "$(date +%s)" > "$SEED_DIR/meta-data"

  # 4 MB FAT image labelled CIDATA, raw layout. -ov overwrites any stale image.
  hdiutil create -size 4m -fs MS-DOS -volname CIDATA -layout NONE -ov "$SEED_DIR/cidata.img" >/dev/null 2>&1 \
    || { echo "failed to create FAT seed image (hdiutil create)"; exit 1; }
  ATTACH_OUT="$(hdiutil attach "$SEED_IMG" 2>&1)" \
    || { echo "failed to attach seed image"; echo "$ATTACH_OUT"; exit 1; }
  SEED_MNT="$(echo "$ATTACH_OUT" | grep -o '/Volumes/[^ ]*' | head -1)"
  SEED_DEV="$(echo "$ATTACH_OUT" | awk 'NR==1{print $1}')"
  [ -n "$SEED_MNT" ] || { echo "seed image did not auto-mount"; exit 1; }
  cp "$USERDATA" "$SEED_MNT/user-data"
  cp "$SEED_DIR/meta-data" "$SEED_MNT/meta-data"
  sync
  hdiutil detach "$SEED_DEV" >/dev/null 2>&1
  SEED_MNT=""   # detached; don't double-detach in cleanup
fi

echo "==> Provisioning Kali VM '$NAME' from '$FROM'"

# --- Clone a fresh throwaway VM (delete a stale one first; base is untouched). -
if tart list 2>/dev/null | grep -q "[[:space:]]${NAME}[[:space:]]"; then
  echo "==> '$NAME' exists; deleting the throwaway clone to start clean"
  run tart delete "$NAME"
fi
# tart pull can leave a partial image if interrupted; clone pulls on demand. If
# the clone fails, delete any half-made VM so the next run starts clean.
if ! run tart clone "$FROM" "$NAME"; then
  echo "clone failed; cleaning up partial VM '$NAME'"
  tart delete "$NAME" 2>/dev/null || true
  exit 1
fi

# --- Boot detached, headless, with the seed attached read-only. ----------------
echo "==> Booting '$NAME' (detached, cidata seed attached read-only)"
if [ "$DRY_RUN" = 1 ]; then
  echo "[dry-run] tart run --no-graphics ${TART_NET_FLAGS[*]} --disk=$SEED_IMG:ro $NAME &"
else
  tart run --no-graphics "${TART_NET_FLAGS[@]}" --disk="$SEED_IMG:ro" "$NAME" \
    >"/tmp/tart-$NAME.log" 2>&1 &
fi

# --- Wait for the Guest Agent (debian base ships tart-guest-agent). -------------
echo "==> Waiting for guest agent..."
if [ "$DRY_RUN" = 1 ]; then
  echo "[dry-run] poll: tart exec $NAME true  until it responds"
else
  ready=0
  for _ in $(seq 1 90); do
    if tart exec "$NAME" true >/dev/null 2>&1; then ready=1; break; fi
    sleep 2
  done
  [ "$ready" = 1 ] || { echo "guest agent never came up; see /tmp/tart-$NAME.log"; exit 1; }
  echo "==> Guest agent ready (user: $(tart exec "$NAME" whoami 2>/dev/null))"
fi

# --- Wait for cloud-init (Kali repo + kali-linux-headless) to finish. ----------
# `cloud-init status --wait` blocks until the seed's runcmd completes. The
# metapackage install is heavy, so give it a generous ceiling.
echo "==> Waiting for cloud-init (Kali bootstrap)... this is the slow part"
if [ "$DRY_RUN" = 1 ]; then
  echo "[dry-run] tart exec $NAME cloud-init status --wait"
else
  # `cloud-init status --wait` exits 0 done / 2 done-with-recoverable-errors / 1 error.
  tart exec "$NAME" sudo cloud-init status --wait
  ci_rc=$?
  ci_state="$(tart exec "$NAME" sh -c 'cat /var/lib/cloud/kali-seed-done 2>/dev/null && echo MARKER-PRESENT || echo MARKER-MISSING' 2>/dev/null | tail -1)"
  echo "==> cloud-init rc=$ci_rc, seed marker: $ci_state"
  if [ "$ci_state" != "MARKER-PRESENT" ]; then
    echo "WARN: Kali seed did not reach its done marker; install may be partial."
    echo "      Last cloud-init log lines:"
    tart exec "$NAME" sh -c 'sudo tail -n 20 /var/log/cloud-init-output.log 2>/dev/null' || true
  fi
  # Confirm we actually have Kali tooling (sanity that the repo path worked).
  if tart exec "$NAME" sh -c 'command -v nmap >/dev/null 2>&1'; then
    echo "==> Kali tooling present (nmap on PATH)"
  else
    echo "WARN: nmap not found — Kali metapackage may not have installed."
  fi
fi

# --- Drive the dotfiles pentest install via the Guest Agent. -------------------
# Exact deliverable command: curl the public installer, pipe to bash, pentest.
echo "==> Running dotfiles install (pentest) inside the guest..."
if [ "$DRY_RUN" = 1 ]; then
  echo "[dry-run] tart exec $NAME bash -lc 'curl -fsSL $DOTFILES_URL | bash -s -- pentest'"
else
  tart exec "$NAME" bash -lc "curl -fsSL '$DOTFILES_URL' | bash -s -- pentest" \
    || echo "WARN: install returned non-zero (see output above)"
fi

# --- Verify with the installer's own --check; its exit code is PASS/FAIL. ------
# --check returns the number of failed checks (0 = all passed).
echo "==> Verifying inside the guest (install.sh --check)..."
RESULT="UNKNOWN"
if [ "$DRY_RUN" = 1 ]; then
  echo "[dry-run] tart exec $NAME bash -lc 'bash ~/.dotfiles/install.sh --check'"
  RESULT="DRY-RUN"
else
  if tart exec "$NAME" bash -lc 'bash ~/.dotfiles/install.sh --check'; then
    RESULT="PASS"
  else
    RESULT="FAIL"
  fi
fi

# --- Stop the VM unless --keep. ------------------------------------------------
if [ "$KEEP" = 1 ]; then
  echo "==> VM '$NAME' left running (--keep). Stop with: tart stop $NAME"
else
  echo "==> Stopping '$NAME'"
  run tart stop "$NAME" 2>/dev/null || true
fi

echo "==> provision-kali-vm finished. Result: $RESULT"
# Exit non-zero on FAIL so callers/CI can branch on it.
[ "$RESULT" = "FAIL" ] && exit 1
exit 0
