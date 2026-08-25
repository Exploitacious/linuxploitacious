# shellcheck shell=bash
# bashrc-overlay.sh — Omarchy bash overlay for the linuxploitacious environment.
#
# SOURCED (not executed) from the bottom "add your own here" override zone of
# ~/.bashrc on Omarchy boxes. It is the non-stow equivalent of the tracked
# bash/.bashrc: Omarchy owns ~/.bashrc (it sources /usr/share/omarchy/default/
# bash/{env-bootstrap,rc}), so we never overwrite it — omarchySetup.sh appends a
# single managed block that sources THIS file. Everything here is guarded so a
# bare box (no herdr/spf/nordvpn/docker yet) still starts a clean interactive
# shell: a missing tool degrades to absent, never to an error.
#
# Deliberately DROPPED vs the zsh original (Omarchy owns these): the oh-my-posh
# prompt (starship is Omarchy's), the bat/eza/tealdeer/zoxide/fzf theming blocks
# (Omarchy owns those tools + theme), the fastfetch-on-login call, and the
# nvm/pyenv/pnpm/opencode PATH blocks (runtimes come from mise; no npm/pip here).
# The claude-wrapper.sh and ~/.bashrc.local sources are NOT here on purpose — the
# managed block in ~/.bashrc adds those, AFTER this file, in the correct order.

# --- PATH: ~/.local/bin first (idempotent) ---
# Native binaries (the lpx helpers) win over anything later on PATH. Re-sourcing
# (via `r`) won't duplicate.
case ":$PATH:" in
  *":$HOME/.local/bin:"*) ;;
  *) export PATH="$HOME/.local/bin:$PATH" ;;
esac

# --- Aliases (ported from zsh/.zshrc) ---
# `c` and `h` intentionally NOT defined — deferred to Omarchy (c = opencode
# --auto, h = herdr) per operator ruling 2026-08-25. `r` keeps the operator's
# reload-shell (overrides Omarchy's r = rails, deliberately).
alias x="exit"
alias e='nano ~/.bashrc'
alias r='source ~/.bashrc'
alias hc="history -c"
alias hg="history | grep "
alias ag="alias | grep "
# Package-manager refresh — INTERACTIVE muscle memory ONLY. Omarchy is Arch, so
# this is a full -Syu; omarchySetup.sh itself never runs it (no unattended
# system upgrades on this box), but the operator keeps the shortcut.
alias sapu='sudo pacman -Syu'
# ls / lsa: intentionally NOT overridden — Omarchy defines `ls` as
# `eza -lh --group-directories-first --icons=auto` (the icon view) and `lsa` as
# `ls -a`; let those win (overriding them was the plain-list regression).
# Only add the long+all variants Omarchy does NOT ship (ll/la), in the same eza
# icon style so the view stays consistent; coreutils fallback if eza is absent.
if command -v eza >/dev/null 2>&1; then
  alias ll='eza -lah --group-directories-first --icons=auto'
  alias la='eza -lah --group-directories-first --icons=auto'
else
  alias ll='ls -alFh --color=auto --time-style=long-iso'
  alias la='ls -alFh --color=auto --time-style=long-iso'
fi
alias cd..='cd ..'
alias cd...='cd .. && cd ..'

# VPN — `vpn` is a script on PATH (~/.local/bin/vpn); these are the shorthands.
alias vpnoff='vpn off'
alias vpnstatus='vpn status'
alias vpnrandom='vpn random'

alias gcu="git config user.name \"Alex Ivantsov\" && git config user.email \"alex@ivantsov.tech\""
alias myip='curl -s http://ipecho.net/plain; echo'
alias distro='cat /etc/*-release'
# rustscan runs in a container — define the alias only when docker is present
# (docker is NOT installed on this box, so it stays undefined here).
command -v docker >/dev/null 2>&1 && \
  alias rustscan='sudo docker run -it --rm --name rustscan --user root --network host --ulimit nofile=100000:100000 --privileged -v $HOME/.rustscan.toml:/root/.rustscan.toml:ro rustscan/rustscan:2.1.1'

