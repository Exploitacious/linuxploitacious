# Linuxploitacious - Linux Shell and Config Setup

An interactive provisioning script for deploying a fully configured Linux environment. Optimized for Arch Linux and Debian/Kali (including WSL).
Centralizes config files and scripts across multiple machines using GNU Stow and Git.

---

## Quick Start

**Remote execution (fresh machine):**

```bash
wget -qO shellSetup.sh https://shell.ivantsov.tech && bash shellSetup.sh
```

```bash
curl -fsSL https://shell.ivantsov.tech | bash
```

**Re-running on an existing machine:**

```bash
cd ~/linuxploitacious && git pull && bash shellSetup.sh
```

The script is fully idempotent. It can be re-run at any time without conflicts. Existing configs are backed up automatically and the repository is always deployed as the source of truth.

### Idempotency: Safe to Re-Run

All components are designed to be safely re-run:

| Component | Safety Mechanism |
|-----------|------------------|
| Package install | `--needed` flag (Arch) won't reinstall existing packages |
| Oh My Zsh | Skips if `~/.oh-my-zsh` already exists |
| Oh My Posh | Skips if binary already installed |
| TPM | Skips if `~/.tmux/plugins/tpm` exists |
| Stow | Removes old symlinks first, then deploys fresh |
| NVM | Skips if `~/.nvm` already exists |
| Node.js | `nvm install --lts` is safe to re-run |
| AI tool symlinks | Removes and recreates symlinks (no duplicates) |
| SSH keys | Skips if key already exists |

**No data loss** - sessions, configs, and credentials are preserved on re-run.

---

## How It Works

### Bootstrap Flow (`shellSetup.sh`)

The script uses a two-stage architecture:

1. **Remote stage** - When piped from a URL (`curl | bash`), it detects there's no `.git` directory, installs Git, clones the repo to `~/linuxploitacious`, then uses `exec ./shellSetup.sh` to hand off to the local copy.
2. **Local stage** - Presents an interactive menu (via `whiptail`) and executes selected components.

### Menu Options

| Option | Description | Default |
|--------|-------------|---------|
| BASE | OS updates, core packages (zsh, stow, tmux, fzf, btop, fastfetch, etc.) | ON |
| NODE | Node.js via NVM, pnpm, AI tools (Gemini CLI, OpenCode, Claude Code) | ON |
| SHELL | Zsh, Oh My Zsh, Oh My Posh theming, Tmux Plugin Manager | ON |
| STOW | Deploy all repo configs to `$HOME` via GNU Stow | ON |
| BRAVE | Brave Browser | OFF |
| ROOT | Replicate user profile to root (configs, NVM, OMZ, OMP, TPM) | OFF |
| SSHKEY | Generate GitHub SSH key, configure SSH, copy to root | OFF |

---

## ROOT Profile Setup

The ROOT option replicates your user profile to the root account:

- Installs missing packages (btop, tmux, fzf, zsh)
- Changes root's shell to zsh
- Installs Oh My Zsh, Oh My Posh, and TPM for root
- Deploys configs via stow to `/root` (symlinks to this repo)
- Shares AI tool data directories with root (OpenCode, Gemini CLI, Claude Code)
- Installs NVM, Node.js LTS, and pnpm for root
- Installs global AI tools (gemini-cli, opencode-ai, claude-code) for root

**AI Tool Data Sharing:**

The following directories are symlinked from your user to `/root`, allowing seamless session continuity:
- `~/.gemini/` - Gemini CLI auth and history
- `~/.claude/` - Claude Code sessions and credentials
- `~/.claude.json` - Claude Code config
- `~/.local/share/opencode/` - OpenCode database and auth

**After running:** Use `sudo -i` to access root's configured environment.

---

## GitHub SSH Key Setup

The SSHKEY option sets up SSH authentication for GitHub:

- Generates ed25519 SSH key at `~/.ssh/id_ed25519` (if not exists)
- Uses email from `git config --global user.email` for the key comment
- Configures `~/.ssh/config` for GitHub
- Switches git remote from HTTPS to SSH
- Copies key pair to `/root/.ssh/` for root access

**After running:** Upload the displayed public key to https://github.com/settings/keys

---

## GNU Stow: How Config Deployment Works

GNU Stow is a stateless symlink manager. It has no daemon, no database. It reads a "package" directory and creates symlinks that mirror its structure into a target directory (`$HOME`).

