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
alias c="clear"
alias x="exit"
alias e='nano ~/.bashrc'
alias r='source ~/.bashrc'
# `h` is bash-corrected: zsh `history -10` is invalid in bash (it parses -1 as an
# option and errors). `history 10` lists the last 10 entries.
alias h='history 10'
alias hc="history -c"
alias hg="history | grep "
alias ag="alias | grep "
# Package-manager refresh — INTERACTIVE muscle memory ONLY. Omarchy is Arch, so
# this is a full -Syu; omarchySetup.sh itself never runs it (no unattended
# system upgrades on this box), but the operator keeps the shortcut.
alias sapu='sudo pacman -Syu'
# Coreutils ls (long / human / ISO time). INTENTIONAL SHADOW: this overlay is
# sourced after Omarchy's rc, so these win over Omarchy's eza-backed `ls`
# (operator's long-standing choice — plain coreutils ls/ll/la/lsa).
alias ls='ls -lFh --color=auto --time-style=long-iso'
alias lsa='ls -alFh --color=auto --time-style=long-iso'
alias ll='ls -alFh --color=auto --time-style=long-iso'
alias la='ls -alFh --color=auto --time-style=long-iso'
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

# --- scratch dirs ------------------------------------------------------------

# try <name> — jump into a dated scratch dir under ~/tries.
try() {
  if [ -z "$1" ]; then printf '%s\n' "usage: try <name>" >&2; return 2; fi
  local d; d="$HOME/tries/$(date +%F)-$1"   # split decl/assign (SC2155)
  mkdir -p "$d" && cd "$d" || return 1
}

# --- tmux layouts ------------------------------------------------------------

# tdl [agent-cmd] — 3-pane dev layout: editor left (55%), agent top-right,
# plain shell bottom-right. Works inside a tmux session (lays out the current
# window) and from outside (creates + attaches a 'dev' session). Raw
# split-window/send-keys, so it doesn't depend on any prefix binding.
tdl() {
  command -v tmux >/dev/null 2>&1 || { printf '%s\n' "tdl: tmux not installed" >&2; return 1; }
  local agent="${1:-claude}" editor="${EDITOR:-vim}" created=0 target p_edit p_agent
  if [ -z "$TMUX" ]; then
    tmux new-session -d -s dev || return 1
    target="dev"; created=1
  else
    target="$(tmux display-message -p '#{session_name}:#{window_index}')"
  fi
  p_edit="$(tmux display-message -p -t "$target" '#{pane_id}')"
  tmux send-keys -t "$p_edit" "$editor" C-m
  p_agent="$(tmux split-window -h -l 45% -t "$p_edit" -P -F '#{pane_id}')"
  tmux send-keys -t "$p_agent" "$agent" C-m
  tmux split-window -v -t "$p_agent"          # plain shell bottom-right
  tmux select-pane -t "$p_edit"
  [ "$created" = 1 ] && tmux attach -t dev
}

# tsl <count> [cmd] — tiled grid of <count> panes, each running [cmd] (default:
# a plain shell). Inside tmux it tiles the current window; outside it creates +
# attaches a 'grid' session.
tsl() {
  command -v tmux >/dev/null 2>&1 || { printf '%s\n' "tsl: tmux not installed" >&2; return 1; }
  local count="${1:-4}" cmd="${2:-}" created=0 target first p i
  case "$count" in ''|*[!0-9]*) printf '%s\n' "usage: tsl <count> [cmd]" >&2; return 2 ;; esac
  [ "$count" -lt 1 ] && { printf '%s\n' "tsl: count must be >= 1" >&2; return 2; }
  if [ -z "$TMUX" ]; then
    tmux new-session -d -s grid || return 1
    target="grid"; created=1
  else
    target="$(tmux display-message -p '#{session_name}:#{window_index}')"
  fi
  first="$(tmux display-message -p -t "$target" '#{pane_id}')"
  [ -n "$cmd" ] && tmux send-keys -t "$first" "$cmd" C-m
  for (( i = 2; i <= count; i++ )); do
    p="$(tmux split-window -t "$target" -P -F '#{pane_id}')"
    tmux select-layout -t "$target" tiled >/dev/null
    [ -n "$cmd" ] && tmux send-keys -t "$p" "$cmd" C-m
  done
  tmux select-layout -t "$target" tiled >/dev/null
  [ "$created" = 1 ] && tmux attach -t grid
}

