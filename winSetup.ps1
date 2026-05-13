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
#  MENU — Interactive Component Selector
# ═══════════════════════════════════════════════════════════════════════════════

$MenuItems = @(
    [PSCustomObject]@{ Key = 'PS7';     On = $true;  Label = 'PowerShell 7';      Desc = 'Modern shell (winget)' }
    [PSCustomObject]@{ Key = 'WEZTERM'; On = $true;  Label = 'WezTerm';           Desc = 'GPU terminal emulator' }
    [PSCustomObject]@{ Key = 'OMP';     On = $true;  Label = 'Oh My Posh';        Desc = 'Prompt engine + catppuccin theme' }
    [PSCustomObject]@{ Key = 'FONT';    On = $true;  Label = 'JetBrains Mono NF'; Desc = 'Nerd Font with ligatures' }
    [PSCustomObject]@{ Key = 'FETCH';   On = $true;  Label = 'Fastfetch';         Desc = 'System info on shell launch' }
    [PSCustomObject]@{ Key = 'JQ';      On = $true;  Label = 'jq';               Desc = 'JSON processor (Claude statusline)' }
    [PSCustomObject]@{ Key = 'CLAUDE';  On = $true;  Label = 'Claude Code';       Desc = 'AI coding assistant' }
    [PSCustomObject]@{ Key = 'CONFIGS'; On = $true;  Label = 'Deploy configs';    Desc = 'Symlink all dotfiles' }
    [PSCustomObject]@{ Key = 'APPS';    On = $false; Label = 'Extra apps';        Desc = 'Browsers, dev tools, productivity' }
    [PSCustomObject]@{ Key = 'TWEAKS';  On = $false; Label = 'System tweaks';     Desc = 'Dark mode, Explorer, taskbar prefs' }
    [PSCustomObject]@{ Key = 'SSHKEY';  On = $false; Label = 'GitHub SSH + CLI';  Desc = 'SSH key, gh auth, key upload' }
    [PSCustomObject]@{ Key = 'COWORK';  On = $false; Label = 'COWORK';            Desc = 'Multi-Agent Coordination (needs SSH)' }
)

