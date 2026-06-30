<#
.SYNOPSIS
    Windows Shell Setup -- mirrors shellSetup.sh for Linux.
.DESCRIPTION
    Deploys a fully configured PowerShell + WezTerm environment on Windows.
    Idempotent -- safe to re-run. Existing configs backed up automatically.
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
#  BOOTSTRAP -- REMOTE EXECUTION DETECTION
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
            Write-Warn 'Git identity not set -- configure before committing.'
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

# ═══════════════════════════════════════════════════════════════════════════════
#  ENSURE: Administrator + PowerShell 7
# ═══════════════════════════════════════════════════════════════════════════════
# Two gates, in this order:
#   1. PowerShell 7+: PS5.1 reads .ps1 as Windows-1252 (no UTF-8 BOM
#      detection); a single em-dash inside a "..." string mid-decodes
#      to a smart-quote and cascades parse errors through the whole
#      file. PS7+ reads UTF-8 natively. Defense in depth on top of
#      the ASCII-only file rule.
#   2. Administrator: most STOW/CONFIGS work requires symlink creation,
#      which on Windows demands either Developer Mode OR admin. winget
#      installs that affect Machine scope also need admin.
# Each gate, when not satisfied, re-launches the script in a new
# process (under pwsh, elevated if needed) and exits this one.

function Get-Pwsh7Path {
    $cmd = Get-Command pwsh -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $fallback = Join-Path $env:ProgramFiles 'PowerShell\7\pwsh.exe'
    if (Test-Path $fallback) { return $fallback }
    return $null
}

function Test-IsAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($id)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

$isPs7   = $PSVersionTable.PSVersion.Major -ge 7
$isAdmin = Test-IsAdmin

if (-not $isPs7) {
    Write-Header 'Switching to PowerShell 7'
    $pwshPath = Get-Pwsh7Path

    if (-not $pwshPath) {
        Write-Info 'PowerShell 7 not installed. Installing via winget...'
        if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
            Write-Err 'winget not found. Install App Installer first, OR install PowerShell 7 manually from https://aka.ms/powershell and re-run.'
            return
        }
        # User scope avoids needing admin for the install itself.
        winget install --id Microsoft.PowerShell -e --scope user --accept-package-agreements --accept-source-agreements --silent
        # Refresh PATH so pwsh becomes visible without restarting the shell.
        $env:Path = [System.Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' +
                     [System.Environment]::GetEnvironmentVariable('Path', 'User')
        $pwshPath = Get-Pwsh7Path
        if (-not $pwshPath) {
            Write-Err 'PowerShell 7 install completed but pwsh.exe still not found. Open a NEW terminal and re-run this script.'
            return
        }
        Write-Success "PowerShell 7 installed at $pwshPath"
    } else {
        Write-Info "PowerShell 7 already installed at $pwshPath"
    }

    $relaunchArgs = @('-NoExit', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath)
    if (-not $isAdmin) {
        Write-Info 'Re-launching under PowerShell 7 with admin elevation (UAC prompt next)...'
        Start-Process -FilePath $pwshPath -ArgumentList $relaunchArgs -Verb RunAs
    } else {
        Write-Info 'Re-launching under PowerShell 7 (already admin)...'
        Start-Process -FilePath $pwshPath -ArgumentList $relaunchArgs
    }
    Write-Info 'This window can now be closed. Continue in the new PowerShell 7 window.'
    return
}

if (-not $isAdmin) {
    Write-Header 'Elevating to Administrator'
    Write-Info 'Most setup steps need admin (symlinks, machine-scope winget, scheduled tasks).'
    Write-Info 'Re-launching elevated (UAC prompt next)...'
    $pwshPath = Get-Pwsh7Path  # we're on PS7 now, this resolves
    if (-not $pwshPath) { $pwshPath = (Get-Process -Id $PID).Path }
    $relaunchArgs = @('-NoExit', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath)
    Start-Process -FilePath $pwshPath -ArgumentList $relaunchArgs -Verb RunAs
    Write-Info 'This window can now be closed. Continue in the new elevated window.'
    return
}

Write-Success "Running on PowerShell $($PSVersionTable.PSVersion) as Administrator"

