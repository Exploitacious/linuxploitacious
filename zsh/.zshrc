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
plugins=(git)
source $ZSH/oh-my-zsh.sh

# User configuration
export PATH="$PATH:$HOME/.local/bin"

### Aliases
# Shell
alias c="clear"
alias x="exit"
alias e="code -n ~/ ~/.zshrc ~/.config/fastfetch/config.jsonc"
alias r="source ~/.zshrc"
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
