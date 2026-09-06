#!/usr/bin/env bash
# omarchySetup.sh — Omarchy-specific Stage-1 deploy for linuxploitacious.
#
# Replaces the generic shellSetup.sh on an Omarchy 4.x (Arch) box: bash +
# starship, herdr launched INTERACTIVELY (no systemd/cron persistence), and the
# COWORK harness wired via its own deploy.sh (Stage 2). It reuses shellSetup.sh's
# msg_* helper STYLE and its optional-install shapes, but is deliberately
# self-contained — it does NOT source shellSetup.sh.
#
# Everything is idempotent and re-runnable. The ONLY edit to Omarchy's ~/.bashrc
# is a single marker-delimited managed block appended to its override zone.
#
# HARD CONSTRAINTS (do not relax): no `pacman -Syu`/system upgrade anywhere, no
# python/npm/pip package installs, no theming, no chsh, no oh-my-posh, no swap,
# no persistence units (herdr@.service / herdr-boot / tmux systemd / linger /
# cron). Passwordless sudo IS enabled (operator directive 2026-08-25 — this box is
# now a headless-style harness node; see section 0b). Excluded optionals: docker,
# lpx-sudo-window.
set -euo pipefail

# --- msg helpers (lean local copies of shellSetup.sh's style) ---
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'
msg_info()    { echo -e "${BLUE}[*] $1${NC}"; }
msg_success() { echo -e "${GREEN}[+] $1${NC}"; }
msg_warn()    { echo -e "${YELLOW}[!] $1${NC}"; }
msg_error()   { echo -e "${RED}[x] $1${NC}"; }
msg_header()  { echo -e "\n${CYAN}=== $1 ===${NC}"; }

# Resolve this script's own directory so it works when run from disk (the overlay
# lives next to it). NOT $PWD — the operator may invoke it from anywhere.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---------------------------------------------------------------------------
# 0. Preamble / environment guards
# ---------------------------------------------------------------------------
msg_header "0. Preamble / environment guards"

if [ "$EUID" -eq 0 ]; then
  msg_error "Refusing to run as root — this provisions the login user's shell + harness."
  exit 1
fi

# Require Arch/Omarchy. Warn (don't abort) if the omarchy marker is absent but
# the box is still Arch — the script is Arch-safe even on plain Arch.
if [ -r /etc/os-release ]; then
  # shellcheck disable=SC1091
  . /etc/os-release
else
  msg_error "/etc/os-release missing — cannot confirm this is Arch/Omarchy. Aborting."
  exit 1
fi
if [ "${ID:-}" != "arch" ] && [[ "${ID_LIKE:-}" != *arch* ]]; then
  msg_error "Not an Arch box (ID='${ID:-}', ID_LIKE='${ID_LIKE:-}'). omarchySetup.sh is Arch-only. Aborting."
  exit 1
fi
if [ ! -x /usr/bin/omarchy ]; then
  msg_warn "Arch confirmed but /usr/bin/omarchy not found — proceeding as generic Arch."
fi

# Required toolchain: mise (runtimes), gh (repo clone + harness access).
for _tool in mise gh; do
  command -v "$_tool" >/dev/null 2>&1 \
    || { msg_error "$_tool not found on PATH — install it before running. Aborting."; exit 1; }
done
if ! gh auth status >/dev/null 2>&1; then
  msg_error "gh is not authenticated (gh auth status failed). Run 'gh auth login' first. Aborting."
  exit 1
fi

# On a passwordless harness node, `sudo -n true` (a NOPASSWD command match)
# succeeds while `sudo -v` (the validate action) still demands a password — so
# probe the command path, and only fall back to an interactive prime when a
# password really is required (fresh box, before section 0b grants NOPASSWD).
if sudo -n true 2>/dev/null; then
  msg_info "sudo: passwordless (harness node) — no prompt needed."
else
  msg_info "Priming sudo (one prompt)..."
  sudo -v || { msg_error "sudo required — aborting."; exit 1; }
fi

msg_success "Environment OK: Arch/Omarchy, non-root, mise + authenticated gh present."