# --- Auto-sync with upstream ---
$dirty = git status --porcelain 2>$null
if ($dirty) {
    Write-Warn 'Working tree has uncommitted changes -- skipping auto-pull.'
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
#  MENU -- Interactive Component Selector
# ═══════════════════════════════════════════════════════════════════════════════

$MenuItems = @(
    [PSCustomObject]@{ Key = 'PS7';     On = $true;  Label = 'PowerShell 7';      Desc = 'Modern shell (winget)' }
    [PSCustomObject]@{ Key = 'WEZTERM'; On = $true;  Label = 'WezTerm';           Desc = 'GPU terminal emulator' }
    [PSCustomObject]@{ Key = 'OMP';     On = $true;  Label = 'Oh My Posh';        Desc = 'Prompt engine + catppuccin theme' }
    [PSCustomObject]@{ Key = 'FONT';    On = $true;  Label = 'JetBrains Mono NF'; Desc = 'Nerd Font with ligatures' }
    [PSCustomObject]@{ Key = 'FETCH';   On = $true;  Label = 'Fastfetch';         Desc = 'System info on shell launch' }
    [PSCustomObject]@{ Key = 'NODE';    On = $true;  Label = 'Node.js';           Desc = 'fnm + Node LTS + pnpm' }
    [PSCustomObject]@{ Key = 'PYTHON';  On = $true;  Label = 'Python';            Desc = 'Python 3, pip globals, pipx' }
    [PSCustomObject]@{ Key = 'JQ';      On = $true;  Label = 'jq';               Desc = 'JSON processor (Claude statusline)' }
    [PSCustomObject]@{ Key = 'CLAUDE';  On = $true;  Label = 'Claude Code';       Desc = 'AI coding assistant + OpenCode' }
    [PSCustomObject]@{ Key = 'CONFIGS'; On = $true;  Label = 'Deploy configs';    Desc = 'Symlink all dotfiles + Claude config' }
    [PSCustomObject]@{ Key = 'APPS';    On = $false; Label = 'Extra apps';        Desc = 'Browsers, dev tools, productivity' }
    [PSCustomObject]@{ Key = 'TWEAKS';  On = $false; Label = 'System tweaks';     Desc = 'Dark mode, Explorer, taskbar prefs' }
    [PSCustomObject]@{ Key = 'SSHKEY';  On = $false; Label = 'GitHub SSH + CLI';  Desc = 'SSH key, gh auth, key upload' }
    [PSCustomObject]@{ Key = 'COWORK';  On = $false; Label = 'COWORK';            Desc = 'Multi-Agent Coordination (needs SSH)' }
)

while ($true) {
    Write-Header 'Select Components'
    Write-Host ''
    Write-Host '  Toggle items by number, then press Enter to proceed.' -ForegroundColor DarkGray
    Write-Host '  All components are idempotent -- safe to re-run.' -ForegroundColor DarkGray
    Write-Host ''

    for ($i = 0; $i -lt $MenuItems.Count; $i++) {
        $mark = if ($MenuItems[$i].On) { 'x' } else { ' ' }
        $num  = ($i + 1).ToString().PadLeft(2)
        $lbl  = $MenuItems[$i].Label.PadRight(20)
        $desc = $MenuItems[$i].Desc
        $color = if ($MenuItems[$i].On) { 'White' } else { 'DarkGray' }
        Write-Host "    [$mark] $num  $lbl  $desc" -ForegroundColor $color
    }

    Write-Host ''
    $input = Read-Host '  Toggle (1-14 / all / none / q=quit) or Enter to proceed'

    if ([string]::IsNullOrWhiteSpace($input)) { break }
    if ($input -match '^[Qq]') { Write-Warn 'Aborted by user.'; return }
    if ($input -eq 'all')  { $MenuItems | ForEach-Object { $_.On = $true };  continue }
    if ($input -eq 'none') { $MenuItems | ForEach-Object { $_.On = $false }; continue }

    # Parse comma/space-separated numbers
    $nums = $input -split '[,\s]+' | Where-Object { $_ -match '^\d+$' } | ForEach-Object { [int]$_ }
    foreach ($n in $nums) {
        if ($n -ge 1 -and $n -le $MenuItems.Count) {
            $MenuItems[$n - 1].On = -not $MenuItems[$n - 1].On
        }
    }
}

$Selected = $MenuItems | Where-Object { $_.On } | ForEach-Object { $_.Key }
if (-not $Selected) {
    Write-Warn 'Nothing selected. Exiting.'
    return
}

# Auto-enable SSHKEY if COWORK selected (dependency)
if ($Selected -contains 'COWORK' -and $Selected -notcontains 'SSHKEY') {
    Write-Warn 'COWORK requires SSHKEY -- enabling automatically.'
    $Selected += 'SSHKEY'
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

    # Check if symlink/junction already points to correct source
    if (Test-Path $Target) {
        $item = Get-Item $Target -Force
        if ($item.LinkType -in @('SymbolicLink', 'Junction')) {
            $linkTarget = ($item | Select-Object -ExpandProperty Target) -join ''
            # Junctions may store \\?\ prefix -- normalize for comparison
            $linkTarget = $linkTarget -replace '^\\\\\?\\', ''
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
        $isDir = Test-Path $Source -PathType Container
        if ($isDir) {
            # Directories: try NTFS junction (no admin required for local paths)
            try {
                New-Item -ItemType Junction -Path $Target -Target $Source -Force -ErrorAction Stop | Out-Null
                Write-Success "Junction: $Target -> $Source"
            } catch {
                Write-Warn 'Symlink & junction failed. Copying directory instead.'
                Copy-Item $Source $Target -Recurse -Force
                Write-Success "Copied (dir): $Source -> $Target"
            }
        } else {
            Write-Warn 'Symlink failed (enable Developer Mode or run as Admin). Copying instead.'
            Copy-Item $Source $Target -Force
            Write-Success "Copied: $Source -> $Target"
        }
    }
}

function Refresh-Path {
    $env:Path = [System.Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' +
                 [System.Environment]::GetEnvironmentVariable('Path', 'User')
}

# ═══════════════════════════════════════════════════════════════════════════════
#  INSTALL COMPONENTS
# ═══════════════════════════════════════════════════════════════════════════════

if ($Selected -contains 'PS7') {
    Write-Header 'PowerShell 7'
    if (Get-Command pwsh -ErrorAction SilentlyContinue) {
        $psVer = (pwsh -NoProfile -Command '$PSVersionTable.PSVersion.ToString()') 2>$null
        Write-Info "PowerShell 7 installed (v$psVer). Checking for updates..."
        winget upgrade --id Microsoft.PowerShell --accept-package-agreements --accept-source-agreements 2>$null | Out-Null
    } else {
        Install-WingetPackage -Id 'Microsoft.PowerShell' -Name 'PowerShell 7'
        Refresh-Path
    }
}

if ($Selected -contains 'WEZTERM') {
    Write-Header 'WezTerm'
    Install-WingetPackage -Id 'wez.wezterm' -Name 'WezTerm'
}

if ($Selected -contains 'OMP') {
    Write-Header 'Oh My Posh'
    Install-WingetPackage -Id 'JanDeDobbeleer.OhMyPosh' -Name 'Oh My Posh'
    Refresh-Path
}

if ($Selected -contains 'FONT') {
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
}

if ($Selected -contains 'FETCH') {
    Write-Header 'Fastfetch'
    Install-WingetPackage -Id 'Fastfetch-cli.Fastfetch' -Name 'Fastfetch'
}

if ($Selected -contains 'JQ') {
    Write-Header 'jq'
    Install-WingetPackage -Id 'jqlang.jq' -Name 'jq'
}

# ═══════════════════════════════════════════════════════════════════════════════
#  NODE -- fnm + Node LTS + pnpm
# ═══════════════════════════════════════════════════════════════════════════════

if ($Selected -contains 'NODE') {
    Write-Header 'Node.js (fnm + LTS + pnpm)'

    # Install fnm (Fast Node Manager) via winget
    Install-WingetPackage -Id 'Schniz.fnm' -Name 'Fast Node Manager (fnm)'
    Refresh-Path

    if (Get-Command fnm -ErrorAction SilentlyContinue) {
        # Configure fnm environment for this session
        fnm env --use-on-cd --shell power-shell | Out-String | Invoke-Expression

        # Install Node LTS if no default version is set
        $fnmDefault = fnm current 2>$null
        if (-not $fnmDefault -or $fnmDefault -eq 'none') {
            Write-Info 'Installing Node.js LTS...'
            fnm install --lts
            fnm default lts-latest
            Write-Success 'Node LTS installed and set as default.'
        } else {
            Write-Info "Node already managed by fnm: $fnmDefault"
            Write-Info 'Checking for LTS updates...'
            fnm install --lts 2>$null
        }
        Refresh-Path

        # Enable pnpm via corepack
        if (Get-Command corepack -ErrorAction SilentlyContinue) {
            Write-Info 'Enabling pnpm via corepack...'
            $env:COREPACK_ENABLE_DOWNLOAD_PROMPT = '0'
            corepack enable pnpm 2>$null
            if ($LASTEXITCODE -eq 0) {
                Write-Success 'pnpm enabled via corepack.'
            } else {
                Write-Warn 'corepack enable pnpm failed. Run manually after restart.'
            }
        } else {
            Write-Warn 'corepack not found -- install Node first, then re-run.'
        }
    } else {
        Write-Warn 'fnm not found after install. Restart terminal and re-run.'
    }
}

# ═══════════════════════════════════════════════════════════════════════════════
#  PYTHON -- Python 3, pip globals, pipx
# ═══════════════════════════════════════════════════════════════════════════════

if ($Selected -contains 'PYTHON') {
    Write-Header 'Python Environment'

    # Install Python 3 via winget
    Install-WingetPackage -Id 'Python.Python.3.13' -Name 'Python 3.13'
    Refresh-Path

    if (Get-Command python -ErrorAction SilentlyContinue) {
        $pyVer = python --version 2>$null
        Write-Info "Python installed: $pyVer"

        # Upgrade pip, setuptools, wheel
        Write-Info 'Upgrading pip, setuptools, wheel...'
        python -m pip install --upgrade pip setuptools wheel 2>$null | Out-Null

        # Core global tools (matching Linux shellSetup.sh)
        Write-Info 'Installing core Python tools...'
        $pipPackages = @(
            'pipx', 'poetry', 'virtualenv', 'pre-commit',
            'black', 'ruff', 'mypy', 'isort',
            'pytest', 'pytest-cov', 'pytest-asyncio',
            'ipython', 'requests', 'httpx',
            'rich', 'typer', 'click',
            'python-dotenv', 'pyyaml'
        )
        python -m pip install --upgrade ($pipPackages -join ' ') 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Write-Success 'Core Python tools installed.'
        } else {
            Write-Warn 'Some pip packages may have failed. Check output above.'
        }

        # Ensure pipx is on PATH
        python -m pipx ensurepath 2>$null | Out-Null
        Refresh-Path

        # Install isolated tools via pipx
        Write-Info 'Installing jupyter and pylint via pipx...'
        foreach ($pkg in @('jupyter', 'pylint')) {
            python -m pipx install $pkg 2>$null | Out-Null
            if ($LASTEXITCODE -eq 0) {
                Write-Success "pipx: $pkg installed."
            } else {
                # pipx returns non-zero if already installed
                Write-Info "pipx: $pkg already installed or skipped."
            }
        }
    } else {
        Write-Warn 'Python not found after install. Restart terminal and re-run.'
    }
}

if ($Selected -contains 'CLAUDE') {
    Write-Header 'AI Coding Tools (Claude Code + OpenCode)'

    # --- Legacy cleanup (mirrors shellSetup.sh install_ai_tools) ---
    # Remove old npm/pnpm global installs that conflict with native installers
    Write-Info 'Cleaning up legacy AI tool installs...'
    foreach ($legacyPkg in @('@anthropic-ai/claude-code', 'opencode-ai', '@google/gemini-cli')) {
        if (Get-Command pnpm -ErrorAction SilentlyContinue) {
            pnpm remove -g $legacyPkg 2>$null | Out-Null
        }
        if (Get-Command npm -ErrorAction SilentlyContinue) {
            npm uninstall -g $legacyPkg 2>$null | Out-Null
        }
    }
    # Remove deprecated ~/.gemini directory
    $geminiDir = Join-Path $env:USERPROFILE '.gemini'
    if (Test-Path $geminiDir) {
        Remove-Item $geminiDir -Recurse -Force -ErrorAction SilentlyContinue
        Write-Info 'Removed deprecated ~/.gemini directory.'
    }

    # --- Claude Code (always refresh -- matches Linux behavior) ---
    Write-Info 'Installing/updating Claude Code...'
    winget install --id Anthropic.ClaudeCode -e --accept-package-agreements --accept-source-agreements 2>$null
    if ($LASTEXITCODE -ne 0) {
        # winget returns non-zero if already up to date -- check if it's actually present
        if (-not (Get-Command claude -ErrorAction SilentlyContinue)) {
            Write-Warn 'winget install failed and Claude Code not found.'
            Write-Warn 'Install manually: https://claude.ai/code'
        }
    }
    Refresh-Path
    if (Get-Command claude -ErrorAction SilentlyContinue) {
        Write-Success 'Claude Code ready.'
    }

    # --- OpenCode ---
    # NOTE: upstream `https://opencode.ai/install` is a bash script.
    # Piping it through PowerShell's iex tokenizes `usage() { ... }`
    # as PS syntax errors. Use winget when possible; warn + skip if
    # unavailable.
    Write-Info 'Installing/updating OpenCode...'
    $openCodeInstalled = Get-Command opencode -ErrorAction SilentlyContinue
    if ($openCodeInstalled) {
        Write-Info 'OpenCode already present. Trying winget upgrade...'
        winget upgrade --id sst-opencode.opencode -e --silent --accept-package-agreements --accept-source-agreements 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Write-Success 'OpenCode upgrade run (no-op if already current).'
        } else {
            Write-Info 'OpenCode upgrade returned non-zero -- not necessarily an error (already current?).'
        }
    } else {
        Write-Info 'Trying winget install: sst-opencode.opencode'
        $wingetOut = winget install --id sst-opencode.opencode -e --silent --accept-package-agreements --accept-source-agreements 2>&1
        if ($LASTEXITCODE -eq 0 -and (Get-Command opencode -ErrorAction SilentlyContinue)) {
            Refresh-Path
            Write-Success 'OpenCode installed via winget.'
        } else {
            Write-Warn 'OpenCode not available via winget on this machine.'
            Write-Warn 'Install manually: https://opencode.ai/docs/getting-started (Scoop or direct binary).'
        }
    }
}

# ═══════════════════════════════════════════════════════════════════════════════
#  APPS -- Extra Applications via Winget
# ═══════════════════════════════════════════════════════════════════════════════

if ($Selected -contains 'APPS') {
    Write-Header 'Installing Extra Applications'

    $AppList = @(
        # --- Core utilities ---
        @{ Id = '7zip.7zip';                    Name = '7-Zip' }
        @{ Id = 'Microsoft.VisualStudioCode';   Name = 'VS Code' }
        @{ Id = 'Greenshot.Greenshot';          Name = 'Greenshot' }
        @{ Id = 'NickeManarin.ScreenToGif';     Name = 'ScreenToGif' }
        @{ Id = 'VideoLAN.VLC';                 Name = 'VLC' }

        # --- Browsers ---
        @{ Id = 'Google.Chrome';                Name = 'Chrome' }
        @{ Id = 'Mozilla.Firefox';              Name = 'Firefox' }

        # --- Dev tools ---
        @{ Id = 'MongoDB.Compass.Full';         Name = 'MongoDB Compass' }
        @{ Id = 'dorssel.usbipd-win';           Name = 'usbipd-win (USB/IP for WSL)' }
        @{ Id = 'Microsoft.WSL';                Name = 'Windows Subsystem for Linux' }
        @{ Id = 'Canonical.Ubuntu';             Name = 'Ubuntu (WSL)' }

        # --- Productivity ---
        @{ Id = 'Obsidian.Obsidian';            Name = 'Obsidian' }
        @{ Id = 'Adobe.Acrobat.Reader.64-bit';  Name = 'Adobe Reader' }

        # --- Network / VPN ---
        @{ Id = 'NordSecurity.NordVPN';         Name = 'NordVPN' }
        @{ Id = 'Tailscale.Tailscale';          Name = 'Tailscale' }
        @{ Id = 'Cloudflare.Warp';              Name = 'Cloudflare WARP' }

        # --- Remote access ---
        @{ Id = 'mRemoteNG.mRemoteNG';         Name = 'mRemoteNG' }

        # --- Communication ---
        @{ Id = 'Zoom.Zoom';                    Name = 'Zoom' }

        # --- Media ---
        @{ Id = 'Spotify.Spotify';              Name = 'Spotify' }
    )

    foreach ($app in $AppList) {
        Install-WingetPackage -Id $app.Id -Name $app.Name
    }

    Refresh-Path
}

# ═══════════════════════════════════════════════════════════════════════════════
#  TWEAKS -- Windows System Preferences
# ═══════════════════════════════════════════════════════════════════════════════

if ($Selected -contains 'TWEAKS') {
    Write-Header 'Applying System Tweaks'

    # --- Explorer ---
    $explorerKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
    $tweaks = @(
        @{ Key = $explorerKey; Name = 'HideFileExt';        Value = 0; Desc = 'Show file extensions' }
        @{ Key = $explorerKey; Name = 'LaunchTo';           Value = 1; Desc = 'Explorer opens to This PC' }
        @{ Key = $explorerKey; Name = 'ShowTaskViewButton'; Value = 0; Desc = 'Hide Task View button' }
        @{ Key = $explorerKey; Name = 'ShowCopilotButton';  Value = 0; Desc = 'Hide Copilot button' }
        @{ Key = $explorerKey; Name = 'TaskbarMn';          Value = 0; Desc = 'Hide Chat button' }
        @{ Key = $explorerKey; Name = 'TaskbarAl';          Value = 1; Desc = 'Center-align taskbar' }
        @{ Key = $explorerKey; Name = 'TaskbarSn';          Value = 1; Desc = 'Enable Snap layouts' }

        # --- Search ---
        @{ Key = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search'
           Name = 'SearchboxTaskbarMode'; Value = 0; Desc = 'Hide search box from taskbar' }
        @{ Key = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search'
           Name = 'BingSearchEnabled';    Value = 0; Desc = 'Disable Bing in Start search' }

        # --- Dark mode ---
        @{ Key = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'
           Name = 'AppsUseLightTheme';    Value = 0; Desc = 'Dark mode for apps' }
        @{ Key = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'
           Name = 'SystemUsesLightTheme'; Value = 0; Desc = 'Dark mode for system' }
        @{ Key = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'
           Name = 'EnableTransparency';   Value = 1; Desc = 'Enable transparency effects' }

        # --- Disable bloatware / suggestions ---
        @{ Key = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'
           Name = 'SilentInstalledAppsEnabled';  Value = 0; Desc = 'Block silent app installs' }
        @{ Key = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'
           Name = 'SystemPaneSuggestionsEnabled'; Value = 0; Desc = 'Disable Start suggestions' }

        # --- Clipboard ---
        @{ Key = 'HKCU:\Software\Microsoft\Clipboard'
           Name = 'EnableClipboardHistory'; Value = 1; Desc = 'Enable clipboard history (Win+V)' }

        # --- Disable Game DVR ---
        @{ Key = 'HKCU:\System\GameConfigStore'
           Name = 'GameDVR_Enabled'; Value = 0; Desc = 'Disable Game DVR / Game Bar recording' }
    )

    foreach ($t in $tweaks) {
        # Ensure registry key exists
        if (-not (Test-Path $t.Key)) {
            New-Item -Path $t.Key -Force | Out-Null
        }
        $current = Get-ItemProperty -Path $t.Key -Name $t.Name -ErrorAction SilentlyContinue
        if ($null -ne $current -and $current.($t.Name) -eq $t.Value) {
            Write-Info "$($t.Desc) -- already set"
        } else {
            Set-ItemProperty -Path $t.Key -Name $t.Name -Value $t.Value -Type DWord
            Write-Success $t.Desc
        }
    }

    # --- Execution policy (requires current process to be elevated for LocalMachine) ---
    $currentPolicy = Get-ExecutionPolicy -Scope LocalMachine
    if ($currentPolicy -ne 'RemoteSigned') {
        try {
            Set-ExecutionPolicy RemoteSigned -Scope LocalMachine -Force -ErrorAction Stop
            Write-Success 'Execution policy set to RemoteSigned (LocalMachine)'
        } catch {
            Write-Warn 'Execution policy requires admin -- run as Administrator to set.'
        }
    } else {
        Write-Info 'Execution policy already RemoteSigned'
    }

    # Restart Explorer to apply changes immediately
    Write-Info 'Restarting Explorer to apply changes...'
    Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    if (-not (Get-Process explorer -ErrorAction SilentlyContinue)) {
        Start-Process explorer
    }
    Write-Success 'System tweaks applied.'
}

# ═══════════════════════════════════════════════════════════════════════════════
#  SSHKEY -- GitHub SSH Key, CLI & Auth
# ═══════════════════════════════════════════════════════════════════════════════

if ($Selected -contains 'SSHKEY') {
    Write-Header 'GitHub SSH Key + CLI'

    # --- Install GitHub CLI ---
    Install-WingetPackage -Id 'GitHub.cli' -Name 'GitHub CLI'
    Refresh-Path

    # --- Generate SSH key ---
    $sshDir  = Join-Path $env:USERPROFILE '.ssh'
    $sshKey  = Join-Path $sshDir 'id_ed25519'
    $needUpload = $true

    if (Test-Path $sshKey) {
        Write-Info "SSH key already exists at $sshKey"
        $reply = Read-Host '  Is this key already added to your GitHub account? [y/N]'
        if ($reply -match '^[Yy]') {
            $needUpload = $false
            Write-Info 'Skipping SSH key upload.'
        }
    } else {
        $gitEmail = git config --global user.email 2>$null
        if (-not $gitEmail) { $gitEmail = 'email@example.com' }
        Write-Info 'Generating new ed25519 SSH key...'
        if (-not (Test-Path $sshDir)) { New-Item -ItemType Directory -Path $sshDir -Force | Out-Null }
        ssh-keygen -t ed25519 -C $gitEmail -f $sshKey -N ""
        Write-Success 'SSH key generated.'
    }

    # --- Configure SSH for GitHub ---
    Write-Info 'Configuring SSH for GitHub...'
    $sshConfig = Join-Path $sshDir 'config'
    if (-not (Test-Path $sshDir)) { New-Item -ItemType Directory -Path $sshDir -Force | Out-Null }

    $configContent = if (Test-Path $sshConfig) { Get-Content $sshConfig -Raw } else { '' }

    if ($configContent -notmatch 'Host \*') {
        $globalBlock = @'

Host *
    AddKeysToAgent yes
    ServerAliveInterval 60
    ServerAliveCountMax 3
'@
        Add-Content -Path $sshConfig -Value $globalBlock
        Write-Success 'SSH global defaults added.'
    }

    if ($configContent -notmatch 'Host github\.com') {
        $ghBlock = @'

Host github.com
    HostName github.com
    User git
    IdentityFile ~/.ssh/id_ed25519
    IdentitiesOnly yes

Host ssh.github.com
    HostName ssh.github.com
    Port 443
    User git
    IdentityFile ~/.ssh/id_ed25519
    IdentitiesOnly yes
'@
        Add-Content -Path $sshConfig -Value $ghBlock
        Write-Success 'GitHub SSH host configured.'
    } else {
        Write-Info 'GitHub host already configured in SSH config.'
    }

    # --- Start ssh-agent and add key ---
    Write-Info 'Ensuring ssh-agent is running...'
    $agentSvc = Get-Service ssh-agent -ErrorAction SilentlyContinue
    if ($agentSvc) {
        if ($agentSvc.StartType -eq 'Disabled') {
            Set-Service ssh-agent -StartupType Manual
        }
        if ($agentSvc.Status -ne 'Running') {
            Start-Service ssh-agent
        }
        ssh-add $sshKey 2>$null
        Write-Success 'SSH key added to agent.'
    } else {
        Write-Warn 'ssh-agent service not found. Key may need manual adding per session.'
    }

    # --- Switch this repo's remote to SSH ---
    Write-Info 'Switching git remotes to SSH...'
    $remoteUrl = git remote get-url origin 2>$null
    if ($remoteUrl -match '^https://github\.com/(.+)$') {
        $repoPath = $Matches[1]
        git remote set-url origin "git@github.com:$repoPath"
        Write-Success "Switched to SSH: git@github.com:$repoPath"
    } elseif ($remoteUrl -match '^git@github\.com:') {
        Write-Info 'Remote already using SSH.'
    }

    # --- Authenticate GitHub CLI ---
    $ghAuthenticated = $false
    if (Get-Command gh -ErrorAction SilentlyContinue) {
        $ghStatus = gh auth status 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Info 'GitHub CLI already authenticated.'
            $ghAuthenticated = $true
        } else {
            Write-Host ''
            Write-Warn 'A browser will open to authenticate with GitHub.'
            Write-Host ''
            gh auth login -p ssh -h github.com
            if ($LASTEXITCODE -eq 0) {
                Write-Success 'GitHub CLI authenticated.'
                gh config set git_protocol ssh -h github.com
                $ghAuthenticated = $true
            } else {
                Write-Warn 'Auth skipped. Run later: gh auth login'
            }
        }

        # Upload SSH key if authenticated and needed
        if ($ghAuthenticated -and $needUpload -and (Test-Path "$sshKey.pub")) {
            $keyTitle = "$env:COMPUTERNAME-$(Get-Date -Format 'yyyyMMdd')"
            Write-Info "Uploading SSH key to GitHub as '$keyTitle'..."
            gh ssh-key add "$sshKey.pub" -t $keyTitle 2>$null
            if ($LASTEXITCODE -eq 0) {
                Write-Success 'SSH key uploaded to GitHub.'
            } else {
                Write-Warn 'SSH key may already exist on GitHub (OK).'
            }
        }
    } else {
        Write-Err 'GitHub CLI not found after install. Run manually: gh auth login'
    }

    # Fallback: show key for manual upload
    if (-not $ghAuthenticated -and $needUpload -and (Test-Path "$sshKey.pub")) {
        $pubKey = Get-Content "$sshKey.pub"
        Write-Host ''
        Write-Host '=== GitHub SSH Key ===' -ForegroundColor Cyan
        Write-Warn 'Upload this public key to: https://github.com/settings/keys'
        Write-Host ''
        Write-Host $pubKey -ForegroundColor Green
        Write-Host ''
    }
    Write-Info 'Test connection with: ssh -T git@github.com'
}

