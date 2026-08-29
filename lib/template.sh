#!/usr/bin/env bash
# Template engine for dotfiles.
#
# REQUIRES BASH (not zsh). The orchestrator install.sh already runs under bash,
# and steps/* are invoked as `bash steps/NN-*.sh`, so this is the standard path.
# If you ever source this from zsh interactively for debugging, prefix the call
# with `bash -c '...'` so BASH_REMATCH and `[[ =~ ]]` behave as expected.
#
# Renders .tmpl files with variable substitution and conditional blocks.
# Avoids duplicating files across machines just for a few environment-specific
# lines.
#
# Syntax in .tmpl files:
#   ${VAR_NAME}                  — variable expansion (envsubst-style)
#   ${VAR_NAME:-default}         — variable with default
#   ${OP:op://Private/foo/bar}   — read secret from 1Password CLI
#   # @if VAR_NAME               — start conditional block (truthy: 1/true/yes)
#   # @if VAR_NAME == "value"    — start conditional block (equality)
#   # @endif                     — end conditional block
#   # @include path/to/file.tmpl — inline another template (recursive)
#
# Variables come from the environment. Set them in install.sh or steps before
# calling render(). Standard vars set by detect.sh: OS_TYPE, ARCH, IS_VM,
# HEADLESS, INTERACTIVE. Template-specific vars are set by detect_template().
#
# Usage:
#   source "$DOTFILES_DIR/lib/template.sh"
#   detect_template
#   render config/gitconfig.tmpl "$HOME/.gitconfig"
#   render_str 'hello ${USER}' returns expanded string on stdout

set -uo pipefail

# detect_template: export template-friendly vars beyond what detect.sh provides.
# Call after sourcing detect.sh. Idempotent.
detect_template() {
  # IS_WORK_MAC: 1 if this is a managed/corporate Mac. Set it explicitly via the
  # environment when needed; defaults to 0. Personal overlays can export it.
  IS_WORK_MAC="${IS_WORK_MAC:-0}"

  HOST_SHORT="$(hostname -s 2>/dev/null || echo unknown)"

  # Git identity defaults. Override via env before calling render().
  GIT_NAME="${GIT_NAME:-Wladmir Junior}"
  GIT_EMAIL="${GIT_EMAIL:-wladmirjunior@users.noreply.github.com}"

  export IS_WORK_MAC HOST_SHORT GIT_NAME GIT_EMAIL
}

# _op_read: read 1Password secret if op CLI is available and signed in.
# Returns the secret value on stdout, or an empty string if unavailable.
# Cached per ref within a single render() call.
_op_read() {
  local ref="$1"
  if ! command -v op >/dev/null 2>&1; then
    echo ""
    return 0
  fi
  op read "$ref" 2>/dev/null || echo ""
}

