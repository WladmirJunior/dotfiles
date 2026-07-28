#!/bin/bash
# Dotfiles installer — orchestrator.
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/WladmirJunior/dotfiles/main/install.sh | bash
#   curl -fsSL .../install.sh | bash -s -- minimal
#   curl -fsSL .../install.sh | bash -s -- pentest
#   ./install.sh [desktop|minimal|pentest]
#
# With no profile arg on an interactive terminal you're asked to pick one.
# Profiles in profiles/. Steps in steps/. Detection in lib/detect.sh. UI in lib/ui.sh.
#
# Flags:
#   --dry-run, -n   announce every state-changing action without executing it
#   --plan, -p      same as --dry-run but show a categorized summary at the end
#                   (create/update/install/skip counts + per-item list)
#   --check         run only the post-install verification (no steps)
#   --status        read-only drift report: catalog vs installed packages for
#                   this OS (no lock, no transaction, no TTY needed);
#                   exit 0 = in sync, 1 = missing packages
set -uo pipefail

REPO_URL="https://github.com/WladmirJunior/dotfiles.git"
REPO_SLUG="WladmirJunior/dotfiles"     # owner/repo, for the tarball URL
REPO_REF="${DOTFILES_REF:-main}"        # branch/tag/sha to fetch (override via env)
CLONE_DIR="$HOME/.dotfiles"

# Parse flags (any order) and keep the first non-flag arg as the profile.
DRY_RUN=0; CHECK_ONLY=0; PLAN_MODE=0; STATUS_ONLY=0; PROFILE_ARG=""
for arg in "$@"; do
  case "$arg" in
    --dry-run|-n) DRY_RUN=1 ;;
    --plan|-p)    DRY_RUN=1; PLAN_MODE=1 ;;
    --check)      CHECK_ONLY=1 ;;
    --status)     STATUS_ONLY=1 ;;
    -*)           echo "Unknown flag: $arg" >&2; exit 2 ;;
    *)            [ -z "$PROFILE_ARG" ] && PROFILE_ARG="$arg" ;;
  esac
done
export DRY_RUN PLAN_MODE

# Step optionality table: one "step-filename policy" pair per line; policy is
# required or optional. required: a failure aborts the install (with rollback).
# optional: a failure is warned, recorded and the install continues. Steps not
# listed default to required (fail-closed). Every public step is required
# today; declare a future nice-to-have step optional HERE instead of
# special-casing its filename in the run loop. Overridable via env so the test
# harness can exercise both policies.
STEP_POLICY_TABLE="${STEP_POLICY_TABLE:-
01-packages.sh required
02-shell.sh required
03-dotfiles.sh required
04-apps.sh required
}"

# step_policy STEP_FILENAME: print the declared policy for a step; anything
# unlisted (or with a mistyped policy) is required.
step_policy() {
  local step_name="$1" name policy
  while read -r name policy; do
    [ "$name" = "$step_name" ] || continue
    case "$policy" in
      required|optional) printf '%s\n' "$policy"; return 0 ;;
    esac
  done <<STEP_POLICY_TABLE
$STEP_POLICY_TABLE
STEP_POLICY_TABLE
  printf 'required\n'
}

SELF_DIR="$( cd "$( dirname "${BASH_SOURCE[0]:-/dev/null}" )" 2>/dev/null && pwd )"
if [ -n "$SELF_DIR" ] && [ -d "$SELF_DIR/steps" ] && [ -d "$SELF_DIR/profiles" ]; then
  # ~/.dotfiles is the canonical location even when the user initially cloned
  # the repository elsewhere (for example ~/dev/dotfiles). Move the whole clone
  # before sourcing any repo files, then restart from its stable path. Preview,
  # verification and status modes remain read-only and use the clone in place.
  if [ "$SELF_DIR" != "$CLONE_DIR" ] && [ "$DRY_RUN" != 1 ] && [ "$CHECK_ONLY" != 1 ] \
    && [ "$STATUS_ONLY" != 1 ]; then
    if [ -e "$CLONE_DIR" ]; then
      echo "ERROR: cannot move dotfiles to $CLONE_DIR because that path already exists." >&2
      echo "Move or remove it, then re-run $SELF_DIR/install.sh." >&2
      exit 1
    fi
    echo "Moving dotfiles from $SELF_DIR to $CLONE_DIR..."
    mkdir -p "$(dirname "$CLONE_DIR")"
    mv "$SELF_DIR" "$CLONE_DIR" || {
      echo "ERROR: failed to move dotfiles to $CLONE_DIR." >&2
      exit 1
    }
    exec "$CLONE_DIR/install.sh" "$@"
  fi
  DOTFILES_DIR="$SELF_DIR"
