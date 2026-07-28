# dotfiles

Dev environment setup for macOS and Linux (Arch, Debian and Fedora families, including
EndeavourOS/CachyOS, Ubuntu and Kali).

The installer detects the host (physical Mac, Mac VM, or Linux/VM) and skips GUI apps that only make sense on a physical machine.

## What's included

**CLI tools:** git, Neovim, fzf, zoxide, eza, bat, ripgrep, fd, git-delta, tldr, Yazi, hexyl, Fastfetch

**ZSH plugins:**
- [fast-syntax-highlighting](https://github.com/zdharma-continuum/fast-syntax-highlighting)
- [fzf-tab](https://github.com/Aloxaf/fzf-tab)
- [zsh-you-should-use](https://github.com/MichaelAquilina/zsh-you-should-use)
- command-not-found (Homebrew on macOS, apt on Debian, pkgfile on Arch)

**Mac apps installed by default (physical Mac only):**
- Font: JetBrains Mono
- Touch ID for sudo (pam_tid)

1Password (+ the `op` CLI) is installed only if you opt into the authentication
step at the end of a desktop install. On Arch, the signed app and CLI packages
are built from the AUR; on macOS they are installed with Homebrew. The Arch AUR
clones are kept under `~/.cache/dotfiles/aur`; re-running
`scripts/install-1password-arch.sh` pulls them and applies available updates.

**Configs:**
- `config/zsh/zshrc`: ZSH with aliases, prompt, history, modern unix tool replacements
- `config/nvim/init.lua`: minimal Neovim config with system clipboard and persistent undo
- `config/git/gitconfig`: git-delta colors and diff highlighting

## Usage

```bash
curl -fsSL https://raw.githubusercontent.com/WladmirJunior/dotfiles/main/install.sh | bash
```

Or locally:

```bash
git clone https://github.com/WladmirJunior/dotfiles.git ~/.dotfiles
~/.dotfiles/install.sh
```

If the repository was initially cloned elsewhere, running `install.sh` normally
moves the whole clone to the canonical `~/.dotfiles` path before installation.
`--dry-run`, `--plan`, and `--check` never move it.

### Profiles

| Profile | Steps | For |
|---|---|---|
| `desktop` | packages, shell, dotfiles, apps | full Mac/Linux setup |
| `minimal` | packages, shell, dotfiles | server, headless, container |
| `pentest` | packages, shell, dotfiles | Linux pentest |

```bash
curl -fsSL .../install.sh | bash                  # desktop (default)
curl -fsSL .../install.sh | bash -s -- minimal
curl -fsSL .../install.sh | bash -s -- pentest
```

### Flags

```bash
./install.sh --dry-run minimal   # announce every action, change nothing (like terraform plan)
./install.sh -n minimal          # short form of --dry-run
./install.sh --plan minimal      # compatibility alias for --dry-run (same behavior)
./install.sh -p minimal          # short form of --plan
./install.sh --check             # verify-only: symlinks resolve, core tools on PATH, no steps run
```

A normal install runs the verification automatically as its last step. `--dry-run`
wraps every state-changing command (symlinks, copies, package installs, `defaults
write`) so you can preview a run on a fresh machine before committing to it.
`--plan`/`-p` is kept as an alias of `--dry-run` for muscle memory; it adds nothing.

### Templates

`config/**/*.tmpl` files are rendered with environment-specific values at install
time, removing the need to keep three near-identical copies across the public /
private / nu repos. See `lib/template.sh`:

```
${VAR}                    expand env var
${VAR:-default}           expand with fallback
${OP:op://Personal/...}   read secret from 1Password
# @if IS_WORK_MAC         conditional block (truthy)
# @if FOO == "value"      conditional block (equality)
# @endif                  end block
# @include path/file.tmpl include another template
```

Standard vars: `OS_TYPE`, `ARCH`, `IS_VM`, `IS_CONTAINER`, `HEADLESS`, `IS_WORK_MAC`,
`DISTRO_ID`, `DISTRO_FAMILY`, `PACKAGE_MANAGER`, `HOST_SHORT`, `GIT_NAME`,
`GIT_EMAIL`. Set in `lib/detect.sh` /
`lib/template.sh::detect_template`.

### Provision a fresh VM

One command clones a VM and provisions it with these dotfiles:

```bash
scripts/provision-vm.sh --profile minimal              # macOS tart VM, via tart exec
scripts/provision-vm.sh --dry-run                       # preview, create nothing
```

For Linux VMs, `config/cloud-init/` has first-boot seeds (`user-data.arch`,
`user-data.kali`) — the Linux equivalent of the tart-exec flow. See
`config/cloud-init/README.md`.

### Architecture

- `install.sh`: orchestrator. Detects environment, reads profile, runs steps.
- `lib/detect.sh`: OS, Linux family/package manager, arch, VM/container, headless and TTY detection.
- `lib/exec.sh`, `lib/step.sh`, `lib/state.sh`: shared execution, step-status and checkpoint contracts.
- `lib/transaction.sh`: canonical rollback API (`DOTFILES_INSTALLER_API=1`) used by public and private installers.
- `lib/packages/`: package-manager adapters; `config/packages.tsv` maps capabilities to each distribution's package names.
- `lib/setup/selection.sh`: maintenance selector that starts with installed components selected and derives installs/removals from the final selection.
- `steps/`: `01-packages` (CLI), `02-shell` (fzf+plugins), `03-dotfiles` (configs), `04-apps` (GUI, desktop only).
- `profiles/`: step list per machine type.
- `scripts/provision-vm.sh`: clone + provision a tart VM hands-off (macOS, via `tart exec`).
- `scripts/install-github-release.sh`: shared verified GitHub Release installer used by distribution fallbacks.
- `scripts/install-yazi.sh`: installs the verified official Yazi `.deb` when a Debian-family distribution does not package it.
- `scripts/install-fastfetch.sh`: installs the verified official Fastfetch `.deb` when a Debian-family distribution does not package it.
- `config/cloud-init/`: first-boot seeds for Linux VMs (Arch, Kali).

The installer detects VM (skips GUI apps), headless (skips GUI on Linux), and TTY: interactive mode prompts for opt-in apps; via `curl|bash` (no TTY) uses defaults.