while ($true) {
    Write-Header 'Select Components'
    Write-Host ''
    Write-Host '  Toggle items by number, then press Enter to proceed.' -ForegroundColor DarkGray
    Write-Host '  All components are idempotent — safe to re-run.' -ForegroundColor DarkGray
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
    $input = Read-Host '  Toggle (1-12 / all / none / q=quit) or Enter to proceed'

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
    Write-Warn 'COWORK requires SSHKEY — enabling automatically.'
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

if ($Selected -contains 'CLAUDE') {
    Write-Header 'Claude Code'
    if (Get-Command claude -ErrorAction SilentlyContinue) {
        Write-Info 'Claude Code already installed.'
    } else {
        Write-Info 'Installing Claude Code...'
        winget install --id Anthropic.ClaudeCode -e --accept-package-agreements --accept-source-agreements 2>$null
        if ($LASTEXITCODE -ne 0) {
            Write-Warn 'winget install failed. Trying npm...'
            if (Get-Command npm -ErrorAction SilentlyContinue) {
                npm install -g @anthropic-ai/claude-code
            } else {
                Write-Warn 'Install Claude Code manually: https://claude.ai/code'
            }
        }
    }
}

# ═══════════════════════════════════════════════════════════════════════════════
#  APPS — Extra Applications via Winget
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
        @{ Id = 'Schniz.fnm';                   Name = 'Fast Node Manager (fnm)' }
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
#  TWEAKS — Windows System Preferences
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
            Write-Info "$($t.Desc) — already set"
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
            Write-Warn 'Execution policy requires admin — run as Administrator to set.'
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
#  SSHKEY — GitHub SSH Key, CLI & Auth
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
#  COWORK — Multi-Agent Coordination
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
            # Idempotent sync — handles dirty working trees by stashing local
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
                Write-Info "Uncommitted changes detected — stashing as '$stashLabel'..."
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
        # Add WORKFORCE/bin to PATH via PS profile (idempotent + clean up legacy AGENTS reference).
        $workforceBin = Join-Path $CoworkDir 'WORKFORCE\bin'
        $profilePath = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'PowerShell\Microsoft.PowerShell_profile.ps1'
        if (Test-Path $profilePath) {
            $profileContent = Get-Content $profilePath -Raw
            $alreadyWired = $profileContent -match 'COWORK.*WORKFORCE.*bin'
            $hasLegacy    = $profileContent -match 'COWORK.*AGENTS.*bin'

            if ($hasLegacy -and -not $alreadyWired) {
                # Remove legacy two-line block (header comment + AGENTS\bin export).
                Write-Info 'Removing legacy COWORK\AGENTS\bin export from profile.'
                $cleaned = $profileContent -replace "(?ms)^\s*#\s*---\s*COWORK Multi-Agent Coordination\s*---\s*\r?\n\s*\`$env:Path\s*=.*?AGENTS\\bin.*?(\r?\n)", ''
                Set-Content -Path $profilePath -Value $cleaned -NoNewline
                $profileContent = $cleaned
                $hasLegacy = $false
            }

            if (-not $alreadyWired) {
                $pathLine = "`n# --- COWORK Multi-Agent Coordination ---`n`$env:Path = `"$workforceBin;`$env:Path`""
                Add-Content -Path $profilePath -Value $pathLine
                Write-Success 'Added WORKFORCE/bin to PATH in PowerShell profile.'
            } else {
                Write-Info 'WORKFORCE/bin already on PATH in profile.'
            }
        }

        # Initialize Claude Code auto-memory git-sync (Option A doctrine).
        # See ~\COWORK\WORKFORCE\FLEETPROJECTS\project-leisure\runtime\decisions\
        #     2026-05-13__memory-sync-doctrine.md
        # Script is idempotent: safe on fresh installs, existing dirs, and re-runs.
        # Requires Windows Developer Mode (Settings → For Developers) OR an elevated
        # PowerShell session for the symlink creation step.
        $memInit = Join-Path $CoworkDir 'WORKFORCE\bin\ac-memory-init.ps1'
        if (Test-Path $memInit) {
            Write-Info 'Initializing Claude Code auto-memory git-sync...'
            try {
                # -AutoCommit: if init creates a new per-host memory subdir,
                # stage + commit + push it. Only commits the exact target path.
                & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $memInit -AutoCommit
                if ($LASTEXITCODE -eq 0) {
                    Write-Success 'Memory sync initialized (or already in place).'
                } elseif ($LASTEXITCODE -eq 2) {
                    Write-Warn 'ac-memory-init: .gitignore excludes the target path. Fix .gitignore then re-run.'
                } else {
                    Write-Warn "ac-memory-init.ps1 exited non-zero (rc=$LASTEXITCODE). Likely cause: Developer Mode not enabled OR not running as Administrator. Enable Dev Mode (Settings → Update & Security → For Developers) or re-run as admin."
                }
            } catch {
                Write-Warn "ac-memory-init.ps1 failed: $_"
            }
        } else {
            Write-Info 'ac-memory-init.ps1 not present yet — skipping memory sync init.'
        }

        Write-Success 'COWORK deployed.'
        Write-Info 'Activation triggers: type ACTIVATE AGENT or ACTIVATE COORDINATOR in any Claude Code session.'
    } elseif ($canProceed) {
        Write-Warn 'COWORK/WORKFORCE/ not present in this branch. Skipping coordination setup.'
    }
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

    # PowerShell profile — deploy to both PS7 and PS5.1
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
        Write-Warn 'Windows Terminal not found — skipping settings deploy.'
    }

    # Claude Code statusline (copy — symlink requires admin in ~/.claude/)
    $statuslineSource = Join-Path $RepoDir 'claude\.claude\statusline.sh'
    $statuslineTarget = Join-Path $env:USERPROFILE '.claude\statusline.sh'
    if (Test-Path (Split-Path $statuslineTarget -Parent)) {
        if (Test-Path $statuslineSource) {
            Copy-Item $statuslineSource $statuslineTarget -Force
            Write-Success "Copied: statusline.sh -> ~/.claude/statusline.sh"
        }
    } else {
        Write-Warn 'Claude Code not initialized — run claude once first, then re-run setup.'
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
    Write-Host '    claude/.claude/statusline   -> ~/.claude/statusline.sh'
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
