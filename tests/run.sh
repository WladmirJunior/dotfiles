#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Run every check with the same interpreter that runs this file ($BASH), not
# whatever `bash` is first on PATH: on macOS runners that guarantees the
# brew-installed bash is used consistently instead of the 3.2 /bin/bash.
"$BASH" -n \
  "$ROOT/install.sh" \
  "$ROOT/uninstall.sh" \
  "$ROOT"/lib/*.sh \
  "$ROOT"/lib/packages/*.sh \
  "$ROOT"/lib/setup/*.sh \
  "$ROOT"/steps/*.sh \
  "$ROOT"/scripts/*.sh \
  "$ROOT"/tests/*.sh

for test_file in "$ROOT"/tests/*.sh; do
  [ "$(basename "$test_file")" = run.sh ] && continue
  echo "RUN $(basename "$test_file")"
  "$BASH" "$test_file"
done