# --- superfile (spf) cd-on-quit wrapper + fm alias ---
# With cd_on_quit=true in superfile's config, spf writes its last dir to a state
# file on quit; sourcing it moves THIS shell there instead of stranding you.
# Function shadows the binary; `command spf` reaches through. Guarded so a box
# without superfile stays clean.
if command -v spf >/dev/null 2>&1; then
  spf() {
    export SPF_LAST_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/superfile/lastdir"
    command spf "$@"
    [ ! -f "$SPF_LAST_DIR" ] || {
      # Runtime-determined state file (superfile writes it on quit) — the
      # dynamic source is intentional.
      # shellcheck disable=SC1090
      . "$SPF_LAST_DIR"
      rm -f -- "$SPF_LAST_DIR" >/dev/null
    }
  }
  alias fm='spf'
fi

# --- git worktree flow -------------------------------------------------------

# gwa <branch> — add a worktree beside the repo (../<repo>-<branch>) and cd in.
# Creates the branch if it doesn't exist. Refuses outside a git repo.
gwa() {
  if ! git rev-parse --git-dir >/dev/null 2>&1; then
    printf '%s\n' "gwa: not inside a git repository" >&2; return 1
  fi
  if [ -z "$1" ]; then printf '%s\n' "usage: gwa <branch>" >&2; return 2; fi
  local branch="$1" root reponame wt
  root="$(git rev-parse --show-toplevel)" || return 1
  reponame="$(basename "$root")"
  wt="$(dirname "$root")/${reponame}-${branch//\//-}"  # flatten any slashes
  if git show-ref --verify --quiet "refs/heads/$branch"; then
    git worktree add "$wt" "$branch" || return 1
  else
    git worktree add -b "$branch" "$wt" || return 1
  fi
  cd "$wt" || return 1
}

# gwd — remove the CURRENT worktree and its branch, cd back to the main checkout.
# Confirms first. Refuses outside a repo, and refuses to run from the main
# checkout (that's not a throwaway worktree).
gwd() {
  if ! git rev-parse --git-dir >/dev/null 2>&1; then
    printf '%s\n' "gwd: not inside a git repository" >&2; return 1
  fi
  local gitdir commondir toplevel branch main_root reply
  gitdir="$(git rev-parse --absolute-git-dir)"
  commondir="$(cd "$(git rev-parse --git-common-dir)" 2>/dev/null && pwd)"
  if [ "$gitdir" = "$commondir" ]; then
    printf '%s\n' "gwd: this is the main checkout, not a worktree — refusing" >&2; return 1
  fi
  toplevel="$(git rev-parse --show-toplevel)"
  branch="$(git rev-parse --abbrev-ref HEAD)"
  main_root="$(git worktree list --porcelain | awk '/^worktree /{print $2; exit}')"
  printf 'gwd: remove worktree %s and delete branch %s? [y/N] ' "$toplevel" "$branch"
  read -r reply
  case "$reply" in
    y|Y) ;;
    *) printf '%s\n' "gwd: aborted"; return 0 ;;
  esac
  cd "$main_root" || return 1
  if ! git worktree remove "$toplevel"; then
    printf '%s\n' "gwd: worktree has changes or is locked — remove by hand with: git worktree remove --force '$toplevel'" >&2
    return 1
  fi
  if [ -n "$branch" ] && [ "$branch" != HEAD ]; then
    git branch -D "$branch" 2>/dev/null || printf '%s\n' "gwd: worktree removed; branch $branch left in place (unmerged?)" >&2
  fi
}