# ═══════════════════════════════════════════════════════════════════════════════
#  DEPLOY CONFIGS
# ═══════════════════════════════════════════════════════════════════════════════

if ($Selected -contains 'CONFIGS') {
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

    # PowerShell profile -- deploy to both PS7 and PS5.1
    $profileSource = Join-Path $RepoDir 'powershell\Microsoft.PowerShell_profile.ps1'
    $ps7ProfileDir = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'PowerShell'
    $ps5ProfileDir = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'WindowsPowerShell'

    Deploy-Symlink -Source $profileSource -Target (Join-Path $ps7ProfileDir 'Microsoft.PowerShell_profile.ps1')
    Deploy-Symlink -Source $profileSource -Target (Join-Path $ps5ProfileDir 'Microsoft.PowerShell_profile.ps1')

    # Windows Terminal settings (Catppuccin Mocha, font, opacity, acrylic)
    $wtSettingsSource = Join-Path $RepoDir 'windows-terminal\settings.json'
    $wtSettingsTarget = Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json'
    if (Test-Path (Split-Path $wtSettingsTarget -Parent)) {
        Deploy-Symlink -Source $wtSettingsSource -Target $wtSettingsTarget
    } else {
        Write-Warn 'Windows Terminal not found -- skipping settings deploy.'
    }

    # Fastfetch config
    $ffSource = Join-Path $RepoDir 'fastfetch\.config\fastfetch\config.jsonc'
    $ffTarget = Join-Path $env:USERPROFILE '.config\fastfetch\config.jsonc'
    if (Test-Path $ffSource) {
        Deploy-Symlink -Source $ffSource -Target $ffTarget
    }

    # --- Claude Code config (CLAUDE.md, settings.json, statusline.sh) ---
    # Mirrors shellSetup.sh deploy_claude_config() -- absolute symlinks.
    # Deploy-Symlink falls back to copy if Developer Mode is off / not admin.
    $claudeHome = Join-Path $env:USERPROFILE '.claude'
    if (-not (Test-Path $claudeHome)) {
        New-Item -ItemType Directory -Path $claudeHome -Force | Out-Null
    }

    $claudeSourceDir = Join-Path $RepoDir 'claude\.claude'
    foreach ($file in @('CLAUDE.md', 'settings.json', 'statusline.sh')) {
        $src = Join-Path $claudeSourceDir $file
        $tgt = Join-Path $claudeHome $file
        if (Test-Path $src) {
            Deploy-Symlink -Source $src -Target $tgt
        }
    }

    # Skills + commands symlinks are owned by COWORK's Stage 2 deployer
    # ($USERPROFILE\COWORK\.claude-config\deploy.ps1), NOT this section.
    # CONFIGS only handles Stage 1 (Level 1 files above). The COWORK menu
    # item invokes deploy.ps1 automatically after cloning.
}

