#!/usr/bin/env bash
# Generic maintenance selector.
#
# maintenance_select DETECT_CALLBACK INSTALL_VAR REMOVE_VAR HEADER ID|LABEL...
#
# The callback receives an ID and returns success when it is installed. Every
# component is shown in one list; installed components start selected. Selecting
# a missing component adds its ID to INSTALL_VAR. Deselecting an installed
# component adds its ID to REMOVE_VAR. Both outputs are comma-separated.

_selection_csv_add() {
  local variable_name="$1" value="$2" current
  eval "current=\${$variable_name:-}"
  if [ -n "$current" ]; then
    printf -v "$variable_name" '%s,%s' "$current" "$value"
  else
    printf -v "$variable_name" '%s' "$value"
  fi
}

_selection_csv_has() {
  printf '%s\n' "${1:-}" | tr ',' '\n' | grep -qxF -- "$2"
}

maintenance_select() {
  local detect_callback="$1" install_var="$2" remove_var="$3" header="$4"
  shift 4

  case "$install_var" in ''|[0-9]*|*[!A-Za-z0-9_]*) return 2 ;; esac
  case "$remove_var" in ''|[0-9]*|*[!A-Za-z0-9_]*) return 2 ;; esac

  local entries=("$@") labels=() installed_ids="" selected_labels=""
  local entry id label picked
  printf -v "$install_var" '%s' ''
  printf -v "$remove_var" '%s' ''

  for entry in "${entries[@]}"; do
    id="${entry%%|*}"
    label="${entry#*|}"
    [ -n "$id" ] && [ "$label" != "$entry" ] || return 2
    case "$id:$label" in *','*) return 2 ;; esac
    labels+=("$label")
    if "$detect_callback" "$id"; then
      _selection_csv_add installed_ids "$id"
      _selection_csv_add selected_labels "$label"
    fi
  done

  # A missing rich UI or a non-interactive session means "leave unchanged",
  # never "remove every installed component".
  command -v pick >/dev/null 2>&1 || return 0
  if command -v have_gum >/dev/null 2>&1 && ! have_gum; then return 0; fi
  if [ "${SELECTION_FORCE_PROMPT:-0}" != 1 ] && [ ! -t 0 ] && [ ! -t 1 ]; then return 0; fi

  PICK_SELECTED="$selected_labels"
  picked="$(pick "$header" "${labels[@]}")" || return $?
  [ "$picked" = none ] && picked=""

  for entry in "${entries[@]}"; do
    id="${entry%%|*}"
    label="${entry#*|}"
    if _selection_csv_has "$picked" "$label"; then
      _selection_csv_has "$installed_ids" "$id" || _selection_csv_add "$install_var" "$id"
    else
      _selection_csv_has "$installed_ids" "$id" && _selection_csv_add "$remove_var" "$id"
    fi
  done
}

export -f _selection_csv_add _selection_csv_has maintenance_select 2>/dev/null || true
