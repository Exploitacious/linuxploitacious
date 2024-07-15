# My Dotfiles
My dotfiles for linux machines. Managed with Stow.

## Initialize
1. Clone the repo directory into ~/ Hopme to create a direcotry ~/dotfiles
2. CD into the directory and run "stow ." to create all symlinks.

## Stow
- Stow is a symlink generator which will take all your config files and place them into a single "dotfiles" directory.
- Make sure your files are set up in the exact same configuration as they would be in the ~/ home directory.

```
Stow . 
```
Initialize Stow to create symlinks

```
Stow --adopt . 
```
Initialize Stow and create symlinks, by adopting the existing file.