# ═══════════════════════════════════════════════════════════════════════════════
#  COWORK -- Multi-Agent Coordination
# ═══════════════════════════════════════════════════════════════════════════════

if ($Selected -contains 'COWORK') {
    Write-Header 'Deploying COWORK (Multi-Agent Coordination)'

    $CoworkDir = Join-Path $env:USERPROFILE 'COWORK'

    # Verify gh is available and authenticated
    $canProceed = $true
    if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
        Write-Warn 'gh CLI not installed. Enable SSHKEY first. Skipping COWORK.'
        $canProceed = $false
    } else {
        gh auth status 2>$null | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-Warn 'gh CLI not authenticated. Re-run with SSHKEY enabled. Skipping COWORK.'
            $canProceed = $false
        }
    }

    if ($canProceed) {
        if (-not (Test-Path (Join-Path $CoworkDir '.git'))) {
            Write-Info "Cloning Exploitacious/COWORK to $CoworkDir..."
            gh repo clone Exploitacious/COWORK $CoworkDir
            if ($LASTEXITCODE -eq 0) {
                Write-Success 'COWORK cloned.'
            } else {
                Write-Err 'COWORK clone failed. Verify gh auth covers private repos.'
                $canProceed = $false
            }
        } else {
            # Idempotent sync -- handles dirty working trees by stashing local
            # edits with a labeled timestamp, pulling, then attempting to
            # restore. If restore conflicts, stash stays for manual recovery
            # and setup continues. Never destroys local work silently.
            Write-Info 'COWORK already cloned; syncing...'
            Push-Location $CoworkDir

            $stashLabel = ''
            # Detect modified-tracked OR staged-but-uncommitted.
            git diff --quiet HEAD 2>$null
            $hasUnstaged = ($LASTEXITCODE -ne 0)
            git diff --cached --quiet 2>$null
            $hasStaged = ($LASTEXITCODE -ne 0)

            if ($hasUnstaged -or $hasStaged) {
                $stashLabel = "setup-auto-" + (Get-Date -Format 'yyyy-MM-ddTHH-mm-ssZ' -AsUTC)
                Write-Info "Uncommitted changes detected -- stashing as '$stashLabel'..."
                git stash push -m $stashLabel 2>$null | Out-Null
                if ($LASTEXITCODE -ne 0) {
                    Write-Warn "git stash failed. Skipping sync. Inspect: cd $CoworkDir; git status"
                    Pop-Location
                    return
                }
            }

            git pull --ff-only 2>$null | Out-Null
            if ($LASTEXITCODE -eq 0) {
                Write-Success 'COWORK synced to origin.'
            } else {
                Write-Warn 'git pull --ff-only failed (diverged history, detached HEAD, or remote config?). Continuing with local HEAD.'
                Write-Info "Inspect manually: cd $CoworkDir; git status; git log --oneline -5"
            }

            # Restore stash if we made one.
            if ($stashLabel) {
                $stashList = (git stash list 2>$null)
                $stashRef = ($stashList | Select-String -Pattern $stashLabel -SimpleMatch | Select-Object -First 1).ToString()
                if ($stashRef -match '^(stash@\{\d+\})') {
                    $ref = $Matches[1]
                    git stash pop $ref 2>$null | Out-Null
                    if ($LASTEXITCODE -eq 0) {
                        Write-Success 'Local changes restored from stash.'
                    } else {
                        Write-Warn "Stash pop conflicted. Local changes preserved in stash '$stashLabel'."
                        Write-Info "Recover with: cd $CoworkDir; git stash list; git stash apply <stash@{N}>"
                    }
                }
            }

            Pop-Location
        }
    }

    # WORKFORCE/ replaced the legacy AGENTS/ name. Per-project runtime
    # lives under WORKFORCE\FLEETPROJECTS\<slug>\runtime\ and is created
    # lazily by ac-register, not at clone time.
    if ($canProceed -and (Test-Path (Join-Path $CoworkDir 'WORKFORCE'))) {
        # Legacy cleanup: earlier winSetup versions wired WORKFORCE\bin to
        # PATH from this section. Now owned by COWORK's deploy.ps1. Strip
        # any AGENTS\bin block this host may have left behind.
        # OneDrive can redirect Documents to a renamed path ("Documents 1")
        # and may also serve files as cloud-only stubs that Test-Path sees
        # but Get-Content can't open. Treat the legacy cleanup as best-effort:
        # if we can't read the profile, the AGENTS/bin line either isn't there
        # or isn't ours to worry about -- skip cleanly.
        $profilePath = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'PowerShell\Microsoft.PowerShell_profile.ps1'
        if (Test-Path $profilePath) {
            $profileContent = $null
            try {
                $profileContent = Get-Content $profilePath -Raw -ErrorAction Stop
            } catch {
                Write-Info "Legacy-cleanup skipped: couldn't read $profilePath ($($_.Exception.Message))"
            }
            if ($profileContent -and $profileContent -match 'COWORK.*AGENTS.*bin') {
                Write-Info 'Removing legacy COWORK\AGENTS\bin export from profile.'
                $cleaned = $profileContent -replace "(?ms)^\s*#\s*---\s*COWORK Multi-Agent Coordination\s*---\s*\r?\n\s*\`$env:Path\s*=.*?AGENTS\\bin.*?(\r?\n)", ''
                Set-Content -Path $profilePath -Value $cleaned -NoNewline
            }
        }

        # Hand off to COWORK's Stage 2 deployer for everything COWORK-internal:
        # skill + commands symlinks, WORKFORCE\bin PATH wiring,
        # ac-memory-init.ps1, daily backup scheduled task, plugin install.
        # See $CoworkDir\DEPLOYMENT.md for the full procedure.
        # Stage 2 symlinks land under ~/.claude/; this block can run BEFORE the
        # CONFIGS block (which also creates ~/.claude) or when CONFIGS isn't
        # selected, so ensure the dir exists first. Mirrors the New-Item guard
        # in the CONFIGS block. (Full Level-1-files-before-Stage-2 reorder is a
        # deferred Windows-live task — see infra worklist WS-9.)
        $claudeHomeEnsure = Join-Path $env:USERPROFILE '.claude'
        if (-not (Test-Path $claudeHomeEnsure)) {
            New-Item -ItemType Directory -Path $claudeHomeEnsure -Force | Out-Null
        }
        $deployScript = Join-Path $CoworkDir '.claude-config\deploy.ps1'
        if (Test-Path $deployScript) {
            Write-Info 'Invoking COWORK deploy.ps1 for Stage 2 setup...'
            # Spawn under the SAME interpreter we're running on (pwsh when
            # we're on PS7). Hardcoding `powershell.exe` drops to PS5.1,
            # which mis-decodes any UTF-8 non-ASCII in deploy.ps1 and
            # cascades parse errors. The PS7+admin gate at the top of this
            # script guarantees we're on pwsh.exe by the time we get here.
            $currentInterp = (Get-Process -Id $PID).Path
            try {
                & $currentInterp -NoProfile -ExecutionPolicy Bypass -File $deployScript
                if ($LASTEXITCODE -eq 0 -or $null -eq $LASTEXITCODE) {
                    Write-Success 'COWORK deploy.ps1 completed.'
                } else {
                    Write-Err "COWORK deploy.ps1 exited rc=$LASTEXITCODE. Re-run manually: $deployScript"
                }
            } catch {
                Write-Err "COWORK deploy.ps1 failed: $_"
            }
        } else {
            Write-Warn "COWORK deploy.ps1 not found at $deployScript -- Stage 2 skipped."
            Write-Warn "After fixing, run: $deployScript"
        }

        Write-Success 'COWORK deployed.'
        Write-Info 'Activation triggers: type ACTIVATE AGENT or ACTIVATE COORDINATOR in any Claude Code session.'
    } elseif ($canProceed) {
        Write-Warn 'COWORK/WORKFORCE/ not present in this branch. Skipping coordination setup.'
    }
}

