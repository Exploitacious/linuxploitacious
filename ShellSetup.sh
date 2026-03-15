#!/bin/bash
# Interactive bootstrap script for Debian/Kali environments using GNU Stow

# Enforce standard user execution
if [ "$EUID" -eq 0 ]; then
  echo "Error: Do not run this script as root. Run as your standard user. Sudo will be requested when necessary."
  exit 1
fi

# Ensure we are running from inside the repository
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
if [ ! -d "$REPO_DIR/.git" ]; then
  echo "Error: This script must be run from within the cloned git repository."
  exit 1
fi

# Request sudo upfront
sudo -v

# Verify whiptail
if ! command -v whiptail &> /dev/null; then
  sudo apt-get update && sudo apt-get install -y whiptail
fi

# --- FUNCTIONS ---

update_repos_and_system() {
  echo "Updating repositories and system..."
  sudo wget -q https://archive.kali.org/archive-key.asc -O /etc/apt/trusted.gpg.d/kali-archive-keyring.asc || true
  sudo curl -fsSLo /usr/share/keyrings/brave-browser-archive-keyring.gpg https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg
  echo "deb [signed-by=/usr/share/keyrings/brave-browser-archive-keyring.gpg] https://brave-browser-apt-release.s3.brave.com/ stable main" | sudo tee /etc/apt/sources.list.d/brave-browser-release.list > /dev/null
  sudo apt-get update && sudo apt-get full-upgrade -y
}

install_base_packages() {
  echo "Installing core packages and dependencies..."
  sudo apt-get install -y zsh stow gnupg2 fastfetch git curl pipx kali-win-kex fzf brave-browser ffmpeg nmap xclip tmux openvpn unzip
}

setup_zsh_and_tpm() {
  echo "Setting up Oh My Zsh and Tmux Plugin Manager..."
  
  # Install OMZ unattended
  if [ ! -d "$HOME/.oh-my-zsh" ]; then
    sh -c "$(curl -fsSL https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh) --unattended"
  fi

  # Change default shell
  sudo chsh -s $(which zsh) "$USER"

  # Remove the OMZ default .zshrc so Stow does not conflict
  if [ -f "$HOME/.zshrc" ] && [ ! -L "$HOME/.zshrc" ]; then
    rm "$HOME/.zshrc"
  fi

  # Clone TPM
  if [ ! -d "$HOME/.tmux/plugins/tpm" ]; then
    git clone https://github.com/tmux-plugins/tpm "$HOME/.tmux/plugins/tpm" -q
  fi
}

install_docker_engine() {
  echo "Installing Docker..."
  sudo apt-get install -y ca-certificates curl
  sudo install -m 0755 -d /etc/apt/keyrings
  sudo curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
  sudo chmod a+r /etc/apt/keyrings/docker.asc

  . /etc/os-release
  local DOCKER_CODENAME=$VERSION_CODENAME
  if [ "$ID" = "kali" ]; then
    DOCKER_CODENAME="bookworm"
  fi

  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian $DOCKER_CODENAME stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
  
  sudo apt-get update
  sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  
  sudo usermod -aG docker "$USER"
  sudo systemctl enable --now docker
}

setup_nordvpn_configs() {
  echo "Deploying NordVPN OpenVPN configurations..."
  local CONFIG_DIR="$HOME/.config/nordvpn/ovpn_udp"
  
  mkdir -p "$CONFIG_DIR"
  wget -q "https://downloads.nordcdn.com/configs/archives/servers/ovpn.zip" -O /tmp/ovpn.zip
  unzip -qo /tmp/ovpn.zip -d "$HOME/.config/nordvpn/"
  rm /tmp/ovpn.zip

  echo "Patching OpenVPN cipher configurations..."
  find "$CONFIG_DIR" -name "*.ovpn" -type f -print0 | xargs -0 sed -i \
    -e "s|cipher AES-256-CBC|data-ciphers AES-256-GCM:AES-128-GCM:CHACHA20-POLY1305|g" \
    -e "\$aauth-user-pass $HOME/.config/nordvpn/vpn-credentials.txt"
}

deploy_stow_packages() {
  echo "Deploying configurations via GNU Stow..."
  cd "$REPO_DIR" || exit 1
  
  # Define the packages you want to stow
  # Ensure these folders actually exist in your repo before running
  local PACKAGES=("zsh" "tmux" "fastfetch" "rustscan" "scripts")
  
  for pkg in "${PACKAGES[@]}"; do
    if [ -d "$pkg" ]; then
      stow -t "$HOME" "$pkg"
      echo "Stowed: $pkg"
    else
      echo "Warning: Package directory '$pkg' not found in repo. Skipping."
    fi
  done
}

cleanup_system() {
  echo "Cleaning up..."
  sudo apt-get autoremove -y
  sudo apt-get clean
}

# --- INTERACTIVE MENU ---

CHOICES=$(whiptail --title "Linux Environment Setup" --checklist \
"Select components to install/deploy (Space to toggle, Enter to confirm):" 22 78 8 \
  "CORE" "Update Repos & Base Packages" ON \
  "ENV" "Setup Zsh, OMZ, and TPM" ON \
  "STOW" "Deploy dotfiles via Stow" ON \
  "DOCKER" "Docker Engine & Compose" OFF \
  "VPN" "Pull & Patch NordVPN Configs" OFF 3>&1 1>&2 2>&3)

if [ -z "$CHOICES" ]; then
  echo "Installation cancelled."
  exit 0
fi

# --- EXECUTION ---

if [[ $CHOICES == *"CORE"* ]]; then 
  update_repos_and_system
  install_base_packages
fi

if [[ $CHOICES == *"ENV"* ]]; then setup_zsh_and_tpm; fi
if [[ $CHOICES == *"DOCKER"* ]]; then install_docker_engine; fi
if [[ $CHOICES == *"VPN"* ]]; then setup_nordvpn_configs; fi
if [[ $CHOICES == *"STOW"* ]]; then deploy_stow_packages; fi

cleanup_system

echo -e "\nSetup complete."
if [[ $CHOICES == *"DOCKER"* ]]; then
  echo "Note: Log out and back in to apply Docker group permissions."
fi
if [[ $CHOICES == *"ENV"* ]] || [[ $CHOICES == *"STOW"* ]]; then
  echo "Restart your terminal or run 'exec zsh' to apply shell changes."
fi
