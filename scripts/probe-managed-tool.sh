#!/usr/bin/env bash
set -euo pipefail
ENVPILOT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "$ENVPILOT_ROOT/lib/common.sh"
. "$ENVPILOT_ROOT/lib/platform.sh"
. "$ENVPILOT_ROOT/lib/config.sh"
. "$ENVPILOT_ROOT/lib/download.sh"
. "$ENVPILOT_ROOT/lib/manifest.sh"
ep_platform_detect
case "${1:-}" in
    git) . "$ENVPILOT_ROOT/components/git.sh"; ep_git_preflight ;;
    python) . "$ENVPILOT_ROOT/components/python.sh"; ep_python_preflight ;;
    *) exit 2 ;;
esac
