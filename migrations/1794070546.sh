#!/usr/bin/env bash
# Migration: poppler and uv on existing boxes, for agent PDF and .msg reading.
#
# Claude Code's Read tool needs pdftotext and pdftoppm (poppler) to read a PDF, and the
# msg-read helper needs uv to run extract-msg. A box provisioned before BASE and PYTHON
# installed them has neither, so every PDF task fell through a cascade of failed probes
# (about 100 failed calls in two weeks) and every .msg started a throwaway venv.
#
# Both steps are always attempted; the exit status is non-zero if either one failed, so
# lpx-migrate fails closed and the box is not marked done. It is numbered after the pyenv
# and OOM drop-in migrations on purpose: lpx-migrate stops at the first failure, and a
# headless box with no passwordless sudo fails this one until someone runs it with a
# terminal, which must not hold back migrations that need no privilege. Each step is a no-op when its
# tool is already there. With no terminal and no passwordless sudo the poppler step
# fails instead of waiting for a password prompt nobody can answer.
set -uo pipefail

install_poppler() {
  if command -v pdftotext >/dev/null 2>&1 && command -v pdftoppm >/dev/null 2>&1; then
    echo "poppler already installed"
    return 0
  fi
  local -a priv=()
  if [ "$(id -u)" -ne 0 ]; then
    if ! command -v sudo >/dev/null 2>&1; then
      echo "poppler: needs root or sudo to install the package" >&2
      return 1
    fi
    if [ ! -t 0 ] && ! sudo -n true 2>/dev/null; then
      echo "poppler: sudo needs a password and there is no terminal to ask on" >&2
      return 1
    fi
    priv=(sudo)
  fi
  if command -v apt-get >/dev/null 2>&1; then
    ${priv[@]+"${priv[@]}"} apt-get update -qq || echo "poppler: apt-get update failed, trying the current index" >&2
    ${priv[@]+"${priv[@]}"} apt-get install -y poppler-utils || return 1
  elif command -v pacman >/dev/null 2>&1; then
    ${priv[@]+"${priv[@]}"} pacman -S --noconfirm --needed poppler || return 1
  elif command -v dnf >/dev/null 2>&1; then
    ${priv[@]+"${priv[@]}"} dnf install -y poppler-utils || return 1
  else
    echo "poppler: no supported package manager (apt-get, pacman, dnf)" >&2
    return 1
  fi
  if command -v pdftotext >/dev/null 2>&1 && command -v pdftoppm >/dev/null 2>&1; then
    echo "poppler installed"
    return 0
  fi
  echo "poppler: package installed but pdftotext or pdftoppm is still not on PATH" >&2
  return 1
}

install_uv() {
  if command -v uv >/dev/null 2>&1 || [ -x "$HOME/.local/bin/uv" ]; then
    echo "uv already installed"
    return 0
  fi
  if ! command -v curl >/dev/null 2>&1; then
    echo "uv: curl is required to download the installer" >&2
    return 1
  fi
  # UV_NO_MODIFY_PATH: the installer must not edit shell rc files, which this repo owns.
  # The pipeline's status is sh's, so a failed download would look like success: judge by
  # the binary instead.
  curl -LsSf https://astral.sh/uv/install.sh | UV_NO_MODIFY_PATH=1 sh
  if [ -x "$HOME/.local/bin/uv" ]; then
    echo "uv installed in ~/.local/bin"
    return 0
  fi
  echo "uv: the installer did not leave ~/.local/bin/uv" >&2
  return 1
}

rc=0
install_poppler || rc=1
install_uv || rc=1
exit "$rc"
