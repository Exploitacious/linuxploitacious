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

# Plugins
plugins=(git zsh-autosuggestions zsh-syntax-highlighting)
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
alias ls='ls -alFh --color=auto --time-style=long-iso'
alias ll='ls -alFh --color=auto --time-style=long-iso'
alias cd..='cd ..'
alias cd...='cd .. && cd ..'
alias ssh='TERM=xterm-256color ssh'

# Utilities
alias connectnord='sudo ~/.local/bin/launch_nordvpn'
alias gcu="git config user.name \"Alex Ivantsov\" && git config user.email \"alex@ivantsov.tech\""
alias myip='curl -s http://ipecho.net/plain; echo'
alias distro='cat /etc/*-release'
alias rustscan='sudo docker run -it --rm --name rustscan --user root --network host --ulimit nofile=100000:100000 --privileged -v $HOME/.rustscan.toml:/root/.rustscan.toml:ro rustscan/rustscan:2.1.1'
alias claude-fix='sudo chown -R $USER:$USER ~/.claude ~/.local/share/opencode 2>/dev/null; sudo setfacl -R -m u:root:rwX -m u:$USER:rwX ~/.claude ~/.local/share/opencode 2>/dev/null; sudo setfacl -R -d -m u:root:rwX -m u:$USER:rwX ~/.claude ~/.local/share/opencode 2>/dev/null; echo "AI tool permissions fixed (ACLs applied)"'
# Fastfetch (replaces Neofetch)
if command -v fastfetch >/dev/null 2>&1; then
  fastfetch
fi

# Fabric Bootstrap
if [ -f "$HOME/.config/fabric/fabric-bootstrap.inc" ]; then 
  . "$HOME/.config/fabric/fabric-bootstrap.inc"
fi

# opencode
export PATH="$HOME/.opencode/bin:$PATH"

# Oh My Posh
if command -v oh-my-posh >/dev/null 2>&1; then
  eval "$(oh-my-posh init zsh --config $HOME/.cache/oh-my-posh/themes/catppuccin_mocha.omp.json)"
fi

export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion

# pnpm
export PNPM_HOME="$HOME/.local/share/pnpm"
case ":$PATH:" in
  *":$PNPM_HOME:"*) ;;
  *) export PATH="$PNPM_HOME:$PATH" ;;
esac
# pnpm end

# OpenClaw
export PATH="${HOME}/.npm-global/bin:${PATH}"
export NODE_PATH="${HOME}/.npm-global/lib/node_modules"
export NODE_COMPILE_CACHE="/var/tmp/openclaw-compile-cache"
export OPENCLAW_NO_RESPAWN=1
alias openclaw-update='pnpm add -g openclaw@latest && systemctl --user restart openclaw-gateway.service'
alias openclaw-logs='openclaw logs --follow'
alias openclaw-status='openclaw gateway status'
alias openclaw-backup='${HOME}/bin/backup-openclaw.sh'

# OpenClaw Completion
[[ -f "${HOME}/.openclaw/completions/openclaw.zsh" ]] && source "${HOME}/.openclaw/completions/openclaw.zsh"
