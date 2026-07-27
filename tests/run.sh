#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

bash -n \
  "$ROOT/install.sh" \
  "$ROOT/uninstall.sh" \
  "$ROOT"/lib/*.sh \
  "$ROOT"/steps/*.sh \
  "$ROOT"/scripts/*.sh \
  "$ROOT"/tests/*.sh

for test_file in "$ROOT"/tests/*.sh; do
  [ "$(basename "$test_file")" = run.sh ] && continue
  bash "$test_file"
done
