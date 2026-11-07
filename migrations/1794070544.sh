#!/usr/bin/env bash
# Migration: keep the pyenv shims for the Stage-1 pip tools resolvable.
#
# A pyenv shim runs only if some version on the global list has that command. When the
# global default moved to a Python that does not hold ruff, pytest or black, the shim
# stayed on disk and failed in every agent shell with "pyenv: ruff: command not found"
# (Codex lanes on two boxes, 2026-11: ruff in 3.14.7, global 3.14.5).
#
# For each tool the PYTHON step installs, if its shim does not resolve under the current
# global list, append the newest installed version that has it. The current default stays
# first, so `python` and `pip` do not change (a box may pin an older Python on purpose,
# for CI parity with a project); only commands that failed before start to work.
# Idempotent: with every tool resolving it changes nothing. No pyenv means nothing to do.
set -uo pipefail

export PYENV_ROOT="${PYENV_ROOT:-$HOME/.pyenv}"
[ -x "$PYENV_ROOT/bin/pyenv" ] && export PATH="$PYENV_ROOT/bin:$PATH"
if ! command -v pyenv >/dev/null 2>&1; then
  echo "pyenv is not installed; nothing to do"
  exit 0
fi

# The tools install_python_env pip-installs into the default Python.
TOOLS=(pipx poetry virtualenv pre-commit black ruff mypy isort pytest ipython)

# Installed CPython versions, newest first (a virtualenv shows up as 3.x.y/envs/name).
mapfile -t versions < <(pyenv versions --bare 2>/dev/null | grep -E '^[0-9][^/]*$' | sort -rV)
# The current global list, "system" included: dropping it would change the default Python.
mapfile -t current < <(pyenv global 2>/dev/null)
changed=0
for tool in "${TOOLS[@]}"; do
  pyenv which "$tool" >/dev/null 2>&1 && continue
  for version in "${versions[@]}"; do
    [ -x "$PYENV_ROOT/versions/$version/bin/$tool" ] || continue
    listed=0
    for entry in "${current[@]}"; do [ "$entry" = "$version" ] && listed=1; done
    if [ "$listed" -eq 0 ]; then
      current+=("$version")
      changed=1
      echo "$tool is only in Python $version: adding it to the pyenv global list"
    fi
    break
  done
done

if [ "$changed" -eq 1 ]; then
  pyenv global "${current[@]}" || exit 1
  pyenv rehash
fi

# Verify: report anything still dangling (a tool that is in no installed version is not
# this migration's problem and is not an error).
status=0
for tool in "${TOOLS[@]}"; do
  if ! pyenv which "$tool" >/dev/null 2>&1; then
    for version in "${versions[@]}"; do
      if [ -x "$PYENV_ROOT/versions/$version/bin/$tool" ]; then
        echo "$tool still does not resolve although Python $version has it" >&2
        status=1
        break
      fi
    done
  fi
done
echo "pyenv global: $(pyenv global | tr '\n' ' ')"
exit "$status"
