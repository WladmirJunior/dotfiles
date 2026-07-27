#!/usr/bin/env bash
set -uo pipefail
SUDO=""; [ "$(id -u)" -eq 0 ] || SUDO=sudo
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/install"
LOG="$STATE_DIR/1password-fedora.log"
mkdir -p "$STATE_DIR"; : >"$LOG"
fail() { echo "  1Password installation failed; details: $LOG" >&2; tail -n 30 "$LOG" >&2; exit 1; }
run() { "$@" >>"$LOG" 2>&1 || fail; }
if rpm -q 1password 1password-cli >/dev/null 2>&1; then
  echo "  1Password: app and CLI are current"; exit 0
fi
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
run curl -fsSL https://downloads.1password.com/linux/keys/1password.asc -o "$tmp/1password.asc"
run $SUDO rpm --import "$tmp/1password.asc"
cat >"$tmp/1password.repo" <<'REPO'
[1password]
name=1Password Stable Channel
baseurl=https://downloads.1password.com/linux/rpm/stable/$basearch
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://downloads.1password.com/linux/keys/1password.asc
REPO
run $SUDO install -Dm644 "$tmp/1password.repo" /etc/yum.repos.d/1password.repo
run $SUDO dnf install -y -q 1password 1password-cli
echo "  1Password: app and CLI are current"
