#!/usr/bin/env bash
# steps/02-shell.sh: the fzf installer must never edit ~/.zshrc behind the
# transaction journal's back. --no-update-rc (with explicit key-bindings and
# completion) replaces --all, whose rc edit rollback could not undo; the repo
# zshrc already sources ~/.fzf.zsh.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/home"

# brew stub: --prefix prints a fake prefix so the Darwin path is exercised.
cat > "$TMP/bin/brew" <<SH
#!/bin/sh
[ "\$1" = --prefix ] && { echo "$TMP/brewprefix"; exit 0; }
exit 0
SH
chmod +x "$TMP/bin/brew"
mkdir -p "$TMP/brewprefix/opt/fzf"
printf '#!/bin/sh\nexit 0\n' > "$TMP/brewprefix/opt/fzf/install"
chmod +x "$TMP/brewprefix/opt/fzf/install"

output="$(
  HOME="$TMP/home" \
  PATH="$TMP/bin:/usr/bin:/bin" \
  DOTFILES_DIR="$ROOT" \
  OS_TYPE=Darwin \
  DRY_RUN=1 \
    bash "$ROOT/steps/02-shell.sh"
)"

grep -Fq -- '--no-update-rc' <<<"$output" || {
  echo "fzf install is missing --no-update-rc:" >&2
  printf '%s\n' "$output" >&2
  exit 1
}
grep -Fq -- '--key-bindings --completion' <<<"$output"
grep -Fq -- '--no-nushell' <<<"$output"
if grep -Fq -- '--all' <<<"$output"; then
  echo "fzf install still uses --all (it appends to ~/.zshrc outside the journal)" >&2
  exit 1
fi

# The repo zshrc must keep sourcing ~/.fzf.zsh, or dropping the rc edit would
# silently disable fzf keybindings.
grep -qF '.fzf.zsh' "$ROOT/config/zsh/zshrc"

# Static guard for the Linux paths of the same step (they run the distro's
# fzf install.sh with identical flags).
if grep -nE '(install|FZF_INSTALL)"? --all' "$ROOT/steps/02-shell.sh"; then
  echo "steps/02-shell.sh still passes --all to an fzf installer" >&2
  exit 1
fi

echo "Shell step fzf flag tests passed."
