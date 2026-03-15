# Linux Shell and Config Setup

---

An interactive provisioning script for deploying a fully configured Linux environment. Optimized for Debian and Kali Linux. 
Designed to deploy a unified Linux environment by centralizing config files and scripts across multiple machines using GNU Stow and Git. It's dead simple.

---

## Execution

```bash
wget -qO shellSetup.sh https://shell.ivantsov.tech && bash shellSetup.sh
```

```bash
curl -fsSL https://shell.ivantsov.tech | bash
```

---

## System Bootstrap (`shellSetup.sh`)

**Purpose:** This script automates the initial environment configuration on a completely blank machine. It is designed to run exactly once per system install. Further changes to configs need to be managed via git/github
* Installs Git and configures your global Git identity.
* Clones this repository to ~/linuxploitacious.
* Launches an interactive menu to install base packages (Zsh, Tmux, Fastfetch, etc.).
* Deploys configurations via GNU Stow.
* Sets up Oh My Zsh and Oh My Posh theming.

---

## GNU Stow: Core Mechanics

We use GNU Stow as a stateless symlink manager. It does not run a background daemon, and it does not maintain a database of what it has deployed. It reads the current state of a "package" directory and mirrors that structure to a target directory.

### The Directory Math (Tree Folding)
When you deploy a package, Stow ignores the name of the package folder itself. It treats the *inside* of the package folder as the equivalent of your target directory (which is `$HOME` in this setup).

After you clone, navigate to the repo directory. You will see a list of folders for each app containing the configs as if they were in `$HOME` already. If we just run `stow .` without providing a target, it will duplicate everything here into `$HOME`.

Therefore, we must declare which exact folders (apps) we're going to symlink into `$HOME`. 

Run `stow -t ~ zsh nvim scripts` (exclude / inlcude any folders you want to symlink):  
* `zsh/.zshrc` deploys to `~/.zshrc`
* `nvim/.config/nvim/init.lua` deploys to `~/.config/nvim/init.lua`
* `scripts/.local/bin/sys-update.sh` deploys to `~/.local/bin/sys-update.sh`

### Repository Architecture
**Rule:** Do not place deployable files in the root of this repository. The root is strictly for management scripts and documentation. All payload files must exist inside a designated package folder.

```text
~/linuxploitacious/
├── README.md                 # This documentation
├── shellSetup.sh             # Master bootstrap script (Not stowed)
├── zsh/                      # Package: Zsh configs
│   └── .zshrc                # Deploys -> ~/.zshrc
├── scripts/                  # Package: Global scripts
│   └── .local/               
│       └── bin/
│           └── ultimate.sh   # Deploys -> ~/.local/bin/ultimate.sh
└── btop/                     # Package: Btop configs
    └── .config/
        └── btop/
            └── btop.conf     # Deploys -> ~/.config/btop/btop.conf