# ---------------------------------------------------------------------------
# 0b. Passwordless sudo (harness-node parity, operator directive 2026-08-25)
# ---------------------------------------------------------------------------
# This box is now a headless-style harness node; match the rest of the fleet.
# Mirrors linuxploitacious configure_passwordless_sudo: validated via `visudo
# -cf` on a tmpfile BEFORE install, so a broken entry can never lock sudo out.
# Idempotent — no-op if the exact NOPASSWD line is already present. FIRST-RUN
# NOTE: the initial grant needs one real sudo password (chicken-and-egg); a
# headless run must be bootstrapped once by the operator before this no-ops.
msg_header "0b. Passwordless sudo (harness-node parity)"
_SUDO_USER="${SUDO_USER:-${USER:-$(id -un)}}"
_SUDOERS_FILE="/etc/sudoers.d/90-${_SUDO_USER}-nopasswd"
_SUDOERS_LINE="${_SUDO_USER} ALL=(ALL:ALL) NOPASSWD:ALL"
if sudo test -f "$_SUDOERS_FILE" && sudo grep -qxF "$_SUDOERS_LINE" "$_SUDOERS_FILE"; then
  msg_info "passwordless sudo already configured for ${_SUDO_USER}."
else
  _tmp_sudoers="$(mktemp)"
  printf '%s\n' "$_SUDOERS_LINE" > "$_tmp_sudoers"
  if sudo visudo -cf "$_tmp_sudoers" >/dev/null; then
    sudo install -m 0440 -o root -g root "$_tmp_sudoers" "$_SUDOERS_FILE" \
      && msg_success "passwordless sudo enabled for ${_SUDO_USER} (${_SUDOERS_FILE})." \
      || msg_warn "could not install ${_SUDOERS_FILE} — leaving sudo as-is."
  else
    msg_error "visudo validation failed — sudoers NOT modified."
  fi
  rm -f "$_tmp_sudoers"
fi

# ---------------------------------------------------------------------------
# 1. Targeted packages (NEVER a full -Syu)
# ---------------------------------------------------------------------------
msg_header "1. Targeted packages (pacman -S --needed, no system upgrade)"
# --needed skips anything already installed; --noconfirm keeps it unattended. NO
# -Syu / -u: refreshing + upgrading the whole system is a hard constraint on this
# box. Install one at a time so a single unknown/renamed package warns and the
# run continues instead of aborting.
PKGS=(stow wget unzip tree jq fd tealdeer inotify-tools git-delta dust wl-clipboard)
for _pkg in "${PKGS[@]}"; do
  if sudo pacman -S --needed --noconfirm "$_pkg"; then
    msg_info "ok: $_pkg"
  else
    msg_warn "package '$_pkg' failed (name drift / not in repos?) — continuing."
  fi
done
msg_success "Targeted package step done."

# ---------------------------------------------------------------------------
# 2. Clone repos (linuxploitacious payload + COWORK harness)
# ---------------------------------------------------------------------------
msg_header "2. Clone repos"
LPX_DIR="$HOME/linuxploitacious"
COWORK_DIR="$HOME/COWORK"

# gh uses the SSH git protocol here, and a fresh box has no github.com host key
# in known_hosts -> the first SSH clone dies with "Host key verification failed".
# setup_github_ssh (skipped: gh is already authed) is where this normally lived,
# so seed it explicitly. Idempotent via ssh-keygen -F.
mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"
touch "$HOME/.ssh/known_hosts" && chmod 600 "$HOME/.ssh/known_hosts"
if ssh-keygen -F github.com >/dev/null 2>&1; then
  msg_info "github.com already in known_hosts."
else
  if ssh-keyscan -t ed25519,rsa github.com >> "$HOME/.ssh/known_hosts" 2>/dev/null; then
    msg_info "seeded github.com host key into known_hosts."
  else
    msg_warn "ssh-keyscan github.com failed — clone may fail on host-key verification."
  fi
fi

# GitHub SSH over port 22 can time out transiently (observed 2026-08-25: one repo
# cloned, the next timed out on the same host seconds later). Retry a few times,
# clearing any partial dest before each attempt so `gh repo clone` doesn't refuse
# a non-empty dir. A command inside `if` is exempt from `set -e`, so a failed
# attempt loops instead of aborting.
clone_with_retry() {  # $1=slug  $2=dest
  local slug="$1" dest="$2" n=0
  while :; do
    n=$((n + 1))
    if [ -e "$dest" ] && [ ! -d "$dest/.git" ]; then rm -rf "$dest"; fi
    if gh repo clone "$slug" "$dest"; then return 0; fi
    if [ "$n" -ge 3 ]; then
      msg_error "clone $slug failed after $n attempts."
      return 1
    fi
    msg_warn "clone $slug failed (attempt $n/3) — retrying in 6s..."
    sleep 6
  done
}