# _eval_condition: evaluate "VAR_NAME" or "VAR_NAME == value" or "VAR_NAME != value".
# Returns 0 (truthy) when block should be kept, 1 when it should be skipped.
_eval_condition() {
  local cond="$1"
  cond="${cond## }"; cond="${cond%% }"   # trim spaces

  # Equality form: VAR == "value" or VAR != "value"
  if [[ "$cond" =~ ^([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*(==|!=)[[:space:]]*\"?([^\"]*)\"?$ ]]; then
    local var="${BASH_REMATCH[1]}"
    local op="${BASH_REMATCH[2]}"
    local expected="${BASH_REMATCH[3]}"
    local actual="${!var:-}"
    if [ "$op" = "==" ]; then
      [ "$actual" = "$expected" ]
      return $?
    else
      [ "$actual" != "$expected" ]
      return $?
    fi
  fi

  # Truthy form: VAR is set to 1/true/yes
  local var="$cond"
  local val="${!var:-}"
  case "$val" in
    1|true|TRUE|yes|YES|on|ON) return 0 ;;
    *) return 1 ;;
  esac
}

# render: process a .tmpl file and write the result to a destination path.
# Backs up existing dst as dst.bak if content would change. Honors DRY_RUN.
render() {
  local src="$1" dst="$2"
  if [ ! -f "$src" ]; then
    echo "render: source not found: $src" >&2
    return 1
  fi

  local rendered
  rendered="$(render_str "$(cat "$src")")"

  if [ "${DRY_RUN:-0}" = "1" ]; then
    if [ -f "$dst" ] && [ "$(cat "$dst")" = "$rendered" ]; then
      echo "  · render (no change): $dst"
    else
      echo "  + render: $src → $dst"
    fi
    return 0
  fi

  mkdir -p "$(dirname "$dst")"
  if [ -f "$dst" ] && [ "$(cat "$dst")" = "$rendered" ]; then
    return 0   # idempotent: nothing to do
  fi
  [ -f "$dst" ] && cp "$dst" "$dst.bak"
  printf '%s' "$rendered" > "$dst"
}

# render_str: render a template given as a string. Echoes result on stdout.
# Processes @if/@endif blocks, @include directives, ${VAR}, ${OP:op://...}.
render_str() {
  local input="$1"
  local output=""
  local skip_depth=0   # >0 means we're inside a @if block that evaluated false
  local line

  while IFS= read -r line || [ -n "$line" ]; do
    # @include directive (only honored outside skipped blocks)
    if [ "$skip_depth" = 0 ] && [[ "$line" =~ ^[[:space:]]*#[[:space:]]*@include[[:space:]]+(.+)$ ]]; then
      local inc_path="${BASH_REMATCH[1]}"
      inc_path="${inc_path%% }"   # rtrim
      # Resolve relative to DOTFILES_DIR if not absolute
      [[ "$inc_path" != /* ]] && inc_path="${DOTFILES_DIR:-$PWD}/$inc_path"
      if [ -f "$inc_path" ]; then
        output+="$(render_str "$(cat "$inc_path")")"$'\n'
      fi
      continue
    fi

    # @if directive
    if [[ "$line" =~ ^[[:space:]]*#[[:space:]]*@if[[:space:]]+(.+)$ ]]; then
      local cond="${BASH_REMATCH[1]}"
      if [ "$skip_depth" -gt 0 ]; then
        skip_depth=$((skip_depth + 1))
      elif ! _eval_condition "$cond"; then
        skip_depth=1
      fi
      continue
    fi

    # @endif directive
    if [[ "$line" =~ ^[[:space:]]*#[[:space:]]*@endif[[:space:]]*$ ]]; then
      [ "$skip_depth" -gt 0 ] && skip_depth=$((skip_depth - 1))
      continue
    fi

    # Skip lines inside a false @if block
    [ "$skip_depth" -gt 0 ] && continue

    # Expand ${OP:op://...} references first (op refs can contain colons)
    while [[ "$line" =~ \$\{OP:(op://[^}]+)\} ]]; do
      local ref="${BASH_REMATCH[1]}"
      local secret
      secret="$(_op_read "$ref")"
      line="${line//\$\{OP:${ref}\}/$secret}"
    done

    # Expand ${VAR} and ${VAR:-default} via envsubst-style processing
    # We use a perl-free approach: emit through bash parameter expansion.
    # Note: this handles ${VAR} and ${VAR:-default}, not full envsubst syntax.
    while [[ "$line" =~ \$\{([A-Za-z_][A-Za-z0-9_]*)(:-([^}]*))?\} ]]; do
      local full="${BASH_REMATCH[0]}"
      local var="${BASH_REMATCH[1]}"
      local default="${BASH_REMATCH[3]:-}"
      local val="${!var:-$default}"
      line="${line//$full/$val}"
    done

    output+="$line"$'\n'
  done <<< "$input"

  # Strip the trailing newline we always add
  output="${output%$'\n'}"
  printf '%s' "$output"
}

# render_dir: render every *.tmpl under SRC_DIR to DST_DIR, preserving subpaths.
# Files without .tmpl extension are copied as-is.
render_dir() {
  local src_dir="$1" dst_dir="$2"
  if [ ! -d "$src_dir" ]; then
    echo "render_dir: source dir not found: $src_dir" >&2
    return 1
  fi

  local f rel dst
  while IFS= read -r f; do
    rel="${f#"$src_dir"/}"
    if [[ "$rel" == *.tmpl ]]; then
      dst="$dst_dir/${rel%.tmpl}"
      render "$f" "$dst"
    else
      dst="$dst_dir/$rel"
      if [ "${DRY_RUN:-0}" = "1" ]; then
        echo "  + copy: $f → $dst"
      else
        mkdir -p "$(dirname "$dst")"
        cp -f "$f" "$dst"
      fi
    fi
  done < <(find "$src_dir" -type f)
}

export -f detect_template render render_str render_dir _op_read _eval_condition
