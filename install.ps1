#Requires -Version 7
<#
.SYNOPSIS
  Dotfiles installer for Windows (native PowerShell 7).

.DESCRIPTION
  Standalone counterpart of install.sh for Windows. Runs five phases:
    1. packages  - CLI tools via winget
    2. dotfiles  - symlink nvim / git configs
    3. shell     - symlink windows/profile.ps1 to the pwsh profile
    4. auth      - wire up the 1Password SSH agent and gh
    5. private   - clone and run the private overlay (repo name from 1Password)

  It does NOT cover sonus, ai-cli-configs or agent memory; those stay
  macOS/Linux only. No transaction journal: each step backs up any
  pre-existing target to <path>.bak-<timestamp> and is idempotent.

.PARAMETER SkipPackages
  Skip phase 1 (winget installs).

.PARAMETER SkipAuth
  Skip phase 4 (1Password / gh).

.PARAMETER SkipPrivate
  Skip phase 5 (private overlay clone).

.PARAMETER Repo
  owner/repo to self-clone from when run via `iwr ... | iex`.

.EXAMPLE
  iwr -useb https://raw.githubusercontent.com/WladmirJunior/dotfiles/main/install.ps1 | iex

.EXAMPLE
  pwsh -File ~/.dotfiles/install.ps1 -WhatIf
  pwsh -File ~/.dotfiles/install.ps1 -SkipAuth
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [switch]$SkipPackages,
    [switch]$SkipAuth,
    [switch]$SkipPrivate,
    [string]$Repo = 'WladmirJunior/dotfiles'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

# --------------------------------------------------------------------------
#  Output helpers (no gum; plain colored Write-Host, mirrors lib/ui.sh intent)
# --------------------------------------------------------------------------
function Write-Section { param([string]$Text) Write-Host "`n=== $Text ===" -ForegroundColor Cyan }
function Write-Step    { param([string]$Text) Write-Host "  - $Text" -ForegroundColor White }
function Write-Ok      { param([string]$Text) Write-Host "  OK $Text" -ForegroundColor Green }
function Write-Note    { param([string]$Text) Write-Host "  .. $Text" -ForegroundColor DarkGray }
function Write-Warn2   { param([string]$Text) Write-Host "  !! $Text" -ForegroundColor Yellow }

# --------------------------------------------------------------------------
#  Phase 0 - guards and detection
# --------------------------------------------------------------------------
if (-not $IsWindows) {
    throw 'install.ps1 is Windows-only. On macOS/Linux use install.sh.'
}
if ($PSVersionTable.PSVersion.Major -lt 7) {
    throw 'PowerShell 7+ is required. Install it: winget install --id Microsoft.PowerShell'
}

$DotfilesDir = Join-Path $HOME '.dotfiles'

# Resolve where this script lives. Run via `iwr | iex` there is no $PSCommandPath:
# self-fetch into ~/.dotfiles and re-exec from there.
function Get-RepoRoot {
    if ($PSCommandPath) {
        return (Split-Path -Parent $PSCommandPath)
    }
    return $null
}