# --- rsync mirror watchers ---------------------------------------------------
# rsw starts a background inotifywait+rsync mirror; lsw lists watchers; dsw
# kills them. State (pid + args) lives under ~/.local/state/lpx/rsw so lsw/dsw
# survive across shells. rsync runs -a WITHOUT --delete by default — --delete
# removes files in <dst> that aren't in <src>, so it's opt-in behind -D only.

_rsw_state() { printf '%s' "${XDG_STATE_HOME:-$HOME/.local/state}/lpx/rsw"; }

rsw() {
  command -v inotifywait >/dev/null 2>&1 || {
    printf '%s\n' "rsw: inotifywait not found — install inotify-tools" >&2; return 1; }
  local del=0
  if [ "$1" = "-D" ]; then del=1; shift; fi
  local src="$1" dst="$2"
  if [ -z "$src" ] || [ -z "$dst" ]; then
    printf '%s\n' "usage: rsw [-D] <src> <dst>    (-D adds rsync --delete — destructive)" >&2; return 2
  fi
  [ -d "$src" ] || { printf '%s\n' "rsw: source '$src' is not a directory" >&2; return 1; }
  mkdir -p "$dst" || return 1
  local state; state="$(_rsw_state)"; mkdir -p "$state"
  local -a flags=(-a)
  [ "$del" = 1 ] && flags+=(--delete)
  rsync "${flags[@]}" "$src"/ "$dst"/ 2>/dev/null   # initial sync before watching
  # ponytail: one event at a time (no -m); events during a sync coalesce into
  # the next pass — fine for a mirror. Use -m + debounce for every-event needs.
  (
    while inotifywait -r -q -e modify,create,delete,move "$src" >/dev/null 2>&1; do
      rsync "${flags[@]}" "$src"/ "$dst"/ 2>/dev/null
    done
  ) &
  local pid=$!
  printf '%s\t%s\t%s\t%s\n' "$pid" "$del" "$src" "$dst" > "$state/$pid"
  printf '%s\n' "rsw: watching $src -> $dst (delete=$del) as pid $pid"
}