else
  # Fetch the repo WITHOUT git. A vanilla macOS has no git until the Xcode CLT
  # is installed, and a clean Debian/Kali has no git either — but both always
  # have curl + tar. So we download the GitHub source tarball and extract it.
  # git itself is just another package the steps install later (step 01); it is
  # not a bootstrap dependency. Re-runs: refresh by re-extracting over the dir.
  if command -v git >/dev/null 2>&1 && [ -d "$CLONE_DIR/.git" ]; then
    echo "Updating existing repo at $CLONE_DIR..."
    git -C "$CLONE_DIR" pull --ff-only 2>/dev/null || true
  else
    echo "Fetching dotfiles ($REPO_REF) to $CLONE_DIR..."
    command -v curl >/dev/null 2>&1 || { echo "ERROR: curl not found." >&2; exit 1; }
    command -v tar  >/dev/null 2>&1 || { echo "ERROR: tar not found." >&2; exit 1; }
    _tgz="$(mktemp -t dotfiles.XXXXXX).tar.gz"
    _tarurl="https://codeload.github.com/$REPO_SLUG/tar.gz/refs/heads/$REPO_REF"
    # Fall back to the tags/sha endpoint if the ref isn't a branch.
    if ! curl -fsSL "$_tarurl" -o "$_tgz"; then
      _tarurl="https://codeload.github.com/$REPO_SLUG/tar.gz/$REPO_REF"
      if ! curl -fsSL "$_tarurl" -o "$_tgz"; then
        echo "ERROR: could not download $REPO_SLUG @ $REPO_REF tarball." >&2
        rm -f "$_tgz"; exit 1
      fi
    fi
    # GitHub tarballs extract into a top-level <repo>-<ref>/ dir; strip it.
    mkdir -p "$CLONE_DIR"
    if ! tar -xzf "$_tgz" -C "$CLONE_DIR" --strip-components=1; then
      echo "ERROR: failed to extract the dotfiles tarball into $CLONE_DIR." >&2
      rm -f "$_tgz"; exit 1
    fi
    rm -f "$_tgz"
  fi
  DOTFILES_DIR="$CLONE_DIR"
fi
export DOTFILES_DIR

# Guard: the repo must actually be present. Catches a half-finished clone or a
# stale empty ~/.dotfiles before we try to source from it (clearer than the
# downstream 'OS_TYPE: unbound variable').
if [ ! -f "$DOTFILES_DIR/lib/detect.sh" ] || [ ! -f "$DOTFILES_DIR/lib/ui.sh" ]; then
  echo "ERROR: $DOTFILES_DIR is missing its lib/ files — the clone did not complete." >&2
  echo "Remove $DOTFILES_DIR and re-run the installer." >&2
  exit 1
fi

source "$DOTFILES_DIR/lib/detect.sh"
source "$DOTFILES_DIR/lib/ui.sh"
[ -f "$DOTFILES_DIR/lib/step.sh" ]        && source "$DOTFILES_DIR/lib/step.sh"
[ -f "$DOTFILES_DIR/lib/state.sh" ]       && source "$DOTFILES_DIR/lib/state.sh"
[ -f "$DOTFILES_DIR/lib/template.sh" ]    && source "$DOTFILES_DIR/lib/template.sh"
[ -f "$DOTFILES_DIR/lib/plan.sh" ]        && source "$DOTFILES_DIR/lib/plan.sh"
[ -f "$DOTFILES_DIR/lib/transaction.sh" ] && source "$DOTFILES_DIR/lib/transaction.sh"
[ -f "$DOTFILES_DIR/lib/telemetry.sh" ]   && source "$DOTFILES_DIR/lib/telemetry.sh"
[ "$PLAN_MODE" = 1 ] && plan_reset

# Transaction log: track mutations so a failed install rolls back cleanly
# instead of leaving the machine half-configured. Disabled in dry-run/plan,
# in --check and --status (read-only: no lock, no journal handling) and when
# the helper isn't present. tx_init also takes the single-install lock: rc 2
# means another install is running, so this one must not proceed at all (two
# concurrent runs would corrupt the journal).
TX_ENABLED=0
if [ "$DRY_RUN" != 1 ] && [ "$CHECK_ONLY" != 1 ] && [ "$STATUS_ONLY" != 1 ] \
  && command -v tx_init >/dev/null 2>&1; then
  tx_init
  tx_rc=$?
  if [ "$tx_rc" -eq 0 ]; then
    TX_ENABLED=1
  elif [ "$tx_rc" -eq 2 ]; then
    echo "ERROR: another dotfiles install is already running. Finish or stop it, then re-run." >&2
    exit 1
  fi
fi
export TX_ENABLED

# Release the install lock (and, later in the script, the sudo keepalive) on
# any exit path. Guarded with command -v because an early exit can happen
# before the helpers exist.
install_cleanup() {
  command -v sudo_keepalive_stop >/dev/null 2>&1 && sudo_keepalive_stop
  [ "$TX_ENABLED" = 1 ] && command -v tx_release_lock >/dev/null 2>&1 && tx_release_lock
  return 0
}
trap install_cleanup EXIT

