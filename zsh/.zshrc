# Path to your oh-my-zsh installation.
export ZSH="$HOME/.oh-my-zsh"

# Theme
ZSH_THEME=""

# Completion behavior
HYPHEN_INSENSITIVE="true"
COMPLETION_WAITING_DOTS="true"
ENABLE_CORRECTION="true"

# Auto-update behavior
zstyle ':omz:update' mode auto

# Plugins (git, sudo, command-not-found, colored-man-pages are OMZ builtins — no install needed)
plugins=(
  git
  sudo
  command-not-found
  colored-man-pages
  docker
  docker-compose
  zsh-autosuggestions
  zsh-syntax-highlighting
  zsh-completions
  fzf-tab
)
# zsh-completions exposes extra completions
[ -d "${ZSH_CUSTOM:-$ZSH/custom}/plugins/zsh-completions/src" ] && \
  fpath+=("${ZSH_CUSTOM:-$ZSH/custom}/plugins/zsh-completions/src")
source $ZSH/oh-my-zsh.sh

# User configuration — put ~/.local/bin first so native binaries (e.g. claude)
# win over any stale pnpm/npm shims that may linger in PNPM_HOME or npm-global.
export PATH="$HOME/.local/bin:$PATH"
typeset -U path PATH

### Aliases
# Shell
alias c="clear"
alias x="exit"
alias e="nano ~/.zshrc"
alias r="source ~/.zshrc"
alias h="history -10"
alias hc="history -c"
alias hg="history | grep "
alias ag="alias | grep "
# Package manager shortcut (cross-platform)
if command -v apt-get >/dev/null 2>&1; then
  alias sapu='sudo apt-get update'
elif command -v dnf >/dev/null 2>&1; then
  alias sapu='sudo dnf makecache'
elif command -v pacman >/dev/null 2>&1; then
  alias sapu='sudo pacman -Syu'
fi
alias ls='ls -lFh --color=auto --time-style=long-iso'
alias lsa='ls -alFh --color=auto --time-style=long-iso'
alias ll='ls -alFh --color=auto --time-style=long-iso'
alias la='ls -alFh --color=auto --time-style=long-iso'
alias cd..='cd ..'
alias cd...='cd .. && cd ..'
alias ssh='TERM=xterm-256color ssh'

# Utilities
# VPN — `vpn` itself is a script on PATH (~/.local/bin/vpn), so it needs no
# alias; these are just the shorthands worth muscle memory. See `vpn help`.
alias vpnoff='vpn off'
alias vpnstatus='vpn status'
alias vpnrandom='vpn random'
# LEGACY: raw-.ovpn OpenVPN fallback, kept for the service-credential path
# (no Nord Account session). Superseded by `vpn` / the official nordvpn CLI.
alias connectnord='sudo ~/.local/bin/launch_nordvpn'
alias gcu="git config user.name \"Alex Ivantsov\" && git config user.email \"alex@ivantsov.tech\""
alias myip='curl -s http://ipecho.net/plain; echo'
alias distro='cat /etc/*-release'
alias rustscan='sudo docker run -it --rm --name rustscan --user root --network host --ulimit nofile=100000:100000 --privileged -v $HOME/.rustscan.toml:/root/.rustscan.toml:ro rustscan/rustscan:2.1.1'

# Superfile — default terminal file manager (installed by shellSetup BASE,
# config stowed from superfile/). Wrapper implements cd-on-quit: with
# cd_on_quit=true in config.toml, spf writes its last dir to a state file on
# quit; sourcing it moves THIS shell there instead of stranding you where you
# started. Function shadows the binary; `command spf` reaches through.
if command -v spf >/dev/null 2>&1; then
  spf() {
    export SPF_LAST_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/superfile/lastdir"
    command spf "$@"
    [ ! -f "$SPF_LAST_DIR" ] || {
      . "$SPF_LAST_DIR"
      rm -f -- "$SPF_LAST_DIR" >/dev/null
    }
  }
  alias fm='spf'
fi

# Fastfetch (replaces Neofetch)
if command -v fastfetch >/dev/null 2>&1; then
  fastfetch
fi

# Oh My Posh — stowed theme (repo-controlled, survives cache wipes)
if command -v oh-my-posh >/dev/null 2>&1; then
  OMP_THEME="$HOME/.config/ohmyposh/catppuccin_mocha.omp.json"
  [ -f "$OMP_THEME" ] || OMP_THEME="$HOME/.cache/oh-my-posh/themes/catppuccin_mocha.omp.json"
  eval "$(oh-my-posh init zsh --config "$OMP_THEME")"
fi

# --- Modern CLI tools (installed by shellSetup CLITOOLS) ---
# Each block is guarded on the tool so a box that hasn't run CLITOOLS yet still
# starts a clean shell — the tools degrade to absent, never to an error.
if command -v bat >/dev/null 2>&1; then
  # Theme ships in the bat/ stow package; MANPAGER pipes man pages through bat.
  export BAT_THEME="Catppuccin Mocha"
  export MANPAGER="sh -c 'col -bx | bat -l man -p'"
