<#
.SYNOPSIS
    Windows Shell Setup — mirrors shellSetup.sh for Linux.
.DESCRIPTION
    Deploys a fully configured PowerShell + WezTerm environment on Windows.
    Idempotent — safe to re-run. Existing configs backed up automatically.
.NOTES
    Created by Alex Ivantsov @Exploitacious
    One-liner: irm https://raw.githubusercontent.com/Exploitacious/linuxploitacious/master/winSetup.ps1 | iex
#>

# ═══════════════════════════════════════════════════════════════════════════════
#  FORMATTING
# ═══════════════════════════════════════════════════════════════════════════════

function Write-Info    { param([string]$Message) Write-Host "[*] $Message" -ForegroundColor Blue }
function Write-Success { param([string]$Message) Write-Host "[+] $Message" -ForegroundColor Green }
function Write-Warn    { param([string]$Message) Write-Host "[!] $Message" -ForegroundColor Yellow }
function Write-Err     { param([string]$Message) Write-Host "[x] $Message" -ForegroundColor Red }
function Write-Header  { param([string]$Message) Write-Host "`n=== $Message ===" -ForegroundColor Cyan }

# ═══════════════════════════════════════════════════════════════════════════════
#  ASCII ART HEADER
# ═══════════════════════════════════════════════════════════════════════════════

Clear-Host
Write-Host @"

   __    _                 _       _ _
  / /   (_)_ __  _   ___  | |_ ___(_) |_
 / /    | | '_ \| | | \ \/ / '_ \ | __|
/ /___  | | | | | |_| |>  <| |_) | | |_
\____/  |_|_| |_|\__,_/_/\_\ .__/|_|\__|
                           |_|
   Windows Shell Setup - @Exploitacious

"@ -ForegroundColor Cyan

# ═══════════════════════════════════════════════════════════════════════════════
#  BOOTSTRAP — REMOTE EXECUTION DETECTION
# ═══════════════════════════════════════════════════════════════════════════════

$ScriptPath = $MyInvocation.MyCommand.Path
$RepoDir = if ($ScriptPath) { Split-Path $ScriptPath -Parent } else { $null }
$IsRemote = -not $RepoDir -or -not (Test-Path (Join-Path $RepoDir '.git') -ErrorAction SilentlyContinue)

if ($IsRemote) {
    Write-Info 'Remote execution detected. Bootstrapping environment...'

    # Validate winget
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Write-Err 'winget not found. Install App Installer from the Microsoft Store.'
        return
    }

    # Install Git if missing
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        Write-Warn 'Git missing. Installing via winget...'
        winget install --id Git.Git -e --accept-package-agreements --accept-source-agreements
        # Refresh PATH
        $env:Path = [System.Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' +
                     [System.Environment]::GetEnvironmentVariable('Path', 'User')

        if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
            Write-Err 'Git install failed. Install manually and re-run.'
            return
        }
    }

    # Configure Git identity if not set
    $gitName  = git config --global user.name 2>$null
    $gitEmail = git config --global user.email 2>$null
    if ($gitName -and $gitEmail) {
        Write-Info "Git identity: $gitName <$gitEmail>"
    } else {
        Write-Header 'Configuring Git Identity'
        $name  = Read-Host '  Git User Name'
        $email = Read-Host '  Git Email'
        if ($name -and $email) {
            git config --global user.name $name
            git config --global user.email $email
            Write-Success "Git identity set: $name <$email>"
        } else {
            Write-Warn 'Git identity not set — configure before committing.'
        }
    }

    # Clone or update repo
    $TargetDir = Join-Path $env:USERPROFILE 'linuxploitacious'
    if (-not (Test-Path $TargetDir)) {
        Write-Info "Cloning repository to $TargetDir..."
        git clone https://github.com/Exploitacious/linuxploitacious.git $TargetDir
    } else {
        Write-Warn "Directory exists. Pulling latest..."
        Push-Location $TargetDir
        git pull --ff-only
        Pop-Location
    }

    # Handoff to local copy
    Write-Info 'Handing off to local repository execution...'
    & (Join-Path $TargetDir 'winSetup.ps1')
    return
}

# ═══════════════════════════════════════════════════════════════════════════════
#  LOCAL EXECUTION
# ═══════════════════════════════════════════════════════════════════════════════

Set-Location $RepoDir

# --- Auto-sync with upstream ---
$dirty = git status --porcelain 2>$null
if ($dirty) {
    Write-Warn 'Working tree has uncommitted changes — skipping auto-pull.'
    Write-Warn 'Commit/stash and re-run to sync with upstream.'
} else {
    Write-Info 'Syncing with upstream (git pull --ff-only)...'
    git pull --ff-only 2>$null
    if ($LASTEXITCODE -eq 0) {
        Write-Success 'Repository up to date.'
    } else {
        Write-Warn 'Auto-pull failed (network, diverged history, or missing upstream). Continuing with local copy.'
    }
}

