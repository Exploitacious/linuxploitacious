# My Dotfiles
My dotfiles for linux machines. Managed with Stow.

## Initialize
1. Clone the repo directory into ~/ Hopme to create a direcotry ~/dotfiles
2. CD into the directory and run "stow ." to create all symlinks.

## Stow
- Stow is a symlink generator which will take all your config files and place them into a single "dotfiles" directory.
- Make sure your files are set up in the exact same configuration as they would be in the ~/ home directory.

```
stow . 
```
Initialize Stow to create symlinks

```
stow --adopt . 
```
Initialize Stow and create symlinks, by adopting the existing file.

## Copy / Migrate files

To copy or migrate new config files, simply move them or copy them into the exact same place as they were located in the home directory. For example:

~/.config/neofetch/config.conf

will need to move to:

~/dotfiles/.config/neofetch/config.conf

You can then either remove the original file from Home, or use the stow . --adopt command.