# verify_install: post-install health check. Symlinks resolve, core tools on PATH.
# Run as the final step of a normal install, or standalone via `--check`.
verify_install() {
  banner "Verify · post-install health check"
  verify_cmd git; verify_cmd zsh
  command -v nvim >/dev/null 2>&1 && verify_cmd nvim
  verify_path "$HOME/.zshrc"
  [ -e "$HOME/.config/nvim/init.lua" ] && verify_link "$HOME/.config/nvim/init.lua"
  if [ "$VERIFY_FAILS" -eq 0 ]; then ok "all checks passed"
  else note "$VERIFY_FAILS check(s) failed — see FAIL lines above"; fi
  return "$VERIFY_FAILS"
}

# --check: verification only, no install steps.
if [ "$CHECK_ONLY" = 1 ]; then
  verify_install; exit $?
fi

# install_status: headless drift report for --status. For the current OS's
# package manager, compare each catalog scope against what is actually
# installed (via the lib/packages adapters; brew uses brew_plan_formulae).
# Read-only by design: no lock, no transaction, no steps, plain output that
# works without a TTY. Exit: 0 = in sync, 1 = drift, 2 = cannot report.
install_status() {
  local manager="${PACKAGE_MANAGER:-}" query_cmd
  if [ -z "$manager" ]; then
    echo "status: unsupported OS/distribution ($OS_TYPE ${DISTRO_ID:-unknown}); no package manager detected" >&2
    return 2
  fi
  source "$DOTFILES_DIR/lib/packages/catalog.sh" || return 2
  [ -f "$DOTFILES_DIR/lib/packages/$manager.sh" ] \
    && source "$DOTFILES_DIR/lib/packages/$manager.sh"
  # Without the manager's query binary every package would read as "missing";
  # refuse to report drift that is really an unbootstrapped machine.
  case "$manager" in
    brew) query_cmd=brew ;;
    apt) query_cmd=dpkg-query ;;
    pacman) query_cmd=pacman ;;
    dnf) query_cmd=rpm ;;
    *) query_cmd="$manager" ;;
  esac
  command -v "$query_cmd" >/dev/null 2>&1 || {
    echo "status: $query_cmd not found; cannot query installed packages (run the installer first)" >&2
    return 2
  }
  echo "status: manager=$manager os=$OS_TYPE${DISTRO_ID:+ distro=$DISTRO_ID}"
  # nvim-optional is an interactive opt-in set; reporting it as drift would be
  # noise. Scopes with no packages for this manager are skipped silently.
  local drift=0 scope pkgs pkg missing total missing_count
  for scope in core best-effort; do
    pkgs="$(package_catalog "$scope" "$manager")" || return 2
    [ -n "$pkgs" ] || continue
    missing=""
    if [ "$manager" = brew ] && command -v brew_plan_formulae >/dev/null 2>&1; then
      # shellcheck disable=SC2086 # catalog identifiers are word-split on purpose.
      brew_plan_formulae $pkgs
      missing="$BREW_MISSING"
      [ -n "$BREW_UPGRADE" ] && echo "$scope outdated: $BREW_UPGRADE"
    else
      for pkg in $pkgs; do
        case "$manager" in
          apt) apt_package_installed "$pkg" ;;
          pacman) pacman_package_installed "$pkg" ;;
          dnf) dnf_package_installed "$pkg" ;;
          *) false ;;
        esac || missing="${missing:+$missing }$pkg"
      done
    fi
    total="$(printf '%s\n' "$pkgs" | wc -w | tr -d ' ')"
    missing_count=0
    [ -n "$missing" ] && missing_count="$(printf '%s\n' "$missing" | wc -w | tr -d ' ')"
    if [ -n "$missing" ]; then
      drift=1
      echo "$scope missing: $missing"
    fi
    if [ "$((total - missing_count))" -eq 1 ]; then
      echo "$scope ok: 1 package"
    else
      echo "$scope ok: $((total - missing_count)) packages"
    fi
  done
  return "$drift"
}

# Announce dry-run / plan mode up front so the user knows nothing will be changed.
if [ "$PLAN_MODE" = 1 ]; then
  info "PLAN: capturing planned changes; nothing will be executed."
elif [ "$DRY_RUN" = 1 ]; then
  info "DRY-RUN: actions are announced, not executed."
fi