function Initialize-Clone {
    param([string]$Target, [string]$RepoSlug)

    if (Test-Path (Join-Path $Target '.git')) {
        Write-Note "repo already at $Target"
        return
    }
    if (Test-Path $Target) {
        throw "$Target exists but is not a git checkout. Move it aside and retry."
    }
    if (Get-Command git -ErrorAction SilentlyContinue) {
        Write-Step "cloning $RepoSlug -> $Target"
        git clone "https://github.com/$RepoSlug.git" $Target
        if ($LASTEXITCODE -ne 0) { throw "git clone failed" }
        return
    }
    # No git yet: download the source tarball (mirrors install.sh 96-125).
    Write-Step "git not found; downloading $RepoSlug tarball"
    $zip = Join-Path $env:TEMP "dotfiles-$([guid]::NewGuid().ToString('N')).zip"
    Invoke-WebRequest "https://codeload.github.com/$RepoSlug/zip/refs/heads/main" -OutFile $zip
    $tmp = Join-Path $env:TEMP "dotfiles-x-$([guid]::NewGuid().ToString('N'))"
    Expand-Archive -Path $zip -DestinationPath $tmp -Force
    $inner = Get-ChildItem $tmp -Directory | Select-Object -First 1
    Move-Item $inner.FullName $Target
    Remove-Item $zip, $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

$repoRoot = Get-RepoRoot
if (-not $repoRoot) {
    # Bootstrapped via iex.
    Initialize-Clone -Target $DotfilesDir -RepoSlug $Repo
    & (Join-Path $DotfilesDir 'install.ps1') @PSBoundParameters
    return
}
if ($repoRoot -ne $DotfilesDir) {
    # Relocating is a real side effect, so honour -WhatIf: report it and keep
    # checking from the current checkout instead. A dry run from an arbitrary
    # path (CI checks out to its own workspace) must not move the running
    # script out from under itself.
    if ($WhatIfPreference) {
        Write-Note "would move this clone from $repoRoot to $DotfilesDir"
        Write-Note "continuing the dry run from $repoRoot"
        $DotfilesDir = $repoRoot
    }
    else {
        if (Test-Path $DotfilesDir) {
            throw "This clone is at $repoRoot but $DotfilesDir already exists. Remove one."
        }
        Write-Step "moving clone from $repoRoot to $DotfilesDir"
        Move-Item $repoRoot $DotfilesDir
        & (Join-Path $DotfilesDir 'install.ps1') @PSBoundParameters
        return
    }
}

Write-Section "dotfiles - Windows native setup"
Write-Note "repo: $DotfilesDir"

$hasWinget = [bool](Get-Command winget -ErrorAction SilentlyContinue)
if (-not $hasWinget) {
    Write-Warn2 "winget not found. Install 'App Installer' from the Microsoft Store, then re-run for phase 1."
}

# --------------------------------------------------------------------------
#  Phase 1 - packages (winget)
# --------------------------------------------------------------------------
# capability -> [winget id, binary that proves it is installed]
$Packages = [ordered]@{
    git            = @('Git.Git',                'git')
    editor         = @('Neovim.Neovim',          'nvim')
    'fuzzy-finder' = @('junegunn.fzf',           'fzf')
    'dir-jump'     = @('ajeetdsouza.zoxide',     'zoxide')
    'enhanced-ls'  = @('eza-community.eza',      'eza')
    'file-viewer'  = @('sharkdp.bat',            'bat')
    'text-search'  = @('BurntSushi.ripgrep.MSVC','rg')
    'file-find'    = @('sharkdp.fd',             'fd')
    'git-diff'     = @('dandavison.delta',       'delta')
    'node-runtime' = @('OpenJS.NodeJS.LTS',      'node')
    'github-cli'   = @('GitHub.cli',             'gh')
    'system-info'  = @('Fastfetch-cli.Fastfetch','fastfetch')
    json           = @('jqlang.jq',              'jq')
    archive        = @('7zip.7zip',              '7z')
    'manual-pages' = @('tldr-pages.tlrc',        'tldr')
}

function Install-WingetPackage {
    [CmdletBinding(SupportsShouldProcess)]
    param([string]$Id, [string]$Binary)

    if (Get-Command $Binary -ErrorAction SilentlyContinue) {
        Write-Note "$Binary already installed"
        return
    }
    if (-not $PSCmdlet.ShouldProcess($Id, 'winget install')) { return }

    # winget can hang without a console; cap it and keep going on failure.
    $job = Start-Job -ScriptBlock {
        winget install --id $using:Id --exact --silent --disable-interactivity `
            --accept-package-agreements --accept-source-agreements 2>&1 | Out-String
    }

    if (Wait-Job $job -Timeout 300) {
        $out = Receive-Job $job
        Remove-Job $job
        if (Get-Command $Binary -ErrorAction SilentlyContinue) {
            Write-Ok "$Binary ($Id)"
        }
        elseif ($out -match 'No package found|No installer|not found') {
            Write-Warn2 "$Id not in winget; install $Binary manually"
        }
        else {
            Write-Ok "$Id installed (open a new shell for '$Binary' on PATH)"
        }
    }
    else {
        Stop-Job $job; Remove-Job $job -Force
        Write-Warn2 "$Id install timed out; skipping"
    }
}

function Install-Yazi {
    # yazi has no stable winget package. Install the verified official Windows
    # release into ~/.local/bin, mirroring scripts/install-github-release.sh:
    # pick the asset from the latest release, check its published SHA-256, extract.
    [CmdletBinding(SupportsShouldProcess)]
    param()

    $binDir = Join-Path $HOME '.local\bin'
    if ((Get-Command yazi -ErrorAction SilentlyContinue) -or
        (Test-Path (Join-Path $binDir 'yazi.exe'))) {
        Write-Note "yazi already installed"
        return
    }
    if (-not $PSCmdlet.ShouldProcess('sxyazi/yazi', 'download verified release')) { return }

    $asset = 'yazi-x86_64-pc-windows-msvc.zip'
    try {
        $rel = Invoke-RestMethod 'https://api.github.com/repos/sxyazi/yazi/releases/latest' `
            -Headers @{ 'User-Agent' = 'dotfiles-install' } -ErrorAction Stop
        $a = @($rel.assets | Where-Object name -EQ $asset)
        if ($a.Count -ne 1) { throw "expected one $asset asset, found $($a.Count)" }
        $digest = "$($a[0].digest)"
        if (-not $digest.StartsWith('sha256:')) { throw "release asset has no SHA-256 digest" }
        $expected = $digest.Substring(7)
        $url = $a[0].browser_download_url
        if ($url -notlike 'https://github.com/sxyazi/yazi/releases/download/*') {
            throw "unexpected download URL: $url"
        }

        $tmp = Join-Path $env:TEMP "yazi-$([guid]::NewGuid().ToString('N'))"
        New-Item -ItemType Directory -Path $tmp -Force | Out-Null
        $zip = Join-Path $tmp $asset
        Write-Step "downloading yazi $($rel.tag_name)"
        Invoke-WebRequest $url -OutFile $zip -ErrorAction Stop

        $actual = (Get-FileHash $zip -Algorithm SHA256).Hash.ToLower()
        if ($actual -ne $expected.ToLower()) { throw "SHA-256 mismatch for $asset" }

        Expand-Archive -Path $zip -DestinationPath $tmp -Force
        New-Item -ItemType Directory -Path $binDir -Force | Out-Null
        Get-ChildItem $tmp -Recurse -Include 'yazi.exe', 'ya.exe' |
            ForEach-Object { Copy-Item $_.FullName (Join-Path $binDir $_.Name) -Force }
        Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue

        if (Test-Path (Join-Path $binDir 'yazi.exe')) {
            Write-Ok "yazi $($rel.tag_name) at $binDir"
        }
        else {
            Write-Warn2 "yazi archive had no yazi.exe; layout changed?"
        }
    }
    catch {
        Write-Warn2 "yazi install failed: $_"
    }
}

if ($SkipPackages) {
    Write-Section "packages (skipped)"
}
elseif (-not $hasWinget) {
    Write-Section "packages (skipped - winget missing)"
}
else {
    Write-Section "packages (winget)"
    foreach ($cap in $Packages.Keys) {
        $id, $bin = $Packages[$cap]
        Install-WingetPackage -Id $id -Binary $bin
    }
    Install-Yazi
    Write-Note "gum is not ported (installer UI); install manually if wanted (see windows/README.md)"
    # Append the persisted Machine/User PATH so later phases see freshly
    # installed tools, without dropping entries only this process has.
    $persisted = @(
        [Environment]::GetEnvironmentVariable('PATH', 'Machine')
        [Environment]::GetEnvironmentVariable('PATH', 'User')
    ) -join ';'
    $current = $env:PATH -split ';'
    foreach ($p in $persisted -split ';') {
        if ($p -and $current -notcontains $p) { $env:PATH += ";$p" }
    }
}

# --------------------------------------------------------------------------
#  Phase 2 - dotfiles (symlinks)
# --------------------------------------------------------------------------
function New-DotfilesLink {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$Target,
        [Parameter(Mandatory)][string]$Link
    )

    if (-not (Test-Path $Target)) {
        Write-Warn2 "target missing, skipping: $Target"
        return
    }
    $parent = Split-Path -Parent $Link
    if (-not (Test-Path $parent)) {
        if ($PSCmdlet.ShouldProcess($parent, 'create directory')) {
            New-Item -ItemType Directory -Path $parent -Force | Out-Null
        }
    }

    $existing = Get-Item $Link -Force -ErrorAction SilentlyContinue
    if ($existing) {
        if ($existing.LinkType -eq 'SymbolicLink' -and $existing.Target -eq $Target) {
            Write-Note "link ok: $Link"
            return
        }
        $bak = "$Link.bak-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
        if ($PSCmdlet.ShouldProcess($Link, "back up to $bak")) {
            Move-Item $Link $bak
            Write-Note "backed up existing $Link -> $bak"
        }
    }

    if (-not $PSCmdlet.ShouldProcess($Link, "symlink -> $Target")) { return }
    try {
        New-Item -ItemType SymbolicLink -Path $Link -Target $Target -Force -ErrorAction Stop | Out-Null
        Write-Ok "linked $Link"
    }
    catch {
        Copy-Item $Target $Link -Force
        Write-Warn2 "symlink failed (enable Developer Mode); copied a static file to $Link"
    }
}