# ═══════════════════════════════════════════════════════════════════════════════
#  MENU
# ═══════════════════════════════════════════════════════════════════════════════

Write-Header 'Select Components'
Write-Host ''
Write-Host '  The following will be installed/configured:' -ForegroundColor White
Write-Host ''
Write-Host '    [1] PowerShell 7       — Modern shell (winget)' -ForegroundColor White
Write-Host '    [2] WezTerm            — GPU terminal emulator' -ForegroundColor White
Write-Host '    [3] Oh My Posh         — Prompt engine + catppuccin_mocha theme' -ForegroundColor White
Write-Host '    [4] JetBrains Mono NF  — Nerd Font with ligatures' -ForegroundColor White
Write-Host '    [5] Fastfetch          — System info display on shell launch' -ForegroundColor White
Write-Host '    [6] Deploy configs     — Symlink WezTerm + PS profile + OMP theme' -ForegroundColor White
Write-Host ''
Write-Host '  All components are idempotent — safe to re-run.' -ForegroundColor DarkGray
Write-Host ''

$proceed = Read-Host '  Proceed with all? [Y/n]'
if ($proceed -match '^[Nn]') {
    Write-Warn 'Aborted by user.'
    return
}

# ═══════════════════════════════════════════════════════════════════════════════
#  HELPERS
# ═══════════════════════════════════════════════════════════════════════════════

function Install-WingetPackage {
    param(
        [string]$Id,
        [string]$Name
    )
    $installed = winget list --id $Id 2>$null | Select-String ([regex]::Escape($Id))
    if ($installed) {
        Write-Info "$Name already installed. Checking for updates..."
        winget upgrade --id $Id --accept-package-agreements --accept-source-agreements 2>$null | Out-Null
        return $true
    } else {
        Write-Info "Installing $Name..."
        winget install --id $Id -e --accept-package-agreements --accept-source-agreements
        return ($LASTEXITCODE -eq 0)
    }
}

function Deploy-Symlink {
    param(
        [string]$Source,
        [string]$Target
    )

    # Ensure parent directory exists
    $parentDir = Split-Path $Target -Parent
    if (-not (Test-Path $parentDir)) {
        New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
    }

    # Check if symlink already points to correct source
    if (Test-Path $Target) {
        $item = Get-Item $Target -Force
        if ($item.LinkType -eq 'SymbolicLink') {
            $linkTarget = ($item | Select-Object -ExpandProperty Target) -join ''
            if ($linkTarget -eq $Source) {
                Write-Info "Already linked: $Target"
                return
            }
        }
        # Backup existing file
        $backup = "${Target}.bak.$(Get-Date -Format 'yyyyMMdd-HHmmss')"
        Write-Warn "Backing up: $Target -> $backup"
        Move-Item $Target $backup -Force
    }

    # Create symlink (needs Developer Mode or Admin)
    try {
        New-Item -ItemType SymbolicLink -Path $Target -Target $Source -Force -ErrorAction Stop | Out-Null
        Write-Success "Symlinked: $Target -> $Source"
    } catch {
        # Fallback to copy if symlinks unavailable
        Write-Warn 'Symlink failed (enable Developer Mode or run as Admin). Copying instead.'
        Copy-Item $Source $Target -Force
        Write-Success "Copied: $Source -> $Target"
    }
}

