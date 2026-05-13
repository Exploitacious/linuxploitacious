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
    msg_warn "Running as root."
    echo
    echo "  This works on single-user / root-only systems (VMs, containers,"
    echo "  pen-testing rigs) but is NOT recommended on machines with regular"
    echo "  user accounts. As root, every package postinstall (pnpm/npm/curl|bash)"
    echo "  runs with full system privileges, and configs deploy to /root only."
    echo
    echo "  If your machine has a standard user, exit and re-run as that user."
    echo
    msg_info "Continuing in 10s. Press 'q' or 'n' (then Enter) to abort, any other key to continue now."

    local secs=10 reply=""
    while [ "$secs" -gt 0 ]; do
      printf "\r  [%2ds] continuing as root... " "$secs"
      if read -r -t 1 -n 1 reply 2>/dev/null; then
        echo
        case "$reply" in
          q|Q|n|N) msg_error "Aborted by user."; exit 1 ;;
          *) break ;;
        esac
      fi
      secs=$((secs - 1))
    done
    echo
    msg_success "Proceeding as root."
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
        sudo pacman -S --noconfirm --needed git
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
      read -p "Enter Git User Name: " GIT_NAME
      read -p "Enter Git Email: " GIT_EMAIL

      if [ -z "$GIT_NAME" ] || [ -z "$GIT_EMAIL" ]; then
        msg_warn "Git identity not set — you'll need to configure it before committing."
      else
        git config --global user.name "$GIT_NAME"
        git config --global user.email "$GIT_EMAIL"
        msg_success "Git identity set to $GIT_NAME <$GIT_EMAIL>"
      fi
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

  # --- AUTO-SYNC WITH UPSTREAM ---
  # Re-runs from inside an existing clone never hit the bootstrap pull above,
  # so they used to drift behind origin. Sync now if the tree is clean.
  if [ -d "$REPO_DIR/.git" ]; then
    cd "$REPO_DIR" || exit 1
    # Mark the repo safe even when invoked under an unexpected uid
    git config --global --add safe.directory "$REPO_DIR" 2>/dev/null || true

    if [ -n "$(git status --porcelain 2>/dev/null)" ]; then
      msg_warn "Working tree has uncommitted changes — skipping auto-pull."
      msg_warn "Commit/stash and re-run to sync with upstream."
    else
      msg_info "Syncing with upstream (git pull --ff-only)..."
      if git pull --ff-only 2>&1; then
        msg_success "Repository up to date."
      else
        msg_warn "Auto-pull failed (network, diverged history, or missing upstream). Continuing with local copy."
      fi
    fi
  fi

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
    if ! command -v whiptail &> /dev/null; then sudo pacman -S --noconfirm --needed libnewt; fi
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
            if ! grep -rq "zhangsongcui3336/fastfetch" /etc/apt/sources.list.d/ 2>/dev/null; then
                sudo add-apt-repository -y ppa:zhangsongcui3336/fastfetch 2>/dev/null && \
                  sudo apt-get update && sudo apt-get install -y fastfetch
            else
                sudo apt-get install -y fastfetch
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
    
    local ARCH_PKGS=(zsh stow git curl wget unzip tmux fzf fastfetch gnupg2 xclip ffmpeg nmap base-devel jq btop tree)
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
    
    # Use `sudo test` — /root isn't readable as the primary user, so a bare
    # `[ -d /root/... ]` always returns false and we end up trying to clone
    # into a populated dir, which fails non-idempotently.
    if ! sudo test -d "/root/.oh-my-zsh"; then
      msg_info "Installing Oh My Zsh for root..."
      sudo git clone https://github.com/ohmyzsh/ohmyzsh.git /root/.oh-my-zsh
    fi

    local ROOT_ZSH_CUSTOM="/root/.oh-my-zsh/custom"
    declare -A ROOT_OMZ_PLUGINS=(
      [zsh-autosuggestions]="https://github.com/zsh-users/zsh-autosuggestions"
      [zsh-syntax-highlighting]="https://github.com/zsh-users/zsh-syntax-highlighting"
      [zsh-completions]="https://github.com/zsh-users/zsh-completions"
      [fzf-tab]="https://github.com/Aloxaf/fzf-tab"
    )
    for plugin in "${!ROOT_OMZ_PLUGINS[@]}"; do
      if ! sudo test -d "$ROOT_ZSH_CUSTOM/plugins/$plugin"; then
        msg_info "Installing OMZ plugin for root: $plugin"
        sudo git clone --depth 1 "${ROOT_OMZ_PLUGINS[$plugin]}" "$ROOT_ZSH_CUSTOM/plugins/$plugin" -q
      fi
    done

    if ! sudo test -f "/root/.local/bin/oh-my-posh"; then
      msg_info "Installing Oh My Posh for root..."
      sudo mkdir -p /root/.local/bin
      sudo curl -s https://ohmyposh.dev/install.sh | sudo bash -s -- -d /root/.local/bin
    fi
    
    if ! sudo test -d "/root/.tmux/plugins/tpm"; then
      msg_info "Installing Tmux Plugin Manager for root..."
      sudo git clone https://github.com/tmux-plugins/tpm /root/.tmux/plugins/tpm
    fi
    
    # Ensure Nerd Fonts are available for root's OMP themes
    install_nerd_fonts

    msg_info "Deploying configs to /root via stow..."
    cd "$REPO_DIR" || exit 1

    # NOTE: claude/ is excluded — ROOT shares ~/.claude via symlink (AI_DIRS block below)
    local PACKAGES=("fastfetch" "omp" "rustscan" "scripts" "tmux" "zsh" "bash" "btop")
    local TS_ROOT
    TS_ROOT="$(date +%Y%m%d_%H%M%S)"
    for pkg in "${PACKAGES[@]}"; do
      if [ -d "$pkg" ]; then
        # Phase 1: drop any prior stow links
        sudo stow -D -t /root "$pkg" 2>/dev/null || true

        # Phase 2/3: back up real files in /root that would conflict with stow.
        # /root/.bashrc ships as a real file from skel; without this, stow aborts.
        while IFS= read -r src_file; do
          local rel_path="${src_file#$pkg/}"
          local dest_file="/root/$rel_path"
          if sudo test -e "$dest_file" && ! sudo test -L "$dest_file"; then
            local backup_file="${dest_file}.backup_${TS_ROOT}"
            msg_warn "Backing up /root real file: $dest_file -> $backup_file"
            sudo mv "$dest_file" "$backup_file"
          fi
        done < <(find "$pkg" -type f)

        # Phase 4: ensure parent dirs exist (skip pkg-root)
        while IFS= read -r src_dir; do
          local rel_path="${src_dir#$pkg/}"
          [ -n "$rel_path" ] && sudo mkdir -p "/root/$rel_path"
        done < <(find "$pkg" -mindepth 1 -type d)

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

    local AI_DIRS=(".claude" ".local/share/opencode")
    local AI_FILES=(".claude.json")

    # Install Node/pnpm and AI CLIs for root BEFORE symlinking AI_DIRS.
    # Installers may stat/clobber their own config dirs; doing this first keeps
    # them away from the user's live state, and the AI_DIRS merge step below
    # will fold any data they wrote into the primary user's home.
    if ! sudo test -d "/root/.nvm"; then
      msg_info "Installing NVM for root..."
      sudo -i bash -c 'curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.4/install.sh | bash'
    fi

    msg_info "Installing Node.js and pnpm for root..."
    sudo -i bash << 'ROOTNVM'
