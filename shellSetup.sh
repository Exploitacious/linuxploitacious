#!/bin/bash
# Cross-Platform Linux Setup Script (Stow, Zsh, OMZ, OMP, Tmux)

main() {
  # 1. RECLAIM TTY: Prevent curl | bash from breaking interactive prompts
  exec < /dev/tty

  # --- COLORS & FORMATTING ---
  RED='\033[0;31m'
  GREEN='\033[0;32m'
  YELLOW='\033[1;33m'
  BLUE='\033[0;34m'
  CYAN='\033[0;36m'
  NC='\033[0m' # No Color

  msg_info() { echo -e "${BLUE}[*] $1${NC}"; }
  msg_success() { echo -e "${GREEN}[+] $1${NC}"; }
  msg_warn() { echo -e "${YELLOW}[!] $1${NC}"; }
  msg_error() { echo -e "${RED}[x] $1${NC}"; }
  msg_header() { echo -e "\n${CYAN}=== $1 ===${NC}"; }

  # --- ASCII ART HEADER ---
  clear
  echo -e "${CYAN}"
  cat << "EOF"
   __    _                 _       _ _   
  / /   (_)_ __  _   ___  | |_ ___(_) |_ 
 / /    | | '_ \| | | \ \/ / '_ \ | __|
/ /___  | | | | | |_| |>  <| |_) | | |_ 
\____/  |_|_| |_|\__,_/_/\_\ .__/|_|\__|
                           |_|          
   Created by Alex Ivantsov @Exploitacious
