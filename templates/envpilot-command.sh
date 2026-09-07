#!/usr/bin/env bash
# envpilot-managed-command
set -euo pipefail
root_file="$HOME/.config/envpilot/command-root"
root=""
if [ -r "$root_file" ]; then
    IFS= read -r root < "$root_file" || true
fi
case "$root" in
    /*) ;;
    *) printf 'envpilot: missing or invalid command registration: %s\nRun bash /path/to/envpilot/envpilot.sh setup-command\n' "$root_file" >&2; exit 1 ;;
esac
if [ ! -f "$root/envpilot.sh" ] || [ ! -f "$root/lib/common.sh" ]; then
    printf 'envpilot: registered repository is unavailable: %s\nRun setup-command from the new repository location.\n' "$root" >&2
    exit 1
fi
exec bash "$root/envpilot.sh" "$@"