export NVM_DIR="/root/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
nvm install --lts
nvm use --lts
corepack enable pnpm
ROOTNVM

    if ! sudo test -d "/root/.pyenv"; then
      msg_info "Installing pyenv for root..."
      sudo -i bash -c 'curl -fsSL https://pyenv.run | bash'
    else
      msg_info "pyenv already installed for root; skipping."
    fi

    msg_info "Installing Python for root..."
    sudo -i bash << 'ROOTPY'
export PYENV_ROOT="/root/.pyenv"
export PATH="$PYENV_ROOT/bin:$PATH"
eval "$(pyenv init -)"
LATEST_PY=$(pyenv install --list | grep -E '^\s+3\.[0-9]+\.[0-9]+$' | tail -1 | tr -d ' ')
if ! pyenv versions --bare | grep -qF "$LATEST_PY"; then
  pyenv install "$LATEST_PY"
fi
pyenv global "$LATEST_PY"
# pip-as-root is fine inside a pyenv prefix (per-version, not system-wide);
# silence the standard warning.
pip install --upgrade --root-user-action ignore pip setuptools wheel
ROOTPY

    msg_info "Installing AI CLIs for root (Claude Code, OpenCode)..."
    sudo -i bash << 'ROOTAI'
export NVM_DIR="/root/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
export PNPM_HOME="/root/.local/share/pnpm"
# Prepend ~/.local/bin so the Claude installer's post-install PATH check passes
# (it warns when its install dir is missing from PATH).
export PATH="$HOME/.local/bin:$PNPM_HOME:$PATH"

if command -v pnpm &> /dev/null; then
  pnpm remove -g @anthropic-ai/claude-code opencode-ai @google/gemini-cli >/dev/null 2>&1 || true
fi
if command -v npm &> /dev/null; then
  npm uninstall -g @anthropic-ai/claude-code opencode-ai @google/gemini-cli >/dev/null 2>&1 || true
fi
for shim in /root/.local/share/pnpm/claude /root/.local/share/pnpm/opencode /root/.local/share/pnpm/gemini; do
  if [ -e "$shim" ] || [ -L "$shim" ]; then
    rm -f "$shim"
  fi
done
if [ -d /root/.nvm/versions/node ]; then
  find /root/.nvm/versions/node -maxdepth 3 \( -name claude -o -name opencode -o -name gemini \) -delete 2>/dev/null || true
fi

