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
- Ghostty (terminal)
- Font: JetBrains Mono
- Touch ID for sudo (pam_tid)

1Password (+ the `op` CLI) is installed only if you opt into the authentication
step at the end of the install.

**Configs:**
- `config/zsh/zshrc`: ZSH with aliases, prompt, history, modern unix tool replacements
- `config/nvim/init.lua`: minimal Neovim config with system clipboard and persistent undo
- `config/ghostty/config`: Ghostty terminal config
- `config/ghostty/ghostty.terminfo`: terminfo for SSH sessions from Ghostty
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
./install.sh --check             # verify-only: symlinks resolve, core tools on PATH, no steps run
```

A normal install runs the verification automatically as its last step. `--dry-run`
wraps every state-changing command (symlinks, copies, package installs, `defaults
write`) so you can preview a run on a fresh machine before committing to it.

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