lsw() {
  local state; state="$(_rsw_state)"
  [ -d "$state" ] || { printf '%s\n' "no watchers"; return 0; }
  local i=0 f pid del src dst
  for f in "$state"/*; do
    [ -e "$f" ] || continue          # nullglob-free guard (zsh had the *(N) qualifier)
    IFS=$'\t' read -r pid del src dst < "$f"
    if ! kill -0 "$pid" 2>/dev/null; then rm -f "$f"; continue; fi   # prune dead
    i=$((i + 1))
    printf '%2d) pid %-7s delete=%s  %s -> %s\n' "$i" "$pid" "$del" "$src" "$dst"
  done
  [ "$i" = 0 ] && printf '%s\n' "no watchers"
}

dsw() {
  local state; state="$(_rsw_state)"
  [ -d "$state" ] || { printf '%s\n' "no watchers"; return 0; }
  local f pid
  local -a live=()
  for f in "$state"/*; do
    [ -e "$f" ] || continue
    IFS=$'\t' read -r pid _ < "$f"
    if kill -0 "$pid" 2>/dev/null; then live+=("$f"); else rm -f "$f"; fi
  done
  [ "${#live[@]}" -eq 0 ] && { printf '%s\n' "no watchers"; return 0; }
  # killing the tracked pid can orphan its inotifywait child (it reparents), so
  # take out the children first, then the loop subshell, then drop the record.
  _dsw_kill() {
    local p="$1" file="$2"
    pkill -P "$p" 2>/dev/null
    kill "$p" 2>/dev/null
    rm -f "$file"
  }
  if [ "${1:-}" = all ] || [ "${1:-}" = -a ]; then
    for f in "${live[@]}"; do IFS=$'\t' read -r pid _ < "$f"; _dsw_kill "$pid" "$f"; done
    printf '%s\n' "dsw: stopped all"; return 0
  fi
  case "${1:-}" in ''|*[!0-9]*) printf '%s\n' "usage: dsw <index|all>  (index from lsw)" >&2; lsw; return 2 ;; esac
  # bash arrays are 0-based, but lsw numbers watchers from 1; map the pick back
  # with -1. Reject <1 explicitly — a bare negative index would wrap to the last
  # element in bash (0 -> live[-1]).
  local idx="$1"
  if [ "$idx" -lt 1 ]; then printf '%s\n' "dsw: no watcher at index $idx" >&2; lsw; return 1; fi
  local target="${live[$((idx - 1))]:-}"
  if [ -z "$target" ]; then printf '%s\n' "dsw: no watcher at index $idx" >&2; lsw; return 1; fi
  IFS=$'\t' read -r pid _ < "$target"
  _dsw_kill "$pid" "$target"
  printf '%s\n' "dsw: stopped watcher $idx (pid $pid)"
}

# --- resilient interactive ssh ----------------------------------------------
# Auto-reconnect an INTERACTIVE ssh that drops (network blip -> exit 255)
# instead of dumping you back at the local prompt. Ctrl-C breaks the loop.
# Anything scripted passes straight through: no tty, a remote command, or a
# forward/control-only invocation all bypass the loop. TERM is pinned (this
# supersedes the old `ssh` alias, which is intentionally NOT defined here) so
# remote tmux / 256-colour apps render.
# unalias first: in bash with expand_aliases (on for ~/.bashrc), an existing
# `ssh` alias makes `ssh() {` a PARSE ERROR that aborts the rest of this file —
# and bash has no `function`-keyword escape from that expansion the way zsh does.
unalias ssh 2>/dev/null || true
ssh() {
  # Not attached to a terminal (pipe/redirect/script) -> passthrough.
  if [ ! -t 0 ] || [ ! -t 1 ]; then
    TERM=xterm-256color command ssh "$@"; return
  fi
  # Detect a remote command or a no-shell/forward-only invocation; if present,
  # don't loop (retrying a one-shot command would re-run it). Errs toward
  # passthrough when unsure — worst case is the plain, original behavior.
  local a skip_next=0 positional=0 noshell=0
  for a in "$@"; do
    if [ "$skip_next" = 1 ]; then skip_next=0; continue; fi
    case "$a" in
      -N|-f|-O|-O*|-W|-W*) noshell=1 ;;                        # forward/control only
      -o|-p|-i|-l|-L|-R|-D|-b|-c|-e|-F|-I|-J|-m|-Q|-S|-w) skip_next=1 ;;  # flags that eat the next arg
      -*) ;;                                                    # other option, no arg
      *) positional=$((positional + 1)) ;;                     # host, then command
    esac
  done
  if [ "$noshell" = 1 ] || [ "$positional" -gt 1 ]; then
    TERM=xterm-256color command ssh "$@"; return
  fi
  # Interactive login shell: retry on abnormal (255) exit only. A session that
  # held >30s resets the budget, so a typo'd/unreachable host fails after 5
  # quick 255s instead of looping forever.
  local rc tries=0 started
  while true; do
    started=$SECONDS
    TERM=xterm-256color command ssh "$@"
    rc=$?
    [ "$rc" != 255 ] && return "$rc"
    (( SECONDS - started > 30 )) && tries=0
    tries=$((tries + 1))
    if (( tries >= 5 )); then
      printf '\033[31mssh: 5 consecutive 255 exits — giving up (unreachable host or auth failure?)\033[0m\n'
      return "$rc"
    fi
    stty sane 2>/dev/null; printf '\033[0m'          # clear stale terminal state
    printf '\033[33mssh: dropped (255) — reconnecting in 2s (Ctrl-C to stop)\033[0m\n'
    sleep 2 || return 130
  done
}

# --- herdr layouts -----------------------------------------------------------
# herdr equivalents of tdl/tsl. Unlike tmux, herdr's per-session server splits
# the focused pane of an ALREADY-RUNNING session, so these run only from inside
# a herdr pane (detected via HERDR_ENV/HERDR_PANE_ID, which herdr injects) —
# they never create a session. `herdr pane split` returns JSON; the new pane ID
# is read from .result.pane.pane_id, so jq is required.

# hdl [agent-cmd] — 3-pane dev layout mirroring tdl: editor in the current pane
# (left), agent top-right (default: claude), plain shell bottom-right.
hdl() {
  command -v herdr >/dev/null 2>&1 || { printf '%s\n' "hdl: herdr not installed" >&2; return 1; }
  if [ "${HERDR_ENV:-}" != 1 ] || [ -z "${HERDR_PANE_ID:-}" ]; then
    printf '%s\n' "hdl: not inside herdr — use tdl for tmux or attach first" >&2; return 1
  fi
  command -v jq >/dev/null 2>&1 || { printf '%s\n' "hdl: jq required to read pane IDs" >&2; return 1; }
  local agent="${1:-claude}" editor="${EDITOR:-vim}" p_edit="$HERDR_PANE_ID" p_agent
  # agent pane: split the editor pane right. herdr's --ratio is the fraction the
  # SPLIT pane keeps (0.55 -> editor ~55% left, agent column ~45%), matching tdl.
  # --no-focus keeps the user in the editor pane.
  p_agent="$(herdr pane split --pane "$p_edit" --direction right --ratio 0.55 --cwd "$PWD" --no-focus 2>/dev/null \
    | jq -r '.result.pane.pane_id // empty')"
  [ -z "$p_agent" ] && { printf '%s\n' "hdl: failed to split agent pane" >&2; return 1; }
  herdr pane run "$p_agent" "$agent" >/dev/null 2>&1
  # shell pane: split the agent pane down -> plain shell bottom-right.
  herdr pane split --pane "$p_agent" --direction down --cwd "$PWD" --no-focus >/dev/null 2>&1
  # editor last, in the calling pane; focus stays here (mirrors tdl's select-pane).
  herdr pane run "$p_edit" "$editor" >/dev/null 2>&1
}

# hds [count] [cmd] — herdr equivalent of tsl: <count> panes each running [cmd]
# (default: a plain shell). herdr has no `select-layout tiled`, so this
# APPROXIMATES a grid by alternating split direction (right, down, ...) off each
# newly created pane — fine for a handful of panes, not tmux's exact tiling.
hds() {
  command -v herdr >/dev/null 2>&1 || { printf '%s\n' "hds: herdr not installed" >&2; return 1; }
  if [ "${HERDR_ENV:-}" != 1 ] || [ -z "${HERDR_PANE_ID:-}" ]; then
    printf '%s\n' "hds: not inside herdr — use tsl for tmux or attach first" >&2; return 1
  fi
  command -v jq >/dev/null 2>&1 || { printf '%s\n' "hds: jq required to read pane IDs" >&2; return 1; }
  local count="${1:-4}" cmd="${2:-}" i p prev="$HERDR_PANE_ID" dir="right"
  case "$count" in ''|*[!0-9]*) printf '%s\n' "usage: hds <count> [cmd]" >&2; return 2 ;; esac
  [ "$count" -lt 1 ] && { printf '%s\n' "hds: count must be >= 1" >&2; return 2; }
  [ -n "$cmd" ] && herdr pane run "$prev" "$cmd" >/dev/null 2>&1
  for (( i = 2; i <= count; i++ )); do
    p="$(herdr pane split --pane "$prev" --direction "$dir" --cwd "$PWD" --no-focus 2>/dev/null \
      | jq -r '.result.pane.pane_id // empty')"
    [ -z "$p" ] && { printf '%s\n' "hds: split $i failed" >&2; return 1; }
    [ -n "$cmd" ] && herdr pane run "$p" "$cmd" >/dev/null 2>&1
    prev="$p"
    [ "$dir" = right ] && dir="down" || dir="right"
  done
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