function Refresh-Path {
    $env:Path = [System.Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' +
                 [System.Environment]::GetEnvironmentVariable('Path', 'User')
}

# ═══════════════════════════════════════════════════════════════════════════════
#  INSTALL COMPONENTS
# ═══════════════════════════════════════════════════════════════════════════════

# --- [1] PowerShell 7 ---
Write-Header 'PowerShell 7'
if (Get-Command pwsh -ErrorAction SilentlyContinue) {
    $psVer = (pwsh -NoProfile -Command '$PSVersionTable.PSVersion.ToString()') 2>$null
    Write-Info "PowerShell 7 installed (v$psVer). Checking for updates..."
    winget upgrade --id Microsoft.PowerShell --accept-package-agreements --accept-source-agreements 2>$null | Out-Null
} else {
    Install-WingetPackage -Id 'Microsoft.PowerShell' -Name 'PowerShell 7'
    Refresh-Path
}

# --- [2] WezTerm ---
Write-Header 'WezTerm'
Install-WingetPackage -Id 'wez.wezterm' -Name 'WezTerm'

# --- [3] Oh My Posh ---
Write-Header 'Oh My Posh'
Install-WingetPackage -Id 'JanDeDobbeleer.OhMyPosh' -Name 'Oh My Posh'
Refresh-Path

# --- [4] JetBrains Mono Nerd Font ---
Write-Header 'JetBrains Mono Nerd Font'
$fontCheck = @(
    (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Fonts')
    'C:\Windows\Fonts'
) | ForEach-Object {
    if (Test-Path $_) { Get-ChildItem $_ -Filter '*JetBrains*Nerd*' -ErrorAction SilentlyContinue }
} | Where-Object { $_ }

if ($fontCheck) {
    Write-Info 'JetBrains Mono Nerd Font already installed.'
} else {
    if (Get-Command oh-my-posh -ErrorAction SilentlyContinue) {
        Write-Info 'Installing JetBrains Mono Nerd Font via oh-my-posh...'
        oh-my-posh font install JetBrainsMono
    } else {
        Write-Warn 'Oh My Posh not in PATH. Run manually after restart: oh-my-posh font install JetBrainsMono'
    }
}

# --- [5] Fastfetch ---
Write-Header 'Fastfetch'
Install-WingetPackage -Id 'Fastfetch-cli.Fastfetch' -Name 'Fastfetch'

# --- [6] Deploy Configs ---
Write-Header 'Deploying Configs'

# WezTerm config
Deploy-Symlink `
    -Source (Join-Path $RepoDir 'wezterm\.wezterm.lua') `
    -Target (Join-Path $env:USERPROFILE '.wezterm.lua')

# Oh My Posh themes (reuse existing repo configs)
$ompSourceDir = Join-Path $RepoDir 'omp\.config\ohmyposh'
$ompTargetDir = Join-Path $env:USERPROFILE '.config\ohmyposh'
if (Test-Path $ompSourceDir) {
    Get-ChildItem $ompSourceDir -File | ForEach-Object {
        Deploy-Symlink -Source $_.FullName -Target (Join-Path $ompTargetDir $_.Name)
    }
} else {
    Write-Warn "OMP theme directory not found at $ompSourceDir"
}

# PowerShell profile — deploy to both PS7 and PS5.1
$profileSource = Join-Path $RepoDir 'powershell\Microsoft.PowerShell_profile.ps1'
$ps7ProfileDir = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'PowerShell'
$ps5ProfileDir = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'WindowsPowerShell'

Deploy-Symlink -Source $profileSource -Target (Join-Path $ps7ProfileDir 'Microsoft.PowerShell_profile.ps1')
Deploy-Symlink -Source $profileSource -Target (Join-Path $ps5ProfileDir 'Microsoft.PowerShell_profile.ps1')

# ═══════════════════════════════════════════════════════════════════════════════
#  DONE
# ═══════════════════════════════════════════════════════════════════════════════

Refresh-Path
Write-Host ''
Write-Header 'Setup Complete'
Write-Host ''
Write-Host '  Installed:' -ForegroundColor White
Write-Host '    PowerShell 7, WezTerm, Oh My Posh, JetBrains Mono NF, Fastfetch'
Write-Host ''
Write-Host '  Configs deployed:' -ForegroundColor White
Write-Host '    wezterm/.wezterm.lua        -> ~/.wezterm.lua'
Write-Host '    powershell/profile.ps1      -> Documents/PowerShell/profile.ps1'
Write-Host '    omp/.config/ohmyposh/*      -> ~/.config/ohmyposh/*'
Write-Host ''
Write-Host '  Keybinds (WezTerm):' -ForegroundColor White
Write-Host '    Shift+Enter                  Multi-line input (Claude Code)'
Write-Host '    Alt+Shift+-                  Split pane down'
Write-Host '    Alt+Shift+=                  Split pane right'
Write-Host '    Alt+Arrow                    Navigate panes'
Write-Host '    Ctrl+Shift+W                 Close pane'
Write-Host '    Alt+1..5                     Switch tabs'
Write-Host '    Right-click                  Paste from clipboard'
Write-Host ''
Write-Host '  Next steps:' -ForegroundColor Cyan
Write-Host '    1. Open WezTerm (Start menu or: wezterm-gui)'
Write-Host '    2. It launches PowerShell 7 with your catppuccin prompt'
Write-Host '    3. Shift+Enter works natively for Claude Code multi-line'
Write-Host ''
Write-Host "  All configs tracked in: $RepoDir" -ForegroundColor DarkGray
Write-Host ''
Write-Success 'Done. Open WezTerm to see your new setup.'
