#!/usr/bin/env bash
# rtk-hook.sh: the PreToolUse(Bash) hook for rtk. Runs `rtk hook claude`, which
# rewrites a Bash command to its `rtk <cmd>` form (for example `git status` to
# `rtk git status`) so the output arrives compact, EXCEPT inside a Claude Code
# isolated worktree lane.
#
# WHY THE EXCEPTION: Claude Code ships a worktree-isolation guard (its strings are
# in the 2.1.286 binary) that refuses `rtk git ...` from an isolated lane: the
# guard recognizes a bare `git`, not the rtk wrapper around it, so every rewritten
# git call in such a lane is rejected and the lane cannot work with its own repo.
# An isolated lane's cwd is <repo>/.claude/worktrees/<name>, so a payload whose cwd
# is under /.claude/worktrees/ is passed through untouched (exit 0, no output: the
# command runs exactly as typed). Everywhere else the rewrite is unchanged.
#
# The hook payload (JSON on stdin) is read once and handed to rtk unchanged. This
# script never prints diagnostics: a PreToolUse hook that talks can disturb the
# session, and a failure here must degrade to "no rewrite" or to the old behavior,
# never to a blocked command. Unreadable cwd (no jq and no match) means the
# payload is treated as NOT in a worktree and rtk runs as before.
#
# Installed as ~/.claude/rtk-hook.sh (a Stage-1 link, like statusline.sh) and
# called from claude/.claude/settings.json; a host without this file falls back to
# calling rtk directly, with the old behavior. Tests: scripts/test_stage1.py.
payload="$(cat)"

cwd=""
if command -v jq >/dev/null 2>&1; then
  cwd="$(printf '%s' "$payload" | jq -r '.cwd // empty' 2>/dev/null)"
else
  # No jq: first "cwd":"..." in the raw payload. An escaped quote inside a command
  # string reads \"cwd\", which this pattern does not match, so only the real key does.
  cwd="$(printf '%s' "$payload" | sed -n 's/.*"cwd"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)"
fi
# A Windows cwd: backslashes to slashes, then runs of slashes to one (the sed path
# above sees the JSON-escaped form, C:\\Users\\x, which would otherwise leave "//").
cwd="${cwd//\\//}"
while [[ "$cwd" == *//* ]]; do cwd="${cwd//\/\///}"; done

case "$cwd" in
  */.claude/worktrees/*) exit 0 ;;
esac

if command -v rtk >/dev/null 2>&1; then
  printf '%s' "$payload" | exec rtk hook claude
elif [ -x "$HOME/.local/bin/rtk" ]; then
  printf '%s' "$payload" | exec "$HOME/.local/bin/rtk" hook claude
fi
exit 0