# Put Homebrew on PATH for every step. 01-packages may have just installed it, or
# it may already exist (CI images, re-runs) — either way its shellenv isn't in the
# orchestrator's env, so later steps (02-shell, 04-apps) would hit
# `brew: command not found`. Re-evaluated before each step (see the loop) so a
# brew installed by 01 is visible to 02+.
brew_env() {
  [ "$OS_TYPE" = "Darwin" ] || return 0
  for brew_bin in /opt/homebrew/bin/brew /usr/local/bin/brew; do
    [ -x "$brew_bin" ] && eval "$("$brew_bin" shellenv)" && return 0
  done
}
brew_env

# --status: drift report only. Placed after brew_env so a Homebrew that is not
# yet on this shell's PATH is still found; exits before any prompt or UI.
if [ "$STATUS_ONLY" = 1 ]; then
  install_status; exit $?
fi

# Fetch the gum fork before the first prompt/banner so the UI renders richly even
# on a clean machine. Single source of truth for the gum binary lives in lib/ui.sh.
ui_bootstrap_gum

# Welcome banner.
if have_gum; then
  "$GUM" style --border double --border-foreground $THEME_BORDER --padding "1 3" \
    --margin "1 0 0 $LAYOUT_MARGIN" --align center --width "$(cwidth)" \
    "$("$GUM" style --foreground $THEME_PRIMARY --bold 'Welcome to the dotfiles setup')" \
    "Bootstrapping this machine · apps, shell, dotfiles" || true
fi

# Resolve the profile. An explicit arg always wins. With no arg: ask interactively
# when a real terminal is reachable, else fall back by environment (headless ->
# minimal). We test /dev/tty rather than FD 0 because under `curl | bash` stdin is
# the script pipe, not the keyboard — but /dev/tty still reaches the terminal.
if [ -n "$PROFILE_ARG" ]; then
  PROFILE="$PROFILE_ARG"
elif [ -r /dev/tty ] && [ "$HEADLESS" != "yes" ]; then
  task "Choose what to install"
  PROFILE="$(choose1 'Profile' \
    'desktop · full GUI setup' \
    'minimal · CLI only' \
    'pentest · CLI + security tools')"
  PROFILE="${PROFILE%% *}"   # keep the first word (desktop/minimal/pentest)
  PROFILE="${PROFILE:-desktop}"
  note "→ $PROFILE"
elif [ "$HEADLESS" = "yes" ]; then
  PROFILE="minimal"
  echo "No profile given and host is headless -> defaulting to 'minimal'."
else
  PROFILE="desktop"
fi

PROFILE_FILE="$DOTFILES_DIR/profiles/$PROFILE"
if [ ! -f "$PROFILE_FILE" ]; then
  echo "Unknown profile '$PROFILE'. Available: $(ls "$DOTFILES_DIR/profiles" | tr '\n' ' ')"
  exit 1
fi

note "profile: $PROFILE · OS: $OS_TYPE $ARCH · VM: $IS_VM · headless: $HEADLESS"

# Count the real steps in the profile up front so headers can read "Step N/total".
STEP_TOTAL=$(grep -cvE '^\s*(#|$)' "$PROFILE_FILE")

banner "Base setup · public dotfiles"

# Authenticate sudo once and keep its terminal-scoped timestamp alive while the
# Linux install runs. Individual steps and the later AUR phase can then elevate
# without repeatedly asking for the same password.
SUDO_KEEPALIVE_PID=""
sudo_keepalive_stop() {
  if [ -n "$SUDO_KEEPALIVE_PID" ]; then
    kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true
    wait "$SUDO_KEEPALIVE_PID" 2>/dev/null || true
  fi
}
if [ "$OS_TYPE" = "Linux" ] && [ "$(id -u)" -ne 0 ] && [ "$DRY_RUN" != 1 ]; then
  command -v sudo >/dev/null 2>&1 || {
    note "sudo is required for Linux package installation"
    exit 1
  }
  note "Authenticating sudo once for this install..."
  sudo -v || {
    note "sudo authentication failed"
    exit 1
  }
  _sudo_parent_pid="$$"
  (
    while kill -0 "$_sudo_parent_pid" 2>/dev/null; do
      sleep 50
      sudo -n -v 2>/dev/null || exit
    done
  ) &
  SUDO_KEEPALIVE_PID=$!
  # No trap here: install_cleanup (set right after tx_init) already stops the
  # keepalive on exit; a second EXIT trap would clobber it.
fi

