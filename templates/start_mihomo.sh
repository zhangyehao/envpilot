#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=templates/mihomo_common.sh
. "$SCRIPT_DIR/mihomo_common.sh"
mihomo_init_runtime

mihomo_command_exists curl || mihomo_die "curl is required for Mihomo health checks"
[ -x "$MIHOMO_SOURCE_BIN" ] || mihomo_die "mihomo executable not found: $MIHOMO_SOURCE_BIN"
[ -s "$MIHOMO_SOURCE_CONFIG/config.yaml" ] ||
    mihomo_die "mihomo config not found: $MIHOMO_SOURCE_CONFIG/config.yaml"

if mihomo_runtime_running; then
    if mihomo_api_healthy; then
        printf '[OK] mihomo is already running and healthy.\n'
        pgrep -u "${USER:-$(id -un)}" -af "$MIHOMO_RUNTIME_BIN" || true
        printf '[OK] proxy: %s:%s\n' "$MIHOMO_PROXY_HOST" "$MIHOMO_PROXY_PORT"
        printf '[OK] API:   %s:%s\n' "$MIHOMO_PROXY_HOST" "$MIHOMO_API_PORT"
        exit 0
    fi

    printf '[WARN] mihomo process exists but its API health check failed.\n' >&2
    pgrep -u "${USER:-$(id -un)}" -af "$MIHOMO_RUNTIME_BIN" >&2 || true
    if [ "${MIHOMO_FORCE_RESTART:-0}" != "1" ]; then
        mihomo_die "run mihomo_stop first, or set MIHOMO_FORCE_RESTART=1"
    fi
    "$SCRIPT_DIR/stop_mihomo.sh"
fi

if mihomo_port_reachable "$MIHOMO_PROXY_PORT"; then
    mihomo_die "proxy port $MIHOMO_PROXY_HOST:$MIHOMO_PROXY_PORT is already in use"
fi
if mihomo_port_reachable "$MIHOMO_API_PORT"; then
    mihomo_die "API port $MIHOMO_PROXY_HOST:$MIHOMO_API_PORT is already in use"
fi

case "$MIHOMO_RUNTIME_DIR" in
    /tmp/*_mihomo_*) ;;
    *) mihomo_die "unsafe runtime directory: $MIHOMO_RUNTIME_DIR" ;;
esac
rm -rf -- "$MIHOMO_RUNTIME_DIR"
mkdir -p "$MIHOMO_RUNTIME_DIR"
chmod 700 "$MIHOMO_RUNTIME_DIR"

cp "$MIHOMO_SOURCE_BIN" "$MIHOMO_RUNTIME_BIN"
chmod 755 "$MIHOMO_RUNTIME_BIN"
cp -a "$MIHOMO_SOURCE_CONFIG/." "$MIHOMO_RUNTIME_DIR/"
rm -f \
    "$MIHOMO_RUNTIME_DIR/cache.db" \
    "$MIHOMO_RUNTIME_DIR/cache.db-shm" \
    "$MIHOMO_RUNTIME_DIR/cache.db-wal"
mihomo_apply_local_config "$MIHOMO_RUNTIME_DIR/config.yaml"

nohup "$MIHOMO_RUNTIME_BIN" \
    -d "$MIHOMO_RUNTIME_DIR" \
    >"$MIHOMO_RUNTIME_LOG" 2>&1 &
mihomo_pid=$!
printf '%s\n' "$mihomo_pid" > "$MIHOMO_PID_FILE"

count=0
while [ "$count" -lt "$MIHOMO_STARTUP_TIMEOUT" ]; do
    if ! kill -0 "$mihomo_pid" 2>/dev/null; then
        printf '[ERROR] mihomo exited during startup.\n' >&2
        tail -n 50 "$MIHOMO_RUNTIME_LOG" >&2 2>/dev/null || true
        exit 1
    fi
    if mihomo_api_healthy && mihomo_port_reachable "$MIHOMO_PROXY_PORT"; then
        printf '[OK] mihomo is ready. PID=%s\n' "$mihomo_pid"
        printf '[OK] runtime: %s\n' "$MIHOMO_RUNTIME_DIR"
        printf '[OK] log:     %s\n' "$MIHOMO_RUNTIME_LOG"
        printf '[OK] proxy:   %s:%s\n' "$MIHOMO_PROXY_HOST" "$MIHOMO_PROXY_PORT"
        printf '[OK] API:     %s:%s\n' "$MIHOMO_PROXY_HOST" "$MIHOMO_API_PORT"
        exit 0
    fi
    sleep 1
    count=$((count + 1))
done

printf '[ERROR] mihomo process exists, but API %s:%s was not ready within %ss.\n' \
    "$MIHOMO_PROXY_HOST" "$MIHOMO_API_PORT" "$MIHOMO_STARTUP_TIMEOUT" >&2
ps -ww -p "$mihomo_pid" -o pid,ppid,stat,etime,wchan:40,%cpu,%mem,args >&2 2>/dev/null || true
tail -n 50 "$MIHOMO_RUNTIME_LOG" >&2 2>/dev/null || true
exit 1