Write-Section "dotfiles"
$nvimDir = Join-Path $env:LOCALAPPDATA 'nvim'
New-DotfilesLink -Target (Join-Path $DotfilesDir 'config\nvim\init.lua')       -Link (Join-Path $nvimDir 'init.lua')
New-DotfilesLink -Target (Join-Path $DotfilesDir 'config\nvim\lazy-lock.json') -Link (Join-Path $nvimDir 'lazy-lock.json')

# git-delta config: cp-style via include.path (mirrors 03-dotfiles.sh 95-132).
$deltaSrc  = Join-Path $DotfilesDir 'config\git\gitconfig'
$deltaDest = Join-Path $HOME '.gitconfig.delta'
if (Test-Path $deltaSrc) {
    if ($PSCmdlet.ShouldProcess($deltaDest, 'copy git-delta config')) {
        if ((Test-Path $deltaDest) -and -not (Get-Item $deltaDest).PSIsContainer) {
            $same = (Get-FileHash $deltaSrc).Hash -eq (Get-FileHash $deltaDest).Hash
            if (-not $same) {
                Copy-Item $deltaDest "$deltaDest.bak-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
            }
        }
        Copy-Item $deltaSrc $deltaDest -Force
        Write-Ok "git-delta config at $deltaDest"
    }
    if (Get-Command git -ErrorAction SilentlyContinue) {
        $includes = (git config --global --get-all include.path 2>$null)
        $deltaFwd = $deltaDest -replace '\\', '/'
        if ($includes -notcontains $deltaFwd) {
            if ($PSCmdlet.ShouldProcess('git config --global include.path', 'add')) {
                git config --global include.path $deltaFwd
            }
        }
        if ($PSCmdlet.ShouldProcess('git config --global core.symlinks', 'set true')) {
            git config --global core.symlinks true
        }
    }
}

