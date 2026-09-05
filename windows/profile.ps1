# Managed by dotfiles. Symlinked to $PROFILE.CurrentUserCurrentHost by install.ps1.
# Windows / PowerShell 7 counterpart of config/zsh/zshrc. Machine-local overrides
# go in ~/.pwsh_profile.local.ps1 (not versioned), sourced at the end.

# --------------------------------- PATH ---------------------------------
$localBin = Join-Path $HOME '.local\bin'
if (Test-Path $localBin) {
    if (($env:PATH -split ';') -notcontains $localBin) {
        $env:PATH = "$localBin;$env:PATH"
    }
}

$env:EDITOR = 'nvim'
$env:VISUAL = 'nvim'

# ---------------------------- Modern unix tools ------------------------------
function v  { nvim @args }
function vi { nvim @args }

if (Get-Command eza -ErrorAction SilentlyContinue) {
    function ls { eza --icons --git --group-directories-first @args }
    function ll { eza -l --icons --git --group-directories-first @args }
    function la { eza -a --icons --git --group-directories-first @args }
    function lt { eza --tree --icons @args }
}
if (Get-Command tldr -ErrorAction SilentlyContinue) {
    function help { tldr @args }
}

# Yazi that returns its final directory to the shell (like the zshrc `y`).
if (Get-Command yazi -ErrorAction SilentlyContinue) {
    function y {
        $tmp = New-TemporaryFile
        try {
            yazi @args --cwd-file="$tmp"
            $cwd = Get-Content -Raw $tmp -ErrorAction SilentlyContinue
            if ($cwd -and $cwd.Trim() -and $cwd.Trim() -ne $PWD.Path) {
                Set-Location $cwd.Trim()
            }
        }
        finally { Remove-Item $tmp -Force -ErrorAction SilentlyContinue }
    }
}

# ----------------------------------- Git ------------------------------------
function gst   { git status @args }
function ga    { git add @args }
function gaa   { git add --all @args }
function gcmsg { git commit -m @args }
function gp    { git push @args }
function gpf   { git push --force-with-lease @args }
function gl    { git pull @args }
function gd    { git diff @args }
function gds   { git diff --staged @args }
function gb    { git branch @args }
function gco   { git checkout @args }
function gsw   { git switch @args }
function gswc  { git switch -c @args }
function grs   { git restore @args }
function grss  { git restore --staged @args }
function gsr   { git remote -v @args }
function glg   { git log --oneline --graph --decorate @args }
function gfa   { git fetch --all --prune @args }
function Get-CurrentBranch { git rev-parse --abbrev-ref HEAD 2>$null }
function ggpull { git pull origin (Get-CurrentBranch) }
function ggpush { git push origin (Get-CurrentBranch) }

# -------------------------------- Navigation --------------------------------
function .. { Set-Location .. }
function ... { Set-Location ..\.. }

# ----------------------------------- fzf ------------------------------------
$env:FZF_DEFAULT_OPTS = '--height 50% --layout=reverse --border --info=inline'
# PSFzf (Ctrl-R / Ctrl-T bindings) is optional; see windows/README.md.
if (Get-Module -ListAvailable -Name PSFzf) {
    Import-Module PSFzf -ErrorAction SilentlyContinue
    Set-PSFzfOption -PSReadlineChordProvider 'Ctrl+t' -PSReadlineChordReverseHistory 'Ctrl+r' -ErrorAction SilentlyContinue
}

# --------------------------------- zoxide -----------------------------------
# zoxide's only supported PowerShell hook is `iex` on its init output.
if (Get-Command zoxide -ErrorAction SilentlyContinue) {
    $zoxideInit = (zoxide init powershell | Out-String)
    . ([ScriptBlock]::Create($zoxideInit))
}

# -------------------------------- PSReadLine --------------------------------
if (Get-Module -ListAvailable -Name PSReadLine) {
    Set-PSReadLineOption -HistoryNoDuplicates -ErrorAction SilentlyContinue
    if ($Host.UI.SupportsVirtualTerminal -and -not [Console]::IsOutputRedirected) {
        Set-PSReadLineOption -PredictionSource History -PredictionViewStyle ListView -ErrorAction SilentlyContinue
    }
    Set-PSReadLineKeyHandler -Key Tab -Function MenuComplete
}

# --------------------------------- Prompt -----------------------------------
# Enxuto, com o branch git como o vcs_info do zshrc.
function prompt {
    $lastOk = $?
    $arrow  = if ($lastOk) { "`e[32m>`e[0m" } else { "`e[31m>`e[0m" }
    $cwd    = Split-Path -Leaf (Get-Location)
    $branch = git rev-parse --abbrev-ref HEAD 2>$null
    $git    = if ($branch) { " `e[34mgit:(`e[31m$branch`e[34m)`e[0m" } else { '' }
    "$arrow `e[36m$cwd`e[0m$git "
}

# ---------------------------- Local overlay (optional) ----------------------
$localProfile = Join-Path $HOME '.pwsh_profile.local.ps1'
if (Test-Path $localProfile) { . $localProfile }
