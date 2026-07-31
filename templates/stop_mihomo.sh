#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=templates/mihomo_common.sh
. "$SCRIPT_DIR/mihomo_common.sh"
mihomo_init_runtime

if ! mihomo_runtime_running; then
    printf '[INFO] mihomo is not running on this node.\n'
    exit 0
fi

printf '[INFO] stopping envpilot-managed mihomo:\n'
pgrep -u "${USER:-$(id -un)}" -af "$MIHOMO_RUNTIME_BIN" || true
pkill -TERM -u "${USER:-$(id -un)}" -f "$MIHOMO_RUNTIME_BIN" 2>/dev/null || true

count=0
while [ "$count" -lt 10 ]; do
    if ! mihomo_runtime_running; then
        rm -f "$MIHOMO_PID_FILE"
        printf '[OK] mihomo stopped.\n'
        exit 0
    fi
    sleep 1
    count=$((count + 1))
done

printf '[WARN] mihomo did not stop within 10 seconds; sending SIGKILL.\n' >&2
pkill -KILL -u "${USER:-$(id -un)}" -f "$MIHOMO_RUNTIME_BIN" 2>/dev/null || true
rm -f "$MIHOMO_PID_FILE"
printf '[OK] mihomo killed.\n'