# Read the profile on a dedicated FD (3), not stdin. Under `curl | bash` stdin is
# the pipe carrying the rest of this script; a step that consumes stdin (e.g. brew
# installing a cask) would otherwise drain it and bash would hit EOF after the
# loop, skipping the closing banner. Each step runs with stdin from /dev/null so it
# can't touch the pipe; interactive steps read /dev/tty directly, not stdin.
# abort_install: a step failed. Roll back everything this run recorded (unless
# disabled) and exit non-zero. This replaces the old "note and continue" which
# left a clean machine half-configured on the first error.
abort_install() {
  local failed_step="$1" rc="$2"
  echo "" >&2
  note "step $failed_step failed (rc=$rc) — aborting install" 2>/dev/null \
    || echo "step $failed_step failed (rc=$rc) — aborting install" >&2
  if [ "$TX_ENABLED" = 1 ]; then
    if tx_rollback; then
      note "machine restored to its pre-install state. Fix the cause and re-run." 2>/dev/null \
        || echo "machine restored to its pre-install state. Fix the cause and re-run." >&2
    else
      # Never claim success when undos failed: point at the journal and the
      # quarantine so the leftover state can be cleaned up by hand.
      note "partial restore: ${TX_ROLLBACK_FAILED:-?} undo action(s) failed (see $TX_LOG and the quarantine dir)." 2>/dev/null \
        || echo "partial restore: ${TX_ROLLBACK_FAILED:-?} undo action(s) failed (see $TX_LOG and the quarantine dir)." >&2
    fi
  else
    note "no transaction log to roll back; inspect the partial state manually." 2>/dev/null \
      || echo "no transaction log; inspect partial state manually." >&2
  fi
  exit "$rc"
}

# Telemetry mode label for this run. A completed base install re-running is a
# maintenance pass; --check never reaches the step loop but is labeled anyway.
INSTALL_RUN_MODE="install"
if [ "$CHECK_ONLY" = 1 ]; then
  INSTALL_RUN_MODE="check"
elif [ "$DRY_RUN" = 1 ]; then
  INSTALL_RUN_MODE="dry-run"
elif command -v state_is >/dev/null 2>&1 && state_is public.base complete; then
  INSTALL_RUN_MODE="maintenance"
fi

STEP_N=0
OPTIONAL_STEP_FAILURES=""
while IFS= read -r step <&3; do
  [ -z "$step" ] && continue
  case "$step" in \#*) continue ;; esac
  STEP_N=$((STEP_N + 1))
  brew_env   # pick up a brew that an earlier step (01-packages) may have installed
  step "$STEP_N/$STEP_TOTAL" "$(step_title "$step")"
  # Fail-fast: a non-zero step aborts the whole install and triggers rollback,
  # EXCEPT the declared non-fatal statuses (STEP_SKIPPED and
  # STEP_DEPENDENCY_UNAVAILABLE, see lib/step.sh), which are announced and the
  # install moves on. Capture the step's real exit code directly (a `if ! cmd`
  # would mask it as 1).
  step_started_at="$(date +%s)"
  step_execute "$DOTFILES_DIR/steps/$step"
  step_rc=$?
  # Best-effort run telemetry: recorded before the abort check so a failing
  # step still gets its line; never fails the install (see lib/telemetry.sh).
  command -v telemetry_record_step >/dev/null 2>&1 && telemetry_record_step \
    "$step" "$step_rc" "$(( $(date +%s) - step_started_at ))" "$INSTALL_RUN_MODE" "$OS_TYPE"
  if [ "$step_rc" -ne 0 ]; then
    step_status=""
    command -v step_status_label >/dev/null 2>&1 \
      && step_status="$(step_status_label "$step_rc" 2>/dev/null || true)"
    if [ -n "$step_status" ]; then
      note "step $step: $step_status (rc=$step_rc); continuing"
    elif [ "$(step_policy "$step")" = optional ]; then
      note "optional step $step failed (rc=$step_rc); continuing"
      OPTIONAL_STEP_FAILURES="$OPTIONAL_STEP_FAILURES $step"
    else
      abort_install "$step" "$step_rc"
    fi
  fi
done 3< "$PROFILE_FILE"

# Optional-step failures never abort, but they must not vanish either: repeat
# them once the loop is over so they are visible after a long install.
if [ -n "$OPTIONAL_STEP_FAILURES" ]; then
  note "optional step(s) failed:$OPTIONAL_STEP_FAILURES (the install continued; re-run after fixing)"
fi

# All steps succeeded: commit the transaction (rotate the log, no rollback).
[ "$TX_ENABLED" = 1 ] && tx_commit
if [ "$DRY_RUN" != 1 ] && command -v state_set >/dev/null 2>&1; then
  state_set public.base complete
fi

ok "Public setup done (profile: $PROFILE)."

# Plan mode: emit the summary of recorded changes and exit before private overlays.
if [ "$PLAN_MODE" = 1 ]; then
  banner "Plan summary"
  plan_summary
  plan_cleanup
  exit 0
fi

# Verify what the steps just applied (skipped in dry-run: nothing was changed).
[ "$DRY_RUN" = 1 ] || verify_install || note "verification reported issues (see above)"

