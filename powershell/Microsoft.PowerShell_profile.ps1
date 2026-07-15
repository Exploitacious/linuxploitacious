# PowerShell Profile -- linuxploitacious
# github.com/Exploitacious/linuxploitacious

# --- Encoding (UTF-8 for Nerd Font glyphs + OMP icons) ---
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding  = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

# --- Oh My Posh ---
# Prefer repo-controlled theme (deployed via symlink), fall back to OMP cache
$ompTheme = Join-Path $env:USERPROFILE '.config\ohmyposh\catppuccin_mocha.omp.json'
if (-not (Test-Path $ompTheme) -and $env:POSH_THEMES_PATH) {
    $ompTheme = Join-Path $env:POSH_THEMES_PATH 'catppuccin_mocha.omp.json'
}
if ((Get-Command oh-my-posh -ErrorAction SilentlyContinue) -and (Test-Path $ompTheme)) {
    oh-my-posh init pwsh --config $ompTheme | Invoke-Expression
}

# --- PSReadLine ---
# Prediction features require VT-capable interactive console (fail silently when piped/redirected)
if ([Environment]::UserInteractive -and -not [Console]::IsOutputRedirected) {
    Set-PSReadLineOption -PredictionSource History
    Set-PSReadLineOption -PredictionViewStyle ListView
}
Set-PSReadLineOption -EditMode Windows
Set-PSReadLineOption -HistorySearchCursorMovesToEnd
Set-PSReadLineKeyHandler -Key UpArrow -Function HistorySearchBackward
Set-PSReadLineKeyHandler -Key DownArrow -Function HistorySearchForward
Set-PSReadLineKeyHandler -Key Tab -Function MenuComplete
Set-PSReadLineKeyHandler -Key Ctrl+d -Function DeleteCharOrExit

# --- Navigation & Shell ---
function c { Clear-Host }
function x { exit }
function .. { Set-Location .. }
function ... { Set-Location ..\.. }
function e { notepad $PROFILE }
function r { . $PROFILE; Write-Host '[+] Profile reloaded' -ForegroundColor Green }
function h { Get-History | Select-Object -Last 20 }
function which ($cmd) { (Get-Command $cmd -ErrorAction SilentlyContinue).Source }

# --- ls Aliases (closer to Unix ls -lFh) ---
function ll {
    Get-ChildItem -Force @args |
        Format-Table Mode, LastWriteTime, @{N='Size';E={
            if ($_.PSIsContainer) { '<DIR>' }
            elseif ($_.Length -ge 1GB) { '{0:N1} GB' -f ($_.Length / 1GB) }
            elseif ($_.Length -ge 1MB) { '{0:N1} MB' -f ($_.Length / 1MB) }
            elseif ($_.Length -ge 1KB) { '{0:N1} KB' -f ($_.Length / 1KB) }
            else { "$($_.Length) B" }
        };Width=10}, Name -AutoSize
}
function la { Get-ChildItem -Force -Hidden @args }

# --- Network ---
function myip { (Invoke-RestMethod http://ipecho.net/plain).Trim() }

# --- Git Shortcuts ---
function gs { git status @args }
function gp { git pull @args }
function gd { git diff @args }
function gl { git log --oneline -20 @args }
function gcu {
    git config user.name 'Alex Ivantsov'
    git config user.email 'alex@ivantsov.tech'
}

# --- Fastfetch on Launch ---
if (Get-Command fastfetch -ErrorAction SilentlyContinue) { fastfetch }

# --- Machine-local overrides (untracked seam; mirrors ~/.<shell>rc.local) ---
# Host-specific content — COWORK deploy.ps1's clawd launcher + WORKFORCE/bin
# PATH, and third-party tools like Intelligent Terminal — is written to the
# untracked profile.local.ps1 beside this file, NEVER into this tracked public
# profile. Sourced last so local definitions win; silent no-op when absent.
$__localProfile = Join-Path (Split-Path -Parent $PROFILE) 'profile.local.ps1'
if (Test-Path -LiteralPath $__localProfile) { . $__localProfile }
Remove-Variable __localProfile -ErrorAction SilentlyContinue
