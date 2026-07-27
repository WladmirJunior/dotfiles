#!/usr/bin/env bash
set -uo pipefail
SUDO=""; [ "$(id -u)" -eq 0 ] || SUDO=sudo
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/install"
LOG="$STATE_DIR/1password-debian.log"
mkdir -p "$STATE_DIR"; : >"$LOG"
fail() { echo "  1Password installation failed; details: $LOG" >&2; tail -n 30 "$LOG" >&2; exit 1; }
run() { "$@" >>"$LOG" 2>&1 || fail; }
if dpkg-query -W -f='${Status}' 1password 2>/dev/null | grep -q 'ok installed' \
   && dpkg-query -W -f='${Status}' 1password-cli 2>/dev/null | grep -q 'ok installed'; then
  echo "  1Password: app and CLI are current"; exit 0
fi
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
run curl -fsSL https://downloads.1password.com/linux/keys/1password.asc -o "$tmp/key.asc"
run gpg --dearmor --yes --output "$tmp/keyring.gpg" "$tmp/key.asc"
run $SUDO install -Dm644 "$tmp/keyring.gpg" /usr/share/keyrings/1password-archive-keyring.gpg
printf '%s\n' 'deb [arch=amd64 signed-by=/usr/share/keyrings/1password-archive-keyring.gpg] https://downloads.1password.com/linux/debian/amd64 stable main' >"$tmp/1password.list"
run $SUDO install -Dm644 "$tmp/1password.list" /etc/apt/sources.list.d/1password.list
run $SUDO apt-get update -qq
run $SUDO env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq 1password 1password-cli
echo "  1Password: app and CLI are current"
