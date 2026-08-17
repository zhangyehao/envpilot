#!/usr/bin/env bash

# envpilot-managed-codex-wrapper
set -e

manager="${ENVPILOT_CODEX_REMOTE_SCRIPT:-$HOME/.local/bin/codex-remote}"
if [ ! -x "$manager" ]; then
    printf 'envpilot Codex remote manager is not installed: %s\n' "$manager" >&2
    printf 'Run: bash envpilot.sh codex remote enable\n' >&2
    exit 1
fi

exec "$manager" exec "$@"
