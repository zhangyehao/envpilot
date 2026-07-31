#!/usr/bin/env bash
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=templates/mihomo_common.sh
. "$SCRIPT_DIR/mihomo_common.sh"
mihomo_init_runtime

printf '=== Process ===\n'
if mihomo_runtime_running; then
    pgrep -u "${USER:-$(id -un)}" -af "$MIHOMO_RUNTIME_BIN" || true
    mihomo_pid="$(pgrep -u "${USER:-$(id -un)}" -f "$MIHOMO_RUNTIME_BIN" | head -n 1)"
    ps -ww -p "$mihomo_pid" -o pid,ppid,stat,lstart,etime,wchan:40,%cpu,%mem,rss,args 2>/dev/null || true
else
    printf 'mihomo is not running on this node.\n'
fi

printf '\n=== Listening ports ===\n'
for port in "$MIHOMO_PROXY_PORT" "$MIHOMO_API_PORT"; do
    if mihomo_port_reachable "$port"; then
        printf '%s:%s listening\n' "$MIHOMO_PROXY_HOST" "$port"
    else
        printf '%s:%s not listening\n' "$MIHOMO_PROXY_HOST" "$port"
    fi
done

printf '\n=== API health ===\n'
if mihomo_api_healthy; then
    printf 'API: OK (%s:%s)\n' "$MIHOMO_PROXY_HOST" "$MIHOMO_API_PORT"
else
    printf 'API: FAILED (%s:%s)\n' "$MIHOMO_PROXY_HOST" "$MIHOMO_API_PORT"
fi

printf '\n=== Proxy egress ===\n'
if mihomo_command_exists curl && curl \
    -4 \
    --proxy "http://${MIHOMO_PROXY_HOST}:${MIHOMO_PROXY_PORT}" \
    --connect-timeout 5 \
    --max-time 20 \
    -fsS \
    https://ipinfo.io/ip; then
    printf '\nProxy: OK\n'
else
    printf '\nProxy: FAILED or external network unavailable\n'
fi

printf '\n=== Recent log ===\n'
tail -n 30 "$MIHOMO_RUNTIME_LOG" 2>/dev/null ||
    printf 'runtime log not found: %s\n' "$MIHOMO_RUNTIME_LOG"