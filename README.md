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
| BASE | OS updates, core packages (zsh, stow, tmux, fzf, btop, fastfetch, cloudflared, superfile, etc.) | ON |
| NODE | Node.js via NVM and pnpm | ON |
| PYTHON | Python via pyenv + pip packages | ON |
| SHELL | Zsh, Oh My Zsh (with autosuggestions, syntax-highlighting, completions, fzf-tab), Oh My Posh, TPM | ON |
| STOW | Deploy all repo configs to `$HOME` via GNU Stow | ON |
| CLITOOLS | Modern CLI tools: bat, eza, fd, zoxide, ripgrep, git-delta, dust, tealdeer, lazygit, lazydocker, inotify-tools | ON |
| TMUX | Tmux persistence: SSH auto-attach + `tmux-main.service` systemd unit + linger | ON |
| DOCKER | Docker Engine (docker-ce + buildx + compose plugin), adds user to `docker` group | OFF |
| BRAVE | Brave Browser | OFF |
| HERDR | Herdr multiplexer, version-pinned (see [Herdr multiplexer](#herdr-multiplexer-herdr)) | OFF |
| ROOT | Replicate user profile to root (configs, NVM, OMZ, OMP, TPM) | OFF (hidden when running as root) |
| NOPASS | Enable passwordless sudo for current user (drops `/etc/sudoers.d/90-<user>-nopasswd`, visudo-validated) | OFF (hidden when running as root) |
| SWAP | Create swapfile sized to match RAM (`/swapfile`, `vm.swappiness=10`) | ON (hidden when swap already exists) |
| SSHKEY | Generate GitHub SSH key, configure SSH, copy to root | OFF |
| HARNESS | Deploy the Stage 2 AI harness and invoke its `deploy.sh`. Auto-detects: with access to the private `Exploitacious/COWORK` it deploys that (Alex's machines); otherwise it walks you through [`Exploitacious/OPS`](https://github.com/Exploitacious/OPS) — the public template — creating your OWN private copy from it (`gh repo create <name> --template Exploitacious/OPS --private`). Requires SSHKEY. | OFF |

**Always runs (no menu toggle):** Claude Code and OpenCode install via their official vendor scripts (`curl -fsSL https://claude.ai/install.sh | bash` and `curl -fsSL https://opencode.ai/install | bash`), dropping native binaries into `~/.local/bin/claude` and `~/.opencode/bin/opencode`. Legacy pnpm/npm-global installations of these tools (and Gemini) are detected and removed on every run to prevent shims from shadowing the native binaries.

> **Supply chain note:** The two installers are fetched unpinned at setup time. Acceptable for a personal dotfiles repo; pin to a version (`bash -s <version>` for Claude) or checksum-verify if you plan to run this on machines you don't own.

---

## Run-once migrations

Some changes can't be expressed as a plain config edit — installing a new tool,
moving a file, seeding state. `migrations/` holds run-once scripts for exactly
that. Each box applies every migration once, records a marker, and skips it
forever after, so an already-provisioned box picks up new work on its next
`shellSetup.sh` run without re-doing everything.

- **Naming:** `migrations/<unix-timestamp>.sh`, applied oldest-first.
- **Scaffold one:** `lpx add-migration` drops a commented template and prints
  its path.
- **Contract:** each migration must be idempotent-safe and non-interactive, and
  must exit non-zero if it didn't finish. See `migrations/README.md`.
- **Runner:** `lpx-migrate` walks the directory, runs each pending migration
  with `bash`, and records a marker under `~/.local/state/lpx/migrations/`
  (`skipped/` for ones you chose to skip). On failure it prompts to skip on a
  terminal and **fails closed** (exit 1) when there's no terminal.

`shellSetup.sh` runs the migration runner automatically right after it syncs
with upstream. Set `LPX_NO_MIGRATE=1` to skip that pass. Note this includes a
first-ever provision: pending migrations apply before any menu selection, so a
migration like the CLI-toolset one effectively makes its payload non-optional
on new boxes (each installer still guards per-tool, so this is safe).

### The `--run` flag

`./shellSetup.sh --run ITEM1,ITEM2` runs those menu items' functions directly
and skips the whiptail menu — the non-interactive path migrations use (e.g. a
migration runs `--run CLITOOLS` to install the modern tools on existing boxes).
It exits with the aggregate status so a failed install is detectable, and it
sets `LPX_NO_MIGRATE=1` internally so a migration that calls it can't loop back
into the migration runner. With no arguments, `shellSetup.sh` behaves exactly
as before (interactive menu).

## Modern CLI tools (`CLITOOLS`)

The `CLITOOLS` menu item (and `--run CLITOOLS`) installs a set of modern
command-line tools, each skipped if already present:

- **apt-provided:** `bat` (Debian's `batcat`, symlinked to `bat` in
  `~/.local/bin`), `fd` (`fd-find`/`fdfind`, symlinked), `ripgrep`, `zoxide`,
  `tealdeer` (`tldr`), `eza`, `inotify-tools`.
- **GitHub releases (arch-aware, verified after install):** `git-delta` (apt if
  available, else the latest `.deb`), `dust` (falls back to apt `ncdu` if the
  download fails), `lazygit`, `lazydocker` (installed to `/usr/local/bin`).

It also wires git to use delta as its pager/diff-filter and sets
`merge.conflictStyle=zdiff3`. Theming is static (no theme engine): the `bat/`
stow package ships a pinned Catppuccin Mocha `.tmTheme`, and `.zshrc` exports
`BAT_THEME`, a bat-backed `MANPAGER`, Catppuccin `FZF_DEFAULT_OPTS`, `eza`
`lt`/`lta` tree aliases, and replaces the oh-my-zsh `z` plugin with a guarded
`zoxide` init (every one degrades silently when the tool is absent).

---

## Herdr multiplexer (`HERDR`)

[Herdr](https://github.com/herdrdev/herdr) is a tmux-like terminal
multiplexer built for AI coding agents. The `HERDR` menu item (and `--run
HERDR`) installs it, arch-aware, from GitHub releases into
`~/.local/bin/herdr` (user-level, no sudo), skipping the download when the
pinned version is already present and upgrading (old -> new) otherwise. It
also generates zsh completion to `~/.local/share/zsh/completions/_herdr`;
`.zshrc` adds that directory to `fpath` before `compinit`, guarded.

**Version is pinned, deliberately.** `install_herdr` hardcodes
`HERDR_VERSION`; herdr ships breaking changes roughly weekly, so tracking
"latest" would drift the fleet unpredictably. Bump it as a considered step:
edit the pin, then add a `migrations/*.sh` that re-runs the installer so
existing boxes pick up the new version. Until that decision is made, `HERDR`
stays out of the default menu set and carries no migration.

### Headless server boot

Herdr's per-session server normally boots only when a TUI client attaches,
and there is no `server start` subcommand. Bare `herdr server` runs that
server as a blocking foreground process, which is the headless entry point.
Two wrappers package it:

- **`herdr-boot <session>`** (stowed to `~/.local/bin`) backgrounds `herdr
  server` under `setsid` (detached, survives the caller), waits for the API
  socket to answer, and no-ops when the session's server is already running.
  Use it for an ad-hoc headless boot with no attached client:

  ```bash
  herdr-boot main
  HERDR_SESSION=main herdr workspace list   # socket answers, no client needed
  ```

- **`herdr@.service`** (a systemd *user* unit, stowed to
  `~/.config/systemd/user/`) is the supervised, start-at-boot path. The
  instance name is the session:

  ```bash
  systemctl --user enable --now herdr@main   # start now + at boot
  systemctl --user status herdr@main
  systemctl --user stop herdr@main
  ```

  It is `Type=simple` (systemd owns the `herdr server` process) with
  `Restart=on-failure`, so a crash respawns but a clean stop does not.
  Start-at-boot needs user lingering (`loginctl enable-linger <user>`, which
  the `TMUX` option already sets); with linger off, user units stop at
  logout. No instance is enabled by the installer: activation is a pending
  decision.

### herdr vs tmux status

The session-management layer is converting from tmux to herdr, one backend
switch at a time. As of this wave the SSH-login session picker (`.zshrc`) is
multiplexer-aware: it lists both herdr and tmux sessions in one menu — herdr
rows marked running/stopped, tmux rows marked `[tmux]` — sends new and default
sessions to herdr via `herdr session attach <name>` (create-or-attach), and
still attaches to a `[tmux]` row with `tmux attach`. Herdr is the default:
naming or creating a plain session lands you in herdr.

The conversion is a backend switch, not a replacement. tmux stays installed as
the fallback multiplexer and the persistence bootloader (`tmux-main.service`,
the whole [Persistence](#persistence-headless-vms) story), the tmux code paths
are preserved, and a box without herdr (or `jq`) degrades cleanly to the prior
tmux-only picker. For a persistent, start-at-boot herdr server behind the
picker, enable the [`herdr@.service`](#headless-server-boot) user unit
(`systemctl --user enable --now herdr@<session>`); the installer enables no
instance, so activation stays a per-box decision.

### herdr status pills

The `herdr` stow package lands `~/.config/herdr/config.toml`, which wires a row
of status pills into herdr's `tab_bar_right` area — the CPU / RAM / NET / clock
widgets the old tmux `status-right` carried, plus a `blocked` pill. Each is a
`command` status entry: herdr runs the command on the server on its own interval
and renders the last line of stdout.

| pill    | source                                             | interval |
| ------- | -------------------------------------------------- | -------- |
| blocked | `hpill blocked` → session-registry sweep           | 15s      |
| CPU     | `hpill cpu` → `/proc/loadavg` (1-min load ÷ cores) | 8s       |
| RAM     | `hpill ram` → `/proc/meminfo` (used/total GiB)     | 8s       |
| NET     | `hpill net` → `netstatus` → cached `pubip`         | 60s      |
| clock   | `hpill clock` → `date` (HH:MM + weekday)           | 30s      |

`hpill` (stowed to `~/.local/bin`) renders one pill per call and delegates the
NET pill to `netstatus`, which gained `--ansi` (truecolor) and `--plain` modes
alongside its tmux default (the tmux `status-right` still calls it bare).

**The pills are plain text by default, deliberately.** herdr 0.8.2 measures a
`tab_bar_right` entry's width by its raw byte length — ANSI escape bytes
included — and drops the *entire* right section when the row overflows the
terminal width. Catppuccin ANSI pills add ~70 escape bytes each, so five colored
pills need a ~400-column terminal or the whole status row silently disappears;
plain text renders at herdr's default 120-column width. Set `HPILL_COLOR=1` in
the herdr server's environment to opt into the Catppuccin Mocha truecolor pills
— only worth it on a reliably wide terminal.

Every entry is absent-safe: a helper whose data source is missing prints
nothing, and herdr clears an empty slot — so a box missing a `/proc` field, or
without the session-registry helper, shows a blank slot rather than an error
string. The `blocked` pill counts sessions an external session-registry helper
reports as blocked and degrades to nothing when that helper is absent (the same
guarded-reference pattern the `.zshrc` login picker uses).

Edit the pills in `herdr/.config/herdr/config.toml` and reload each running
server (`herdr server reload-config`, or `prefix+shift+r` in an attached
client). Note `herdr config reset-keys` rewrites `config.toml` in place, which
would edit the stowed symlink target — run it against a real copy, not the
symlink.

---

## Claude Code Setup

Claude Code configuration is deployed in **two stages**. This repo
(`linuxploitacious`) is **Stage 1** — host setup + Level 1 Claude
files only. Anything personal / opinionated / multi-machine-state
belongs in **Stage 2** (your own private repo). Alex's Stage 2 lives
at [`Exploitacious/COWORK`](https://github.com/Exploitacious/COWORK)
(private). A public template of that harness ships as
[`Exploitacious/OPS`](https://github.com/Exploitacious/OPS) — the
HARNESS menu option sets you up with your own private copy of it.

**Stage 1 — Level 1 files (this repo):** The `claude/` directory
deploys `~/.claude/CLAUDE.md` (behavioral rules, conversational
compression), `~/.claude/settings.json` (model, effort level,
permissions), and `~/.claude/statusline.sh`. On Linux all three use
absolute symlinks instead of stow (necessary because stow's relative
symlinks break when chained through the ROOT profile's `~/.claude` →
`/home/user/.claude` symlink). On Windows `CLAUDE.md` + `statusline.sh`
are symlinks, but `settings.json` is **materialized as a real file
deep-merged from the tracked base** (base wins on managed keys,
local-only keys preserved) — Claude Code has no user-level
`settings.local.json` for plugin keys, so a symlink there would let a
local tool's plugin injection dirty this public repo. The PowerShell
`$PROFILE` is likewise a real host-local shim (not a symlink) that
sources the tracked profile + an untracked `profile.local.ps1` seam.
These config files apply to every Claude Code session regardless of
project directory.

**Stage 1 — Plugins:** After Claude Code installs (via the always-on
vendor installer), the script registers the
[caveman](https://github.com/JuliusBrussee/caveman) plugin — an
ultra-compressed communication mode that reduces token usage while
keeping full technical accuracy. It activates automatically via
SessionStart hooks.

**Stage 2 — HARNESS (optional):** Selecting `HARNESS` in the menu
deploys the workspace repo — `~/COWORK/` (private, if your gh auth
can see it) or `~/OPS/` (your private copy of the public template,
created for you from `Exploitacious/OPS` if you don't have one) —
then auto-invokes its `.claude-config/deploy.sh`. That Stage 2
script owns everything harness-specific — skills symlink
(`~/.claude/skills/` → `<harness>/SKILLS/`), commands symlink,
`WORKFORCE/bin` PATH wiring, `claude-wrapper.sh` sourcing for
master + root rcs, `ac-memory-init` auto-memory git-sync, daily
backup cron, and additional plugins. Fresh OPS copies run a
BOOTSTRAP interview on their first Claude Code session to
personalize the harness. **This repo deliberately does NOT do any
of those steps** — keeping the Stage 1 / Stage 2 boundary clean
means Stage 1 stays usable without a Stage 2 repo, and Stage 2
stays the single source of truth for harness content.

**ROOT sharing:** The ROOT option symlinks `~/.claude/` from the
user account to `/root`, so both users share the same config,
sessions, and credentials. The `claude/` stow package is
intentionally excluded from ROOT's stow deployment to avoid
conflicting with this symlink.

**Personalizing Claude with a context directory:** The global
CLAUDE.md includes a "Context Awareness" section that checks for
`~/COWORK/CONTEXT/` (falling back to `~/OPS/CONTEXT/`) at session
start. If you fork this repo with a different harness path,
replace it with your own. The idea: keep a directory
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

This repo is public + opinionated, and since the
[`Exploitacious/OPS`](https://github.com/Exploitacious/OPS) public
template exists, **most people don't need to fork at all**: the
HARNESS menu option detects that you don't have access to the
author's private `Exploitacious/COWORK` and walks you through
creating your own private harness repo from the OPS template — no
string changes anywhere. The Stage 1 layer (host setup, shell
config, Level 1 Claude files) is generic and runs cleanly on any
machine; every harness code path self-gates on directory existence.

Fork only if you want to change Stage 1 itself, or point the
HARNESS flow at a different template/private repo:

1. **`shellSetup.sh::setup_harness` + `acquire_ops_repo`** — the
   detection call (`gh repo view Exploitacious/COWORK`) and the
   template source (`Exploitacious/OPS`). Swap for your own repos.
2. **`winSetup.ps1` HARNESS section** — same two references.
3. **`claude/.claude/CLAUDE.md`** "Harness Context Awareness"
   section — checks `~/COWORK/` then `~/OPS/`. Replace with your
   own harness path, or delete the section; the rest of the file
   is generic.
4. **`claude/.claude/settings.json`** hooks — resolve
   `$HOME/COWORK` falling back to `$HOME/OPS`. The `test -x`
   guards make them silent without a harness; replace the paths
   only for a custom harness location.
5. **README references** — search for `COWORK`/`OPS` in
   user-facing prose.

If you don't want a Stage 2 layer at all, just don't select
HARNESS (it's opt-in and fail-safe when the gh CLI isn't
authenticated).

## Stage 2 contract (what `setup_harness` assumes)

`setup_harness` (Linux) and the HARNESS menu item (Windows) clone
the Stage 2 repo — private COWORK or your private OPS copy — then
invoke its `deploy.{sh,ps1}` to finish setup. For that handoff to
work, the Stage 2 repo MUST expose at minimum:

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
├── superfile/                         # Package: Superfile (spf) config
│   └── .config/superfile/             #   -> ~/.config/superfile/
│       ├── config.toml                #   cd_on_quit=true pairs with the
│       ├── hotkeys.toml               #   spf() cd-on-quit wrapper in zsh/.zshrc
│       └── theme/
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
│       ├── pbhistory                  #   -> ~/.local/bin/pbhistory
│       ├── pubip                      #   -> ~/.local/bin/pubip
│       ├── netdot                     #   -> ~/.local/bin/netdot
│       ├── netstatus                  #   -> ~/.local/bin/netstatus (tmux/--ansi/--plain)
│       ├── hpill                      #   -> ~/.local/bin/hpill (herdr status pills)
│       ├── vpn                        #   -> ~/.local/bin/vpn
│       ├── launch_nordvpn             #   -> ~/.local/bin/launch_nordvpn
│       │                              #   (legacy OpenVPN fallback)
│       ├── lpx                        #   -> ~/.local/bin/lpx (command router)
│       ├── lpx-migrate                #   run-once migration runner
│       ├── lpx-add-migration          #   scaffold a migration
│       ├── lpx-state                  #   flag set/clear/check
│       ├── lpx-hook                   #   run a hook + its .d drop-ins
│       ├── lpx-debug                  #   system diagnostic snapshot
│       ├── lpx-version                #   checkout version
│       ├── lpx-sudo-window            #   time-boxed passwordless sudo
│       └── herdr-boot                 #   headless herdr session-server boot
├── bat/                               # Package: bat config + pinned theme
│   └── .config/bat/
│       ├── config                     #   -> ~/.config/bat/config
│       └── themes/                    #   Catppuccin Mocha .tmTheme (vendored)
├── systemd/                           # Package: systemd user unit templates
│   └── .config/systemd/user/
│       └── herdr@.service             #   -> ~/.config/systemd/user/ (fold)
├── herdr/                             # Package: herdr config (status pills)
│   └── .config/herdr/
│       └── config.toml                #   -> ~/.config/herdr/config.toml
├── migrations/                        # Run-once migrations (NOT stowed)
│   ├── README.md                      #   the migration contract
│   └── <unix-timestamp>.sh            #   applied once per box by lpx-migrate
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

These aliases are defined in both `.bashrc` and `.zshrc` and available in either shell, except `lt`/`lta` which are zsh-only (defined alongside the workflow functions).

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
| `lt` | `eza --tree --level=2 ...` | Tree view (2 levels). Requires `eza` (CLITOOLS); `ls`/`ll`/`la` stay coreutils by design |
| `lta` | `eza --tree --level=2 --all` | Tree view including dotfiles. Requires `eza` |
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
| `vpnoff` | `vpn off` | Disconnect NordVPN and disarm the kill switch |
| `vpnstatus` | `vpn status` | Show NordVPN connection status |
| `vpnrandom` | `vpn random` | Connect to a randomly drawn country + city |
| `connectnord` | `sudo ~/.local/bin/launch_nordvpn` | **Legacy** raw-`.ovpn` OpenVPN fallback — see [VPN](#vpn-nordvpn) |
| `rustscan` | `sudo docker run ... rustscan/rustscan:2.1.1` | Run RustScan via Docker (full port scan, hands off to nmap) |

`vpn` itself is a script on `PATH`, not an alias — run `vpn`, `vpn us`,
`vpn random`, `vpn help`, etc. directly. Full reference in the
[VPN](#vpn-nordvpn) section.

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
| `vpn` | Wrapper around the official NordVPN CLI — connect / random / off / status / kill switch. See [VPN](#vpn-nordvpn) |
| `launch_nordvpn` | **Legacy.** Self-provisioning raw-`.ovpn` OpenVPN wrapper with random server selection. Superseded by `vpn`; kept for the service-credential path |
| `herdr-boot` | *(stowed script in `~/.local/bin`, not an rc alias)* Boot a [herdr](#herdr-multiplexer-herdr) session's headless server (`herdr-boot <session>`) with no attached TUI client; idempotent. The ad-hoc counterpart to the `herdr@.service` user unit |

The `lpx-*` helpers are documented under [The `lpx` command suite](#the-lpx-command-suite).

---

## The `lpx` command suite

`lpx` is a small router over the `lpx-*` scripts in `~/.local/bin`. Run `lpx`
or `lpx help` for a table generated from each command's metadata; run
`lpx <command> [args]` to dispatch to `lpx-<command>`. No dependencies beyond
coreutils/grep/awk.

| Command | Description |
|---------|-------------|
| `lpx migrate` | Apply pending run-once migrations (see [Run-once migrations](#run-once-migrations)) |
| `lpx add-migration` | Scaffold a new timestamped migration and print its path |
| `lpx state set\|clear\|check <name>` | Persistent boolean flags under `~/.local/state/lpx/flags/`; `check` exits 0/1 for scripting |
| `lpx hook <name> [args]` | Run `~/.config/lpx/hooks/<name>` then every executable in `<name>.d/` (sorted, skips `*.sample`), continuing past failures |
| `lpx debug` | Write a system diagnostic snapshot to `/tmp/lpx-debug-<ts>.log` (kernel, disk, memory, failed units, dmesg, docker ps, top processes). Captures **no** environment, home contents, or secrets |
| `lpx version` | Print the repo checkout version (`git describe` / short SHA) |
| `lpx sudo-window <minutes>` | Grant the current user a time-boxed `NOPASSWD:ALL` window, validated with `visudo -cf` before install and auto-revoked by a `systemd-run` timer; a boot-time cleanup unit ensures a reboot can't leave a stale grant. `lpx sudo-window reset` revokes immediately. Requires sudo |

## Shell workflow functions

Defined in `zsh/.zsh_functions` (sourced from `.zshrc`), available in
interactive zsh shells only:

| Function | Description |
|----------|-------------|
| `gwa <branch>` | Add a git worktree beside the repo (`../<repo>-<branch>`), creating the branch if needed, and `cd` into it |
| `gwd` | From inside a worktree, confirm then remove it and delete its branch, `cd` back to the main checkout (refuses in the main checkout) |
| `try <name>` | `cd` into a dated scratch dir `~/tries/<date>-<name>` |
| `tdl [agent-cmd]` | 3-pane tmux dev layout: editor left (55%), agent top-right (default `claude`), shell bottom-right. Works inside or outside tmux |
| `tsl <count> [cmd]` | Tiled grid of `<count>` panes, each running `[cmd]` (default: a shell) |
| `hdl [agent-cmd]` | Herdr equivalent of `tdl`: editor left (55%), agent top-right (default `claude`), shell bottom-right. Runs only from inside a herdr pane (errors and points at `tdl` otherwise) |
| `hds [count] [cmd]` | Herdr equivalent of `tsl`: `<count>` panes each running `[cmd]`. herdr has no tiled layout, so it approximates a grid by alternating split direction. Inside-herdr only |
| `rsw [-D] <src> <dst>` / `lsw` / `dsw <index\|all>` | Background `inotifywait`+`rsync` mirror watchers. `rsw` starts one (`-a`, no `--delete` unless `-D`), `lsw` lists them, `dsw` stops one or all. Needs `inotify-tools` |
| `ssh` | Reconnects an interactive session that drops (exit 255); scripted, piped, and command/forward-only invocations pass straight through |

---

## VPN (NordVPN)

Two independent paths ship in this repo. The official CLI is the one to use;
the OpenVPN wrapper is kept only as a fallback.

| Path | Command | Auth | Status |
|------|---------|------|--------|
| Official NordVPN CLI + `vpn` helper | `vpn` | Nord Account (`nordvpn login`) | **Current** |
| Raw `.ovpn` + OpenVPN | `connectnord` | NordVPN *service credentials* | Legacy fallback |

### Install (once per machine)

`shellSetup.sh`'s **BASE** step installs this automatically and idempotently
(`install_nordvpn`), so a fresh box gets the CLI behind `vpn` without extra
steps. The manual form, for boxes provisioned before that landed:

```bash
sh -c "$(curl -sSf https://downloads.nordcdn.com/apps/linux/install.sh)"
sudo usermod -aG nordvpn "$USER"
```

The installer adds NordVPN's apt repo, installs the `nordvpn` package, and
enables the `nordvpnd` systemd daemon. It adds the installing user to the
`nordvpn` group itself; the explicit `usermod` above is the idempotent
belt-and-braces for other users. **Log out and back in afterwards** — group
membership is not picked up by an already-running shell. `vpn` detects this
case and prints the fix rather than failing cryptically.

`nordvpn` *Recommends* `nordvpn-gui`, so a default apt run pulls a ~17 MB
desktop app in alongside the CLI. On a headless box, skip it:

```bash
sudo apt-get install --no-install-recommends nordvpn
```

### Sign in (once per machine)

```bash
nordvpn login                  # opens a browser, supports MFA
nordvpn login --token <TOKEN>  # headless boxes; no MFA support
```

Get the token from the Nord web dashboard: **Nord Account -> Services ->
NordVPN -> Manual setup -> access token**. Nothing else in this repo needs
credentials; `vpn` never prompts for any.

### `vpn` command reference

| Command | Does |
|---------|------|
| `vpn` | Connect to the recommended server |
| `vpn connect [target]` | Same, optionally aimed at a target |
| `vpn <target>` | Connect to a country, city, country code, server or group — `vpn us`, `vpn United_States`, `vpn Chicago`, `vpn us9999`, `vpn Onion_Over_VPN` |
| `vpn connect <country> <city>` | Two-argument form, e.g. `vpn connect Hungary Budapest` |
| `vpn random` | Draw a random country from `nordvpn countries`, then a random city inside it with `shuf`, then connect |
| `vpn safe [target]` | Lockout-proof connect for when you are managing the box remotely over the tailnet — ensures the tailnet allowlist, then arms an auto-revert dead-man's-switch (see [Remote / tailnet safety](#remote--tailnet-safety)) |
| `vpn keep` | Cancel the auto-revert armed by `vpn safe`, once you have confirmed your session survived |
| `vpn off` / `vpn disconnect` | Disconnect **and** disarm the kill switch (also cancels any armed `vpn safe` timer) |
| `vpn status` | Connection status |
| `vpn settings` | Every current NordVPN setting |
| `vpn killswitch on\|off` | Arm / disarm the kill switch by hand |
| `vpn setup` | Apply the hardening defaults that work while signed out |
| `vpn help` | Usage |

### Kill switch behaviour (read this once)

`nordvpn set killswitch on` starts dropping **all** traffic the moment it is
set while the tunnel is down — not just on an unexpected drop. Verified on
5.3.0: with the switch armed and no VPN session, `curl https://1.1.1.1` times
out until it is turned back off.

`vpn` is built around that:

- The switch is armed **only after a connect returns success**, never before.
- `vpn off` disarms it as part of disconnecting, so a deliberate disconnect
  can never strand the box offline.
- `vpn killswitch on` still lets you seal the machine by hand, and warns you
  first.

If you ever find yourself with no network and no VPN, the escape hatch is
`nordvpn set killswitch off`.

### Remote / tailnet safety

A full-tunnel connect hands NordVPN the default route, and with the kill switch
armed the firewall drops every non-tunnel egress. On a box you manage remotely
that is a self-inflicted lockout: the replies leaving `tailscale0` (and the
box's own LAN) no longer have a route back out, so the very tailnet SSH session
you are connecting from hangs the instant the tunnel comes up. NordVPN's
allowlist is the carve-out, and `vpn` applies it for you — so remote management
survives a connect on any box the dotfiles land on, not just the one this was
written against.

**Tailnet-safe by default.** Every connect (`vpn`, `vpn <target>`, `vpn
connect`, `vpn random`, `vpn safe`) first re-applies three allowlist entries,
idempotently, whenever Tailscale is installed and up:

| Entry | Value | Why |
|-------|-------|-----|
| Subnet | `100.64.0.0/10` | Tailscale's fixed CGNAT range (RFC 6598); every tailnet peer IP lives inside it, so one entry covers the whole tailnet |
| Port | Tailscale's UDP listen port (`41641` fallback) | Keeps Tailscale's direct-transport reachable; detected from the live `tailscaled` socket, falling back to the well-known default |
| Subnet | The primary LAN | Auto-detected from the default-route interface; only added when detection yields a real CIDR, never guessed |

On a box without Tailscale this is a no-op — nothing is touched.

**`vpn safe` for the paranoid case.** The allowlist makes a normal connect
safe, but a single wrong entry could still cut you off, and you would have no
way back in. `vpn safe [target]` guards against that: it ensures the allowlist,
then arms a detached dead-man's-switch that outlives an SSH drop. If you lose
the box, the timer disconnects and disarms the kill switch on its own after
`${VPN_SAFE_TIMEOUT:-120}` seconds, handing your tailnet SSH back — a bad
connect self-heals. If your session survives, run `vpn keep` to cancel the
timer. `vpn off` cancels it too, so a manual disconnect never leaves a surprise
revert pending.

### Defaults

Applied by `vpn setup` (these are the only hardening switches the CLI accepts
while signed out):

| Setting | Value | Why |
|---------|-------|-----|
| `threatprotectionlite` | on | DNS-level malware/ad blocking |
| `analytics` | off | No usage telemetry |

Waiting on `nordvpn login` — the CLI answers `You're not logged in.` for these
until a session exists:

| Setting | Command |
|---------|---------|
| Auto-connect on boot | `nordvpn set autoconnect on` |

The kill switch is deliberately *not* in either list. The CLI does accept
`nordvpn set killswitch on` while signed out, but doing so takes the machine
offline immediately (see above), so `vpn` arms it on the first successful
connect instead.

Red-team caveats:

- **Threat Protection Lite filters DNS.** If a target domain refuses to
  resolve mid-engagement, turn it off first: `nordvpn set threatprotectionlite off`.
- **LAN Discovery is off by default**, so local subnets are unreachable while
  connected. For pivoting onto the local network:
  `nordvpn set lan-discovery on`.

### Legacy: `connectnord` / `launch_nordvpn`

Fully interactive OpenVPN wrapper predating the official CLI. It downloads
NordVPN's `.ovpn` archive to `~/.config/nordvpn/`, prompts for **service
credentials** (not your Nord Account login), and runs `openvpn` under `sudo`.
Kept for the case where the daemon or a Nord Account session is unavailable.
Prefer `vpn` for everything else.

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

1. **Session picker on SSH login** — on an SSH-originated shell that is not already inside a multiplexer, `.zshrc` shows an interactive picker over both herdr and tmux sessions, defaulting new sessions and typed-name choices to herdr (see [herdr vs tmux status](#herdr-vs-tmux-status)); `.bashrc` ships the tmux-only form of the same picker. SSH in → pick an existing session or start a fresh one, every login.
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
for pkg in bash zsh tmux btop fastfetch omp rustscan scripts superfile bat systemd; do
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
