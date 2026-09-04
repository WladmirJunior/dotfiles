#!/usr/bin/env bash
# summary_table must never render wider than the terminal, and every line it
# emits must be the same width, whatever the terminal size and however long a
# Details value is. Before the fit pass, a long Details value sized the grid by
# itself: gum drew the horizontal rules at one width and the cells at another,
# so the border came apart in a wide terminal.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

mkdir -p "$WORK/bin"

# Stub tput so cwidth() sees the terminal size the case asks for.
make_tput() {
  cat > "$WORK/bin/tput" <<EOF
#!/bin/sh
[ "\$1" = cols ] && echo $1 && exit 0
exec /usr/bin/tput "\$@"
EOF
  chmod +x "$WORK/bin/tput"
}

long="$(printf 'a%.0s' $(seq 1 400))"
cat > "$WORK/report.txt" <<EOF
private|00-developer-symlink.sh|unchanged|already current
private|01-zsh.sh|changed|symlink:/Users/someone/.config/private/zshrc.private, cp:/Users/someone/.local/bin/audit-ssh-keys, cp:/Users/someone/.local/bin/op-auth-trace, +9 more
private|02-apps.sh|changed|brew-untap:lightpanda-io/browser, brew_cask:brave-browser
private|04-ai-cli-configs.sh|failed|exit 1
runaway-scope-name-that-is-long|another-really-long-component-name.sh|changed|$long
EOF

fails=0
for cols in 40 60 80 90 120 200; do
  make_tput "$cols"
  out="$(PATH="$WORK/bin:$PATH" bash -c "
    cd '$ROOT'
    . lib/ui.sh
    . lib/setup/report.sh
    export DOTFILES_REPORT_FILE='$WORK/report.txt'
    setup_report_print
  " 2>&1)"

  verdict="$(printf '%s\n' "$out" | python3 -c "
import sys, re
widths = set()
for line in sys.stdin:
    line = re.sub(chr(27) + r'\[[0-9;]*m', '', line.rstrip('\n'))
    if line.strip():
        widths.add(len(line))
if not widths:
    print('no output')
elif len(widths) != 1:
    print('ragged: %s' % sorted(widths))
elif max(widths) > $cols:
    print('overflow: %d > $cols' % max(widths))
else:
    print('ok')
")"

  if [ "$verdict" = ok ]; then
    echo "  cols=$cols ok"
  else
    echo "  cols=$cols FAIL: $verdict" >&2
    fails=$((fails + 1))
  fi
done

# The report shortens $HOME to ~ so the useful tail of a path survives the fit.
home_out="$(HOME=/Users/someone bash -c "
  cd '$ROOT'
  . lib/ui.sh
  . lib/setup/report.sh
  setup_report_init t
  setup_report_add private 01-zsh.sh changed 'symlink:/Users/someone/.config/private/zshrc.private'
  cat \"\$DOTFILES_REPORT_FILE\"
")"
case "$home_out" in
  *'symlink:~/.config/private/zshrc.private'*) echo "  home shortening ok" ;;
  *) echo "  home shortening FAIL: $home_out" >&2; fails=$((fails + 1)) ;;
esac

if [ "$fails" -ne 0 ]; then
  echo "summary_table width tests failed ($fails)" >&2
  exit 1
fi
echo "summary_table width tests passed."
