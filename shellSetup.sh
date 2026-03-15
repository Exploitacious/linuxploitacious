#!/bin/bash
# Cross-Platform Linux Setup Script (Stow, Zsh, OMZ, OMP, Tmux)

# 1. RECLAIM TTY: Prevent curl | bash from breaking interactive prompts
exec < /dev/tty

if [ "$EUID" -eq 0 ]; then
  echo "Error: Run as standard user. Sudo will be requested when needed."
  exit 1
fi

# 2. CONTEXT AWARENESS & BOOTSTRAPPING
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"

if [ ! -d "$REPO_DIR/.git" ]; then
  echo "[*] Remote execution detected. Bootstrapping environment..."
  
  sudo -v

  # Validate/Install Git
  if ! command -v git &> /dev/null; then
    echo "[*] Git missing. Installing..."
    if [ -f /etc/debian_version ]; then
      sudo apt-get update && sudo apt-get install -y git
    elif [ -f /etc/arch-release ]; then
      sudo pacman -Sy --noconfirm git
    else
      echo "[-] Unsupported OS for automatic Git installation. Install Git manually."
      exit 1
    fi
  fi

  # Configure Global Git Identity
  echo -e "\n[*] Configuring Git Global Identity..."
  read -p "Enter Git User Name [Alex Ivantsov]: " GIT_NAME
  GIT_NAME=${GIT_NAME:-"Alex Ivantsov"}
  
  read -p "Enter Git Email [alex@ivantsov.tech]: " GIT_EMAIL
  GIT_EMAIL=${GIT_EMAIL:-"alex@ivantsov.tech"}

  git config --global user.name "$GIT_NAME"
  git config --global user.email "$GIT_EMAIL"
  echo "[+] Git identity set to $GIT_NAME <$GIT_EMAIL>"

  # Clone Repository
  TARGET_DIR="$HOME/linuxploitacious"
  if [ ! -d "$TARGET_DIR" ]; then
    echo "[*] Cloning repository to $TARGET_DIR..."
    git clone https://github.com/Exploitacious/linuxploitacious.git "$TARGET_DIR"
  else
    echo "[!] Directory $TARGET_DIR already exists. Pulling latest..."
    cd "$TARGET_DIR" && git pull
  fi

  # 3. THE HANDOFF: Execute the local script and kill the remote stream
  echo "[*] Handoff to local repository execution..."
  cd "$TARGET_DIR" || exit 1
  chmod +x ShellSetup.sh
  exec ./ShellSetup.sh
fi

# --- LOCAL EXECUTION CONTINUES HERE ---
sudo -v

# Verify whiptail
if ! command -v whiptail &> /dev/null; then
  if [ -f /etc/debian_version ]; then
    sudo apt-get update && sudo apt-get install -y whiptail
  elif [ -f /etc/arch-release ]; then
    sudo pacman -Sy --noconfirm libnewt
  fi
fi

# --- OS DETECTION ---
if [ -f /etc/os-release ]; then
  . /etc/os-release
  OS_ID=$ID
  OS_LIKE=$ID_LIKE
else
  echo "Error: Cannot detect Operating System."
  exit 1
fi

# Ensure menu dependencies
if [[ "$OS_ID" == "debian" || "$OS_ID" == "ubuntu" || "$OS_ID" == "kali" || "$OS_LIKE" == *"debian"* ]]; then
  if ! command -v whiptail &> /dev/null; then sudo apt-get update && sudo apt-get install -y whiptail; fi
elif [[ "$OS_ID" == "arch" || "$OS_LIKE" == *"arch"* ]]; then
  if ! command -v whiptail &> /dev/null; then sudo pacman -Sy --noconfirm libnewt; fi
fi

# --- PACKAGE MANAGERS ---