# ═══════════════════════════════════════════════════════════════════════════════
#  CLAUDE PLUGINS -- Install after CONFIGS deploys settings.json
# ═══════════════════════════════════════════════════════════════════════════════

# Unconditional -- runs whenever claude is in PATH (matches shellSetup.sh behavior).
# settings.json (deployed above) contains extraKnownMarketplaces for caveman.
if (Get-Command claude -ErrorAction SilentlyContinue) {
    Write-Header 'Claude Code Plugins'
    Write-Info 'Registering caveman plugin marketplace...'
    $marketplaceOut = & claude plugin marketplace add JuliusBrussee/caveman 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Success 'Marketplace registered.'
        Write-Info 'Installing caveman plugin...'
        $pluginOut = & claude plugin install caveman@caveman 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Success 'Caveman plugin installed.'
        } else {
            Write-Warn "Plugin install returned: $pluginOut"
            Write-Warn 'Run manually: claude plugin install caveman@caveman'
        }
    } else {
        Write-Warn "Marketplace add returned: $marketplaceOut"
    }
}

# ═══════════════════════════════════════════════════════════════════════════════
#  DONE
# ═══════════════════════════════════════════════════════════════════════════════

Refresh-Path
Write-Host ''
Write-Header 'Setup Complete'
Write-Host ''
$installedNames = ($MenuItems | Where-Object { $_.On -and $_.Key -notin @('CONFIGS','APPS','TWEAKS','SSHKEY','COWORK') } |
    ForEach-Object { $_.Label }) -join ', '