EOF
  echo -e "${NC}"

  if [ "$EUID" -eq 0 ]; then
    msg_error "Run as standard user. Sudo will be requested when needed."
    exit 1
  fi

  # 2. CONTEXT AWARENESS & BOOTSTRAPPING
  # If BASH_SOURCE is empty (piped) or doesn't have a .git folder, we are remote.
  REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$PWD}")" &> /dev/null && pwd)"

  if [ ! -d "$REPO_DIR/.git" ]; then
    msg_info "Remote execution detected. Bootstrapping environment..."
    
    sudo -v

    # Validate/Install Git
    if ! command -v git &> /dev/null; then
      msg_warn "Git missing. Installing..."
      if [ -f /etc/debian_version ]; then
        sudo apt-get update && sudo apt-get install -y git
      elif [ -f /etc/arch-release ]; then
        sudo pacman -Sy --noconfirm git
      elif [ -f /etc/redhat-release ]; then
        sudo dnf install -y git
      else
        msg_error "Unsupported OS for automatic Git installation. Install Git manually."
        exit 1
      fi
    fi

    # Configure Global Git Identity
    EXISTING_GIT_NAME=$(git config --global user.name 2>/dev/null)
    EXISTING_GIT_EMAIL=$(git config --global user.email 2>/dev/null)
    
    if [ -n "$EXISTING_GIT_NAME" ] && [ -n "$EXISTING_GIT_EMAIL" ]; then
      msg_info "Git identity already configured: $EXISTING_GIT_NAME <$EXISTING_GIT_EMAIL>"
    else
      msg_header "Configuring Git Global Identity"
      read -p "Enter Git User Name [Your Name]: " GIT_NAME
      GIT_NAME=${GIT_NAME:-"Your Name"}
      
      read -p "Enter Git Email [email@example.com]: " GIT_EMAIL
      GIT_EMAIL=${GIT_EMAIL:-"email@example.com"}

      git config --global user.name "$GIT_NAME"
      git config --global user.email "$GIT_EMAIL"
      msg_success "Git identity set to $GIT_NAME <$GIT_EMAIL>"
    fi

    # Clone Repository
    TARGET_DIR="$HOME/linuxploitacious"
    if [ ! -d "$TARGET_DIR" ]; then
      msg_info "Cloning repository to $TARGET_DIR..."
      git clone https://github.com/Exploitacious/linuxploitacious.git "$TARGET_DIR"
    else
      msg_warn "Directory $TARGET_DIR already exists. Pulling latest..."
      cd "$TARGET_DIR" && git pull
    fi

    # 3. THE HANDOFF: Execute the local script and kill the remote stream
    msg_info "Handoff to local repository execution..."
    cd "$TARGET_DIR" || exit 1
    chmod +x shellSetup.sh
    exec ./shellSetup.sh
  fi

  # --- LOCAL EXECUTION CONTINUES HERE ---
  sudo -v

  # --- OS DETECTION ---
  if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS_ID=$ID
    OS_LIKE=$ID_LIKE
  else
    msg_error "Cannot detect Operating System."
    exit 1
  fi

  # Verify whiptail
  if [[ "$OS_ID" == "debian" || "$OS_ID" == "ubuntu" || "$OS_ID" == "kali" || "$OS_LIKE" == *"debian"* ]]; then
    if ! command -v whiptail &> /dev/null; then sudo apt-get update && sudo apt-get install -y whiptail; fi
  elif [[ "$OS_ID" == "arch" || "$OS_LIKE" == *"arch"* ]]; then
    if ! command -v whiptail &> /dev/null; then sudo pacman -Sy --noconfirm libnewt; fi
  elif [[ "$OS_ID" == "fedora" || "$OS_LIKE" == *"fedora"* ]]; then
    if ! command -v whiptail &> /dev/null; then sudo dnf install -y newt; fi
  fi

  # --- PACKAGE MANAGERS ---

  install_nerd_fonts() {
    local FONT_DIR="/usr/local/share/fonts/NerdFonts"
    if [ -d "$FONT_DIR" ] && fc-list | grep -qi "Nerd Font"; then
      msg_info "Nerd Fonts already installed. Skipping."
      return 0
    fi

    msg_header "Installing Nerd Fonts (MesloLG - recommended for Oh My Posh)"
    sudo mkdir -p "$FONT_DIR"

    local MESLO_URL
    MESLO_URL=$(curl -s https://api.github.com/repos/ryanoasis/nerd-fonts/releases/latest | jq -r '.assets[] | select(.name == "Meslo.zip") | .browser_download_url')

    if [[ -z "$MESLO_URL" || "$MESLO_URL" == "null" ]]; then
      msg_error "Could not find Meslo Nerd Font download URL."
      return 1
    fi

    msg_info "Downloading MesloLG Nerd Font..."
    if wget -q "$MESLO_URL" -O /tmp/meslo-nf.zip; then
      sudo unzip -o /tmp/meslo-nf.zip -d "$FONT_DIR/" > /dev/null 2>&1
      rm /tmp/meslo-nf.zip
      sudo fc-cache -f
      msg_success "MesloLG Nerd Font installed. Set your terminal font to 'MesloLGM Nerd Font' for full symbol support."
    else
      msg_error "Failed to download Meslo Nerd Font."
      return 1
    fi
  }

  install_debian_base() {
    msg_header "Configuring Debian/Kali base"
    sudo apt-get update

    # Ensure software-properties-common is installed first
    sudo apt-get install -y software-properties-common

    msg_info "Upgrading system..."
    sudo apt-get update && sudo apt-get full-upgrade -y

    # Install base packages (stow, jq, etc.) first to ensure they exist for later steps
    local DEBIAN_PKGS=(zsh stow git curl unzip tmux fzf gnupg2 xclip ffmpeg nmap build-essential wget jq btop tree)
    if [[ "$OS_ID" == "kali" ]]; then DEBIAN_PKGS+=(kali-win-kex); fi

    msg_info "Installing packages: ${DEBIAN_PKGS[*]}"
    sudo apt-get install -y "${DEBIAN_PKGS[@]}"

    # Attempt Fastfetch installation separately to avoid blocking other packages
    if ! command -v fastfetch &> /dev/null; then
        msg_info "Attempting to install Fastfetch..."

        # 1. Try PPA for Ubuntu
        if [[ "$OS_ID" == "ubuntu" ]]; then
            msg_info "Trying Fastfetch PPA..."
            if sudo add-apt-repository -y ppa:zhangsongcui3336/fastfetch 2>/dev/null; then
                sudo apt-get update && sudo apt-get install -y fastfetch
            fi
        # 2. Try direct install (available in newer Debian/Kali)
        else
            sudo apt-get install -y fastfetch 2>/dev/null
        fi

        # 3. Manual Fallback using jq (which we just installed)
        if ! command -v fastfetch &> /dev/null; then
            msg_warn "Fastfetch not found in repos. Attempting robust manual install..."
            local FASTFETCH_URL
            FASTFETCH_URL=$(curl -s https://api.github.com/repos/fastfetch-cli/fastfetch/releases/latest | jq -r '.assets[] | select(.name | test("linux-amd64.deb")) | .browser_download_url' | head -n 1)

            if [[ -n "$FASTFETCH_URL" && "$FASTFETCH_URL" != "null" ]]; then
                msg_info "Downloading Fastfetch from: $FASTFETCH_URL"
                if wget -q "$FASTFETCH_URL" -O /tmp/fastfetch.deb; then
                    sudo apt-get install -y /tmp/fastfetch.deb
                    rm /tmp/fastfetch.deb
                    msg_success "Fastfetch installed manually."
                else
                    msg_error "Failed to download Fastfetch .deb"
                fi
            else
                msg_error "Could not find Fastfetch download URL."
            fi
        fi
    fi

    # Install Nerd Fonts for Oh My Posh / terminal symbol support
    install_nerd_fonts

    msg_success "Base packages installed."
  }

  install_arch_base() {
    msg_header "Configuring Arch base"
    sudo pacman -Syu --noconfirm
    
    local ARCH_PKGS=(zsh stow git curl unzip tmux fzf fastfetch gnupg2 xclip ffmpeg nmap base-devel btop)
    msg_info "Installing packages: ${ARCH_PKGS[*]}"
    sudo pacman -S --noconfirm --needed "${ARCH_PKGS[@]}"

    if ! command -v yay &> /dev/null; then
      msg_info "Installing yay..."
      git clone https://aur.archlinux.org/yay.git /tmp/yay
      cd /tmp/yay && makepkg -si --noconfirm
      cd "$REPO_DIR" || exit 1
    fi

    # Install Nerd Fonts for Oh My Posh / terminal symbol support
    install_nerd_fonts

    msg_success "Base packages installed."
  }

  install_fedora_base() {
    msg_header "Configuring Fedora/RHEL base"
    sudo dnf upgrade -y

    local FEDORA_PKGS=(zsh stow git curl unzip tmux fzf gnupg2 xclip nmap wget jq btop tree)
    msg_info "Installing packages: ${FEDORA_PKGS[*]}"
    sudo dnf install -y "${FEDORA_PKGS[@]}"

    # Install Development Tools group (equivalent of build-essential)
    msg_info "Installing Development Tools group..."
    sudo dnf group install -y "Development Tools"

    # FFmpeg: try ffmpeg-free (Fedora default repos) then ffmpeg (RPM Fusion)
    if ! command -v ffmpeg &> /dev/null; then
        sudo dnf install -y ffmpeg-free 2>/dev/null || sudo dnf install -y ffmpeg 2>/dev/null || \
          msg_warn "FFmpeg unavailable in current repos. Enable RPM Fusion for full codec support."
    fi

    # Attempt Fastfetch installation separately
    if ! command -v fastfetch &> /dev/null; then
        msg_info "Attempting to install Fastfetch..."
        sudo dnf install -y fastfetch 2>/dev/null

        # Manual Fallback using jq (which we just installed)
        if ! command -v fastfetch &> /dev/null; then
            msg_warn "Fastfetch not found in repos. Attempting manual install..."
            local FASTFETCH_URL
            FASTFETCH_URL=$(curl -s https://api.github.com/repos/fastfetch-cli/fastfetch/releases/latest | jq -r '.assets[] | select(.name | test("linux-amd64\\.rpm$")) | .browser_download_url' | head -n 1)

            if [[ -n "$FASTFETCH_URL" && "$FASTFETCH_URL" != "null" ]]; then
                msg_info "Downloading Fastfetch from: $FASTFETCH_URL"
                if wget -q "$FASTFETCH_URL" -O /tmp/fastfetch.rpm; then
                    sudo dnf install -y /tmp/fastfetch.rpm
                    rm /tmp/fastfetch.rpm
                    msg_success "Fastfetch installed manually."
                else
                    msg_error "Failed to download Fastfetch .rpm"
                fi
            else
                msg_error "Could not find Fastfetch download URL."
            fi
        fi
    fi

    # Install Nerd Fonts for Oh My Posh / terminal symbol support
    install_nerd_fonts

    msg_success "Base packages installed."
  }

  install_brave() {
    msg_header "Installing Brave Browser"
    
    if [[ "$OS_ID" == "debian" || "$OS_ID" == "ubuntu" || "$OS_ID" == "kali" || "$OS_LIKE" == *"debian"* ]]; then
      sudo apt-get install -y curl
      sudo curl -fsSLo /usr/share/keyrings/brave-browser-archive-keyring.gpg https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg
      echo "deb [signed-by=/usr/share/keyrings/brave-browser-archive-keyring.gpg] https://brave-browser-apt-release.s3.brave.com/ stable main" | sudo tee /etc/apt/sources.list.d/brave-browser-release.list > /dev/null
      sudo apt-get update && sudo apt-get install -y brave-browser
    elif [[ "$OS_ID" == "arch" || "$OS_LIKE" == *"arch"* ]]; then
      if ! command -v yay &> /dev/null; then
        msg_error "yay not found. Please install yay first or run BASE option."
        return 1
      fi
      yay -S --noconfirm brave-bin
    elif [[ "$OS_ID" == "fedora" || "$OS_LIKE" == *"fedora"* ]]; then
      sudo rpm --import https://brave-browser-rpm-release.s3.brave.com/brave-core.asc
      cat << 'BRAVEREPO' | sudo tee /etc/yum.repos.d/brave-browser.repo > /dev/null
[brave-browser]
name=Brave Browser
baseurl=https://brave-browser-rpm-release.s3.brave.com/$basearch
enabled=1
gpgcheck=1
gpgkey=https://brave-browser-rpm-release.s3.brave.com/brave-core.asc
BRAVEREPO
      sudo dnf install -y brave-browser
    fi
    msg_success "Brave Browser installed."
  }

  setup_root_profile() {
    msg_header "Setting up Root Profile"
    
    if [ "$EUID" -eq 0 ]; then
      msg_error "This option must be run as a regular user, not as root."
      return 1
    fi
    
    msg_info "Ensuring system packages are installed..."
    if [[ "$OS_ID" == "debian" || "$OS_ID" == "ubuntu" || "$OS_ID" == "kali" || "$OS_LIKE" == *"debian"* ]]; then
      sudo apt-get install -y btop tmux fzf zsh
    elif [[ "$OS_ID" == "arch" || "$OS_LIKE" == *"arch"* ]]; then
      sudo pacman -S --noconfirm --needed btop tmux fzf zsh
    elif [[ "$OS_ID" == "fedora" || "$OS_LIKE" == *"fedora"* ]]; then
      sudo dnf install -y btop tmux fzf zsh
    fi
    
    if ! grep -q "/usr/bin/zsh" /etc/shells; then
      echo "/usr/bin/zsh" | sudo tee -a /etc/shells
    fi
    sudo chsh -s /usr/bin/zsh root
    msg_success "Root shell set to zsh"
    
    if [ ! -d "/root/.oh-my-zsh" ]; then
      msg_info "Installing Oh My Zsh for root..."
      sudo git clone https://github.com/ohmyzsh/ohmyzsh.git /root/.oh-my-zsh
    fi
    
    if ! sudo test -f "/root/.local/bin/oh-my-posh"; then
      msg_info "Installing Oh My Posh for root..."
      sudo mkdir -p /root/.local/bin
      sudo curl -s https://ohmyposh.dev/install.sh | sudo bash -s -- -d /root/.local/bin
    fi
    
    if [ ! -d "/root/.tmux/plugins/tpm" ]; then
      msg_info "Installing Tmux Plugin Manager for root..."
      sudo git clone https://github.com/tmux-plugins/tpm /root/.tmux/plugins/tpm
    fi
    
    # Ensure Nerd Fonts are available for root's OMP themes
    install_nerd_fonts

    msg_info "Deploying configs to /root via stow..."
    cd "$REPO_DIR" || exit 1

    local PACKAGES=("fastfetch" "omp" "rustscan" "scripts" "tmux" "zsh" "bash" "btop")
    for pkg in "${PACKAGES[@]}"; do
      if [ -d "$pkg" ]; then
        sudo stow -D -t /root "$pkg" 2>/dev/null || true
        if sudo stow -v -t /root "$pkg" 2>&1; then
          msg_success "Stowed to /root: $pkg"
        else
          msg_error "Failed to stow to /root: $pkg"
        fi
      fi
    done
    
    msg_info "Sharing AI tool data with root (symlinks + ACLs)..."
    local PRIMARY_USER="$USER"
    local PRIMARY_HOME="$HOME"

    # Install ACL utilities for proper cross-user file access
    if ! command -v setfacl &> /dev/null; then
      msg_info "Installing ACL utilities..."
      if [[ "$OS_ID" == "debian" || "$OS_ID" == "ubuntu" || "$OS_ID" == "kali" || "$OS_LIKE" == *"debian"* ]]; then
        sudo apt-get install -y acl
      elif [[ "$OS_ID" == "arch" || "$OS_LIKE" == *"arch"* ]]; then
        sudo pacman -S --noconfirm acl
      elif [[ "$OS_ID" == "fedora" || "$OS_LIKE" == *"fedora"* ]]; then
        sudo dnf install -y acl
      fi
    fi

    local AI_DIRS=(".gemini" ".claude" ".local/share/opencode")
    local AI_FILES=(".claude.json")

    for dir in "${AI_DIRS[@]}"; do
      local SRC="$PRIMARY_HOME/$dir"
      local DST="/root/$dir"

      # Skip if source doesn't exist (tool not installed yet)
      if [ ! -d "$SRC" ]; then
        msg_info "Skipping $dir (not present in $PRIMARY_HOME)"
        continue
      fi

      # Already a correct symlink — just refresh ACLs
      if [ -L "$DST" ] && [ "$(readlink -f "$DST")" = "$(readlink -f "$SRC")" ]; then
        msg_info "$DST already linked correctly"
      else
        # Merge any unique data from root's copy into user's copy before replacing
        if [ -d "$DST" ] && [ ! -L "$DST" ]; then
          msg_info "Merging root's $dir data into $SRC before linking..."
          sudo cp -rn "$DST"/* "$SRC"/ 2>/dev/null || true
          sudo mv "$DST" "${DST}.bak.$(date +%Y%m%d_%H%M%S)"
          msg_warn "Root's original $dir backed up to ${DST}.bak.*"
        else
          sudo rm -rf "$DST"
        fi

        sudo mkdir -p "$(dirname "$DST")"
        sudo ln -s "$SRC" "$DST"
        msg_success "Linked: $DST -> $SRC"
      fi

      # Fix ownership and set ACLs for seamless cross-user access
      sudo chown -R "$PRIMARY_USER:$PRIMARY_USER" "$SRC"
      if command -v setfacl &> /dev/null; then
        sudo setfacl -R -m u:root:rwX "$SRC"
        sudo setfacl -R -d -m u:root:rwX "$SRC"
        sudo setfacl -R -m u:"$PRIMARY_USER":rwX "$SRC"
        sudo setfacl -R -d -m u:"$PRIMARY_USER":rwX "$SRC"
        msg_success "ACLs set on $SRC (both root and $PRIMARY_USER have full access)"
      else
        sudo chmod -R g+rw "$SRC"
        msg_warn "setfacl not available — falling back to group permissions on $SRC"
      fi
    done

    for file in "${AI_FILES[@]}"; do
      local SRC="$PRIMARY_HOME/$file"
      local DST="/root/$file"
      if [ -f "$SRC" ] || [ -L "$SRC" ]; then
        if [ -L "$DST" ] && [ "$(readlink -f "$DST")" = "$(readlink -f "$SRC")" ]; then
          msg_info "$DST already linked correctly"
        else
          # Back up root's copy if it's a real file
          if [ -f "$DST" ] && [ ! -L "$DST" ]; then
            sudo mv "$DST" "${DST}.bak.$(date +%Y%m%d_%H%M%S)"
          else
            sudo rm -f "$DST"
          fi
          sudo ln -s "$SRC" "$DST"
          msg_success "Linked: $DST -> $SRC"
        fi
        sudo chown "$PRIMARY_USER:$PRIMARY_USER" "$SRC"
        if command -v setfacl &> /dev/null; then
          sudo setfacl -m u:root:rw "$SRC"
          sudo setfacl -m u:"$PRIMARY_USER":rw "$SRC"
        fi
      fi
    done
    
    if [ ! -d "/root/.nvm" ]; then
      msg_info "Installing NVM for root..."
      sudo -i bash -c 'curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash'
    fi
    
    msg_info "Installing Node.js, pnpm, and AI tools for root..."
    sudo -i bash << 'ROOTNVM'
export NVM_DIR="/root/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
nvm install --lts
nvm use --lts
corepack enable pnpm
export PNPM_HOME="/root/.local/share/pnpm"
export PATH="$PNPM_HOME:$PATH"
pnpm add -g @google/gemini-cli opencode-ai @anthropic-ai/claude-code
ROOTNVM
    
    msg_success "Root profile setup complete. Run 'sudo -i' to use."
  }

  setup_github_ssh() {
    msg_header "Setting up GitHub SSH Key"
    
    local SSH_KEY="$HOME/.ssh/id_ed25519"
    local GIT_EMAIL=$(git config --global user.email 2>/dev/null)
    GIT_EMAIL=${GIT_EMAIL:-"email@example.com"}
    
    if [ -f "$SSH_KEY" ]; then
      msg_info "SSH key already exists at $SSH_KEY"
    else
      msg_info "Generating new ed25519 SSH key..."
      mkdir -p "$HOME/.ssh"
      ssh-keygen -t ed25519 -C "$GIT_EMAIL" -f "$SSH_KEY" -N ""
      msg_success "SSH key generated"
    fi
    
    msg_info "Configuring SSH for GitHub..."
    mkdir -p "$HOME/.ssh"
    if ! grep -q "Host github.com" "$HOME/.ssh/config" 2>/dev/null; then
      cat >> "$HOME/.ssh/config" << 'EOF'

Host github.com
    HostName github.com
    User git
    IdentityFile ~/.ssh/id_ed25519
EOF
      chmod 600 "$HOME/.ssh/config"
      msg_success "SSH config updated"
    else
      msg_info "GitHub host already configured in SSH config"
    fi
    
    msg_info "Switching git remotes to SSH..."
    if [ -d "$REPO_DIR/.git" ]; then
      cd "$REPO_DIR" || exit 1
      local REMOTE_URL=$(git remote get-url origin 2>/dev/null)
      if [[ "$REMOTE_URL" == https://github.com/* ]]; then
        local REPO_PATH="${REMOTE_URL#https://github.com/}"
        git remote set-url origin "git@github.com:$REPO_PATH"
        msg_success "Switched to SSH: git@github.com:$REPO_PATH"
      elif [[ "$REMOTE_URL" == git@github.com:* ]]; then
        msg_info "Remote already using SSH"
      fi
    fi
    
    msg_info "Copying SSH key to root..."
    sudo mkdir -p /root/.ssh
    sudo cp "$SSH_KEY" /root/.ssh/id_ed25519
    sudo cp "$SSH_KEY.pub" /root/.ssh/id_ed25519.pub
    sudo chmod 600 /root/.ssh/id_ed25519
    sudo chmod 644 /root/.ssh/id_ed25519.pub
    
    if ! sudo grep -q "Host github.com" /root/.ssh/config 2>/dev/null; then
      sudo tee -a /root/.ssh/config > /dev/null << 'EOF'

Host github.com
    HostName github.com
    User git
    IdentityFile ~/.ssh/id_ed25519
EOF
      sudo chmod 600 /root/.ssh/config
    fi
    msg_success "SSH key copied to /root/.ssh/"
    
    SSH_PUBLIC_KEY=$(cat "$SSH_KEY.pub")
    echo ""
    echo -e "${CYAN}=== GitHub SSH Key ===${NC}"
    echo -e "${YELLOW}Upload this public key to:${NC} https://github.com/settings/keys"
    echo ""
    echo -e "${GREEN}$SSH_PUBLIC_KEY${NC}"
    echo ""
    echo -e "${YELLOW}After uploading, test with:${NC} ssh -T git@github.com"
    echo ""
  }

  install_node_env() {
    msg_header "Installing Node.js Environment"
    
    # Clean up conflicting npm config
    if [ -f "$HOME/.npmrc" ]; then
        msg_warn "Backing up existing .npmrc to .npmrc.bak (incompatible with NVM)"
        mv "$HOME/.npmrc" "$HOME/.npmrc.bak"
    fi

    # Install NVM
    msg_info "Installing NVM..."
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
    
    # Load NVM for current session
    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

    # Install Node LTS
    msg_info "Installing Node LTS..."
    nvm install --lts
    nvm use --lts

    # Enable pnpm with suppressed prompts
    msg_info "Enabling pnpm..."
    export COREPACK_ENABLE_DOWNLOAD_PROMPT=0
    corepack enable pnpm

    # Set up pnpm environment for this session
    export PNPM_HOME="$HOME/.local/share/pnpm"
    export PATH="$PNPM_HOME:$PATH"
    mkdir -p "$PNPM_HOME"

    # Install global packages
    msg_info "Installing Global AI Tools (@google/gemini-cli, opencode-ai)..."
    pnpm add -g @google/gemini-cli opencode-ai @anthropic-ai/claude-code
    msg_success "Node environment ready."
  }

  # --- SHELL ENVIRONMENT ---

  setup_shell_env() {
    msg_header "Setting up Shell Environment (Zsh, OMZ, OMP, TPM)"
    
    # Ensure dependencies are present if BASE was skipped
    if ! command -v zsh &> /dev/null || ! command -v unzip &> /dev/null; then
        msg_info "Installing missing dependencies (zsh/unzip)..."
        if [ -f /etc/debian_version ]; then
            sudo apt-get update && sudo apt-get install -y zsh unzip
        elif [ -f /etc/arch-release ]; then
            sudo pacman -S --noconfirm zsh unzip
        elif [ -f /etc/redhat-release ]; then
            sudo dnf install -y zsh unzip
        fi
    fi
    
    if [ ! -d "$HOME/.oh-my-zsh" ]; then
      msg_info "Installing Oh My Zsh..."
      sh -c "$(curl -fsSL https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh) --unattended"
    fi

    if ! command -v oh-my-posh &> /dev/null; then
      msg_info "Installing Oh My Posh..."
      mkdir -p "$HOME/.local/bin"
      curl -s https://ohmyposh.dev/install.sh | bash -s -- -d "$HOME/.local/bin"
      export PATH=$PATH:$HOME/.local/bin
    fi

    if [ ! -d "$HOME/.tmux/plugins/tpm" ]; then
      msg_info "Cloning Tmux Plugin Manager..."
      git clone https://github.com/tmux-plugins/tpm "$HOME/.tmux/plugins/tpm" -q
    fi

    if [ -f "$HOME/.zshrc" ] && [ ! -L "$HOME/.zshrc" ]; then
      msg_warn "Backing up existing .zshrc..."
      mv "$HOME/.zshrc" "$HOME/.zshrc.bak"
    fi

    # Ensure zsh is in allowed shells
    if ! grep -q "$(which zsh)" /etc/shells; then
        echo "$(which zsh)" | sudo tee -a /etc/shells
    fi
    sudo chsh -s "$(which zsh)" "$USER"
    msg_success "Shell environment configured."
  }

  # --- STOW DEPLOYMENT ---
  # Ensures a completely clean slate before stowing each package.
  # Handles: previous stow deployments, stale/broken symlinks, real file conflicts.

  unstow_package() {
    # Phase 1: Remove any existing stow symlinks for this package
    local pkg="$1"
    msg_info "Unstowing previous deployment of '$pkg'..."
    stow -D -t "$HOME" "$pkg" 2>/dev/null || true
  }

  clean_stale_symlinks() {
    # Phase 2: Remove broken or stale symlinks at target paths
    local pkg_dir="$REPO_DIR/$1"
    local target_dir="$HOME"

    find "$pkg_dir" -type f | while read -r src_file; do
        local rel_path="${src_file#$pkg_dir/}"
        local dest_file="$target_dir/$rel_path"

        if [ -L "$dest_file" ]; then
            # Remove any symlink (broken or pointing elsewhere)
            local link_target
            link_target="$(readlink -f "$dest_file" 2>/dev/null || echo "")"
            if [ ! -e "$dest_file" ] || [ "$link_target" != "$(readlink -f "$src_file")" ]; then
                msg_warn "Removing stale symlink: $dest_file"
                rm -f "$dest_file"
            fi
        fi
    done
  }

  backup_real_files() {
    # Phase 3: Back up any real (non-symlink) files that would conflict
    local pkg_dir="$REPO_DIR/$1"
    local target_dir="$HOME"
    local timestamp
    timestamp="$(date +%Y%m%d_%H%M%S)"

    find "$pkg_dir" -type f | while read -r src_file; do
        local rel_path="${src_file#$pkg_dir/}"
        local dest_file="$target_dir/$rel_path"

        if [ -e "$dest_file" ] && [ ! -L "$dest_file" ]; then
            local backup_file="${dest_file}.backup_${timestamp}"
            msg_warn "Backing up real file: $dest_file -> $backup_file"
            mv "$dest_file" "$backup_file"
        fi
    done
  }

  ensure_target_dirs() {
    # Phase 4: Pre-create parent directories so stow doesn't have to fold trees
    # through directories that contain non-stow files (prevents tree folding conflicts)
    local pkg_dir="$REPO_DIR/$1"
    local target_dir="$HOME"

    find "$pkg_dir" -type d | while read -r src_dir; do
        local rel_path="${src_dir#$pkg_dir/}"
        if [ -n "$rel_path" ]; then
            mkdir -p "$target_dir/$rel_path"
        fi
    done
  }

  deploy_stow() {
    msg_header "Deploying Dotfiles (GNU Stow)"
    cd "$REPO_DIR" || exit 1
    
    # Ensure stow is installed
    if ! command -v stow &> /dev/null; then
        msg_warn "Stow not found. Installing..."
        if [ -f /etc/debian_version ]; then
            sudo apt-get update && sudo apt-get install -y stow
        elif [ -f /etc/arch-release ]; then
            sudo pacman -S --noconfirm stow
        elif [ -f /etc/redhat-release ]; then
            sudo dnf install -y stow
        fi
    fi

    if [ -d "$REPO_DIR/scripts/.local/bin" ]; then
      chmod -R +x "$REPO_DIR/scripts/.local/bin/"
    fi

    local PACKAGES=("fastfetch" "omp" "rustscan" "scripts" "tmux" "zsh" "bash" "btop")
    
    for pkg in "${PACKAGES[@]}"; do
      if [ -d "$pkg" ]; then
        # Full 4-phase conflict resolution
        unstow_package "$pkg"
        clean_stale_symlinks "$pkg"
        backup_real_files "$pkg"
        ensure_target_dirs "$pkg"

        if stow -v -t "$HOME" "$pkg" 2>&1; then
            msg_success "Stowed: $pkg"
        else
            msg_error "Failed to stow: $pkg"
        fi
      else
        msg_warn "Directory '$pkg' missing. Skipping."
      fi
    done

    msg_success "All dotfiles deployed. Repository is the source of truth."
  }

  # --- MENU & EXECUTION ---

  CHOICES=$(whiptail --title "Linux Environment Setup" --checklist \
  "Select components to install/deploy (Space to toggle, Enter to confirm):" 24 78 9 \
    "BASE" "OS Updates & Core Packages" ON \
    "NODE" "Node.js, NVM, pnpm, AI Tools" ON \
    "SHELL" "Zsh, OMZ, OMP, & TPM" ON \
    "STOW" "Deploy Repo configs" ON \
    "BRAVE" "Brave Browser" OFF \
    "ROOT" "Replicate profile to root user" OFF \
    "SSHKEY" "Generate GitHub SSH key & configure" OFF 3>&1 1>&2 2>&3)

  if [ -z "$CHOICES" ]; then
    msg_warn "Installation cancelled."
    exit 0
  fi

  if [[ $CHOICES == *"BASE"* ]]; then
    if [[ "$OS_ID" == "debian" || "$OS_ID" == "ubuntu" || "$OS_ID" == "kali" || "$OS_LIKE" == *"debian"* ]]; then
      install_debian_base
    elif [[ "$OS_ID" == "arch" || "$OS_LIKE" == *"arch"* ]]; then
      install_arch_base
    elif [[ "$OS_ID" == "fedora" || "$OS_LIKE" == *"fedora"* ]]; then
      install_fedora_base
    fi
  fi

  if [[ $CHOICES == *"NODE"* ]]; then install_node_env; fi
  if [[ $CHOICES == *"SHELL"* ]]; then setup_shell_env; fi
  if [[ $CHOICES == *"STOW"* ]]; then deploy_stow; fi
  if [[ $CHOICES == *"BRAVE"* ]]; then install_brave; fi
  if [[ $CHOICES == *"ROOT"* ]]; then setup_root_profile; fi
  if [[ $CHOICES == *"SSHKEY"* ]]; then setup_github_ssh; fi

  echo -e "\n${GREEN}Setup complete. Restart your terminal to apply shell changes.${NC}"
}

# Execute the buffered payload
main "$@"