# -----------------------------------------------------------------------------
#  Connect & authenticate (opt-in) — wire up the 1Password SSH agent + GitHub CLI
#  so private overlays can be fetched. Generic: only ever names 1Password/GitHub,
#  never any private repo. Supports macOS and Arch/Debian/Fedora Linux desktops.
# -----------------------------------------------------------------------------
OP_SOCK="$HOME/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"
ZLOCAL="$HOME/.zshrc.local"   # machine-local overlay sourced by the thin ~/.zshrc

# append_once FILE MARKER LINE: add LINE to FILE only if MARKER not already there.
append_once() {
  local f="$1" marker="$2" line="$3"
  mkdir -p "$(dirname "$f")"; touch "$f"
  grep -qF "$marker" "$f" 2>/dev/null || printf '%s\n' "$line" >> "$f"
}

# github_ssh_ready: private overlays clone over git@github.com, which uses the
# 1Password SSH agent rather than the PAT configured by `op plugin init gh`.
# Verify that independent authentication path before running a bootstrap that
# would otherwise continue after a failed clone and emit misleading errors.
github_ssh_ready() {
  if ! SSH_AUTH_SOCK="${SSH_AUTH_SOCK:-}" ssh-add -l >/dev/null 2>&1; then
    note "The 1Password SSH agent is not exposing any keys."
    note "Unlock 1Password and ensure your SSH Key item is available to its agent."
    return 1
  fi
  local ssh_result
  ssh_result="$(ssh -o BatchMode=yes -o ConnectTimeout=15 -T git@github.com 2>&1 || true)"
  if grep -q 'successfully authenticated' <<<"$ssh_result"; then
    return 0
  fi
  note "GitHub did not accept any key offered by the 1Password SSH agent."
  note "Add the public key from your 1Password SSH Key item to GitHub > Settings > SSH and GPG keys."
  return 1
}

apply_private_overlay() {
  # The overlay repo, and therefore its local dir name, comes from the
  # 1Password bootstrap note; no overlay name is hardcoded in this file.
  local private_repo private_dir
  private_repo="$(op item get dotfiles-bootstrap --vault Personal \
    --fields private_repo 2>/dev/null)" || return 1
  [ -n "$private_repo" ] || return 1
  private_dir="$HOME/.$(basename "${private_repo%.git}")"
  if [ -d "$private_dir/.git" ]; then
    git -C "$private_dir" pull --ff-only || return 1
  else
    git clone "git@github.com:$private_repo.git" "$private_dir" || return 1
  fi
  bash "$private_dir/install.sh"
}

# configure_1password_ssh_agent_linux: make SSH Key items from every signed-in
# 1Password account available to the Linux agent, including keys stored outside
# the default Personal/Private/Employee vaults. On a personal Linux machine,
# expose only the personal GitHub key so a work key cannot be selected first.
configure_1password_ssh_agent_linux() {
  command -v op >/dev/null 2>&1 || return 1
  command -v jq >/dev/null 2>&1 || {
    note "jq is required to configure 1Password SSH keys automatically."
    return 1
  }

  local agent_dir="$HOME/.config/1Password/ssh"
  local agent_file="$agent_dir/agent.toml"
  local marker="# Managed by dotfiles · generated from 1Password SSH Key items"
  if [ -f "$agent_file" ] && ! grep -qF "$marker" "$agent_file"; then
    note "Keeping existing unmanaged 1Password agent config: $agent_file"
    return 0
  fi

  local accounts_json account_uuid keys_json
  accounts_json="$(op account list --format=json)" || {
    note "Could not list signed-in 1Password accounts."
    return 1
  }

  local all_keys=() github_keys=() personal_github_keys=() key_id key_title
  while IFS= read -r account_uuid; do
    [ -n "$account_uuid" ] || continue
    keys_json="$(op item list --account "$account_uuid" --categories 'SSH Key' --format=json)" || continue
    while IFS=$'\t' read -r key_id key_title; do
      [ -n "$key_id" ] || continue
      all_keys+=("$key_id")
      if [[ "$key_title" =~ [Gg]it[Hh]ub ]]; then github_keys+=("$key_id"); fi
      if [[ "$key_title" =~ [Gg]it[Hh]ub ]] && [[ "$key_title" =~ [Pp]ersonal ]]; then
        personal_github_keys+=("$key_id")
      fi
    done < <(jq -r '.[] | [.id, .title] | @tsv' <<<"$keys_json")
  done < <(jq -r '.[].account_uuid // empty' <<<"$accounts_json")

  local selected_keys=("${all_keys[@]}")
  if [ "$OS_TYPE" = "Linux" ] && [ "${#personal_github_keys[@]}" -gt 0 ]; then
    selected_keys=("${personal_github_keys[@]}")
  elif [ "${#github_keys[@]}" -gt 0 ]; then
    selected_keys=("${github_keys[@]}")
  fi
  if [ "${#selected_keys[@]}" -eq 0 ]; then
    note "No 1Password items of type SSH Key were found."
    return 1
  fi

  mkdir -p "$agent_dir"
  local tmp_file="$agent_file.tmp.$$"
  {
    printf '%s\n' "$marker"
    for key_id in "${selected_keys[@]}"; do
      printf '\n[[ssh-keys]]\nitem = "%s"\n' "$key_id"
    done
  } > "$tmp_file"
  chmod 600 "$tmp_file"
  mv "$tmp_file" "$agent_file"
  ok "1Password SSH agent configured with ${#selected_keys[@]} key(s)"
}

