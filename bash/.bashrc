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

# User configuration
export PATH="$PATH:$HOME/.local/bin"

# Shell Aliases
alias c="clear"
alias x="exit"
alias e="code -n ~/ ~/.bashrc ~/.config/fastfetch/config.jsonc"
alias r="source ~/.bashrc"
alias vsc="cd /mnt/c/users/Alex/VSCODE"
alias h="history -10"
alias hc="history -c"
alias hg="history | grep "
alias ag="alias | grep "
alias sapu='sudo apt-get update'
alias ls='ls -alFh --color=auto --time-style=long-iso'
alias ll='ls -alFh --color=auto --time-style=long-iso'
alias cd..='cd ..'
alias cd...='cd .. && cd ..'

# Utilities
alias connectnord='sudo ~/.local/bin/launch_nordvpn'
alias gcu="git config user.name \"Alex Ivantsov\" && git config user.email \"alex@ivantsov.tech\""
alias myip='curl -s http://ipecho.net/plain; echo'
alias distro='cat /etc/*-release'
alias rustscan='sudo docker run -it --rm --name rustscan --user root --network host --ulimit nofile=100000:100000 --privileged -v $HOME/.rustscan.toml:/root/.rustscan.toml:ro rustscan/rustscan:2.1.1'
alias claude-fix='sudo chown -R $USER:$USER ~/.claude ~/.gemini ~/.local/share/opencode && sudo chmod -R g+rw ~/.claude ~/.gemini ~/.local/share/opencode && echo "AI tool permissions fixed"'

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

# Oh My Posh
if command -v oh-my-posh >/dev/null 2>&1; then
  eval "$(oh-my-posh init bash --config $HOME/.config/ohmyposh/kali.json)"
fi

# NVM
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"

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