if (Get-Command git -ErrorAction SilentlyContinue) {
    # Git for Windows ships its own MSYS2 OpenSSH and prefers it over the
    # one on PATH. That build cannot talk to the 1Password named pipe, so
    # `ssh -T git@github.com` authenticates while `git clone` fails with
    # "Permission denied (publickey)". Point git at the system ssh.exe,
    # which does speak the pipe. Forward slashes are required: git hands
    # this value to an MSYS-style shell that strips backslashes.
    $sysSsh = Join-Path $env:WINDIR 'System32\OpenSSH\ssh.exe'
    if (Test-Path $sysSsh) {
        $sysSshFwd = $sysSsh -replace '\\', '/'
        if ((git config --global core.sshCommand 2>$null) -ne $sysSshFwd) {
            if ($PSCmdlet.ShouldProcess('git config --global core.sshCommand', 'set')) {
                git config --global core.sshCommand $sysSshFwd
                Write-Ok "git will use the Windows OpenSSH (1Password agent)"
            }
        }
    }
    else {
        Write-Warn2 "Windows OpenSSH not found; git over SSH may not reach the 1Password agent."
    }
}

$devDir = Join-Path $HOME 'dev'
if (-not (Test-Path $devDir)) {
    if ($PSCmdlet.ShouldProcess($devDir, 'create')) {
        New-Item -ItemType Directory -Path $devDir -Force | Out-Null
        Write-Ok "created $devDir"
    }
}