install_debian_base() {
  echo "Configuring Debian/Kali base..."
  sudo apt-get update
  
  # Brave Browser Repo
  sudo curl -fsSLo /usr/share/keyrings/brave-browser-archive-keyring.gpg https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg
  echo "deb [signed-by=/usr/share/keyrings/brave-browser-archive-keyring.gpg] https://brave-browser-apt-release.s3.brave.com/ stable main" | sudo tee /etc/apt/sources.list.d/brave-browser-release.list > /dev/null
  
  sudo apt-get update && sudo apt-get full-upgrade -y
  
  local DEBIAN_PKGS=(zsh stow git curl unzip tmux fzf fastfetch gnupg2 xclip ffmpeg nmap brave-browser)
  
  if [[ "$OS_ID" == "kali" ]]; then
    DEBIAN_PKGS+=(kali-win-kex)
  fi

  sudo apt-get install -y "${DEBIAN_PKGS[@]}"
}

install_arch_base() {
  echo "Configuring Arch base..."
  sudo pacman -Syu --noconfirm
  
  local ARCH_PKGS=(zsh stow git curl unzip tmux fzf fastfetch gnupg2 xclip ffmpeg nmap base-devel)
  sudo pacman -S --noconfirm --needed "${ARCH_PKGS[@]}"

  # Check for Yay (AUR Helper)
  if ! command -v yay &> /dev/null; then
    echo "Installing yay..."
    git clone https://aur.archlinux.org/yay.git /tmp/yay
    cd /tmp/yay && makepkg -si --noconfirm
    cd "$REPO_DIR" || exit 1
  fi

  yay -S --noconfirm brave-bin
}

# --- SHELL ENVIRONMENT ---

setup_shell_env() {
  echo "Setting up Oh My Zsh, Oh My Posh, and TPM..."
  
  # Oh My Zsh
  if [ ! -d "$HOME/.oh-my-zsh" ]; then
    sh -c "$(curl -fsSL https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh) --unattended"
  fi

  # Oh My Posh (System-wide install)
  if ! command -v oh-my-posh &> /dev/null; then
    sudo curl -s https://ohmyposh.dev/install.sh | sudo bash -s
  fi

  # Tmux Plugin Manager
  if [ ! -d "$HOME/.tmux/plugins/tpm" ]; then
    git clone https://github.com/tmux-plugins/tpm "$HOME/.tmux/plugins/tpm" -q
  fi

  # Clear collision for Stow
  if [ -f "$HOME/.zshrc" ] && [ ! -L "$HOME/.zshrc" ]; then
    rm "$HOME/.zshrc"
  fi

  sudo chsh -s $(which zsh) "$USER"
}

# --- STOW DEPLOYMENT ---

deploy_stow() {
  echo "Deploying dotfiles via GNU Stow..."
  cd "$REPO_DIR" || exit 1

# Force executable permissions on all global scripts before stowing
if [ -d "$REPO_DIR/scripts/.local/bin" ]; then
  chmod -R +x "$REPO_DIR/scripts/.local/bin/"
fi
  
  local PACKAGES=("fastfetch" "omp" "rustscan" "scripts" "tmux" "zsh")
  
  for pkg in "${PACKAGES[@]}"; do
    if [ -d "$pkg" ]; then
      stow -t "$HOME" "$pkg"
      echo "Stowed: $pkg"
    else
      echo "Warning: Directory '$pkg' missing. Skipping."
    fi
  done
}

# --- MENU & EXECUTION ---

CHOICES=$(whiptail --title "Linux Environment Setup" --checklist \
"Select components to install/deploy (Space to toggle, Enter to confirm):" 20 78 5 \
  "BASE" "OS Updates & Core Packages" ON \
  "SHELL" "Zsh, OMZ, OMP, & TPM" ON \
  "STOW" "Deploy Repo configs" ON 3>&1 1>&2 2>&3)

if [ -z "$CHOICES" ]; then
  echo "Installation cancelled."
  exit 0
fi

if [[ $CHOICES == *"BASE"* ]]; then 
  if [[ "$OS_ID" == "debian" || "$OS_ID" == "ubuntu" || "$OS_ID" == "kali" || "$OS_LIKE" == *"debian"* ]]; then
    install_debian_base
  elif [[ "$OS_ID" == "arch" || "$OS_LIKE" == *"arch"* ]]; then
    install_arch_base
  fi
fi

if [[ $CHOICES == *"SHELL"* ]]; then setup_shell_env; fi
if [[ $CHOICES == *"STOW"* ]]; then deploy_stow; fi

echo -e "\nSetup complete. Restart your terminal to apply shell changes."