# --- Multiplexer session picker on SSH login ---------------------------------
# Fronts BOTH backends in one list: new/default sessions go to herdr, existing
# tmux sessions stay reachable and are marked [tmux]. Gated on an SSH shell that
# is neither already inside tmux ($TMUX) nor inside a herdr pane ($HERDR_ENV), so
# it fires once per fresh login and never nests. Degrades to pure-tmux behaviour
# on a box without herdr (or jq). NOTE: runs at file scope (sourced), so it uses
# plain vars + a trailing `unset`, never `local` (illegal outside a function in
# bash).
if [[ $- == *i* ]] && [ -z "$TMUX" ] && [ -z "$HERDR_ENV" ] && [ -n "$SSH_CONNECTION" ] \
   && { command -v tmux >/dev/null 2>&1 || command -v herdr >/dev/null 2>&1; }; then
  # An optional session console may front this picker. When present + executable
  # it fully replaces the generic picker below (same gating); otherwise the
  # generic picker runs unchanged, so this stays useful on a box with no console.
  _rc_console="$HOME/COWORK/.claude-config/remote-sessions/rc-console.sh"
  if [ -x "$_rc_console" ]; then
    unset _rc_console
    # Run it (do NOT exec or return): the console execs its own attach in a
    # child, and on detach — or when it drops to a shell — control returns here
    # and this file finishes sourcing normally. A `return` here would abort it.
    "$HOME/COWORK/.claude-config/remote-sessions/rc-console.sh"
  else
    unset _rc_console
    # jq parses the --json list AND is a base dep, so a box that lacks it (or
    # herdr) takes the pure-tmux path as one flag, not two.
    _have_herdr=0
    command -v herdr >/dev/null 2>&1 && command -v jq >/dev/null 2>&1 && _have_herdr=1

    # Rows are TAB-joined "<backend><TAB>...": TAB cannot appear in a herdr or
    # tmux session name, so it is a safe field separator. Kept parallel to the
    # printed list so a numeric pick maps back to its backend + name.
    _picker_rows=()
    sep=$'\t'

    # herdr sessions first (the default backend). ONE timeout-guarded call, 3s
    # cap: a herdr query can hang against a wedged server and this runs on every
    # SSH login, so a slow/dead server costs at most 3s and degrades to tmux rows.
    if [ "$_have_herdr" = 1 ]; then
      while IFS= read -r line; do
        [ -n "$line" ] && _picker_rows+=("herdr${sep}${line}")
      done < <(timeout 3 herdr session list --json 2>/dev/null \
               | jq -r '.sessions[] | [.running, .name] | @tsv' 2>/dev/null)
    fi

    # tmux sessions next, one call, marked [tmux] at print time.
    while IFS= read -r line; do
      [ -n "$line" ] && _picker_rows+=("tmux${sep}${line}")
    done < <(tmux list-sessions -F '#S' 2>/dev/null)

    printf '\033[36m━━ session picker ━━\033[0m\n'
    if [ "${#_picker_rows[@]}" -gt 0 ]; then
      i=1
      for row in "${_picker_rows[@]}"; do
        IFS=$'\t' read -ra parts <<< "$row"   # 0-based: parts[0]=backend, ...
        if [ "${parts[0]}" = herdr ]; then
          [ "${parts[1]}" = true ] && state=running || state=stopped
          printf '  %s) attach → %s [herdr, %s]\n' "$i" "${parts[2]}" "$state"
        else
          printf '  %s) attach → %s [tmux]\n' "$i" "${parts[1]}"
        fi
        i=$((i + 1))
      done
    else
      printf '  (no existing sessions)\n'
    fi
    if [ "$_have_herdr" = 1 ]; then printf '  n) new herdr session\n'; else printf '  n) new tmux session\n'; fi
    printf '  q) plain shell (no multiplexer)\n'
    printf 'choice [n]: '
    read -r choice
    case "$choice" in
      q|Q) ;;
      ''|n|N)
        printf 'session name [work]: '
        read -r name
        name="${name:-work}"
        # attach is the interactive foreground session (create-or-attach), NOT a
        # query — deliberately NOT timeout-wrapped.
        if [ "$_have_herdr" = 1 ]; then
          herdr session attach "$name"
        else
          tmux new -s "$name"
        fi
        ;;
      [0-9]*)
        idx=$((choice - 1))
        # bash negative indices wrap to the array end, so reject <0 explicitly.
        if [ "$idx" -ge 0 ]; then row="${_picker_rows[$idx]:-}"; else row=""; fi
        if [ -n "$row" ]; then
          IFS=$'\t' read -ra parts <<< "$row"
          if [ "${parts[0]}" = herdr ]; then
            herdr session attach "${parts[2]}"
          else
            tmux attach -t "${parts[1]}"
          fi
        else
          printf 'invalid index — starting plain shell\n'
        fi
        ;;
      *)
        # A raw name -> the default backend (herdr) create-or-attach; a pure-tmux
        # box falls back to tmux attach-or-new.
        if [ "$_have_herdr" = 1 ]; then
          herdr session attach "$choice"
        else
          tmux attach -t "$choice" 2>/dev/null || tmux new -s "$choice"
        fi
        ;;
    esac
    unset _picker_rows _have_herdr sep line choice name row parts i state idx
  fi
fi

# --- clawd (personal Claude profile) fallback --------------------------------
# The rich .env version is written to ~/.bashrc.local by COWORK's deploy.sh and
# sourced AFTER this file by the managed block, so it wins. This is the bare
# fallback for a box where deploy.sh has not run yet.
clawd() ( export CLAUDE_CONFIG_DIR="$HOME/.claude-personal"; claude "$@"; )
