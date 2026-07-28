#!/usr/bin/env bash
# Declarative capability-to-package catalog reader.

PACKAGE_CATALOG_FILE="${PACKAGE_CATALOG_FILE:-${DOTFILES_DIR:-.}/config/packages.tsv}"
_PACKAGE_CATALOG_VALIDATED=""

_package_catalog_column() {
  case "$1" in
    brew) printf '3\n' ;;
    apt) printf '4\n' ;;
    pacman) printf '5\n' ;;
    dnf) printf '6\n' ;;
    *) return 2 ;;
  esac
}

# package_catalog_validate: fail-closed schema check, run once per catalog file
# (re-run when PACKAGE_CATALOG_FILE changes). Every line must have exactly 6
# tab-separated columns; data lines must use a known scope, a non-empty
# capability unique within its scope, and non-empty package cells ("-" means
# "not packaged for this manager"). Any violation reports the offending line
# number and fails, so a malformed catalog aborts the install instead of
# silently degrading to a wrong package set.
package_catalog_validate() {
  [ "${_PACKAGE_CATALOG_VALIDATED:-}" = "$PACKAGE_CATALOG_FILE" ] && return 0
  [ -r "$PACKAGE_CATALOG_FILE" ] || {
    echo "Package catalog unavailable: $PACKAGE_CATALOG_FILE" >&2
    return 1
  }
  local schema_errors
  schema_errors="$(awk -F '\t' '
    NF != 6 {
      printf "line %d: expected 6 tab-separated columns, found %d\n", NR, NF
      next
    }
    NR == 1 {
      # Column positions are hardcoded by _package_catalog_column; a reordered
      # header would silently serve another manager'\''s packages.
      if ($0 != "scope\tcapability\tbrew\tapt\tpacman\tdnf")
        printf "line 1: unexpected header (expected scope/capability/brew/apt/pacman/dnf order)\n"
      next
    }
    $1 != "core" && $1 != "best-effort" && $1 != "nvim-optional" {
      printf "line %d: unknown scope \"%s\" (expected core, best-effort or nvim-optional)\n", NR, $1
      next
    }
    $2 == "" || $2 == "-" {
      printf "line %d: missing capability\n", NR
      next
    }
    {
      for (i = 3; i <= 6; i++) if ($i == "")
        printf "line %d: empty package column %d (use \"-\" for none)\n", NR, i
    }
    seen[$1 SUBSEP $2]++ {
      printf "line %d: duplicate capability \"%s\" in scope \"%s\"\n", NR, $2, $1
    }
  ' "$PACKAGE_CATALOG_FILE")"
  if [ -n "$schema_errors" ]; then
    {
      echo "ERROR: malformed package catalog: $PACKAGE_CATALOG_FILE"
      printf '%s\n' "$schema_errors"
    } >&2
    return 1
  fi
  _PACKAGE_CATALOG_VALIDATED="$PACKAGE_CATALOG_FILE"
}

# package_catalog SCOPE MANAGER
# Print package identifiers in catalog order, separated by spaces.
package_catalog() {
  local scope="$1" manager="$2" column
  column="$(_package_catalog_column "$manager")" || return $?
  package_catalog_validate || return 1
  awk -F '\t' -v wanted_scope="$scope" -v package_column="$column" '
    NR > 1 && $1 == wanted_scope && $package_column != "-" {
      value = $package_column
      gsub(/,/, " ", value)
      print value
    }
  ' "$PACKAGE_CATALOG_FILE" | paste -sd ' ' -
}

# package_for CAPABILITY MANAGER [SCOPE]
package_for() {
  local capability="$1" manager="$2" scope="${3:-}" column
  column="$(_package_catalog_column "$manager")" || return $?
  package_catalog_validate || return 1
  awk -F '\t' -v wanted="$capability" -v wanted_scope="$scope" -v package_column="$column" '
    NR > 1 && $2 == wanted && (wanted_scope == "" || $1 == wanted_scope) && $package_column != "-" {
      value = $package_column
      gsub(/,/, " ", value)
      print value
    }
  ' "$PACKAGE_CATALOG_FILE" | paste -sd ' ' -
}

export PACKAGE_CATALOG_FILE
export -f _package_catalog_column package_catalog_validate package_catalog package_for 2>/dev/null || true

# Validate eagerly at load when the catalog is present, so a malformed file
# fails the sourcing script up front instead of at the first lookup. A missing
# file is still reported lazily by the lookups (some callers source this lib
# before deciding whether they need the catalog at all).
if [ -e "$PACKAGE_CATALOG_FILE" ]; then
  package_catalog_validate || return 1
fi
