# Sourced by EVERY zsh invocation (login, interactive, and `zsh -c` — which
# includes sshd remote commands and cron), so keep it small and cheap.
# Non-interactive shells never read .zshrc, where ~/.local/bin used to be
# added — so `ssh <box> herdr ...` failed command-not-found while interactive
# logins worked (hit live 2026-08-23: the workspace() hop's `command -v herdr`
# probe failed on the remote side and silently fell back to tmux).
case ":$PATH:" in
  *":$HOME/.local/bin:"*) ;;
  *) export PATH="$HOME/.local/bin:$PATH" ;;
esac

# Agent tools run `zsh -lc '<command>'` on a box whose login shell is zsh. Codex
# takes the login shell from the password database and has no setting to change it
# (checked on Codex 0.167: $SHELL and shell_environment_policy.set are both ignored;
# only the per-call `shell` argument chooses another one), and the login shell is not
# ours to change. Bash habits then fail as zsh errors: `ls *.log` with no match is
# "zsh: no matches found", and a word starting with `=` is expanded as a command path.
# Make a `zsh -c` command string behave like bash on those two points. ZSH_EXECUTION_STRING
# is set only for -c, so interactive shells and script files keep zsh's defaults.
if [[ -n ${ZSH_EXECUTION_STRING-} ]]; then
  setopt nonomatch noequals
fi
