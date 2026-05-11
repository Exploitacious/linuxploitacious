# ~/.bashrc: executed by bash(1) for non-login shells.

# If not running interactively, don't do anything
case $- in
    *i*) ;;
      *) return;;
esac

# History control
HISTCONTROL=ignoreboth
shopt -s histappend
HISTSIZE=1000
HISTFILESIZE=2000
shopt -s checkwinsize

# Set a fancy prompt (non-color, unless we know we "want" color)
case "$TERM" in
    xterm-color|*-256color) color_prompt=yes;;
esac

if [ -n "$force_color_prompt" ]; then
    if [ -x /usr/bin/tput ] && tput setaf 1 >&/dev/null; then
        color_prompt=yes
    else
        color_prompt=
    fi
fi

if [ "$color_prompt" = yes ]; then
    PS1='${debian_chroot:+($debian_chroot)}\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ '
else
    PS1='${debian_chroot:+($debian_chroot)}\u@\h:\w\$ '
fi
unset color_prompt force_color_prompt

# Enable color support of ls and others
if [ -x /usr/bin/dircolors ]; then
    test -r ~/.dircolors && eval "$(dircolors -b ~/.dircolors)" || eval "$(dircolors -b)"
    alias ls='ls --color=auto'
    alias grep='grep --color=auto'
    alias fgrep='fgrep --color=auto'
    alias egrep='egrep --color=auto'
fi

# --- Custom Aliases & Configuration (Merged from Zsh) ---

# User configuration — put ~/.local/bin first so native binaries (e.g. claude)
# win over any stale pnpm/npm shims that may linger in PNPM_HOME or npm-global.
export PATH="$HOME/.local/bin:$PATH"

# Shell Aliases
alias c="clear"
alias x="exit"
alias e="nano ~/.bashrc"
alias r="source ~/.bashrc"
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
# Fastfetch
if command -v fastfetch >/dev/null 2>&1; then
  fastfetch
fi

# Fabric Bootstrap
if [ -f "$HOME/.config/fabric/fabric-bootstrap.inc" ]; then 
  . "$HOME/.config/fabric/fabric-bootstrap.inc"
fi

# Opencode
export PATH="$HOME/.opencode/bin:$PATH"

# Oh My Posh — stowed theme (repo-controlled, survives cache wipes)
if command -v oh-my-posh >/dev/null 2>&1; then
  OMP_THEME="$HOME/.config/ohmyposh/catppuccin_mocha.omp.json"
  [ -f "$OMP_THEME" ] || OMP_THEME="$HOME/.cache/oh-my-posh/themes/catppuccin_mocha.omp.json"
  eval "$(oh-my-posh init bash --config "$OMP_THEME")"
fi

# NVM
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"

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

# OpenClaw
export PATH="${HOME}/.npm-global/bin:${PATH}"
export NODE_PATH="${HOME}/.npm-global/lib/node_modules"
export NODE_COMPILE_CACHE="/var/tmp/openclaw-compile-cache"
export OPENCLAW_NO_RESPAWN=1
alias openclaw-update='pnpm add -g openclaw@latest && systemctl --user restart openclaw-gateway.service'
alias openclaw-logs='openclaw logs --follow'
alias openclaw-status='openclaw gateway status'
alias openclaw-backup='${HOME}/bin/backup-openclaw.sh'

# --- Tmux session picker on SSH login ---
if [[ -z "$TMUX" && -n "$SSH_CONNECTION" ]] && command -v tmux >/dev/null 2>&1; then
  _tmux_sessions=()
  while IFS= read -r line; do
    [[ -n "$line" ]] && _tmux_sessions+=("$line")
  done < <(tmux list-sessions -F '#S' 2>/dev/null)

  printf '\033[36m━━ tmux session picker ━━\033[0m\n'
  if (( ${#_tmux_sessions[@]} > 0 )); then
    i=1
    for s in "${_tmux_sessions[@]}"; do
      printf "  %d) attach → %s\n" "$i" "$s"
      ((i++))
    done
  else
    printf "  (no existing sessions)\n"
  fi
  printf "  n) new named session\n"
  printf "  q) plain shell (no tmux)\n"
  printf "choice [n]: "
  read choice
  case "$choice" in
    q|Q) ;;
    ''|n|N)
      printf "session name [work]: "
      read name
      tmux new -s "${name:-work}"
      ;;
    [0-9]*)
      idx=$((choice - 1))
      target="${_tmux_sessions[$idx]:-}"
      if [[ -n "$target" ]]; then
        tmux attach -t "$target"
      else
        printf "invalid index — starting plain shell\n"
      fi
      ;;
    *)
      tmux attach -t "$choice" 2>/dev/null || tmux new -s "$choice"
      ;;
  esac
  unset _tmux_sessions choice name target i s idx
fi
