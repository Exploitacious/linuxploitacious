#!/usr/bin/env bash
# Migration: install the modern CLI toolset (CLITOOLS) on existing boxes.
#
# Runs once per box via lpx-migrate so already-provisioned fleet boxes pick up
# bat/eza/fd/zoxide/delta/dust/lazygit/... without a manual menu run.
# Idempotent: install_cli_tools skips every tool that is already present.
#
# LPX_NO_MIGRATE=1 stops shellSetup's own migration runner from recursing into
# this one. If the install needs sudo/apt and neither is available, --run exits
# non-zero here, so the migration fails loudly and lpx-migrate's fail-closed
# path handles it — no half-installed box that looks done.
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
LPX_NO_MIGRATE=1 bash "$REPO/shellSetup.sh" --run CLITOOLS