if ($installedNames) {
    Write-Host "  Installed: $installedNames" -ForegroundColor White
    Write-Host ''
}

if ($Selected -contains 'CONFIGS') {
    Write-Host '  Configs deployed:' -ForegroundColor White
    Write-Host '    wezterm/.wezterm.lua        -> ~/.wezterm.lua'
    Write-Host '    powershell/profile.ps1      -> Documents/PowerShell/profile.ps1'
    Write-Host '    omp/.config/ohmyposh/*      -> ~/.config/ohmyposh/*'
    Write-Host '    windows-terminal/settings   -> AppData/.../WindowsTerminal/settings.json'
    Write-Host '    fastfetch/config.jsonc      -> ~/.config/fastfetch/config.jsonc'
    Write-Host '    claude/.claude/CLAUDE.md    -> ~/.claude/CLAUDE.md'
    Write-Host '    claude/.claude/settings.json-> ~/.claude/settings.json'
    Write-Host '    claude/.claude/statusline.sh-> ~/.claude/statusline.sh'
    Write-Host ''
}

if ($Selected -contains 'APPS') {
    Write-Host '  Extra apps installed via winget (idempotent)' -ForegroundColor White
    Write-Host ''
}

if ($Selected -contains 'TWEAKS') {
    Write-Host '  System tweaks applied:' -ForegroundColor White
    Write-Host '    Dark mode, file extensions visible, Explorer -> This PC'
    Write-Host '    Taskbar: centered, Copilot/Chat/TaskView/Search hidden'
    Write-Host '    Bing search disabled, Game DVR off, clipboard history on'
    Write-Host '    Bloatware auto-install blocked'
    Write-Host ''
}

if ($Selected -contains 'SSHKEY') {
    Write-Host '  SSH:' -ForegroundColor White
    Write-Host '    GitHub SSH key generated + CLI authenticated'
    Write-Host '    Test: ssh -T git@github.com'
    Write-Host ''
}

if ($Selected -contains 'COWORK') {
    Write-Host '  COWORK:' -ForegroundColor White
    Write-Host '    Multi-Agent Coordination deployed to ~/COWORK'
    Write-Host '    Triggers: ACTIVATE AGENT / ACTIVATE COORDINATOR'
    Write-Host ''
}

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