### The Directory Math

Stow ignores the package folder name itself. The *contents* of the package folder map directly to `$HOME`:

```
stow -t ~ zsh        # zsh/.zshrc          -> ~/.zshrc
stow -t ~ tmux       # tmux/.tmux.conf     -> ~/.tmux.conf
stow -t ~ btop       # btop/.config/btop/  -> ~/.config/btop/
```

### 4-Phase Conflict Resolution (Re-run Safe)

When deploying, the script runs four phases per package to guarantee a clean deployment:

| Phase | Action | Purpose |
|-------|--------|---------|
| 1. Unstow | `stow -D` removes previous symlinks | Clean slate from prior runs |
| 2. Clean | Remove stale/broken symlinks at targets | Handle moved or renamed files |
| 3. Backup | Move real files to `<file>.backup_<timestamp>` | Preserve local configs safely |
| 4. Stow | `stow -v` creates fresh symlinks | Deploy repo as source of truth |

This means: **the repository always wins**. Any local file that conflicts gets timestamped backups (never overwritten), and the symlink is recreated pointing to the repo.

### Repository Architecture

**Rule:** The repo root is strictly for management scripts and documentation. All deployable files must exist inside a designated package folder.

```text
~/linuxploitacious/
├── README.md                          # This documentation (not stowed)
├── shellSetup.sh                      # Bootstrap script (not stowed)
├── bash/                              # Package: Bash config
│   └── .bashrc                        #   -> ~/.bashrc
├── zsh/                               # Package: Zsh config
│   └── .zshrc                         #   -> ~/.zshrc
├── tmux/                              # Package: Tmux config
│   └── .tmux.conf                     #   -> ~/.tmux.conf
├── btop/                              # Package: Btop config
│   └── .config/btop/
│       └── btop.conf                  #   -> ~/.config/btop/btop.conf
├── fastfetch/                         # Package: Fastfetch config
│   └── .config/fastfetch/
│       └── config.jsonc               #   -> ~/.config/fastfetch/config.jsonc
├── omp/                               # Package: Oh My Posh themes
│   └── .config/ohmyposh/
│       ├── kali.json                  #   -> ~/.config/ohmyposh/kali.json
│       └── zen.toml                   #   -> ~/.config/ohmyposh/zen.toml
├── rustscan/                          # Package: RustScan config
│   └── .rustscan.toml                 #   -> ~/.rustscan.toml
├── scripts/                           # Package: Utility scripts
│   └── .local/bin/
│       ├── start-kex                  #   -> ~/.local/bin/start-kex
│       ├── usb-attach                 #   -> ~/.local/bin/usb-attach
│       ├── pbcopy                     #   -> ~/.local/bin/pbcopy
│       ├── pbpaste                    #   -> ~/.local/bin/pbpaste
│       └── launch_nordvpn             #   -> ~/.local/bin/launch_nordvpn
└── dockerHost/                        # NOT a stow package (docker infra, unrelated)
    ├── docker-compose.yml
    └── dockerhost.md
```

---

## Alias Quick Reference

These aliases are defined in both `.bashrc` and `.zshrc` and available in either shell.

### Shell Navigation

| Alias | Command | Description |
|-------|---------|-------------|
| `c` | `clear` | Clear the terminal |
| `x` | `exit` | Exit the shell |
| `e` | `code -n ~/ ~/.zshrc ...` | Open home dir and shell config in VS Code |
| `r` | `source ~/.zshrc` / `source ~/.bashrc` | Reload shell configuration |
| `h` | `history -10` | Show last 10 history entries |
| `hc` | `history -c` | Clear shell history |
| `hg` | `history \| grep` | Search history (e.g., `hg docker`) |
| `ag` | `alias \| grep` | Search aliases (e.g., `ag rust`) |

### File System

| Alias | Command | Description |
|-------|---------|-------------|
| `ls` | `ls -alFh --color=auto --time-style=long-iso` | Detailed file listing |
| `ll` | (same as `ls`) | Alias for `ls` |
| `cd..` | `cd ..` | Go up one directory (typo-friendly) |
| `cd...` | `cd .. && cd ..` | Go up two directories |
| `vsc` | `cd /mnt/c/users/Alex/VSCODE` | Jump to VS Code workspace (WSL) |

### Package Management

