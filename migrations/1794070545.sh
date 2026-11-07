#!/usr/bin/env bash
# Migration: OOMPolicy=continue for T3 Code thread scopes on existing boxes.
#
# T3 Code runs each Claude thread in a transient user scope, t3code-claude-<id>.scope,
# and systemd's default for a scope is OOMPolicy=stop: one OOM-killed child (a test
# runner, a PowerShell process) stops the scope and fails the whole thread, foreman and
# every lane in it (five times in a week on one box). The drop-in in the systemd/ stow
# package sets OOMPolicy=continue. A box that already ran STOW has it as a symlink; this
# migration copies it into place on the others, so it does not take a full re-stow.
#
# A copy, not a link, because stow only owns links it made itself: a hand-made link
# would make the next STOW report a conflict. A later STOW backs this copy up
# (oom-continue.conf.backup_<time>, ignored by systemd) and links the repo file.
# The file is inert on a box without T3. It applies to scopes created after the daemon
# reload; running threads keep the policy they started with.
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$REPO/systemd/.config/systemd/user/t3code-claude-.scope.d/oom-continue.conf"
DEST="$HOME/.config/systemd/user/t3code-claude-.scope.d/oom-continue.conf"

[ -f "$SRC" ] || { echo "missing $SRC" >&2; exit 1; }

if [ -L "$DEST" ] && [ "$(readlink -f "$DEST")" = "$(readlink -f "$SRC")" ]; then
  echo "drop-in already linked by stow"
elif [ -f "$DEST" ] && cmp -s "$SRC" "$DEST"; then
  echo "drop-in already in place"
else
  mkdir -p "$(dirname "$DEST")"
  if [ -e "$DEST" ] || [ -L "$DEST" ]; then
    backup="$DEST.backup_$(date +%Y%m%d_%H%M%S)"
    mv "$DEST" "$backup"
    echo "kept the previous file as $backup"
  fi
  install -m 0644 "$SRC" "$DEST"
  echo "installed $DEST"
fi

# Best effort: with no user manager (ssh without a session bus, a container) the next
# login reads the file anyway.
if command -v systemctl >/dev/null 2>&1; then
  systemctl --user daemon-reload 2>/dev/null \
    || echo "systemctl --user daemon-reload did not run; the drop-in applies after the next login or reload"
fi