# Dry-run stops here: everything below mutates state outside the step/tx
# machinery (1Password install, ~/.zshrc.local, ~/.ssh/config, gh credentials).
if [ "$DRY_RUN" = 1 ]; then
  info "DRY-RUN: skipping the connect & authenticate phase (it changes shell/SSH config)."
elif [ "$OS_TYPE" = "Darwin" ] && confirm "Authenticate with 1Password now?"; then
  banner "Connect & authenticate · 1Password, GitHub, SSH"

  task "1Password · install & connect (one time)"
  # 1Password 8 ships via the brew cask from the official site (the App Store only
  # has the legacy v7). Installed here, not in the base setup, so a machine that
  # opts out of auth never pulls the 198MB cask.
  if [ ! -d "/Applications/1Password.app" ]; then
    spin "installing 1Password" -- brew install --cask 1password </dev/null \
      || note "1Password install failed — install it manually"
  fi
  # open by path, not by name: LaunchServices may not have indexed the just-moved
  # app yet, so `open -a "1Password"` can fail right after install.
  open /Applications/1Password.app 2>/dev/null || note "open 1Password manually"
  note "In the 1Password app:"
  note "1. Sign in to your 1Password account"
  note "2. Settings > Developer > enable \"Use the SSH agent\""
  note "3. Settings > Developer > enable \"Integrate with 1Password CLI\""
  note "   (if a \"Set Up SSH Agent\" popup offers to edit ~/.ssh/config, just"
  note "    close it — this script writes that config for you)"
  confirm "Done? Continue" || true

  task "SSH agent · 1Password"
  export SSH_AUTH_SOCK="$OP_SOCK"
  append_once "$ZLOCAL" "2BUA8C4S2C.com.1password/t/agent.sock" \
    'export SSH_AUTH_SOCK="$HOME/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"'
  # ~/.ssh/config IdentityAgent so GUI apps (not just the shell) use the agent.
  # Match on the agent-socket fragment (not the exact line) so we don't duplicate
  # a block 1Password may have written itself via its "Edit Automatically" popup.
  append_once "$HOME/.ssh/config" "2BUA8C4S2C.com.1password/t/agent.sock" \
    "$(printf 'Host *\n  IdentityAgent "%s"' "$OP_SOCK")"
  chmod 600 "$HOME/.ssh/config" 2>/dev/null || true
  ok "SSH uses the 1Password agent (Touch ID per use)"

  task "GitHub CLI · 1Password shell plugin"
  # The op CLI is a separate cask from the desktop app; install it if missing.
  if ! command -v op >/dev/null 2>&1; then
    spin "installing 1Password CLI" -- brew install --cask 1password-cli </dev/null || true
    brew_env
  fi
  if command -v op >/dev/null 2>&1; then
    op plugin init gh </dev/tty || note "op plugin init gh did not complete"
    # op prints a manual "echo source ... >> ~/.zshrc" hint — we've already wired
    # the source into ~/.zshrc.local, so that hint can be ignored.
    append_once "$ZLOCAL" 'op/plugins.sh' \
      '[ -f "$HOME/.config/op/plugins.sh" ] && source "$HOME/.config/op/plugins.sh"'
    rm -f "$HOME/.config/gh/hosts.yml" 2>/dev/null || true   # no on-disk gh creds
    ok "gh plugin wired into ~/.zshrc.local (ignore op's echo hint above)"
  else
    note "1Password CLI unavailable — run 'op plugin init gh' after installing it"
  fi

  banner "Next · private overlays"
  if command -v op >/dev/null 2>&1 && confirm "Apply private overlays now?"; then
    if github_ssh_ready; then
      # Load the op gh plugin alias into THIS session so the bootstrap's gh calls
      # authenticate via 1Password without a shell reload.
      [ -f "$HOME/.config/op/plugins.sh" ] && source "$HOME/.config/op/plugins.sh"
      note "fetching and applying private overlay..."
      if ! apply_private_overlay; then
        note "private overlay did not complete"
        info "Re-run this installer and choose to apply private overlays."
      fi
    else
      note "Private overlays skipped until GitHub SSH authentication works."
      info "Test after fixing the key: ssh -T git@github.com"
    fi
  else
    note "Apply your private overlays later with:"
    info "Re-run this installer and choose to apply private overlays."
    note "(reload the shell first if gh isn't authenticated yet: exec zsh)"
  fi
