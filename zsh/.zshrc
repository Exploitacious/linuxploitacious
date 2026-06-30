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
  z
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
alias connectnord='sudo ~/.local/bin/launch_nordvpn'
alias gcu="git config user.name \"Alex Ivantsov\" && git config user.email \"alex@ivantsov.tech\""
alias myip='curl -s http://ipecho.net/plain; echo'
alias distro='cat /etc/*-release'
alias rustscan='sudo docker run -it --rm --name rustscan --user root --network host --ulimit nofile=100000:100000 --privileged -v $HOME/.rustscan.toml:/root/.rustscan.toml:ro rustscan/rustscan:2.1.1'
# Fastfetch (replaces Neofetch)
if command -v fastfetch >/dev/null 2>&1; then
  fastfetch
fi

# opencode
export PATH="$HOME/.opencode/bin:$PATH"

# Oh My Posh — stowed theme (repo-controlled, survives cache wipes)
if command -v oh-my-posh >/dev/null 2>&1; then
  OMP_THEME="$HOME/.config/ohmyposh/catppuccin_mocha.omp.json"
  [ -f "$OMP_THEME" ] || OMP_THEME="$HOME/.cache/oh-my-posh/themes/catppuccin_mocha.omp.json"
  eval "$(oh-my-posh init zsh --config "$OMP_THEME")"
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

# NOTE: COWORK claude-wrapper sourcing is owned by Stage 2 deploy.sh.
# It appends a tagged block here on first run; do not hardcode it.

# --- COWORK clawd (personal Claude profile) ---
clawd() ( export CLAUDE_CONFIG_DIR="$HOME/.claude-personal"; claude "$@"; )