fi
if command -v eza >/dev/null 2>&1; then
  # Tree views only. ls/ll/la deliberately stay coreutils (operator choice).
  alias lt='eza --tree --level=2 --group-directories-first --icons'
  alias lta='eza --tree --level=2 --group-directories-first --icons --all'
fi
# tealdeer ships its binary as `tldr` on most distros; alias only if it didn't.
if ! command -v tldr >/dev/null 2>&1 && command -v tealdeer >/dev/null 2>&1; then
  alias tldr='tealdeer'
fi
# zoxide replaces the oh-my-zsh `z` plugin (dropped from plugins= above).
# Silent no-op until zoxide is installed.
if command -v zoxide >/dev/null 2>&1; then
  eval "$(zoxide init zsh)"
fi
# fzf colours: Catppuccin Mocha, to match Oh My Posh / bat. Single export.
if command -v fzf >/dev/null 2>&1; then
  export FZF_DEFAULT_OPTS="--color=bg+:#313244,bg:#1e1e2e,spinner:#f5e0dc,hl:#f38ba8 --color=fg:#cdd6f4,header:#f38ba8,info:#cba6f7,pointer:#f5e0dc --color=marker:#b4befe,fg+:#cdd6f4,prompt:#cba6f7,hl+:#f38ba8 --color=selected-bg:#45475a --multi"
fi

export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion

# pyenv
export PYENV_ROOT="$HOME/.pyenv"
[[ -d "$PYENV_ROOT/bin" ]] && export PATH="$PYENV_ROOT/bin:$PATH"
command -v pyenv >/dev/null 2>&1 && eval "$(pyenv init -)"

# pnpm
export PNPM_HOME="$HOME/.local/share/pnpm"
case ":$PATH:" in
  *":$PNPM_HOME:"*) ;;
  *) export PATH="$PNPM_HOME:$PATH" ;;
esac
# pnpm end

# NOTE: WORKFORCE/bin PATH wiring is owned by COWORK's Stage 2 deployer
# (~/COWORK/.claude-config/deploy.sh). It appends its own tagged block to
# this file on first run. The old `COWORK/AGENTS/bin` entry was retired
# during the WORKFORCE rename — do not re-add either form here.

# --- Tmux session picker on SSH login ---
if [[ -z "$TMUX" && -n "$SSH_CONNECTION" ]] && command -v tmux >/dev/null 2>&1; then
  _tmux_sessions=()
  while IFS= read -r line; do
    [[ -n "$line" ]] && _tmux_sessions+=("$line")
  done < <(tmux list-sessions -F '#S' 2>/dev/null)

  print -P "%F{cyan}━━ tmux session picker ━━%f"
  if (( ${#_tmux_sessions[@]} > 0 )); then
    local i=1
    for s in "${_tmux_sessions[@]}"; do
      print "  $i) attach → $s"
      ((i++))
    done
  else
    print "  (no existing sessions)"
  fi
  print "  n) new named session"
  print "  q) plain shell (no tmux)"
  printf "choice [n]: "
  read choice
  case "$choice" in
    q|Q) ;;
    ''|n|N)
      printf "session name [work]: "
      read name
      tmux new -s "${name:-work}"
      ;;
    <->)
      target="${_tmux_sessions[$choice]}"
      if [[ -n "$target" ]]; then
        tmux attach -t "$target"
      else
        print "invalid index — starting plain shell"
      fi
      ;;
    *)
      tmux attach -t "$choice" 2>/dev/null || tmux new -s "$choice"
      ;;
  esac
  unset _tmux_sessions choice name target
fi

# opencode
[[ -d "$HOME/.opencode/bin" ]] && export PATH="$HOME/.opencode/bin:$PATH"

# --- COWORK clawd (personal Claude profile) ---
clawd() ( export CLAUDE_CONFIG_DIR="$HOME/.claude-personal"; claude "$@"; )

# --- COWORK Claude wrapper (root/master safety) ---
# $HOME-relative and readability-guarded: this is a public provisioning repo,
# so the path must not assume the operator's username, and the wrapper only
# exists on boxes where COWORK is actually deployed. Sourced ABOVE the .local
# seam below so machine-local overrides remain the last word.
[ -r "$HOME/COWORK/WORKFORCE/bin/claude-wrapper.sh" ] && . "$HOME/COWORK/WORKFORCE/bin/claude-wrapper.sh"

# Interactive workflow helpers (gwa/gwd/try/tdl/tsl/rsw/ssh…). Sourced from the
# zsh stow package; absent until stowed, so the guard keeps a bare box clean.
[ -r "$HOME/.zsh_functions" ] && . "$HOME/.zsh_functions"

# Machine-local overrides (untracked; survive git sync of this public repo).
# Host-/operator-specific shell config that must NOT live in this public repo
# goes here. COWORK Stage-2 (deploy.sh) writes operator-only Claude config —
# e.g. the always-on ultracode claude() shim — into ~/.zshrc.local. It does
# NOT edit this tracked file: ~/.zshrc is a stow symlink to the repo, so any
# append here dirties the public repo and is wiped on the next sync. Generic
# seam, no external assumptions; keep last so locals win.
[ -r "${HOME}/.zshrc.local" ] && . "${HOME}/.zshrc.local"