elif [ "$OS_TYPE" = "Linux" ] \
  && { [ "$PACKAGE_MANAGER" = "pacman" ] || [ "$PACKAGE_MANAGER" = "apt" ] || [ "$PACKAGE_MANAGER" = "dnf" ]; } \
  && [ "$PROFILE" = "desktop" ] && [ "$HEADLESS" = "no" ] \
  && confirm "Install and configure 1Password now?"; then
  banner "Connect & authenticate · 1Password, GitHub, SSH"

  if [ "$PACKAGE_MANAGER" = pacman ]; then
    task "1Password · app + CLI from AUR"
    op_installer="$DOTFILES_DIR/scripts/install-1password-arch.sh"
  elif [ "$PACKAGE_MANAGER" = apt ]; then
    task "1Password · app + CLI from official APT repository"
    op_installer="$DOTFILES_DIR/scripts/install-1password-debian.sh"
  else
    task "1Password · app + CLI from official RPM repository"
    op_installer="$DOTFILES_DIR/scripts/install-1password-fedora.sh"
  fi
  if bash "$op_installer"; then
    ok "1Password app and CLI are up to date"
  else
    note "1Password installation did not complete"
    info "Re-run: bash \"$op_installer\""
  fi

  if command -v 1password >/dev/null 2>&1; then
    nohup 1password >/dev/null 2>&1 &
  else
    note "Open 1Password from your desktop application menu after installation."
  fi
  note "In the 1Password app:"
  note "1. Sign in to your 1Password account"
  note "2. Settings > Developer > enable \"Use the SSH agent\""
  note "3. Settings > Developer > enable \"Integrate with 1Password CLI\""
  confirm "Done? Continue" || true

  task "SSH agent · 1Password"
  LINUX_OP_SOCK="$HOME/.1password/agent.sock"
  export SSH_AUTH_SOCK="$LINUX_OP_SOCK"
  append_once "$ZLOCAL" '.1password/agent.sock' \
    'export SSH_AUTH_SOCK="$HOME/.1password/agent.sock"'
  append_once "$HOME/.ssh/config" '.1password/agent.sock' \
    'Host *
  IdentityAgent ~/.1password/agent.sock'
  chmod 600 "$HOME/.ssh/config" 2>/dev/null || true
  if configure_1password_ssh_agent_linux; then
    if ssh-add -l >/dev/null 2>&1; then
      ok "SSH configured to use the 1Password agent"
    else
      note "Lock and unlock 1Password once to reload the generated SSH agent config."
      confirm "Done? Re-check SSH keys" || true
      if ssh-add -l >/dev/null 2>&1; then
        ok "SSH configured to use the 1Password agent"
      else
        note "1Password agent still exposes no SSH identities."
      fi
    fi
  else
    note "1Password SSH agent setup did not complete."
  fi

  task "GitHub CLI · 1Password shell plugin"
  if command -v op >/dev/null 2>&1; then
    op plugin init gh </dev/tty || note "op plugin init gh did not complete"
    append_once "$ZLOCAL" 'op/plugins.sh' \
      '[ -f "$HOME/.config/op/plugins.sh" ] && source "$HOME/.config/op/plugins.sh"'
    rm -f "$HOME/.config/gh/hosts.yml" 2>/dev/null || true
    ok "gh plugin wired into ~/.zshrc.local"
  else
    note "1Password CLI unavailable — install 1password-cli and run 'op plugin init gh'"
  fi

  banner "Next · private overlays"
  if command -v op >/dev/null 2>&1 && confirm "Apply private overlays now?"; then
    if github_ssh_ready; then
      [ -f "$HOME/.config/op/plugins.sh" ] && source "$HOME/.config/op/plugins.sh"
      note "fetching and applying private overlay..."
      if ! apply_private_overlay; then
        note "private overlay did not complete"
        info "Re-run this installer and choose to apply private overlays."
      fi
    else
      note "Private overlays skipped until GitHub SSH authentication works."
      info "Test after fixing the key: ssh -T git@github.com"
    fi
  else
    note "Apply your private overlays later with:"
    info "Re-run this installer and choose to apply private overlays."
  fi
else
  [ "$OS_TYPE" = "Darwin" ] && info "Skipped authentication. Run it later from the 1Password handoff."
  [ "$OS_TYPE" = "Linux" ] && info "Restart your terminal to use zsh."
  [ "$OS_TYPE" = "Darwin" ] && info "Reload your shell to pick up the new config:  exec zsh"
fi

# Explicit success exit. Without it the script's exit code is that of the last
# command run, which on Linux is a false `[ "$OS_TYPE" = "Darwin" ]` test (-> 1),
# making a fully-successful install look like a failure to any caller checking $?.
exit 0
