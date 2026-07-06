# Linuxploitacious

An opinionated, interactive provisioning system for deploying a fully configured shell environment on **Linux** and **Windows**. The goal: same tools, same config, same experience on every machine.

- **Linux** (`shellSetup.sh`): Arch Linux, Debian/Kali, WSL. Uses GNU Stow for config deployment.
- **Windows** (`winSetup.ps1`): PowerShell 7, WezTerm, winget-based. Uses symlinks (with junction fallback) for config deployment.

Both scripts are maintained in parallel and should be kept in sync when adding features. See [Keeping scripts in sync](#keeping-scripts-in-sync) below.

## Expected Location

This repo must live at **`~/linuxploitacious/`** on both Linux and Windows. The home-folder location is canonical because:

- **Linux**: Stow operates on the home folder. Symlinks expect the repo to be a sibling of `~/.bashrc`, `~/.zshrc`, etc.
- **Windows**: Symlinks/junctions for the matching configs target the same relative home-folder layout for consistency across OSes.

Do **not** place this repo under `~/COWORK/PROJECTS/` or any other path. It is the outlier in Alex's repo portfolio — it lives outside the standard `PROJECTS/<space>/<repo>/` convention for this reason.

If you ever find a stray copy at `~/COWORK/PROJECTS/linuxploitacious/`, delete it; the canonical clone is `~/linuxploitacious/`.

---

## Quick Start

**Remote execution (fresh machine):**

Linux (bash/zsh):

```bash
curl -fsSL https://shell.ivantsov.tech | bash
```

Windows (PowerShell, elevated):

```powershell
irm https://winshell.ivantsov.tech | iex
```

**Re-running on an existing machine:**

Linux:

```bash
cd ~/linuxploitacious && git pull && bash shellSetup.sh
```

Windows (PowerShell):

```powershell
cd $HOME\linuxploitacious; git pull; .\winSetup.ps1
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
| BASE | OS updates, core packages (zsh, stow, tmux, fzf, btop, fastfetch, cloudflared, etc.) | ON |
| NODE | Node.js via NVM and pnpm | ON |
| PYTHON | Python via pyenv + pip packages | ON |
| SHELL | Zsh, Oh My Zsh (with autosuggestions, syntax-highlighting, completions, fzf-tab), Oh My Posh, TPM | ON |
| STOW | Deploy all repo configs to `$HOME` via GNU Stow | ON |
| TMUX | Tmux persistence: SSH auto-attach + `tmux-main.service` systemd unit + linger | ON |
| DOCKER | Docker Engine (docker-ce + buildx + compose plugin), adds user to `docker` group | OFF |
| BRAVE | Brave Browser | OFF |
| ROOT | Replicate user profile to root (configs, NVM, OMZ, OMP, TPM) | OFF (hidden when running as root) |
| NOPASS | Enable passwordless sudo for current user (drops `/etc/sudoers.d/90-<user>-nopasswd`, visudo-validated) | OFF (hidden when running as root) |
| SWAP | Create swapfile sized to match RAM (`/swapfile`, `vm.swappiness=10`) | ON (hidden when swap already exists) |
| SSHKEY | Generate GitHub SSH key, configure SSH, copy to root | OFF |
| COWORK | Clone Alex's private Stage 2 repo (`Exploitacious/COWORK`) and invoke its `deploy.sh`. Requires SSHKEY. Forkers: replace with your own Stage 2 repo (see "Forking this repo" below). | OFF |

**Always runs (no menu toggle):** Claude Code and OpenCode install via their official vendor scripts (`curl -fsSL https://claude.ai/install.sh | bash` and `curl -fsSL https://opencode.ai/install | bash`), dropping native binaries into `~/.local/bin/claude` and `~/.opencode/bin/opencode`. Legacy pnpm/npm-global installations of these tools (and Gemini) are detected and removed on every run to prevent shims from shadowing the native binaries.

> **Supply chain note:** The two installers are fetched unpinned at setup time. Acceptable for a personal dotfiles repo; pin to a version (`bash -s <version>` for Claude) or checksum-verify if you plan to run this on machines you don't own.

---

## Claude Code Setup

Claude Code configuration is deployed in **two stages**. This repo
(`linuxploitacious`) is **Stage 1** — host setup + Level 1 Claude
files only. Anything personal / opinionated / multi-machine-state
belongs in **Stage 2** (your own private repo). Alex's Stage 2 lives
at [`Exploitacious/COWORK`](https://github.com/Exploitacious/COWORK)
(private); fork the pattern with your own.

**Stage 1 — Level 1 files (this repo):** The `claude/` directory
deploys `~/.claude/CLAUDE.md` (behavioral rules, conversational
compression), `~/.claude/settings.json` (model, effort level,
permissions), and `~/.claude/statusline.sh` using absolute symlinks
instead of stow. Absolute is necessary because stow's relative
symlinks break when chained through the ROOT profile's `~/.claude` →
`/home/user/.claude` symlink. These config files apply to every
Claude Code session regardless of project directory.

**Stage 1 — Plugins:** After Claude Code installs (via the always-on
vendor installer), the script registers the
[caveman](https://github.com/JuliusBrussee/caveman) plugin — an
ultra-compressed communication mode that reduces token usage while
keeping full technical accuracy. It activates automatically via
SessionStart hooks.

**Stage 2 — COWORK (optional):** Selecting `COWORK` in the menu
clones the user's private workspace repo to `~/COWORK/` and then
auto-invokes `~/COWORK/.claude-config/deploy.sh`. That Stage 2
script owns everything COWORK-specific — skills symlink
(`~/.claude/skills/` → `~/COWORK/SKILLS/`), commands symlink,
`WORKFORCE/bin` PATH wiring, `claude-wrapper.sh` sourcing for
master + root rcs, `ac-memory-init` auto-memory git-sync, daily
backup cron, and additional plugins. **This repo deliberately does
NOT do any of those steps** — keeping the Stage 1 / Stage 2
boundary clean means Stage 1 stays usable without a private repo,
and Stage 2 stays the single source of truth for COWORK content.

**ROOT sharing:** The ROOT option symlinks `~/.claude/` from the
user account to `/root`, so both users share the same config,
sessions, and credentials. The `claude/` stow package is
intentionally excluded from ROOT's stow deployment to avoid
conflicting with this symlink.

**Personalizing Claude with a context directory:** The global
CLAUDE.md includes a "Context Awareness" section that checks for
`~/COWORK/CONTEXT/` at session start. If you fork this repo,
replace that path with your own. The idea: keep a directory
somewhere on your machine with markdown files that describe who
you are, how you communicate, and how you want Claude to behave
(`about-me.md`, `brand-voice.md`, `working-preferences.md`, or
whatever fits). The global CLAUDE.md points Claude there so every
session starts with that context, even when you're working in an
unrelated project. You don't need a full COWORK setup — any
directory with a few context files works. Project-level
`CLAUDE.md` files then layer on top for project-specific
instructions.

---

---

## Forking this repo

This repo is public + opinionated. The Stage 1 layer (host setup,
shell config, Level 1 Claude files) is intentionally generic and
runs cleanly on any machine. The COWORK references that exist are
pointers to Alex's **private** Stage 2 repo
(`Exploitacious/COWORK`); they're already self-gating (every
COWORK code path checks for the directory before doing anything),
so a fork without your own COWORK works out-of-the-box.

If you want your own Stage 2 layer, here's the complete list of
things to change in a fork:

1. **`shellSetup.sh::setup_cowork`** (the `gh repo clone` call
   inside this function) — change
   `gh repo clone Exploitacious/COWORK` to your own private repo
   path. The function will clone it to `$HOME/COWORK` and then
   invoke `$HOME/COWORK/.claude-config/deploy.sh` on completion.
2. **`winSetup.ps1` COWORK section** (the `gh repo clone` call in
   the COWORK block) — same change,
   `gh repo clone Exploitacious/COWORK`.
3. **`claude/.claude/CLAUDE.md`** "COWORK Context Awareness"
   section — either replace `~/COWORK/` with your own personal
   context directory path, or delete the section entirely. The
   rest of the file is generic.
4. **`claude/.claude/settings.json`** SessionStart hook (in the
   SessionStart hooks array) — references
   `$HOME/COWORK/WORKFORCE/bin/ac-reorient`. The
   `test -x` guard makes it silent without COWORK, so you can
   leave it alone. Replace the path if you want the hook to fire
   from your own Stage 2.
5. **README references** — search for `COWORK` and replace with
   your own Stage 2 repo name in user-facing prose.

If you don't want a Stage 2 layer at all, skip steps 1-2-5 and
just delete the COWORK menu items in `shellSetup.sh` + `winSetup.ps1`
(or leave them — they're opt-in and fail-safe when the gh CLI
isn't authenticated).

## Stage 2 contract (what `setup_cowork` assumes)

`setup_cowork` (Linux) and the COWORK menu item (Windows) clone
the private Stage 2 repo, then invoke its `deploy.{sh,ps1}` to
finish setup. For that handoff to work, the Stage 2 repo MUST
expose at minimum:

| Path | Purpose |
|------|---------|
| `.claude-config/deploy.sh` (Linux) | Stage 2 entry point. Stage 1 invokes via `bash $COWORK_DIR/.claude-config/deploy.sh`. Idempotent. |
| `.claude-config/deploy.ps1` (Windows) | Same for Windows. Stage 1 invokes via `powershell.exe -File ...`. Idempotent. |
| `WORKFORCE/` directory | Existence-checked by Stage 1 before invoking deploy.{sh,ps1}. If absent, Stage 1 skips Stage 2 with a warning. |

Optional (referenced if present; silent otherwise):

| Path | Purpose |
|------|---------|
| `WORKFORCE/bin/ac-reorient` | Invoked by the SessionStart hooks array in `claude/.claude/settings.json`. Guarded by `test -x`. |
| `CONTEXT/` directory | Read by Claude Code per `claude/.claude/CLAUDE.md` "COWORK Context Awareness" section. Existence-checked. |

Stage 2 is responsible for everything else — its own symlinks
(skills, commands), PATH wiring, plugin installs, scheduled
tasks, auto-memory wiring, claude-wrapper sourcing, etc. Stage 1
deliberately does NOT do any of that work; the split keeps this
repo public-safe and Stage 2 the single source of truth for
private content. See Alex's COWORK `DEPLOYMENT.md` for a working
example of a Stage 2 implementation.

---

## Windows Setup (`winSetup.ps1`)

The Windows script mirrors the Linux experience as closely as possible. Run from an elevated PowerShell:

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force
.\winSetup.ps1
```

### Windows Menu Options

| Option | Description | Default |
|--------|-------------|---------|
| PS7 | PowerShell 7 (winget) | ON |
| WEZTERM | GPU terminal emulator | ON |
| OMP | Oh My Posh + catppuccin theme | ON |
| FONT | JetBrains Mono Nerd Font | ON |
| FETCH | Fastfetch | ON |
| NODE | fnm + Node LTS + pnpm (via corepack) | ON |
| PYTHON | Python 3, pip globals, pipx tools | ON |
| JQ | jq JSON processor (Claude statusline) | ON |
| CLAUDE | Claude Code + OpenCode + legacy cleanup | ON |
| CONFIGS | Symlink all dotfiles + Level 1 Claude config (CLAUDE.md, settings.json, statusline.sh). **Does NOT deploy COWORK content** — Stage 2 (`deploy.ps1`) owns that. | ON |
| APPS | Browsers, dev tools, productivity (opt-in) | OFF |
| TWEAKS | Dark mode, Explorer, taskbar prefs | OFF |
| SSHKEY | GitHub SSH + gh auth + key upload | OFF |
| COWORK | Multi-Agent Coordination (needs SSH) | OFF |

**Always runs (no menu toggle):** Claude Code plugin installation (caveman) after CONFIGS deploys `settings.json`.

### Key differences from Linux

| Concern | Linux | Windows |
|---------|-------|---------|
| Config deployment | GNU Stow (relative symlinks) | `Deploy-Symlink` (symlink → junction → copy fallback) |
| Node version manager | NVM | fnm |
| Terminal | tmux inside any terminal | WezTerm (native panes) |
| Shell | Zsh + Oh My Zsh | PowerShell 7 + Oh My Posh |
| Package manager | apt/pacman | winget |
| Root sharing | Symlink `~/.claude/` to `/root` | N/A (single-user) |

---

## Keeping Scripts in Sync

`shellSetup.sh` and `winSetup.ps1` are maintained in parallel. When adding a feature to one, check whether the other needs a matching change. The menu items should stay aligned — same names, same defaults, same order where practical.

**What to sync:** Tool installations, config file deployments, Level 1 Claude Code setup (CLAUDE.md + settings.json + statusline.sh + caveman plugin), AI tool management (install, legacy cleanup), menu structure. Stage 2 content (skills, commands, WORKFORCE, ac-memory-init) is NOT this repo's responsibility — Stage 2 owns it.

**What diverges by design:** Platform-specific tools (tmux vs WezTerm, stow vs Deploy-Symlink, apt vs winget), root/sudo handling (Linux-only), Docker setup (different install paths), swap management (Linux-only).

When reviewing changes, use this mental model: if a user runs `shellSetup.sh` on Linux and `winSetup.ps1` on Windows, they should end up with the same tools, the same Claude Code environment, and the same COWORK integration. The *how* differs; the *what* should match.

---

## ROOT Profile Setup

The ROOT option replicates your user profile to the root account:

- Installs missing packages (btop, tmux, fzf, zsh)
- Changes root's shell to zsh
- Installs Oh My Zsh, Oh My Posh, and TPM for root
- Deploys configs via stow to `/root` (symlinks to this repo)
- Installs NVM, Node.js LTS, and pnpm for root
- Installs Claude Code and OpenCode for root via their official vendor installers (native binaries, no npm)
- Shares AI tool data directories with root (Claude Code, OpenCode)

**AI Tool Data Sharing:**

The following directories are symlinked from your user to `/root`, allowing seamless session continuity:
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
├── shellSetup.sh                      # Linux bootstrap script
├── winSetup.ps1                       # Windows bootstrap script (parallel to shellSetup.sh)
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
├── claude/                            # NOT a stow package — deployed via
│   └── .claude/                       # deploy_claude_config() with absolute
│       ├── CLAUDE.md                  # symlinks. See "Claude Code Setup" §.
│       ├── settings.json              #   -> ~/.claude/CLAUDE.md
│       └── statusline.sh              #   -> ~/.claude/settings.json
│                                      #   -> ~/.claude/statusline.sh
├── rustscan/                          # Package: RustScan config
│   └── .rustscan.toml                 #   -> ~/.rustscan.toml
├── scripts/                           # Package: Utility scripts
│   └── .local/bin/
│       ├── start-kex                  #   -> ~/.local/bin/start-kex
│       ├── usb-attach                 #   -> ~/.local/bin/usb-attach
│       ├── pbcopy                     #   -> ~/.local/bin/pbcopy
│       ├── pbpaste                    #   -> ~/.local/bin/pbpaste
│       └── launch_nordvpn             #   -> ~/.local/bin/launch_nordvpn
├── powershell/                        # Package: PowerShell profile (Windows)
│   └── Microsoft.PowerShell_profile.ps1
├── wezterm/                           # Package: WezTerm config (cross-platform)
│   └── .wezterm.lua
├── windows-terminal/                  # Package: Windows Terminal settings
│   └── settings.json
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
| `e` | `nano ~/.zshrc` / `nano ~/.bashrc` | Open shell config in nano |
| `r` | `source ~/.zshrc` / `source ~/.bashrc` | Reload shell configuration |
| `h` | `history -10` | Show last 10 history entries |
| `hc` | `history -c` | Clear shell history |
| `hg` | `history \| grep` | Search history (e.g., `hg docker`) |
| `ag` | `alias \| grep` | Search aliases (e.g., `ag rust`) |

### File System

| Alias | Command | Description |
|-------|---------|-------------|
| `ls` | `ls -lFh --color=auto --time-style=long-iso` | Detailed listing, **hides dotfiles** |
| `lsa` | `ls -alFh --color=auto --time-style=long-iso` | Detailed listing **including dotfiles** |
| `la` | (same as `lsa`) | Alias for `lsa` |
| `ll` | (same as `lsa`) | Alias for `lsa` (muscle-memory shortcut) |
| `cd..` | `cd ..` | Go up one directory (typo-friendly) |
| `cd...` | `cd .. && cd ..` | Go up two directories |


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
| `pbhistory` | fzf picker over `~/.clipboard_history` (populated by `pbcopy`, capped at 500 entries) — select an entry to re-copy it to the clipboard |
| `pubip` | Public IP lookup, caches to `~/.cache/pubip` for 5 minutes so repeated callers (like the tmux status bar) don't hit api.ipify.org every refresh |
| `netdot` | Prints just the colored online/offline dot (calls `pubip`) — used in the tmux status-right widget |
| `netstatus` | Renders the full catppuccin-style `NET` pill (label + IP, or `offline`) that sits next to `netdot` on the tmux status bar |
| `launch_nordvpn` | Self-provisioning NordVPN OpenVPN wrapper with random server selection |

---

<details>
<summary><strong>Tmux</strong> — full reference (collapsed; click to expand)</summary>

### Configuration

| Setting | Value |
|---------|-------|
| Prefix | **`Ctrl+a`** (screen-default — avoids the Windows IME `Ctrl+a` collision in Termius/PuTTY) |
| Window/pane indexing | Starts at 1 (not 0) |
| Copy mode | Vi keybindings |
| Mouse | Enabled |
| History limit | 50 000 lines |
| Theme | Catppuccin Mocha (via TPM) |
| Pane splits | Open in current working directory |
| Reload bind | `PFX r` runs `source-file ~/.tmux.conf` |

**First run:** TPM auto-clones itself on first launch and `install_plugins` runs once. After that, plugins are managed via `PFX I` (install) and `PFX U` (update).

### Plugins (declared in `.tmux.conf`)

| Plugin | Purpose |
|--------|---------|
| `tmux-plugins/tpm` | Plugin manager |
| `tmux-plugins/tmux-sensible` | Sane defaults (escape-time, history, etc.) |
| `dreamsofcode-io/catppuccin-tmux` | Theme (mocha flavour) |
| `tmux-plugins/tmux-resurrect` | Save/restore sessions, windows, panes, running programs, and pane contents. Manual: `PFX Ctrl+s` save, `PFX Ctrl+r` restore |
| `tmux-plugins/tmux-continuum` | Auto-saves resurrect every 15 min; auto-restores on tmux server start (pairs with `tmux-main.service`) |
| `tmux-plugins/tmux-yank` | `y` in copy mode + mouse-drag → system clipboard via OSC52 (works through Termius → Windows) |
| `tmux-plugins/tmux-prefix-highlight` | Status-bar indicator that lights up when prefix is active or in copy/sync mode |
| `tmux-plugins/tmux-cpu` | CPU / RAM widgets for status bar |

### Status bar (right side)

`PFX-indicator │ CPU% │ RAM% │ online-dot │ Public IP │ YYYY-MM-DD HH:MM`

Public IP is fetched via the `pubip` script (`~/.local/bin/pubip`) which caches to `~/.cache/pubip` for 5 minutes — keeps the status bar fast and stops every refresh from hitting api.ipify.org.

### Persistence (headless VMs)

The `TMUX` menu option wires three things so your work survives SSH disconnects, reboots, and laptop closes:

1. **Auto-attach on SSH login** — `.zshrc` and `.bashrc` ship with a snippet that, on SSH-originated shells outside an existing tmux, runs `tmux attach -t main 2>/dev/null || tmux new -s main`. SSH in → land directly in the `main` session every time.
2. **`tmux-main.service`** — a `~/.config/systemd/user/tmux-main.service` unit that starts `tmux new-session -d -s main` at boot. Survives reboots.
3. **`loginctl enable-linger <user>`** — user services run without an active login session, so step 2 actually triggers at boot rather than at first login.

To detach from a session and keep it running: **`Ctrl+a d`**. Do **not** `exit` — that kills the pane (and if it's the only pane, the window; if the only window, the session).

### Command Cheatsheet

The prefix on this setup is **`Ctrl+a`** (written as `PFX` below). All commands except shell ones are typed *after* hitting the prefix.

**Shell (outside tmux)**

| Command | Purpose |
|---------|---------|
| `tmux` | Start unnamed session |
| `tmux new -s <name>` | Start named session |
| `tmux ls` | List sessions |
| `tmux a` | Attach to most recent session |
| `tmux a -t <name>` | Attach to specific session |
| `tmux kill-session -t <name>` | Kill one session |
| `tmux kill-server` | Kill all sessions (nukes tmux server) |

**Sessions (inside tmux)**

| Keys | Purpose |
|------|---------|
| `PFX d` | Detach (keeps session alive) |
| `PFX s` | Interactive session picker |
| `PFX $` | Rename current session |
| `PFX (` / `PFX )` | Previous / next session |

**Windows (tabs)**

| Keys | Purpose |
|------|---------|
| `PFX c` | New window |
| `PFX ,` | Rename window |
| `PFX &` | Kill window (confirms) |
| `PFX n` / `PFX p` | Next / previous window |
| `PFX 1` … `PFX 9` | Jump to window by number |
| `PFX w` | Interactive window picker |

**Panes (splits)**

| Keys | Purpose |
|------|---------|
| `PFX "` | Split horizontally (top/bottom) — opens in `$PWD` |
| `PFX %` | Split vertically (left/right) — opens in `$PWD` |
| `PFX <arrow>` | Move focus between panes |
| `PFX x` | Kill current pane (confirms) |
| `PFX z` | Toggle pane zoom (fullscreen current pane) |
| `PFX {` / `PFX }` | Swap pane with previous / next |
| `PFX SPACE` | Cycle pane layouts |
| `PFX q` | Show pane numbers (press number to jump) |

**Copy mode (vi keys enabled)**

| Keys | Purpose |
|------|---------|
| `PFX [` | Enter copy mode |
| `v` | Start selection (vi-style) |
| `y` | Yank selection to tmux buffer |
| `q` | Exit copy mode |
| `PFX ]` | Paste most recent buffer |
| `PFX =` | Show buffer list |
| Mouse drag | Select + auto-copy (mouse is on) |

**Misc**

| Keys | Purpose |
|------|---------|
| `PFX ?` | Show all keybindings |
| `PFX :` | Command prompt (`:source-file ~/.tmux.conf`, etc.) |
| `PFX r` (if bound) | Reload `.tmux.conf` — not bound by default; use `:source ~/.tmux.conf` |
| `PFX I` | Install TPM plugins (capital i) |
| `PFX U` | Update TPM plugins |

### Typical headless-VM workflow

```sh
ssh vm                              # SSH in → drops you into 'main' session automatically
# ... work ...
Ctrl+a d                        # detach, close laptop, walk away
ssh vm                              # reconnect later → same session, same state
```

If `main` ever gets cluttered, spin up project-scoped sessions:

```sh
tmux new -s coworkdev               # for COWORK work
tmux new -s claude                  # for a long Claude session
PFX s                               # inside tmux: switch between them
```

To survive flaky networks, install Mosh on both ends and replace `ssh vm` with `mosh vm -- tmux a -t main`.

</details>

---

<details>
<summary><strong>Snapper Snapshot Guide</strong> — Arch system backup/rollback reference (collapsed; click to expand)</summary>

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

</details>

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

# Deploy all stow packages
# (NOTE: `claude/` is intentionally excluded — it is deployed via
# absolute symlinks in deploy_claude_config(), not stow. See "Claude
# Code Setup" section above.)
# NOTE: this list must match STOW_PACKAGES in shellSetup.sh
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