| Alias | Command | Description |
|-------|---------|-------------|
| `sapu` | `sudo apt-get update` | Quick apt update |

### Networking / Security

| Alias | Command | Description |
|-------|---------|-------------|
| `myip` | `curl -s http://ipecho.net/plain; echo` | Show public IP address |
| `connectnord` | `sudo ~/.local/bin/launch_nordvpn` | Launch NordVPN (OpenVPN wrapper) |
| `rustscan` | `sudo docker run ... rustscan/rustscan:2.1.1` | Run RustScan via Docker (full port scan, hands off to nmap) |

### Git / Utilities

| Alias | Command | Description |
|-------|---------|-------------|
| `gcu` | `git config user.name "..." && git config user.email "..."` | Set local git identity |
| `distro` | `cat /etc/*-release` | Show distro information |

---

## Utility Scripts (`~/.local/bin/`)

| Script | Description |
|--------|-------------|
| `start-kex` | Manages Kali Win-KeX sessions (ESM/VNC/RDP) for WSL |
| `usb-attach` | Forwards USB devices from Windows to WSL via `usbip` |
| `pbcopy` / `pbpaste` | macOS-style clipboard commands using `xclip` |
| `launch_nordvpn` | Self-provisioning NordVPN OpenVPN wrapper with random server selection |

---

## Tmux Configuration

| Setting | Value |
|---------|-------|
| Prefix | `Ctrl+Space` (instead of default `Ctrl+B`) |
| Window/pane indexing | Starts at 1 (not 0) |
| Copy mode | Vi keybindings |
| Mouse | Enabled |
| Theme | Catppuccin (via TPM) |
| Pane splits | Open in current working directory |

**First run:** After opening tmux, press `Ctrl+Space` then `I` (capital i) to install plugins via TPM.

---

## Snapper Snapshot Guide: Managing System Backups

This guide explains how to use **Snapper** on your Arch Linux system to create, manage, and restore system snapshots. Your system is configured to take automatic snapshots of the root filesystem (`/`).

### ⚙️ Current Configuration
- **Tool**: `snapper` (Btrfs snapshot manager).
- **Target**: Root filesystem (`/`).
- **Automatic Retention Policy**:
  - **Hourly**: Keeps the last **10** hourly snapshots.
  - **Daily**: Keeps the last **7** daily snapshots.
  - **Weekly/Monthly/Yearly**: Disabled (0).
- **Package Manager Integration**:
  - **snap-pac**: Installed. Automatically creates a "pre" snapshot before any pacman transaction and a "post" snapshot after.

### 📸 Managing Snapshots

#### 1. Listing Snapshots
To see all current snapshots, including their type (single, pre, post) and description:
```bash
sudo snapper -c root list
```

#### 2. Creating a Manual Snapshot
Before making risky changes (e.g., editing system configs, installing experimental software), create a manual checkpoint:
```bash
sudo snapper -c root create -d "Description of the checkpoint"
```
*   `-c root`: Specifies the config (root filesystem).
*   `-d "..."`: Adds a description to the snapshot.

#### 3. Deleting Snapshots
To manually delete a specific snapshot (replace `NUMBER` with the ID from `list`):
```bash
sudo snapper -c root delete NUMBER
```

#### 4. Comparing Snapshots
To see what files changed between two snapshots (e.g., between snapshot 10 and 11):
```bash
sudo snapper -c root status 10..11
```
To see the actual content differences (diff) of a specific file:
```bash
sudo snapper -c root diff 10..11 /path/to/file
```

### 🔄 Restoration Guide (Rollback)

Since your system uses a standard Btrfs layout with specific subvolumes (`@`, `@home`, `@snapshots`), the safest way to restore the *entire* system is via a live environment.

#### ⚠️ Warning
Restoring the root filesystem will revert system files (`/etc`, `/usr`, `/var`) to a previous state. Your home directory (`/home`) is on a separate subvolume (`@home`) and **will not be touched**, so your personal files are safe.

#### Step-by-Step Restoration
1.  **Boot Live ISO**: Insert your Arch Linux USB installation media and boot into it.
2.  **Mount Root Partition**:
    Identify your root partition (likely `/dev/nvme0n1p4` based on your setup):
    ```bash
    mount /dev/nvme0n1p4 /mnt
    ```