if [ -d "$LPX_DIR/.git" ]; then
  msg_info "linuxploitacious already cloned at $LPX_DIR — leaving as-is."
else
  msg_info "Cloning Exploitacious/linuxploitacious -> $LPX_DIR"
  clone_with_retry Exploitacious/linuxploitacious "$LPX_DIR" || exit 1
fi

if [ -d "$COWORK_DIR/.git" ]; then
  msg_info "COWORK already cloned — pulling (best-effort, --ff-only)."
  git -C "$COWORK_DIR" pull --ff-only \
    || msg_warn "COWORK pull failed (dirty/diverged/offline) — continuing with local copy."
else
  msg_info "Cloning Exploitacious/COWORK -> $COWORK_DIR"
  clone_with_retry Exploitacious/COWORK "$COWORK_DIR" || exit 1
fi

# The payload (lpx scripts, herdr config, migrations) is read from the CLONE,
# NOT from SCRIPT_DIR.
PAYLOAD="$LPX_DIR"
if [ ! -d "$PAYLOAD/scripts/.local/bin" ]; then
  msg_error "Payload missing: $PAYLOAD/scripts/.local/bin not found after clone. Aborting."
  exit 1
fi

# The overlay is co-located with THIS script; fall back to the clone's copy.
OVERLAY_SRC="$SCRIPT_DIR/bashrc-overlay.sh"
if [ ! -r "$OVERLAY_SRC" ]; then
  OVERLAY_SRC="$LPX_DIR/omarchy/bashrc-overlay.sh"
fi
if [ ! -r "$OVERLAY_SRC" ]; then
  msg_error "bashrc-overlay.sh not found next to this script or at $LPX_DIR/omarchy/. Aborting."
  exit 1
fi
msg_success "Repos ready. Overlay source: $OVERLAY_SRC"

# ---------------------------------------------------------------------------
# 3. Install lpx suite + helpers to ~/.local/bin
# ---------------------------------------------------------------------------
msg_header "3. Install lpx scripts -> ~/.local/bin"
BIN_SRC="$PAYLOAD/scripts/.local/bin"
BIN_DST="$HOME/.local/bin"
mkdir -p "$BIN_DST"

# Deliberate subset. EXCLUDED on purpose: lpx-sudo-window, launch_nordvpn,
# start-kex, usb-attach, herdr-boot (persistence / legacy / interactive-only
# tools not wanted on this box).
LPX_SCRIPTS=(lpx lpx-add-migration lpx-debug lpx-hook lpx-migrate lpx-state lpx-version hpill netdot netstatus pubip vpn)
for _s in "${LPX_SCRIPTS[@]}"; do
  if [ -f "$BIN_SRC/$_s" ]; then
    cp -f "$BIN_SRC/$_s" "$BIN_DST/$_s"
    chmod +x "$BIN_DST/$_s"
    msg_info "installed $_s"
  else
    msg_warn "source script missing: $_s — skipping."
  fi
done

# Clipboard shims: install pb* then repoint xclip -> wl-clipboard on the
# INSTALLED copies only (Omarchy is Wayland; xclip is X11). Order matters — patch
# the `-o` (paste) form BEFORE the bare (copy) form, since the former is a
# superstring of the latter.
for _s in pbcopy pbpaste pbhistory; do
  if [ -f "$BIN_SRC/$_s" ]; then
    cp -f "$BIN_SRC/$_s" "$BIN_DST/$_s"
    sed -i \
      -e 's/xclip -selection clipboard -o/wl-paste -n/g' \
      -e 's/xclip -selection clipboard/wl-copy/g' \
      "$BIN_DST/$_s"
    chmod +x "$BIN_DST/$_s"
    msg_info "installed $_s (patched xclip -> wl-clipboard)"
  else
    msg_warn "source script missing: $_s — skipping."
  fi
done
msg_success "lpx suite installed."

