# Sourced by EVERY zsh invocation (login, interactive, and `zsh -c` — which
# includes sshd remote commands and cron), so keep it to PATH only.
# Non-interactive shells never read .zshrc, where ~/.local/bin used to be
# added — so `ssh <box> herdr ...` failed command-not-found while interactive
# logins worked (hit live 2026-08-23: the workspace() hop's `command -v herdr`
# probe failed on the remote side and silently fell back to tmux).
case ":$PATH:" in
  *":$HOME/.local/bin:"*) ;;
  *) export PATH="$HOME/.local/bin:$PATH" ;;
esac
