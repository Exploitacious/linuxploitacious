#!/usr/bin/env bash
# Migration: upgrade herdr 0.8.2 -> 0.9.3 on existing boxes.
#
# herdr-web 0.6.1 (the rc-web hub and session bridges) refuses a Herdr daemon
# older than 0.9.0 (protocol 22), so a box provisioned at 0.8.2 has a hub that
# crash-loops. This re-runs the pinned, checksum-verified installer, which
# replaces ~/.local/bin/herdr only when the installed version differs.
#
# It does not restart running herdr servers: that would end live agent
# sessions. After it runs, restart them when the box is idle, for example
#   systemctl --user restart herdr@console herdr-web-hub
# LPX_NO_MIGRATE=1 stops shellSetup's own migration runner from recursing.
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
LPX_NO_MIGRATE=1 bash "$REPO/shellSetup.sh" --run HERDR
"$HOME/.local/bin/herdr" --version | grep -q '^herdr 0\.9\.3' || { echo "herdr is not 0.9.3 after install" >&2; exit 1; }