# ---------------------------------------------------------------------------
# 4. Migration baseline (mark present migrations applied WITHOUT running them)
# ---------------------------------------------------------------------------
msg_header "4. Migration baseline"
# A fresh box must NOT retroactively run historical fleet migrations (they patch
# state that never existed here). Mechanism (read from lpx-migrate + lpx-state):
# lpx-migrate skips any migrations/<name>.sh that has a marker file at
# <state>/migrations/<name>, where <state> resolves as
#   ${LPX_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/lpx}
# So we baseline by TOUCHING those markers — the runner is never invoked. If that
# mechanism ever changes shape, this must be re-derived by hand; never run
# lpx-migrate blind on a fresh box.
MIG_SRC="$PAYLOAD/migrations"
STATE_ROOT="${LPX_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/lpx}"
DONE_DIR="$STATE_ROOT/migrations"
if [ -d "$MIG_SRC" ]; then
  mkdir -p "$DONE_DIR"
  _n=0
  shopt -s nullglob
  for _mig in "$MIG_SRC"/*.sh; do
    _base="$(basename "$_mig")"
    if [ -e "$DONE_DIR/$_base" ]; then
      msg_info "already baselined: $_base"
    else
      touch "$DONE_DIR/$_base"
      msg_info "baselined (marked applied, NOT run): $_base"
      _n=$((_n + 1))
    fi
  done
  shopt -u nullglob
  msg_success "Migration baseline done ($_n newly marked; runner never invoked)."
else
  msg_warn "No migrations dir at $MIG_SRC — nothing to baseline."
fi

# ---------------------------------------------------------------------------
# 5. herdr config (deploy a copy with default_shell -> bash; back up existing)
# ---------------------------------------------------------------------------
msg_header "5. herdr config"
# herdr the BINARY is already present on this box (/usr/bin/herdr) — we only
# deploy config. Copy (not symlink) so `herdr config` edits never dirty the repo,
# and flip default_shell zsh -> bash (this box is bash).
HERDR_CFG_DIR="$HOME/.config/herdr"
HERDR_CFG_SRC="$PAYLOAD/herdr/.config/herdr/config.toml"
mkdir -p "$HERDR_CFG_DIR"
if [ -r "$HERDR_CFG_SRC" ]; then
  if [ -f "$HERDR_CFG_DIR/config.toml" ]; then
    _stamp="$(date +%Y%m%d-%H%M%S)"
    cp -f "$HERDR_CFG_DIR/config.toml" "$HERDR_CFG_DIR/config.toml.backup_$_stamp"
    msg_info "backed up existing config.toml -> config.toml.backup_$_stamp"
  fi
  sed 's#^default_shell = "/usr/bin/zsh"#default_shell = "/usr/bin/bash"#' \
    "$HERDR_CFG_SRC" > "$HERDR_CFG_DIR/config.toml"
  if grep -q '^default_shell = "/usr/bin/bash"' "$HERDR_CFG_DIR/config.toml"; then
    msg_success "herdr config installed (default_shell = /usr/bin/bash)."
  else
    msg_warn "herdr config installed but the default_shell flip did not match — check $HERDR_CFG_DIR/config.toml"
  fi
else
  msg_warn "herdr config source missing at $HERDR_CFG_SRC — skipping."
fi

# Optional bash completion — never fail the run on this.
mkdir -p "$HOME/.local/share/bash-completion/completions"
herdr completion bash > "$HOME/.local/share/bash-completion/completions/herdr" 2>/dev/null \
  || msg_warn "herdr completion generation skipped."

# ---------------------------------------------------------------------------
# 6. Install the bash overlay
# ---------------------------------------------------------------------------
msg_header "6. Install bash overlay -> ~/.config/lpx/"
mkdir -p "$HOME/.config/lpx"
cp -f "$OVERLAY_SRC" "$HOME/.config/lpx/bashrc-overlay.sh"
msg_success "Overlay installed at ~/.config/lpx/bashrc-overlay.sh"

# fastfetch: a user config at ~/.config/fastfetch/config.jsonc OVERRIDES Omarchy's
# /etc/fastfetch/config.jsonc (which stays untouched — it's theme-managed). This
# is the operator's merge: Omarchy's categories + color scheme, a smaller
# (wordmark) logo, and the Software group removed. The overlay runs `fastfetch`
# on terminal launch. Deployed as a COPY; backs up any existing user config.
FASTFETCH_SRC="$SCRIPT_DIR/fastfetch-config.jsonc"
[ -r "$FASTFETCH_SRC" ] || FASTFETCH_SRC="$LPX_DIR/omarchy/fastfetch-config.jsonc"
if [ -r "$FASTFETCH_SRC" ]; then
  mkdir -p "$HOME/.config/fastfetch"
  if [ -f "$HOME/.config/fastfetch/config.jsonc" ]; then
    cp -f "$HOME/.config/fastfetch/config.jsonc" \
      "$HOME/.config/fastfetch/config.jsonc.backup_$(date +%Y%m%d-%H%M%S)"
  fi
  cp -f "$FASTFETCH_SRC" "$HOME/.config/fastfetch/config.jsonc"
  msg_success "fastfetch user config installed (smaller logo, no Software group)."
else
  msg_warn "fastfetch-config.jsonc not found next to script or in clone — skipping."
fi

# ---------------------------------------------------------------------------
# 7. Wire the ~/.bashrc managed block (THE ONLY edit to Omarchy's ~/.bashrc)
# ---------------------------------------------------------------------------
msg_header "7. Wire ~/.bashrc managed block"
BASHRC="$HOME/.bashrc"
MARK_START="# >>> lpx-omarchy (managed) >>>"
MARK_END="# <<< lpx-omarchy (managed) <<<"
touch "$BASHRC"

# Idempotent: if the block is already present, delete it (start..end inclusive)
# before re-adding, so a re-run replaces rather than duplicates. `#` can't be the
# sed delimiter (the marker lines start with it), so use `/` — the markers hold
# no `/`. The marker substrings are unique to this repo.
if grep -qF "$MARK_START" "$BASHRC"; then
  msg_info "managed block present — replacing it."
  sed -i '/lpx-omarchy (managed) >>>/,/lpx-omarchy (managed) <<</d' "$BASHRC"
else
  msg_info "appending managed block to bottom of ~/.bashrc (override zone)."
fi
# Strip trailing blank lines before appending so the block's own leading blank
# stays a single separator — keeps re-runs byte-stable instead of piling up
# blank lines each time (the delete above leaves the prior separator behind).
sed -i -e ':a' -e '/^[[:space:]]*$/{$d;N;ba' -e '}' "$BASHRC"

# Block content, in EXACT order:
#   1) the overlay,
#   2) the COWORK Claude wrapper. Its marker line is IDENTICAL to deploy.sh's
#      WRAPPER_MARKER and it carries a `claude-wrapper.sh` source line, so
#      deploy.sh's wire_wrapper_master DETECTS it and SKIPS appending its own
#      copy after ~/.bashrc.local (which would break the wrapper-before-.local
#      ordering that ultracode depends on),
#   3) ~/.bashrc.local (deploy.sh writes WORKFORCE PATH + ultracode + tmpdir +
#      clawd .env + workspace alias there; keep it LAST so locals win).
# The `$HOME`/`$-refs below are single-quoted ON PURPOSE: they must land in
# ~/.bashrc LITERALLY and expand at shell-startup, not at install time.
# shellcheck disable=SC2016
{
  printf '\n%s\n' "$MARK_START"
  printf '%s\n' '[ -r "$HOME/.config/lpx/bashrc-overlay.sh" ] && . "$HOME/.config/lpx/bashrc-overlay.sh"'
  printf '%s\n' '# --- COWORK Claude wrapper (root/master safety) ---'
  printf '%s\n' '[ -r "$HOME/COWORK/WORKFORCE/bin/claude-wrapper.sh" ] && . "$HOME/COWORK/WORKFORCE/bin/claude-wrapper.sh"'
  printf '%s\n' '[ -r "$HOME/.bashrc.local" ] && . "$HOME/.bashrc.local"'
  printf '%s\n' "$MARK_END"
} >> "$BASHRC"
msg_success "managed block wired at bottom of ~/.bashrc."

# ---------------------------------------------------------------------------
# 7b. Stage-1 Claude files + tailscaled.
#     The generic shellSetup.sh lays down the Level-1 Claude files
#     (deploy_claude_config); this Omarchy variant originally skipped them, so
#     `claude`/`clawd` booted on Claude's onboarding stub (model:sonnet, no
#     hooks/statusline/model-pins). deploy.sh (Stage-2) MIRRORS these to the
#     personal profile but does NOT lay down the Level-1 files — that is
#     Stage-1's job. Gap found + fixed on t2omarchy 2026-08-25. The caveman +
#     ponytail plugins this section used to install are retired (operator ruling
#     2026-08-31, merged into the umbrella-operating-model skill); Stage-2
#     deploy.sh now uninstalls any leftovers. Runs before section 8 so deploy.sh
#     has the files to mirror.
# ---------------------------------------------------------------------------
msg_header "7b. Claude Stage-1 files + tailscaled"

# Level-1 Claude config: symlink from the repo (Stage-1-owned), back up real files.
CLAUDE_SRC="$LPX_DIR/claude/.claude"
CLAUDE_DIR="$HOME/.claude"
if [ -d "$CLAUDE_SRC" ]; then
  mkdir -p "$CLAUDE_DIR"
  for src in "$CLAUDE_SRC"/settings.json "$CLAUDE_SRC"/statusline.sh "$CLAUDE_SRC"/CLAUDE.md; do
    [ -f "$src" ] || continue
    tgt="$CLAUDE_DIR/$(basename "$src")"
    if [ -L "$tgt" ] && [ "$(readlink -f "$tgt")" = "$(readlink -f "$src")" ]; then
      msg_info "Already linked: $tgt"; continue
    fi
    if [ -e "$tgt" ] && [ ! -L "$tgt" ]; then
      mv "$tgt" "${tgt}.backup_$(date +%Y%m%d_%H%M%S)"
      msg_warn "Backed up existing $(basename "$src")"
    fi
    [ -L "$tgt" ] && rm -f "$tgt"
    ln -s "$src" "$tgt" && msg_success "Linked: $tgt -> $src"
  done
else
  msg_warn "$CLAUDE_SRC not found — skipping Level-1 Claude files."
fi

# Enable tailscaled so remote access survives a reboot (`tailscale up` alone does
# not persist — a t2omarchy reboot dropped the tailnet until this was set 2026-08-25).
if command -v tailscale >/dev/null 2>&1 && systemctl list-unit-files tailscaled.service >/dev/null 2>&1; then
  if sudo -n systemctl enable --now tailscaled >/dev/null 2>&1; then
    msg_success "tailscaled enabled + started (survives reboot)."
  else
    msg_warn "Could not enable tailscaled — run: sudo systemctl enable --now tailscaled"
  fi
else
  msg_info "tailscale not installed — skipping tailscaled enable."
fi

# ---------------------------------------------------------------------------
# 8. Stage-2: COWORK deploy.sh (skills/commands symlinks, WORKFORCE PATH,
#    ultracode + clawd .env + CLAUDE_CODE_TMPDIR + workspace alias into
#    ~/.bashrc.local, MCP, plugins). Its daily-backup cron step self-skips when
#    crontab is absent — expected on this box (no cronie); let it warn.
# ---------------------------------------------------------------------------
msg_header "8. Stage-2 harness deploy (COWORK deploy.sh)"
DEPLOY="$COWORK_DIR/.claude-config/deploy.sh"
if [ -f "$DEPLOY" ]; then
  if bash "$DEPLOY"; then
    msg_success "deploy.sh completed."
  else
    msg_warn "deploy.sh returned non-zero — review its output above; re-run: bash $DEPLOY"
  fi
else
  msg_warn "deploy.sh not found at $DEPLOY — Stage-2 skipped. Re-run after fixing: bash $DEPLOY"
fi

# ---------------------------------------------------------------------------
# 9. Optionals: cloudflared, NordVPN, superfile (guard, warn-don't-abort)
# ---------------------------------------------------------------------------
msg_header "9. Optionals (cloudflared, NordVPN, superfile)"

# Try official repos first, then AUR fallbacks (yay). $1 = pacman name; the rest
# = AUR candidate package names.
install_from_repo_or_aur() {
  local name="$1"; shift
  if sudo pacman -S --needed --noconfirm "$name" 2>/dev/null; then
    msg_success "$name installed from official repos."
    return 0
  fi
  local cand
  for cand in "$@"; do
    if command -v yay >/dev/null 2>&1 && yay -S --needed --noconfirm "$cand" 2>/dev/null; then
      msg_success "$name installed from AUR ($cand)."
      return 0
    fi
  done
  return 1
}

# cloudflared: repo -> AUR -> GitHub binary (mirrors shellSetup install_cloudflared).
if command -v cloudflared >/dev/null 2>&1; then
  msg_info "cloudflared already installed: $(cloudflared --version 2>&1 | head -1)"
elif install_from_repo_or_aur cloudflared cloudflared-bin; then
  :
else
  msg_warn "cloudflared not in repos/AUR — falling back to GitHub binary."
  _cf_arch="amd64"; case "$(uname -m)" in aarch64|arm64) _cf_arch="arm64" ;; esac
  _cf_tmp="$(mktemp -d)"
  if curl -fsSL -o "$_cf_tmp/cloudflared" \
       "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${_cf_arch}"; then
    sudo install -m 0755 "$_cf_tmp/cloudflared" /usr/local/bin/cloudflared \
      && msg_success "cloudflared installed: $(cloudflared --version 2>&1 | head -1)" \
      || msg_warn "cloudflared install failed — skipping."
  else
    msg_warn "cloudflared binary download failed — skipping."
  fi
  rm -rf "$_cf_tmp"
fi

# NordVPN via AUR (the vendor install.sh is apt/dnf only). The daemon-enable +
# group-add run whenever nordvpn is present — NOT only on a fresh install — so a
# re-run (or a run that resumes after the install already succeeded) still
# ensures them instead of short-circuiting on "already installed".
_nordvpn_ready=0
if command -v nordvpn >/dev/null 2>&1; then
  msg_info "NordVPN present: $(nordvpn --version 2>&1 | head -1)"
  _nordvpn_ready=1
elif command -v yay >/dev/null 2>&1 && yay -S --needed --noconfirm nordvpn-bin 2>/dev/null; then
  msg_success "NordVPN installed from AUR (nordvpn-bin)."
  _nordvpn_ready=1
else
  msg_warn "NordVPN (nordvpn-bin) install failed or yay absent — skipping."
fi
if [ "$_nordvpn_ready" = 1 ]; then
  sudo systemctl enable --now nordvpnd.service 2>/dev/null \
    && msg_info "nordvpnd.service enabled + started." \
    || msg_warn "could not enable nordvpnd.service — start it manually."
  _u="${USER:-$(id -un)}"
  if id -nG "$_u" 2>/dev/null | tr ' ' '\n' | grep -qx nordvpn; then
    msg_info "'$_u' already in the 'nordvpn' group."
  else
    sudo usermod -aG nordvpn "$_u" 2>/dev/null \
      && msg_warn "Added '$_u' to 'nordvpn' group — LOG OUT + BACK IN (or 'newgrp nordvpn')." \
      || msg_warn "could not add '$_u' to 'nordvpn' group."
  fi
  msg_info "Finish with 'nordvpn login' (headless: 'nordvpn login --token <TOKEN>')."
fi

# superfile: repo -> AUR (superfile / superfile-bin). Binary is `spf`, not
# `superfile`, so probe with spf.
if command -v spf >/dev/null 2>&1; then
  msg_info "superfile already installed: $(spf --version 2>&1 | head -1)"
elif install_from_repo_or_aur superfile superfile superfile-bin; then
  :
else
  msg_warn "superfile not installable from repos/AUR — skipping."
fi

# ---------------------------------------------------------------------------
# 10. Summary
# ---------------------------------------------------------------------------
msg_header "10. Summary"
msg_success "omarchySetup complete."
cat <<SUMMARY
  Installed / wired:
    - Targeted packages (--needed): ${PKGS[*]}
    - lpx suite -> ~/.local/bin: ${LPX_SCRIPTS[*]}
      + pbcopy / pbpaste / pbhistory (xclip -> wl-clipboard)
    - herdr config -> ~/.config/herdr/config.toml (default_shell = /usr/bin/bash)
    - bash overlay -> ~/.config/lpx/bashrc-overlay.sh
    - managed block in ~/.bashrc (overlay + Claude wrapper + ~/.bashrc.local)
    - Stage-2 harness via COWORK deploy.sh
    - Optionals attempted: cloudflared, NordVPN (nordvpn-bin), superfile

  Next:
    - Open a NEW shell, or run:  source ~/.bashrc   (to pick up the overlay)
    - NordVPN group change needs a LOG OUT + BACK IN (or 'newgrp nordvpn').
    - Persistence is intentionally OFF: launch herdr interactively.
SUMMARY
