# dotfiles

Dev environment setup for macOS and Linux (Debian/Kali).

The installer detects the host (physical Mac, Mac VM, or Linux/VM) and skips GUI apps that only make sense on a physical machine.

## What's included

**CLI tools:** git, Neovim, fzf, zoxide, eza, bat, ripgrep, fd, git-delta, tldr

**ZSH plugins:**
- [fast-syntax-highlighting](https://github.com/zdharma-continuum/fast-syntax-highlighting)
- [fzf-tab](https://github.com/Aloxaf/fzf-tab)
- [zsh-you-should-use](https://github.com/MichaelAquilina/zsh-you-should-use)
- command-not-found (Homebrew on macOS, apt on Linux)

**Mac apps installed by default (physical Mac only):**
- Font: JetBrains Mono
- Touch ID for sudo (pam_tid)

1Password (+ the `op` CLI) is installed only if you opt into the authentication
step at the end of the install.

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
./install.sh --plan minimal      # like --dry-run but ends with a categorized summary
./install.sh -p minimal          # short form of --plan
./install.sh --check             # verify-only: symlinks resolve, core tools on PATH, no steps run
```

A normal install runs the verification automatically as its last step. `--dry-run`
wraps every state-changing command (symlinks, copies, package installs, `defaults
write`) so you can preview a run on a fresh machine before committing to it.

`--plan` is `--dry-run` plus a final summary: create/update/replace/install/skip
counts and a per-item list, color-coded. Use it to review what would change
before applying.

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

Standard vars: `OS_TYPE`, `ARCH`, `IS_VM`, `HEADLESS`, `IS_WORK_MAC`,
`HOST_SHORT`, `GIT_NAME`, `GIT_EMAIL`. Set in `lib/detect.sh` /
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
- `lib/detect.sh`: OS, arch, VM, headless, TTY detection.
- `steps/`: `01-packages` (CLI), `02-shell` (fzf+plugins), `03-dotfiles` (configs), `04-apps` (GUI, desktop only).
- `profiles/`: step list per machine type.
- `scripts/provision-vm.sh`: clone + provision a tart VM hands-off (macOS, via `tart exec`).
- `config/cloud-init/`: first-boot seeds for Linux VMs (Arch, Kali).

The installer detects VM (skips GUI apps), headless (skips GUI on Linux), and TTY: interactive mode prompts for opt-in apps; via `curl|bash` (no TTY) uses defaults.
