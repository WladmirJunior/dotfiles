#!/usr/bin/env bash
# Declarative capability-to-package catalog reader.

PACKAGE_CATALOG_FILE="${PACKAGE_CATALOG_FILE:-${DOTFILES_DIR:-.}/config/packages.tsv}"

_package_catalog_column() {
  case "$1" in
    brew) printf '3\n' ;;
    apt) printf '4\n' ;;
    pacman) printf '5\n' ;;
    dnf) printf '6\n' ;;
    *) return 2 ;;
  esac
}

# package_catalog SCOPE MANAGER
# Print package identifiers in catalog order, separated by spaces.
package_catalog() {
  local scope="$1" manager="$2" column
  column="$(_package_catalog_column "$manager")" || return $?
  [ -r "$PACKAGE_CATALOG_FILE" ] || {
    echo "Package catalog unavailable: $PACKAGE_CATALOG_FILE" >&2
    return 1
  }
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
  awk -F '\t' -v wanted="$capability" -v wanted_scope="$scope" -v package_column="$column" '
    NR > 1 && $2 == wanted && (wanted_scope == "" || $1 == wanted_scope) && $package_column != "-" {
      value = $package_column
      gsub(/,/, " ", value)
      print value
    }
  ' "$PACKAGE_CATALOG_FILE" | paste -sd ' ' -
}

export PACKAGE_CATALOG_FILE
export -f _package_catalog_column package_catalog package_for 2>/dev/null || true
