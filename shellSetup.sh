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
      else
        msg_error "Unsupported OS for automatic Git installation. Install Git manually."
        exit 1
      fi
    fi

    # Configure Global Git Identity
    msg_header "Configuring Git Global Identity"
    read -p "Enter Git User Name [Your Name]: " GIT_NAME
    GIT_NAME=${GIT_NAME:-"Your Name"}
    
    read -p "Enter Git Email [email@example.com]: " GIT_EMAIL
    GIT_EMAIL=${GIT_EMAIL:-"email@example.com"}

    git config --global user.name "$GIT_NAME"
    git config --global user.email "$GIT_EMAIL"
    msg_success "Git identity set to $GIT_NAME <$GIT_EMAIL>"

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
  fi

  # --- PACKAGE MANAGERS ---

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
    fi
    msg_success "Brave Browser installed."
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

  backup_stow_conflicts() {
    local pkg_dir="$REPO_DIR/$1"
    local target_dir="$HOME"
    
    # Find all files in the package directory relative to package root
    find "$pkg_dir" -type f | while read -r src_file; do
        # Get relative path from pkg_dir
        local rel_path="${src_file#$pkg_dir/}"
        local dest_file="$target_dir/$rel_path"
        
        # Check if destination exists and is NOT a symlink
        if [ -e "$dest_file" ] && [ ! -L "$dest_file" ]; then
            msg_warn "Conflict found: $dest_file. Backing up to $dest_file.bak"
            mv "$dest_file" "$dest_file.bak"
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
        fi
    fi

    if [ -d "$REPO_DIR/scripts/.local/bin" ]; then
      chmod -R +x "$REPO_DIR/scripts/.local/bin/"
    fi

    local PACKAGES=("fastfetch" "omp" "rustscan" "scripts" "tmux" "zsh" "bash" "btop")
    
    for pkg in "${PACKAGES[@]}"; do
      if [ -d "$pkg" ]; then
        backup_stow_conflicts "$pkg"
        stow -t "$HOME" "$pkg"
        msg_success "Stowed: $pkg"
      else
        msg_warn "Directory '$pkg' missing. Skipping."
      fi
    done
  }

  # --- MENU & EXECUTION ---

  CHOICES=$(whiptail --title "Linux Environment Setup" --checklist \
  "Select components to install/deploy (Space to toggle, Enter to confirm):" 20 78 7 \
    "BASE" "OS Updates & Core Packages" ON \
    "NODE" "Node.js, NVM, pnpm, AI Tools" ON \
    "SHELL" "Zsh, OMZ, OMP, & TPM" ON \
    "STOW" "Deploy Repo configs" ON \
    "BRAVE" "Brave Browser" OFF 3>&1 1>&2 2>&3)

  if [ -z "$CHOICES" ]; then
    msg_warn "Installation cancelled."
    exit 0
  fi

  if [[ $CHOICES == *"BASE"* ]]; then 
    if [[ "$OS_ID" == "debian" || "$OS_ID" == "ubuntu" || "$OS_ID" == "kali" || "$OS_LIKE" == *"debian"* ]]; then
      install_debian_base
    elif [[ "$OS_ID" == "arch" || "$OS_LIKE" == *"arch"* ]]; then
      install_arch_base
    fi
  fi

  if [[ $CHOICES == *"NODE"* ]]; then install_node_env; fi
  if [[ $CHOICES == *"SHELL"* ]]; then setup_shell_env; fi
  if [[ $CHOICES == *"STOW"* ]]; then deploy_stow; fi
  if [[ $CHOICES == *"BRAVE"* ]]; then install_brave; fi

  echo -e "\n${GREEN}Setup complete. Restart your terminal to apply shell changes.${NC}"
}

# Execute the buffered payload
main "$@"