3.  **Locate Snapshot**:
    Snapshots are stored in `.snapshots/`. List them to find the one you want (check the timestamp):
    ```bash
    ls -l /mnt/@snapshots/*/snapshot
    ```
    *Note the number of the snapshot directory (e.g., `/mnt/@snapshots/55/snapshot`).*

4.  **Backup Current State (Optional but Recommended)**:
    Move the current broken system subvolume to a backup name:
    ```bash
    mv /mnt/@ /mnt/@_broken_$(date +%Y%m%d)
    ```

5.  **Restore the Snapshot**:
    Create a read-write snapshot of the desired backup into the root position (`@`):
    ```bash
    btrfs subvolume snapshot /mnt/@snapshots/NUMBER/snapshot /mnt/@
    ```
    *(Replace `NUMBER` with the snapshot ID you chose).*

6.  **Reboot**:
    Unmount and reboot into your restored system:
    ```bash
    umount /mnt
    reboot
    ```

#### Post-Restoration Cleanup
Once you have successfully booted and verified the system is working, you can delete the broken backup subvolume to free up space:
```bash
sudo btrfs subvolume delete /mnt/@_broken_YYYYMMDD
```

---

## Troubleshooting

### "CONFIG NOT FOUND" or missing prompt theme

**Cause:** Oh My Posh can't find `~/.config/ohmyposh/kali.json`.

**Fix:** Re-run the STOW deployment:
```bash
cd ~/linuxploitacious && bash shellSetup.sh
# Select STOW from the menu
```
Or deploy manually:
```bash
cd ~/linuxploitacious && stow -R -t ~ omp
```

### Stow reports "existing target" conflicts

**Cause:** A real file exists where stow wants to create a symlink.

**Fix:** The setup script handles this automatically by backing up conflicting files. If running stow manually:
```bash
# Back up the conflicting file, then restow
mv ~/.zshrc ~/.zshrc.backup
cd ~/linuxploitacious && stow -t ~ zsh
```

### Stale symlinks after changing repo structure

**Cause:** Files were renamed or moved in the repo, but old symlinks still exist in `$HOME`.

**Fix:** Unstow the old package, then stow fresh:
```bash
cd ~/linuxploitacious
stow -D -t ~ <package>    # Remove old symlinks
stow -t ~ <package>       # Create new ones
```
Or simply re-run `shellSetup.sh` -- it does this automatically.

### Verifying stow deployment

Check that configs are properly symlinked:
```bash
ls -la ~/.zshrc ~/.bashrc ~/.tmux.conf
# Should show -> linuxploitacious/...

ls -la ~/.config/ohmyposh/ ~/.config/fastfetch/ ~/.config/btop/
# Should show -> ../linuxploitacious/... or actual symlinked files
```

### Shell changes not taking effect

After editing configs in the repo, reload your shell:
```bash
r          # Uses the 'r' alias to re-source your shell config
# OR
source ~/.zshrc
source ~/.bashrc
```

### Oh My Posh or Fastfetch not loading

Both commands are wrapped in `command -v` guards. If they don't appear:
1. Verify they're installed: `which oh-my-posh` / `which fastfetch`
2. If missing, re-run `shellSetup.sh` with BASE selected
3. Ensure `~/.local/bin` is in your PATH: `echo $PATH | tr ':' '\n' | grep local`

### Manual stow commands reference

```bash
cd ~/linuxploitacious

# Deploy a single package
stow -t ~ zsh

# Restow (unstow + stow, good for updates)
stow -R -t ~ zsh

# Remove a package's symlinks
stow -D -t ~ zsh

# Deploy all packages
for pkg in bash zsh tmux btop fastfetch omp rustscan scripts; do
  stow -R -t ~ "$pkg"
done
```

---

## Making Changes to Configs

Since all config files in `$HOME` are symlinks pointing to this repo, you can edit them in-place:

```bash
# Edit directly (changes are immediately in the repo)
vim ~/.zshrc

# Or edit from the repo
vim ~/linuxploitacious/zsh/.zshrc

# Both edit the same file. Commit and push when ready:
cd ~/linuxploitacious
git add -A && git commit -m "update zsh config" && git push
```

On other machines, pull and restow:
```bash
cd ~/linuxploitacious && git pull
# Symlinks already point to the repo files, so changes are instant after pull
```

---

## dockerHost

This folder is unrelated to the stow dotfiles. It contains a Docker Compose stack for separate infrastructure. It is not deployed by `shellSetup.sh` and can be ignored or deleted.