# --------------------------------------------------------------------------
#  Phase 3 - shell (pwsh profile)
# --------------------------------------------------------------------------
Write-Section "shell (pwsh profile)"
New-DotfilesLink -Target (Join-Path $DotfilesDir 'windows\profile.ps1') -Link $PROFILE.CurrentUserCurrentHost

# Keep new Windows Terminal tabs predictable. Without an explicit starting
# directory, launches can inherit the installer's working directory.
function Set-WindowsTerminalDefault {
    [CmdletBinding(SupportsShouldProcess)]
    param()

    $settingsPaths = @(
        (Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json'),
        (Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json'),
        (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows Terminal\settings.json')
    )
    $pwshGuid = '{574e775e-4f2a-5b96-ac1e-a2962a402336}'

    foreach ($settingsPath in $settingsPaths) {
        if (-not (Test-Path $settingsPath)) { continue }
        $settings = Get-Content -Raw $settingsPath | ConvertFrom-Json
        $startProperty = $settings.profiles.defaults.PSObject.Properties['startingDirectory']
        $currentStart = if ($startProperty) { $startProperty.Value } else { $null }
        if ($settings.defaultProfile -eq $pwshGuid -and $currentStart -eq '%USERPROFILE%') {
            Write-Note "Windows Terminal defaults already configured"
            continue
        }
        if (-not $PSCmdlet.ShouldProcess($settingsPath, 'set PowerShell 7 and %USERPROFILE% as defaults')) {
            continue
        }
        Copy-Item $settingsPath "$settingsPath.bak-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
        $settings.defaultProfile = $pwshGuid
        if (-not $settings.profiles.defaults.PSObject.Properties['startingDirectory']) {
            $settings.profiles.defaults | Add-Member -NotePropertyName startingDirectory -NotePropertyValue '%USERPROFILE%'
        }
        else {
            $settings.profiles.defaults.startingDirectory = '%USERPROFILE%'
        }
        $json = $settings | ConvertTo-Json -Depth 100
        [IO.File]::WriteAllText($settingsPath, "$json`n", [Text.UTF8Encoding]::new($false))
        Write-Ok "Windows Terminal starts PowerShell 7 in %USERPROFILE%"
    }
}

Set-WindowsTerminalDefault

# --------------------------------------------------------------------------
#  Phase 4 - 1Password SSH agent + gh
# --------------------------------------------------------------------------
function Invoke-AuthPhase {
    [CmdletBinding(SupportsShouldProcess)]
    param()

    Write-Section "connect and authenticate (1Password, SSH, gh)"

    # Detect the desktop app by its WindowsApps install dir (Get-AppxPackage
    # pulls in a compat shim that floods -WhatIf output with alias noise).
    $opApp = [bool](Get-ChildItem "$env:ProgramFiles\WindowsApps" -Filter 'AgileBits.1Password_*' `
            -Directory -ErrorAction SilentlyContinue)
    if (-not $opApp -and $hasWinget) {
        if ($PSCmdlet.ShouldProcess('AgileBits.1Password', 'winget install')) {
            winget install --id AgileBits.1Password --exact --silent `
                --accept-package-agreements --accept-source-agreements 2>&1 | Out-Null
        }
    }

    Write-Step "In the 1Password app:"
    Write-Host "     1. Settings > Developer > enable 'Use the SSH agent'"
    Write-Host "     2. Settings > Developer > enable 'Integrate with 1Password CLI'"
    if (-not $WhatIfPreference) { Read-Host "     Press Enter when done" | Out-Null }

    # The Windows OpenSSH ssh-agent service must not own the named pipe or
    # 1Password cannot bind it. Disabling the service needs admin, so instruct
    # rather than elevate.
    $svc = Get-Service ssh-agent -ErrorAction SilentlyContinue
    if ($svc -and $svc.Status -eq 'Running') {
        Write-Warn2 "The Windows ssh-agent service is running and will shadow 1Password."
        Write-Host  "     Run this ONCE in an elevated PowerShell:"
        Write-Host  "       Stop-Service ssh-agent; Set-Service ssh-agent -StartupType Disabled"
    }

    $pipe = Test-Path '\\.\pipe\openssh-ssh-agent'
    if ($pipe) {
        $keys = ssh-add -l 2>&1 | Out-String
        if ($keys -match 'SHA256:') {
            Write-Ok "1Password SSH agent is exposing keys"
        }
        else {
            Write-Warn2 "SSH agent pipe exists but no keys yet; unlock 1Password."
        }
    }
    else {
        Write-Warn2 "No SSH agent pipe. Enable the 1Password SSH agent and reopen this shell."
    }

    # gh auth via 1Password. `op plugin` (the shell-plugin mechanism used by
    # install.sh on macOS/Linux) is not supported on Windows
    # (1Password/shell-plugins#403). Instead, resolve a GitHub PAT from the
    # vault into $env:GH_TOKEN at shell start: gh reads GH_TOKEN before any
    # on-disk config, so nothing is written to ~/.config/gh/hosts.yml.
    if (Get-Command op -ErrorAction SilentlyContinue) {
        $localProfile = Join-Path $HOME '.pwsh_profile.local.ps1'
        $marker = 'GH_TOKEN'
        if ((Test-Path $localProfile) -and
            (Select-String -Path $localProfile -SimpleMatch $marker -Quiet)) {
            Write-Note "GH_TOKEN wiring already in ~/.pwsh_profile.local.ps1"
        }
        elseif ($WhatIfPreference) {
            Write-Note "would prompt for a GitHub PAT secret reference and wire GH_TOKEN"
        }
        else {
            $ref = Read-Host "1Password secret reference for the GitHub PAT (blank to skip)"
            if ($ref) {
                if (-not ($ref -like 'op://*')) {
                    Write-Warn2 "expected an op://Vault/Item/field reference; skipping"
                }
                elseif ($PSCmdlet.ShouldProcess($localProfile, 'add GH_TOKEN wiring')) {
                    # Resolve the PAT lazily. Calling `op read` at profile load
                    # makes 1Password prompt for authentication in EVERY new
                    # shell; a wrapper defers it to the first actual gh call.
                    $block = @(
                        ''
                        '# gh authenticates via a GitHub PAT read from 1Password (no token on disk).'
                        '# Resolved on first use, not at shell start, so opening a terminal'
                        '# never triggers a 1Password prompt.'
                        "`$script:GhTokenRef = '$ref'"
                        'function gh {'
                        '    if (-not $env:GH_TOKEN) {'
                        '        $env:GH_TOKEN = (op read $script:GhTokenRef 2>$null)'
                        '    }'
                        '    & (Get-Command gh.exe -CommandType Application | Select-Object -First 1) @args'
                        '}'
                    )
                    Add-Content $localProfile $block
                    Write-Ok "GH_TOKEN wired into ~/.pwsh_profile.local.ps1 (resolved on first gh use)"
                }
            }
            else {
                Write-Note "skipped gh wiring; add it later to ~/.pwsh_profile.local.ps1:"
                Write-Host  '       function gh { if (-not $env:GH_TOKEN) { $env:GH_TOKEN = (op read "op://<vault>/<item>/<field>" 2>$null) }; & (Get-Command gh.exe -CommandType Application | Select-Object -First 1) @args }'
            }
        }
        $ghHosts = Join-Path $HOME '.config\gh\hosts.yml'
        Remove-Item $ghHosts -ErrorAction SilentlyContinue   # no on-disk gh creds
    }
    else {
        Write-Warn2 "op CLI not found; install it (winget install AgileBits.1Password.CLI)"
    }

    Write-Note "sonus and ai-cli-configs stay macOS/Linux only; not applied here."
}

# --------------------------------------------------------------------------
#  Phase 5: private overlay
# --------------------------------------------------------------------------
# Mirrors apply_private_overlay() in install.sh: the overlay repo name comes
# from the 1Password bootstrap note, so no private repo name is hardcoded in
# this public repository. Cloning uses git over SSH, which relies on the
# 1Password SSH agent rather than the PAT.
function Invoke-PrivateOverlayPhase {
    [CmdletBinding(SupportsShouldProcess)]
    param()

    Write-Section "private overlay"

    if (-not (Get-Command op -ErrorAction SilentlyContinue)) {
        Write-Warn2 "op CLI not available; skipping the private overlay."
        return
    }

    if ($WhatIfPreference) {
        Write-Note "would read private_repo from 1Password, then clone and run the overlay"
        return
    }

    $privateRepo = (op item get dotfiles-bootstrap --vault Private `
            --fields private_repo 2>$null)
    if (-not $privateRepo) {
        Write-Warn2 "could not read private_repo from the 1Password bootstrap note; skipping."
        return
    }
    $privateRepo = $privateRepo.Trim()

    $leaf = [System.IO.Path]::GetFileNameWithoutExtension($privateRepo)
    $privateDir = Join-Path $HOME ".$leaf"

    if (Test-Path (Join-Path $privateDir '.git')) {
        if ($PSCmdlet.ShouldProcess($privateDir, 'git pull --ff-only')) {
            git -C $privateDir pull --ff-only
            if ($LASTEXITCODE -ne 0) { Write-Warn2 "pull failed in $privateDir"; return }
            Write-Ok "updated $privateDir"
        }
    }
    elseif ($PSCmdlet.ShouldProcess($privateDir, 'git clone')) {
        # Fail fast when the agent cannot authenticate, instead of letting the
        # clone fail with a misleading error.
        $probe = (ssh -o BatchMode=yes -o ConnectTimeout=15 -T git@github.com 2>&1 | Out-String)
        if ($probe -notmatch 'successfully authenticated') {
            Write-Warn2 "GitHub did not accept any key from the 1Password SSH agent."
            Write-Host  "     Unlock 1Password, enable its SSH agent, and rerun."
            return
        }
        git clone "git@github.com:$privateRepo.git" $privateDir
        if ($LASTEXITCODE -ne 0) { Write-Warn2 "clone failed"; return }
        Write-Ok "cloned $privateRepo into $privateDir"
    }

    $privateInstaller = Join-Path $privateDir 'install.ps1'
    if (-not (Test-Path $privateInstaller)) {
        Write-Note "no install.ps1 in the overlay; nothing further to run."
        return
    }
    if ($PSCmdlet.ShouldProcess($privateInstaller, 'run private installer')) {
        & pwsh -NoProfile -File $privateInstaller
    }
}

if ($SkipAuth) {
    Write-Section "connect and authenticate (skipped)"
}
else {
    Invoke-AuthPhase
}

if ($SkipPrivate) {
    Write-Section "private overlay (skipped)"
}
else {
    Invoke-PrivateOverlayPhase
}


# --------------------------------------------------------------------------
#  Verify
# --------------------------------------------------------------------------
if ($WhatIfPreference) {
    Write-Section "verify (skipped under -WhatIf)"
    Write-Host "`nDry run complete. Nothing was changed." -ForegroundColor Cyan
    return
}

Write-Section "verify"
$fails = 0
foreach ($bin in 'git', 'nvim', 'pwsh') {
    if (Get-Command $bin -ErrorAction SilentlyContinue) { Write-Ok "$bin on PATH" }
    else { Write-Warn2 "$bin not found"; $fails++ }
}
$prof = Get-Item $PROFILE.CurrentUserCurrentHost -Force -ErrorAction SilentlyContinue
if ($prof -and $prof.LinkType -eq 'SymbolicLink') { Write-Ok "pwsh profile is a symlink" }
elseif ($prof) { Write-Note "pwsh profile exists (static copy)" }
else { Write-Warn2 "pwsh profile missing"; $fails++ }

if (Test-Path (Join-Path $HOME '.gitconfig.delta')) { Write-Ok "~/.gitconfig.delta present" }

if ($fails -eq 0) { Write-Host "`nAll checks passed." -ForegroundColor Green }
else { Write-Host "`n$fails check(s) failed (see above)." -ForegroundColor Yellow }

Write-Host "`nReopen PowerShell to load the new profile." -ForegroundColor Cyan