curl -fsSL https://claude.ai/install.sh | bash
curl -fsSL https://opencode.ai/install | bash
ROOTAI

    if [ -L /root/.gemini ] || [ -e /root/.gemini ]; then
      msg_warn "Removing deprecated /root/.gemini..."
      sudo rm -rf /root/.gemini
    fi

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

    msg_success "Root profile setup complete. Run 'sudo -i' to use."
  }

  setup_swapfile() {
    msg_header "Setting up Swapfile"

    if [ -n "$(swapon --show=NAME --noheadings 2>/dev/null)" ]; then
      msg_info "Swap already active:"
      swapon --show
      return 0
    fi

    # Size = round(RAM in GB), min 2, max 32
    local RAM_GB
    RAM_GB=$(awk '/MemTotal/ {printf "%d", ($2/1024/1024)+0.5}' /proc/meminfo)
    [ "$RAM_GB" -lt 2 ] && RAM_GB=2
    [ "$RAM_GB" -gt 32 ] && RAM_GB=32

    local SWAPFILE=/swapfile
    if sudo test -e "$SWAPFILE"; then
      msg_warn "$SWAPFILE exists but is not active. Investigate manually; not touching it."
      return 1
    fi

    # Check free space — need RAM_GB + 1GB headroom on /
    local FREE_GB
    FREE_GB=$(df -BG --output=avail / | tail -1 | tr -dc '0-9')
    if [ "$FREE_GB" -lt $((RAM_GB + 1)) ]; then
      msg_error "Not enough free space on / (need ${RAM_GB}G + 1G headroom, have ${FREE_GB}G). Skipping."
      return 1
    fi

    # Detect FS type — btrfs needs special handling (chattr +C, no holes)
    local FS_TYPE
    FS_TYPE=$(df -T / | awk 'NR==2 {print $2}')
    if [ "$FS_TYPE" = "btrfs" ]; then
      msg_warn "Root is btrfs — fallocate creates holes; using btrfs-safe path."
      sudo touch "$SWAPFILE"
      sudo chattr +C "$SWAPFILE" 2>/dev/null || true
      sudo dd if=/dev/zero of="$SWAPFILE" bs=1M count=$((RAM_GB*1024)) status=progress
    else
      msg_info "Allocating ${RAM_GB}G swapfile at $SWAPFILE (fs: $FS_TYPE)..."
      if ! sudo fallocate -l "${RAM_GB}G" "$SWAPFILE" 2>/dev/null; then
        msg_warn "fallocate failed, falling back to dd..."
        sudo dd if=/dev/zero of="$SWAPFILE" bs=1M count=$((RAM_GB*1024)) status=progress
      fi
    fi

    sudo chmod 600 "$SWAPFILE"
    sudo mkswap "$SWAPFILE"
    sudo swapon "$SWAPFILE"

    if ! grep -qE "^${SWAPFILE}[[:space:]]" /etc/fstab; then
      echo "${SWAPFILE} none swap sw 0 0" | sudo tee -a /etc/fstab > /dev/null
      msg_success "Added swapfile entry to /etc/fstab."
    fi

    # Tune swappiness — low so swap is emergency-only on a workstation/VM
    if [ ! -f /etc/sysctl.d/99-swappiness.conf ]; then
      echo 'vm.swappiness=10' | sudo tee /etc/sysctl.d/99-swappiness.conf > /dev/null
      sudo sysctl -q --system
      msg_success "vm.swappiness=10 (swap reserved for memory pressure)."
    fi

    msg_success "Swap active: $(swapon --show=NAME,SIZE --noheadings | head -1)"
  }

  install_docker() {
    msg_header "Installing Docker Engine"

    if command -v docker &> /dev/null && docker --version &> /dev/null; then
      msg_info "Docker already installed: $(docker --version)"
    else
      if [[ "$OS_ID" == "debian" || "$OS_ID" == "ubuntu" || "$OS_ID" == "kali" || "$OS_LIKE" == *"debian"* ]]; then
        msg_info "Installing Docker via official APT repo..."
        sudo apt-get update
        sudo apt-get install -y ca-certificates curl gnupg
        sudo install -m 0755 -d /etc/apt/keyrings

        # Kali ships with Debian-derived sources; force docker repo to match Debian codename
        local DOCKER_CODENAME="$VERSION_CODENAME"
        if [[ "$OS_ID" == "kali" ]] || [ -z "$DOCKER_CODENAME" ]; then
          DOCKER_CODENAME="bookworm"
        fi
        local DOCKER_OS="debian"
        if [[ "$OS_ID" == "ubuntu" ]]; then DOCKER_OS="ubuntu"; fi

        curl -fsSL "https://download.docker.com/linux/${DOCKER_OS}/gpg" | \
          sudo gpg --dearmor --yes -o /etc/apt/keyrings/docker.gpg
        sudo chmod a+r /etc/apt/keyrings/docker.gpg

        echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/${DOCKER_OS} ${DOCKER_CODENAME} stable" | \
          sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

        sudo apt-get update
        sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
      elif [[ "$OS_ID" == "arch" || "$OS_LIKE" == *"arch"* ]]; then
        sudo pacman -S --noconfirm --needed docker docker-compose
      elif [[ "$OS_ID" == "fedora" || "$OS_LIKE" == *"fedora"* ]]; then
        sudo dnf -y install dnf-plugins-core
        sudo dnf config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo
        sudo dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
      else
        msg_error "Unsupported OS for Docker auto-install."
        return 1
      fi
      msg_success "Docker installed: $(docker --version)"
    fi

    # Enable + start daemon
    if command -v systemctl &> /dev/null; then
      sudo systemctl enable --now docker.service containerd.service 2>/dev/null || true
    fi

    # Add current user to docker group (skip if root)
    if [ "$EUID" -ne 0 ]; then
      local TARGET_USER="${SUDO_USER:-$USER}"
      if ! id -nG "$TARGET_USER" | tr ' ' '\n' | grep -qx docker; then
        sudo usermod -aG docker "$TARGET_USER"
        msg_warn "Added $TARGET_USER to 'docker' group. Log out + back in (or 'newgrp docker') for it to take effect."
      else
        msg_info "$TARGET_USER already in docker group."
      fi
    fi

    # Smoke test (won't fail script if daemon isn't ready yet)
    if sudo docker run --rm hello-world &> /dev/null; then
      msg_success "Docker smoke test passed."
    else
      msg_warn "Docker smoke test skipped or failed — daemon may need a moment."
    fi
  }

  setup_tmux_persistence() {
    msg_header "Setting up Tmux Persistence (auto-attach + systemd boot)"

    if ! command -v tmux &> /dev/null; then
      msg_info "Installing tmux..."
      if [[ "$OS_ID" == "debian" || "$OS_ID" == "ubuntu" || "$OS_ID" == "kali" || "$OS_LIKE" == *"debian"* ]]; then
        sudo apt-get install -y tmux
      elif [[ "$OS_ID" == "arch" || "$OS_LIKE" == *"arch"* ]]; then
        sudo pacman -S --noconfirm --needed tmux
      elif [[ "$OS_ID" == "fedora" || "$OS_LIKE" == *"fedora"* ]]; then
        sudo dnf install -y tmux
      fi
    fi

    # The .zshrc/.bashrc shipped by this repo already contains the SSH auto-attach snippet,
    # so re-stow is enough to wire it up. Just inform the user.
    msg_info "SSH auto-attach snippet ships in stowed .zshrc/.bashrc (deploys via STOW step)."

    if [ "$EUID" -eq 0 ]; then
      msg_warn "Running as root — skipping systemd --user unit setup."
      return 0
    fi

    # systemd user unit so the 'main' session survives reboots
    local UNIT_DIR="$HOME/.config/systemd/user"
    local UNIT_FILE="$UNIT_DIR/tmux-main.service"
    mkdir -p "$UNIT_DIR"

    local TMUX_BIN
    TMUX_BIN="$(command -v tmux)"

    cat > "$UNIT_FILE" <<EOF
[Unit]
Description=tmux default session (main)
Documentation=man:tmux(1)
After=network.target

[Service]
Type=forking
ExecStart=${TMUX_BIN} new-session -d -s main
ExecStop=${TMUX_BIN} kill-session -t main
KillMode=none
Restart=on-failure

[Install]
WantedBy=default.target
EOF

    msg_success "Wrote $UNIT_FILE"

    systemctl --user daemon-reload
    systemctl --user enable --now tmux-main.service && \
      msg_success "tmux-main.service enabled + started" || \
      msg_warn "Failed to enable tmux-main.service (check 'systemctl --user status tmux-main')"

    # Enable linger so user services run without an active login (survive reboots)
    local TARGET_USER="${SUDO_USER:-$USER}"
    if loginctl show-user "$TARGET_USER" 2>/dev/null | grep -q "Linger=yes"; then
      msg_info "Linger already enabled for $TARGET_USER."
    else
      sudo loginctl enable-linger "$TARGET_USER" && \
        msg_success "Linger enabled for $TARGET_USER (user services run at boot)." || \
        msg_warn "Failed to enable linger."
    fi

    msg_info "Usage:"
    echo "  SSH login:     session picker shows on connect (attach existing / new / plain shell)"
    echo "  Detach:        Ctrl-a d               (keeps session alive — prefix is Ctrl-a)"
    echo "  Switch:        Ctrl-a s               (visual session picker inside tmux)"
    echo "  List:          tmux ls"
    echo "  Attach:        tmux a -t <name>"
    echo "  New session:   tmux new -s <name>"
    echo "  Kill session:  tmux kill-session -t <name>"
  }

  configure_passwordless_sudo() {
    msg_header "Configuring Passwordless Sudo"

    if [ "$EUID" -eq 0 ]; then
      msg_warn "Running as root — passwordless sudo not applicable. Skipping."
      return 0
    fi

    if ! command -v sudo &> /dev/null; then
      msg_error "sudo not installed. Skipping."
      return 1
    fi

    local TARGET_USER="${SUDO_USER:-$USER}"
    local SUDOERS_FILE="/etc/sudoers.d/90-${TARGET_USER}-nopasswd"
    local SUDOERS_LINE="${TARGET_USER} ALL=(ALL:ALL) NOPASSWD:ALL"

    if sudo test -f "$SUDOERS_FILE" && sudo grep -qxF "$SUDOERS_LINE" "$SUDOERS_FILE"; then
      msg_info "Passwordless sudo already configured for ${TARGET_USER}."
      return 0
    fi

    msg_warn "About to grant ${TARGET_USER} passwordless sudo (NOPASSWD: ALL)."
    msg_warn "This means anyone with shell access as ${TARGET_USER} gets full root."
    echo -ne "${YELLOW}Proceed? [y/N]: ${NC}"
    read -r REPLY
    if [[ ! "$REPLY" =~ ^[Yy]$ ]]; then
      msg_info "Skipping passwordless sudo."
      return 0
    fi

    # Write via a tmpfile + visudo -cf so we never install a broken sudoers entry
    local TMP_SUDOERS
    TMP_SUDOERS="$(mktemp)"
    printf '%s\n' "$SUDOERS_LINE" > "$TMP_SUDOERS"

    if sudo visudo -cf "$TMP_SUDOERS" > /dev/null; then
      sudo install -m 0440 -o root -g root "$TMP_SUDOERS" "$SUDOERS_FILE"
      rm -f "$TMP_SUDOERS"
      msg_success "Passwordless sudo enabled for ${TARGET_USER} (${SUDOERS_FILE})."
    else
      rm -f "$TMP_SUDOERS"
      msg_error "visudo validation failed. Sudoers not modified."
      return 1
    fi
  }

  install_github_cli() {
    msg_header "Installing GitHub CLI"

    if command -v gh &> /dev/null; then
      msg_info "GitHub CLI already installed: $(gh --version | head -1)"
      return 0
    fi

    if [[ "$OS_ID" == "debian" || "$OS_ID" == "ubuntu" || "$OS_ID" == "kali" || "$OS_LIKE" == *"debian"* ]]; then
      msg_info "Adding GitHub CLI repository..."
      sudo mkdir -p -m 755 /etc/apt/keyrings
      wget -qO- https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg > /dev/null
      sudo chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg
      echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
      sudo apt-get update
      sudo apt-get install -y gh
    elif [[ "$OS_ID" == "arch" || "$OS_LIKE" == *"arch"* ]]; then
      sudo pacman -S --noconfirm --needed github-cli
    elif [[ "$OS_ID" == "fedora" || "$OS_LIKE" == *"fedora"* ]]; then
      sudo dnf install -y gh
    else
      msg_error "Unsupported OS for GitHub CLI auto-install"
      return 1
    fi

    if command -v gh &> /dev/null; then
      msg_success "GitHub CLI installed: $(gh --version | head -1)"
    else
      msg_error "GitHub CLI installation failed"
      return 1
    fi
  }

  setup_github_ssh() {
    msg_header "Setting up GitHub SSH Key"
    
    local SSH_KEY="$HOME/.ssh/id_ed25519"
    local GIT_EMAIL=$(git config --global user.email 2>/dev/null)
    GIT_EMAIL=${GIT_EMAIL:-"email@example.com"}
    local NEED_KEY_UPLOAD=true

    if [ -f "$SSH_KEY" ]; then
      msg_info "SSH key already exists at $SSH_KEY"
      echo -ne "${YELLOW}Is this key already added to your GitHub account? [y/N]: ${NC}"
      read -r REPLY
      if [[ "$REPLY" =~ ^[Yy]$ ]]; then
        NEED_KEY_UPLOAD=false
        msg_info "Skipping SSH key upload"
      fi
    else
      msg_info "Generating new ed25519 SSH key..."
      mkdir -p "$HOME/.ssh"
      ssh-keygen -t ed25519 -C "$GIT_EMAIL" -f "$SSH_KEY" -N ""
      msg_success "SSH key generated"
    fi
    
    msg_info "Configuring SSH for GitHub..."
    mkdir -p "$HOME/.ssh"
    if ! grep -q "Host \*" "$HOME/.ssh/config" 2>/dev/null; then
      cat >> "$HOME/.ssh/config" << 'EOF'

Host *
    AddKeysToAgent yes
    ServerAliveInterval 60
    ServerAliveCountMax 3
EOF
      msg_success "SSH global defaults added"
    fi
    if ! grep -q "Host github.com" "$HOME/.ssh/config" 2>/dev/null; then
      cat >> "$HOME/.ssh/config" << 'EOF'

Host github.com
    HostName github.com
    User git
    IdentityFile ~/.ssh/id_ed25519
    IdentitiesOnly yes

Host ssh.github.com
    HostName ssh.github.com
    Port 443
    User git
    IdentityFile ~/.ssh/id_ed25519
    IdentitiesOnly yes
EOF
      msg_success "GitHub SSH host configured"
    else
      msg_info "GitHub host already configured in SSH config"
    fi
    chmod 600 "$HOME/.ssh/config"
    
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
    
    if ! sudo grep -q "Host \*" /root/.ssh/config 2>/dev/null; then
      sudo tee -a /root/.ssh/config > /dev/null << 'EOF'

Host *
    AddKeysToAgent yes
    ServerAliveInterval 60
    ServerAliveCountMax 3
EOF
    fi
    if ! sudo grep -q "Host github.com" /root/.ssh/config 2>/dev/null; then
      sudo tee -a /root/.ssh/config > /dev/null << 'EOF'

Host github.com
    HostName github.com
    User git
    IdentityFile ~/.ssh/id_ed25519
    IdentitiesOnly yes

Host ssh.github.com
    HostName ssh.github.com
    Port 443
    User git
    IdentityFile ~/.ssh/id_ed25519
    IdentitiesOnly yes
EOF
    fi
    sudo chmod 600 /root/.ssh/config
    msg_success "SSH key and config copied to /root/.ssh/"
    
    # Install and configure GitHub CLI
    install_github_cli

    local GH_AUTHENTICATED=false
    if command -v gh &> /dev/null; then
      if gh auth status &> /dev/null; then
        msg_info "GitHub CLI already authenticated"
        GH_AUTHENTICATED=true
      else
        echo ""
        msg_warn "A browser will open (or you'll get a device code for github.com/login/device)"
        echo ""
        if gh auth login -p ssh -h github.com; then
          msg_success "GitHub CLI authenticated"
          gh config set git_protocol ssh -h github.com
          GH_AUTHENTICATED=true
        else
          msg_warn "Auth skipped. Run later: gh auth login"
        fi
      fi

      # Upload SSH key if authenticated and needed
      if $GH_AUTHENTICATED && $NEED_KEY_UPLOAD && [ -f "$SSH_KEY.pub" ]; then
        local KEY_TITLE="$(hostname)-$(date +%Y%m%d)"
        msg_info "Uploading SSH key to GitHub as '$KEY_TITLE'..."
        if gh ssh-key add "$SSH_KEY.pub" -t "$KEY_TITLE" 2>/dev/null; then
          msg_success "SSH key uploaded to GitHub"
        else
          msg_warn "SSH key may already exist on GitHub (OK)"
        fi
      fi
    fi

    # Fallback: show key for manual upload if gh auth unavailable and upload needed
    if ! $GH_AUTHENTICATED && $NEED_KEY_UPLOAD; then
      SSH_PUBLIC_KEY=$(cat "$SSH_KEY.pub")
      echo ""
      echo -e "${CYAN}=== GitHub SSH Key ===${NC}"
      echo -e "${YELLOW}Upload this public key to:${NC} https://github.com/settings/keys"
      echo ""
      echo -e "${GREEN}$SSH_PUBLIC_KEY${NC}"
      echo ""
    fi
    echo -e "${YELLOW}Test connection with:${NC} ssh -T git@github.com"
    echo ""
  }

  install_node_env() {
    msg_header "Installing Node.js Environment (NVM, Node LTS, pnpm)"
    
    # Clean up conflicting npm config
    if [ -f "$HOME/.npmrc" ]; then
        msg_warn "Backing up existing .npmrc to .npmrc.bak (incompatible with NVM)"
        mv "$HOME/.npmrc" "$HOME/.npmrc.bak"
    fi

    # Install NVM
    msg_info "Installing NVM..."
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.4/install.sh | bash
    
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

    msg_success "Node environment ready."
  }

  # --- PYTHON ENVIRONMENT (pyenv, Python latest, common pip packages) ---

  install_python_env() {
    msg_header "Installing Python Environment (pyenv, Python, pip packages)"

    # Install pyenv build dependencies (OS-specific)
    msg_info "Installing pyenv build dependencies..."
    if [[ "$OS_ID" == "debian" || "$OS_ID" == "ubuntu" || "$OS_ID" == "kali" || "$OS_LIKE" == *"debian"* ]]; then
      sudo apt-get install -y make build-essential libssl-dev zlib1g-dev \
        libbz2-dev libreadline-dev libsqlite3-dev llvm libncursesw5-dev \
        xz-utils tk-dev libxml2-dev libxmlsec1-dev libffi-dev liblzma-dev
    elif [[ "$OS_ID" == "arch" || "$OS_LIKE" == *"arch"* ]]; then
      sudo pacman -S --noconfirm --needed base-devel openssl zlib bzip2 \
        readline sqlite llvm ncurses xz tk libxml2 xmlsec libffi
    elif [[ "$OS_ID" == "fedora" || "$OS_LIKE" == *"fedora"* ]]; then
      sudo dnf install -y make gcc zlib-devel bzip2 bzip2-devel \
        readline-devel sqlite sqlite-devel openssl-devel tk-devel \
        libffi-devel xz-devel libuuid-devel gdbm-libs
    fi

    # Install pyenv via official installer
    if [ -d "$HOME/.pyenv" ]; then
      msg_info "pyenv already installed; updating..."
      cd "$HOME/.pyenv" && git pull -q && cd "$REPO_DIR"
    else
      msg_info "Installing pyenv..."
      curl -fsSL https://pyenv.run | bash
    fi

    # Load pyenv for current session
    export PYENV_ROOT="$HOME/.pyenv"
    export PATH="$PYENV_ROOT/bin:$PATH"
    eval "$(pyenv init -)"
    eval "$(pyenv virtualenv-init -)" 2>/dev/null || true

    # Install latest stable Python 3
    local LATEST_PY
    LATEST_PY=$(pyenv install --list | grep -E '^\s+3\.[0-9]+\.[0-9]+$' | tail -1 | tr -d ' ')
    if pyenv versions --bare | grep -qF "$LATEST_PY"; then
      msg_info "Python $LATEST_PY already installed"
    else
      msg_info "Installing Python $LATEST_PY (this takes a few minutes)..."
      pyenv install "$LATEST_PY"
    fi
    pyenv global "$LATEST_PY"

    # Upgrade pip, setuptools, wheel
    msg_info "Upgrading pip, setuptools, wheel..."
    pip install --upgrade pip setuptools wheel

    # Minimal globals: tools you want available everywhere. Project libraries
    # belong in per-project virtualenvs (poetry/uv/pyenv-virtualenv) — not here.
    msg_info "Installing core Python tools (lint/format/test/env management)..."
    pip install --upgrade \
      pipx \
      poetry \
      virtualenv \
      pre-commit \
      black \
      ruff \
      mypy \
      isort \
      pytest \
      pytest-cov \
      pytest-asyncio \
      ipython \
      requests \
      httpx \
      rich \
      typer \
      click \
      python-dotenv \
      pyyaml

    # Heavier optional groups via pipx (isolated, on-demand). Only the CLI
    # tools — libraries still belong in project venvs.
    msg_info "Installing CLI apps via pipx (isolated)..."
    pipx ensurepath >/dev/null 2>&1 || true
    for app in jupyter pylint; do
      if ! pipx list --short 2>/dev/null | grep -q "^$app "; then
        pipx install "$app" 2>&1 | tail -1
      fi
    done

    # Optional bundles — opt-in via whiptail. Each one installs into the
    # global pyenv. Project work should still use venvs; these are for ad-hoc
    # REPL / scratch use.
    if command -v whiptail >/dev/null 2>&1; then
      local PY_CHOICES
      PY_CHOICES=$(whiptail --title "Optional Python Package Bundles" --checklist \
        "Pick global bundles to install (cancel to skip — recommended)." 18 78 6 \
        "DATA"    "numpy, pandas, matplotlib, seaborn, scipy, scikit-learn, pillow" OFF \
        "WEB"     "flask, fastapi, uvicorn, django, jinja2, gunicorn, pydantic" OFF \
        "DB"      "sqlalchemy, alembic, psycopg2-binary, pymongo, redis, celery" OFF \
        "SCRAPE"  "beautifulsoup4, lxml, scrapy, selenium" OFF \
        "CLOUD"   "boto3, google-cloud-storage, azure-identity, docker, kubernetes, ansible-core" OFF \
        "CRYPTO"  "cryptography, pyopenssl, bcrypt, passlib, pyjwt, paramiko, fabric" OFF \
        3>&1 1>&2 2>&3) || PY_CHOICES=""

      if [[ "$PY_CHOICES" == *"DATA"* ]]; then
        msg_info "Installing DATA bundle..."
        pip install --upgrade numpy pandas matplotlib seaborn scipy scikit-learn pillow
      fi
      if [[ "$PY_CHOICES" == *"WEB"* ]]; then
        msg_info "Installing WEB bundle..."
        pip install --upgrade flask fastapi uvicorn django jinja2 gunicorn pydantic python-multipart websockets
      fi
      if [[ "$PY_CHOICES" == *"DB"* ]]; then
        msg_info "Installing DB bundle..."
        pip install --upgrade sqlalchemy alembic psycopg2-binary pymongo redis celery pika
      fi
      if [[ "$PY_CHOICES" == *"SCRAPE"* ]]; then
        msg_info "Installing SCRAPE bundle..."
        pip install --upgrade beautifulsoup4 lxml scrapy selenium
      fi
      if [[ "$PY_CHOICES" == *"CLOUD"* ]]; then
        msg_info "Installing CLOUD bundle..."
        pip install --upgrade boto3 google-cloud-storage azure-identity docker kubernetes ansible-core
      fi
      if [[ "$PY_CHOICES" == *"CRYPTO"* ]]; then
        msg_info "Installing CRYPTO bundle..."
        pip install --upgrade cryptography pyopenssl bcrypt passlib pyjwt paramiko fabric
      fi
    fi

    msg_success "Python environment ready: $(python --version), pip $(pip --version | awk '{print $2}')"
  }

  # --- AI CLI TOOLS (Claude Code, OpenCode) via official vendor installers ---
  # Runs unconditionally — installers are fast and self-updating. Handles legacy
  # pnpm/npm/nvm shim cleanup so old versions don't shadow the native binaries.

  install_ai_tools() {
    msg_header "Installing AI CLIs (Claude Code, OpenCode)"

    # Silent cleanup — pnpm/npm print ERR_PNPM_CANNOT_REMOVE_MISSING_DEPS on stderr
    # before returning non-zero when the packages aren't installed. Suppress both.
    if command -v pnpm &> /dev/null; then
      pnpm remove -g @anthropic-ai/claude-code opencode-ai @google/gemini-cli >/dev/null 2>&1 || true
    fi
    if command -v npm &> /dev/null; then
      npm uninstall -g @anthropic-ai/claude-code opencode-ai @google/gemini-cli >/dev/null 2>&1 || true
    fi

    local pnpm_home="${PNPM_HOME:-$HOME/.local/share/pnpm}"
    for shim in claude opencode gemini; do
      if [ -e "$pnpm_home/$shim" ] || [ -L "$pnpm_home/$shim" ]; then
        rm -f "$pnpm_home/$shim"
      fi
    done

    if [ -d "$HOME/.nvm/versions/node" ]; then
      find "$HOME/.nvm/versions/node" -maxdepth 3 \( -name claude -o -name opencode -o -name gemini \) -delete 2>/dev/null || true
    fi

    if command -v npm &> /dev/null; then
      local npm_prefix
      npm_prefix="$(npm config get prefix 2>/dev/null)"
      if [ -n "$npm_prefix" ] && [ -d "$npm_prefix/bin" ]; then
        for shim in claude opencode gemini; do
          if [ -e "$npm_prefix/bin/$shim" ] || [ -L "$npm_prefix/bin/$shim" ]; then
            rm -f "$npm_prefix/bin/$shim"
          fi
        done
      fi
    fi

    if [ -e "$HOME/.gemini" ] || [ -L "$HOME/.gemini" ]; then
      msg_warn "Removing deprecated ~/.gemini..."
      rm -rf "$HOME/.gemini"
    fi

    if [ -x "$HOME/.local/bin/claude" ]; then
      msg_info "Claude Code already present; refreshing via installer..."
    else
      msg_info "Installing Claude Code..."
    fi
    curl -fsSL https://claude.ai/install.sh | bash

    if [ -x "$HOME/.opencode/bin/opencode" ]; then
      msg_info "OpenCode already present; refreshing via installer..."
    else
      msg_info "Installing OpenCode..."
    fi
    curl -fsSL https://opencode.ai/install | bash

    export PATH="$HOME/.local/bin:$HOME/.opencode/bin:$PATH"

    msg_success "AI CLIs installed: $(command -v claude 2>/dev/null || echo claude-missing), $(command -v opencode 2>/dev/null || echo opencode-missing)"
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

    local ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"

    # OMZ custom plugins (third-party — git/sudo/docker/etc. are builtins, no clone needed)
    declare -A OMZ_PLUGINS=(
      [zsh-autosuggestions]="https://github.com/zsh-users/zsh-autosuggestions"
      [zsh-syntax-highlighting]="https://github.com/zsh-users/zsh-syntax-highlighting"
      [zsh-completions]="https://github.com/zsh-users/zsh-completions"
      [fzf-tab]="https://github.com/Aloxaf/fzf-tab"
    )
    for plugin in "${!OMZ_PLUGINS[@]}"; do
      if [ ! -d "$ZSH_CUSTOM/plugins/$plugin" ]; then
        msg_info "Installing OMZ plugin: $plugin"
        git clone --depth 1 "${OMZ_PLUGINS[$plugin]}" "$ZSH_CUSTOM/plugins/$plugin" -q
      fi
    done

    if ! command -v oh-my-posh &> /dev/null; then
      msg_info "Installing Oh My Posh..."
      mkdir -p "$HOME/.local/bin"
      curl -s https://ohmyposh.dev/install.sh | bash -s -- -d "$HOME/.local/bin"
      export PATH=$PATH:$HOME/.local/bin
    fi

    # Ensure catppuccin_mocha theme cached locally (OMP init falls back here if repo copy missing)
    local OMP_CACHE_DIR="$HOME/.cache/oh-my-posh/themes"
    mkdir -p "$OMP_CACHE_DIR"
    if [ ! -f "$OMP_CACHE_DIR/catppuccin_mocha.omp.json" ]; then
      msg_info "Downloading catppuccin_mocha OMP theme..."
      curl -fsSL https://raw.githubusercontent.com/JanDeDobbeleer/oh-my-posh/main/themes/catppuccin_mocha.omp.json \
        -o "$OMP_CACHE_DIR/catppuccin_mocha.omp.json" || msg_warn "Theme download failed (will fall back to stowed copy)."
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

    # -mindepth 1 skips the package root; otherwise the first find entry equals
    # $pkg_dir exactly, the "${src_dir#$pkg_dir/}" prefix strip (with trailing /)
    # leaves it unchanged, and mkdir -p "$HOME/$abs_path" creates a phantom tree.
    find "$pkg_dir" -mindepth 1 -type d | while read -r src_dir; do
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

    # NOTE: claude/ is excluded from stow — uses absolute symlinks instead (see deploy_claude_config)
    # Stow's relative symlinks break through chained symlinks (user -> root sharing via AI_DIRS)
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

  # --- CLAUDE CODE CONFIG (absolute symlinks — stow's relative links break through chained symlinks) ---

  deploy_claude_config() {
    msg_header "Deploying Claude Code Config"
    local CLAUDE_DIR="$HOME/.claude"
    local SOURCE_DIR="$REPO_DIR/claude/.claude"

    if [ ! -d "$SOURCE_DIR" ]; then
      msg_warn "claude/.claude/ not found in repo. Skipping."
      return
    fi

    mkdir -p "$CLAUDE_DIR"

    for file in "$SOURCE_DIR"/*; do
      local filename
      filename="$(basename "$file")"
      local target="$CLAUDE_DIR/$filename"
      local source="$SOURCE_DIR/$filename"

      if [ -L "$target" ] && [ "$(readlink -f "$target")" = "$(readlink -f "$source")" ]; then
        msg_info "Already linked: $target"
        continue
      fi

      # Backup existing real files (not symlinks)
      if [ -f "$target" ] && [ ! -L "$target" ]; then
        local backup="${target}.backup_$(date +%Y%m%d_%H%M%S)"
        mv "$target" "$backup"
        msg_warn "Backed up existing $filename to $backup"
      fi

      # Remove stale symlink if present
      [ -L "$target" ] && rm "$target"

      ln -s "$source" "$target"
      msg_success "Linked: $target -> $source"
    done
  }

  # --- CLAUDE CODE PLUGINS (runs after config so settings.json exists) ---

  install_claude_plugins() {
    if ! command -v claude &> /dev/null; then
      msg_warn "Claude CLI not found in PATH. Skipping plugin install."
      return
    fi

    msg_header "Installing Claude Code Plugins"

    msg_info "Registering caveman plugin marketplace..."
    if claude plugin marketplace add JuliusBrussee/caveman; then
      msg_success "Marketplace registered."
      msg_info "Installing caveman plugin..."
      if claude plugin install caveman@caveman; then
        msg_success "Caveman plugin installed."
      else
        msg_warn "Caveman plugin install failed. Run manually: claude plugin install caveman@caveman"
      fi
    else
      msg_warn "Marketplace registration failed. Run manually: claude plugin marketplace add JuliusBrussee/caveman"
    fi
  }

  # --- COWORK + AGENT COORDINATION (private repo; needs gh auth from SSHKEY first) ---

  setup_cowork() {
    msg_header "Deploying COWORK (Multi-Agent Coordination)"

    local COWORK_DIR="$HOME/COWORK"

    if ! command -v gh &> /dev/null; then
      msg_warn "gh CLI not installed. Enable SSHKEY first. Skipping COWORK."
      return
    fi
    if ! gh auth status &> /dev/null; then
      msg_warn "gh CLI not authenticated. Re-run with SSHKEY enabled. Skipping COWORK."
      return
    fi

    if [ ! -d "$COWORK_DIR/.git" ]; then
      msg_info "Cloning Exploitacious/COWORK to $COWORK_DIR..."
      if gh repo clone Exploitacious/COWORK "$COWORK_DIR"; then
        msg_success "COWORK cloned."
      else
        msg_error "COWORK clone failed. Verify gh auth covers private repos."
        return
      fi
    else
      # Idempotent sync — handles dirty working trees by stashing local edits
      # with a labeled timestamp, pulling, then attempting to restore.
      # If restore conflicts, the stash stays in `git stash list` for manual
      # recovery and setup continues. Never destroys local work silently.
      msg_info "COWORK already cloned; syncing..."
      (
        cd "$COWORK_DIR" || exit 1

        local stash_label=""
        # Detect modified-tracked OR staged-but-uncommitted changes.
        if ! git diff --quiet HEAD 2>/dev/null || ! git diff --cached --quiet 2>/dev/null; then
          stash_label="setup-auto-$(date -u +%Y-%m-%dT%H-%M-%SZ)"
          msg_info "Uncommitted changes detected — stashing as '$stash_label'..."
          if ! git stash push -m "$stash_label" >/dev/null 2>&1; then
            msg_warn "git stash failed. Skipping sync. Inspect: cd $COWORK_DIR && git status"
            exit 1
          fi
        fi

        if git pull --ff-only 2>/dev/null; then
          msg_success "COWORK synced to origin."
        else
          msg_warn "git pull --ff-only failed (diverged history, detached HEAD, or remote config?). Continuing with local HEAD."
          msg_info "Inspect manually: cd $COWORK_DIR && git status && git log --oneline -5"
        fi

        # Restore stash if we made one.
        if [ -n "$stash_label" ]; then
          local stash_ref
          stash_ref=$(git stash list 2>/dev/null | grep -F "$stash_label" | head -1 | sed -E 's/^([^:]+):.*/\1/')
          if [ -n "$stash_ref" ]; then
            if git stash pop "$stash_ref" >/dev/null 2>&1; then
              msg_success "Local changes restored from stash."
            else
              # Pop conflicted — leave the stash in place + tell user.
              msg_warn "Stash pop conflicted. Local changes preserved in stash '$stash_label'."
              msg_info "Recover with: cd $COWORK_DIR && git stash list && git stash apply <stash@{N}>"
            fi
          fi
        fi
      )
    fi

    # WORKFORCE/ replaced the legacy AGENTS/ name. Per-project runtime
    # lives under WORKFORCE/FLEETPROJECTS/<slug>/runtime/ and is created
    # lazily by ac-register, not at clone time.
    if [ ! -d "$COWORK_DIR/WORKFORCE" ]; then
      msg_warn "COWORK/WORKFORCE/ not present in this branch. Skipping coordination setup."
      return
    fi

    # Make bin/ scripts executable. Skip non-shell extensions
    # (.md, .ps1, .json, .yml, .yaml) — chmod +x on those dirties
    # git status without doing anything useful.
    if [ -d "$COWORK_DIR/WORKFORCE/bin" ]; then
      for f in "$COWORK_DIR/WORKFORCE/bin"/*; do
        [ -f "$f" ] || continue
        case "$(basename "$f")" in
          *.md|*.ps1|*.json|*.yml|*.yaml|*.txt) continue ;;
        esac
        chmod +x "$f" 2>/dev/null
      done
    fi

    # Add WORKFORCE/bin to PATH via shellrc fragment (idempotent).
    local SHELLRC
    if [ -n "${ZSH_VERSION:-}" ] || [ -f "$HOME/.zshrc" ]; then
      SHELLRC="$HOME/.zshrc"
    else
      SHELLRC="$HOME/.bashrc"
    fi
    if ! grep -q 'COWORK/WORKFORCE/bin' "$SHELLRC" 2>/dev/null; then
      # Clean up legacy AGENTS/bin export if it's still in place.
      if grep -q 'COWORK/AGENTS/bin' "$SHELLRC" 2>/dev/null; then
        msg_info "Removing legacy COWORK/AGENTS/bin export from $SHELLRC"
        # Match the two-line block: comment header + export.
        sed -i.bak \
          -e '/# --- COWORK Multi-Agent Coordination ---/{N;/COWORK\/AGENTS\/bin/d;}' \
          "$SHELLRC"
        rm -f "$SHELLRC.bak"
      fi
      printf '\n# --- COWORK Multi-Agent Coordination ---\nexport PATH="$HOME/COWORK/WORKFORCE/bin:$PATH"\n' >> "$SHELLRC"
      msg_success "Added WORKFORCE/bin to PATH in $SHELLRC"
    else
      msg_info "WORKFORCE/bin already on PATH in $SHELLRC"
    fi

    # Initialize Claude Code auto-memory git-sync (Option A doctrine).
    # See ~/COWORK/WORKFORCE/FLEETPROJECTS/project-leisure/runtime/decisions/
    #     2026-05-13__memory-sync-doctrine.md
    # Script is idempotent + walks all encoded cwd subdirs Claude Code has
    # created (master's $HOME, root's $HOME, per-project sessions like
    # ~/COWORK, etc.), symlinking each into .claude-memory/<host>-<encoded>/.
    if [ -x "$COWORK_DIR/WORKFORCE/bin/ac-memory-init" ]; then
      msg_info "Initializing Claude Code auto-memory git-sync (all cwd subdirs)..."
      if "$COWORK_DIR/WORKFORCE/bin/ac-memory-init" --auto-commit; then
        msg_success "Memory sync initialized (or already in place)."
      else
        local rc=$?
        if [ "$rc" -eq 2 ]; then
          msg_warn "ac-memory-init: .gitignore excludes target path. Fix .gitignore then re-run."
        else
          msg_warn "ac-memory-init exited non-zero (rc=$rc) — inspect manually."
        fi
      fi
    else
      msg_info "ac-memory-init not present yet — skipping memory sync init."
    fi

    # Wire the claude wrapper into master's and root's shellrcs. The
    # wrapper handles two issues that surface when claude is invoked
    # under both UIDs on the same host:
    #   1. Root-mode --permission-mode auto auto-injection (claude refuses
    #      bypassPermissions when running as root; this overrides at CLI
    #      level without touching settings.json).
    #   2. Cross-user flock (master + root share state via symlinks; concurrent
    #      claude processes can corrupt .credentials.json, sessions, etc).
    # Idempotent — marker-comment check prevents duplicate appends.
    local wrapper_file="$COWORK_DIR/WORKFORCE/bin/claude-wrapper.sh"
    if [ -f "$wrapper_file" ]; then
      msg_info "Wiring Claude wrapper into master + root shellrcs..."
      local marker="# --- COWORK Claude wrapper (root/master safety) ---"

      _add_wrapper_source() {
        local target="$1" source_path="$2"
        [ -f "$target" ] || return 0  # skip absent shellrc
        if grep -qF "$marker" "$target" 2>/dev/null; then
          return 0  # already wired
        fi
        printf '\n%s\nsource "%s" 2>/dev/null\n' "$marker" "$source_path" >> "$target"
        msg_success "Wired wrapper into $target"
      }

      # Master's shellrcs — use $HOME-relative source.
      _add_wrapper_source "$HOME/.zshrc"  "\$HOME/COWORK/WORKFORCE/bin/claude-wrapper.sh"
      _add_wrapper_source "$HOME/.bashrc" "\$HOME/COWORK/WORKFORCE/bin/claude-wrapper.sh"

      # Root's shellrcs — use absolute path (root's $HOME is /root, not master's).
      if sudo -n true 2>/dev/null; then
        local root_abs="$wrapper_file"  # absolute path, master-owned
        for root_rc in /root/.zshrc /root/.bashrc; do
          if sudo test -f "$root_rc"; then
            if ! sudo grep -qF "$marker" "$root_rc" 2>/dev/null; then
              sudo bash -c "printf '\n%s\nsource %s 2>/dev/null\n' '$marker' '$root_abs' >> '$root_rc'"
              msg_success "Wired wrapper into $root_rc"
            fi
          fi
        done
      else
        msg_warn "passwordless sudo unavailable — root shellrcs not wired. Manual: add 'source $wrapper_file' to /root/.zshrc + /root/.bashrc"
      fi
    else
      msg_info "claude-wrapper.sh not present yet — skipping wrapper wiring."
    fi

    # One-time migration from legacy ~/.agent-coordination/ if present.
    if [ -d "$HOME/.agent-coordination" ]; then
      msg_info "Legacy ~/.agent-coordination/ detected."
      echo -ne "${YELLOW}Run migrate-from-legacy now? [y/N]: ${NC}"
      read -r REPLY
      if [[ "$REPLY" =~ ^[Yy]$ ]]; then
        if "$COWORK_DIR/WORKFORCE/bin/migrate-from-legacy"; then
          msg_success "Legacy coordination migrated."
        else
          msg_warn "Migration failed. Inspect manually: $COWORK_DIR/WORKFORCE/bin/migrate-from-legacy"
        fi
      fi
    fi

    msg_success "COWORK deployed. Open a new shell, then test with 'ac-status'."
    msg_info "Activation triggers: type 'ACTIVATE AGENT' or 'ACTIVATE COORDINATOR' in any Claude Code session."
  }

  # --- MENU & EXECUTION ---

  # Build menu items dynamically so the ROOT option is hidden when we're
  # already running as root — there's no "regular user" to mirror configs from.
  local MENU_ITEMS=(
    "BASE"   "OS Updates & Core Packages" ON
    "NODE"   "Node.js, NVM, pnpm" ON
    "PYTHON" "Python, pyenv, pip packages" ON
    "SHELL"  "Zsh, OMZ, OMP, & TPM" ON
    "STOW"   "Deploy Repo configs" ON
    "TMUX"   "Tmux persistence (auto-attach + systemd boot)" ON
    "DOCKER" "Docker Engine (CE + compose plugin)" OFF
    "BRAVE"  "Brave Browser" OFF
  )
  if [ "$EUID" -ne 0 ]; then
    MENU_ITEMS+=("ROOT" "Replicate profile to root user" OFF)
    MENU_ITEMS+=("NOPASS" "Enable passwordless sudo for current user" OFF)
  fi
  # Offer SWAP only when none is configured (always-on for the rare case where it'd help)
  if [ -z "$(swapon --show=NAME --noheadings 2>/dev/null)" ]; then
    local _RAM_GB
    _RAM_GB=$(awk '/MemTotal/ {printf "%d", ($2/1024/1024)+0.5}' /proc/meminfo)
    MENU_ITEMS+=("SWAP" "Create ${_RAM_GB}G swapfile (matches RAM, none currently)" ON)
  fi
  MENU_ITEMS+=("SSHKEY" "GitHub SSH key, CLI & auth" OFF)
  MENU_ITEMS+=("COWORK" "COWORK repo + Multi-Agent Coordination (needs SSHKEY)" OFF)

  CHOICES=$(whiptail --title "Linux Environment Setup" --checklist \
    "Select components to install/deploy (Space to toggle, Enter to confirm):" 26 78 11 \
    "${MENU_ITEMS[@]}" 3>&1 1>&2 2>&3)

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
  if [[ $CHOICES == *"PYTHON"* ]]; then install_python_env; fi
  if [[ $CHOICES == *"SHELL"* ]]; then setup_shell_env; fi
  if [[ $CHOICES == *"STOW"* ]]; then deploy_stow; fi

  # Claude config uses absolute symlinks (not stow) to survive chained symlinks for root sharing
  if [[ $CHOICES == *"STOW"* ]]; then deploy_claude_config; fi

  # AI CLIs always install via vendor scripts — fast, idempotent, the core of this setup
  install_ai_tools

  # Claude plugins: self-gates if claude CLI or settings are missing
  install_claude_plugins

  if [[ $CHOICES == *"SWAP"* ]]; then setup_swapfile; fi
  if [[ $CHOICES == *"DOCKER"* ]]; then install_docker; fi
  if [[ $CHOICES == *"TMUX"* ]]; then setup_tmux_persistence; fi
  if [[ $CHOICES == *"BRAVE"* ]]; then install_brave; fi
  if [[ $CHOICES == *"ROOT"* ]]; then setup_root_profile; fi
  if [[ $CHOICES == *"NOPASS"* ]]; then configure_passwordless_sudo; fi
  if [[ $CHOICES == *"SSHKEY"* ]]; then setup_github_ssh; fi

  # COWORK runs LAST — requires gh auth established by SSHKEY (private repo)
  if [[ $CHOICES == *"COWORK"* ]]; then setup_cowork; fi

  echo -e "\n${GREEN}Setup complete. Restart your terminal to apply shell changes.${NC}"
}

# Execute the buffered payload
main "$@"
