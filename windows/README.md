# Windows (native)

`install.ps1` is the Windows counterpart of `install.sh`. It targets native
PowerShell 7, not WSL. It is a minimal port: CLI tools, editor/git configs, a
pwsh profile and the 1Password SSH agent. It does not install sonus,
ai-cli-configs, agent memory or the private overlay (those stay macOS/Linux).

For a full Linux-parity setup on a Windows box, run `install.sh` inside WSL2
instead.

## Requirements

- Windows 10/11
- PowerShell 7+ (`winget install --id Microsoft.PowerShell`)
- winget (ships as "App Installer"; install from the Microsoft Store if missing)
- Developer Mode on (Settings > System > For developers) so symlinks work
  without elevation. Without it the installer falls back to static file copies.

## Usage

```powershell
# remote bootstrap
iwr -useb https://raw.githubusercontent.com/WladmirJunior/dotfiles/main/install.ps1 | iex

# or local
git clone https://github.com/WladmirJunior/dotfiles ~/.dotfiles
pwsh -File ~/.dotfiles/install.ps1 -WhatIf      # preview, change nothing
pwsh -File ~/.dotfiles/install.ps1 -SkipAuth    # packages + dotfiles + shell
pwsh -File ~/.dotfiles/install.ps1              # everything, including 1Password/gh
```

### Flags

| Flag | Effect |
|---|---|
| `-WhatIf` | announce every action, change nothing |
| `-SkipPackages` | skip the winget phase |
| `-SkipAuth` | skip the 1Password / gh phase |

## Phases

1. packages (winget): git, Neovim, fzf, zoxide, eza, bat, ripgrep, fd,
   git-delta, Node LTS, gh, Fastfetch, jq, 7-Zip, tldr. Already-present tools
   are skipped. A failed package is a warning, not a stop. yazi is not on
   winget, so its verified GitHub release is downloaded into `~/.local/bin`.
2. dotfiles: symlinks `config/nvim/init.lua` and `lazy-lock.json` into
   `%LOCALAPPDATA%\nvim`, copies `config/git/gitconfig` to `~/.gitconfig.delta`
   and wires it via `git config --global include.path`.
3. shell: symlinks `windows/profile.ps1` to `$PROFILE.CurrentUserCurrentHost`.
   Machine-local tweaks go in `~/.pwsh_profile.local.ps1` (not versioned).
4. auth: guides enabling the 1Password SSH agent, checks the
   `\\.\pipe\openssh-ssh-agent` pipe. For `gh`: 1Password shell plugins are not
   supported on Windows (1Password/shell-plugins#403), so instead it writes a
   `$env:GH_TOKEN = (op read "op://...")` line into `~/.pwsh_profile.local.ps1`
   from a secret reference you provide. `gh` reads `GH_TOKEN` before any
   on-disk config, so no token is written to `~/.config/gh/hosts.yml`.

### Not installed

- gum: the rich installer UI is not ported.
- fzf key bindings: install the `PSFzf` module yourself
  (`Install-Module PSFzf`); the profile picks it up automatically.

## Undo

No transaction journal. To reverse:

- packages: `winget uninstall --id <id>` per tool
- configs: restore the `*.bak-<timestamp>` next to each replaced file
- profile: `Remove-Item $PROFILE.CurrentUserCurrentHost`, restore its `.bak-*`
- git: `git config --global --unset include.path <path>`
