#!/usr/bin/env bash
set -euo pipefail

MIHOMO_BIN="${HOME}/software/mihomo/mihomo"
CONFIG_DIR="${HOME}/.config/mihomo"
LOG_FILE="${HOME}/logs/mihomo.log"
MIHOMO_PROXY_HOST="${MIHOMO_PROXY_HOST:-127.0.0.1}"
MIHOMO_PROXY_PORT="${MIHOMO_PROXY_PORT:-}"

command_exists()
{
    command -v "$1" >/dev/null 2>&1
}

proxy_port_socket_listening()
{
    local port="$1"
    local line
    if command_exists ss; then
        line="$(ss -lntH "sport = :$port" 2>/dev/null | head -n 1 || true)"
        [ -n "$line" ] && return 0
    fi
    if command_exists lsof; then
        line="$(lsof -nP -iTCP:"$port" -sTCP:LISTEN 2>/dev/null | awk 'NR == 2 { print; exit }' || true)"
        [ -n "$line" ] && return 0
    fi
    if command_exists netstat; then
        line="$(netstat -an 2>/dev/null | grep -E "[.:]${port}[[:space:]].*LISTEN" | head -n 1 || true)"
        [ -n "$line" ] && return 0
    fi
    return 1
}

proxy_port_is_listening()
{
    local host="$1"
    local port="$2"
    if proxy_port_socket_listening "$port"; then
        return 0
    fi
    if command_exists nc && nc -z -w 1 "$host" "$port" >/dev/null 2>&1; then
        return 0
    fi
    if command_exists timeout && timeout 1 bash -c ": </dev/tcp/$host/$port" >/dev/null 2>&1; then
        return 0
    fi
    return 1
}

if [ -z "$MIHOMO_PROXY_PORT" ] && [ -r "$HOME/.config/envpilot/shell.local" ]; then
    MIHOMO_PROXY_PORT="$(grep -E '^[[:space:]]*(export[[:space:]]+)?BASHRC_PROXY_PORT=' "$HOME/.config/envpilot/shell.local" 2>/dev/null | tail -n 1 | sed -E 's/^[[:space:]]*(export[[:space:]]+)?BASHRC_PROXY_PORT=//' | tr -d "\"'[:space:]" || true)"
fi
if [ -z "$MIHOMO_PROXY_PORT" ] && [ -r "$CONFIG_DIR/config.yaml" ]; then
    MIHOMO_PROXY_PORT="$(grep -E '^[[:space:]]*mixed-port:[[:space:]]*[0-9]+' "$CONFIG_DIR/config.yaml" 2>/dev/null | tail -n 1 | sed -E 's/^[^:]+:[[:space:]]*([0-9]+).*/\1/' || true)"
fi
case "${MIHOMO_PROXY_PORT:-}" in
    ''|*[!0-9]*) MIHOMO_PROXY_PORT=7890 ;;
esac
if [ "$MIHOMO_PROXY_PORT" -lt 1 ] || [ "$MIHOMO_PROXY_PORT" -gt 65535 ]; then
    echo "[ERROR] invalid mihomo proxy port: $MIHOMO_PROXY_PORT" >&2
    exit 1
fi

mkdir -p "$(dirname "$LOG_FILE")"

if [ ! -x "$MIHOMO_BIN" ]; then
    echo "[ERROR] mihomo executable not found: $MIHOMO_BIN" >&2
    exit 1
fi

if [ ! -s "$CONFIG_DIR/config.yaml" ]; then
    echo "[ERROR] mihomo config not found: $CONFIG_DIR/config.yaml" >&2
    echo "[ERROR] Provide a Clash/Mihomo subscription URL during envpilot install mihomo, or put config.yaml there manually." >&2
    exit 1
fi

if proxy_port_is_listening "$MIHOMO_PROXY_HOST" "$MIHOMO_PROXY_PORT"; then
    echo "[INFO] mihomo already running."
    exit 0
fi
if pgrep -u "$USER" -f "$MIHOMO_BIN" >/dev/null 2>&1; then
    echo "[INFO] mihomo already running."
    pgrep -u "$USER" -af "$MIHOMO_BIN"
    exit 0
fi

nohup "$MIHOMO_BIN" -d "$CONFIG_DIR" >> "$LOG_FILE" 2>&1 &
mihomo_pid=$!

attempts=20
count=0
while [ "$count" -lt "$attempts" ]; do
    if proxy_port_is_listening "$MIHOMO_PROXY_HOST" "$MIHOMO_PROXY_PORT"; then
        echo "[INFO] mihomo started. PID=$mihomo_pid"
        echo "[INFO] log file: $LOG_FILE"
        echo "[INFO] proxy: http://${MIHOMO_PROXY_HOST}:${MIHOMO_PROXY_PORT}"
        exit 0
    fi
    sleep 1
    count=$((count + 1))
done

echo "[ERROR] mihomo did not open proxy port ${MIHOMO_PROXY_HOST}:${MIHOMO_PROXY_PORT} within ${attempts}s." >&2
if [ -s "$LOG_FILE" ]; then
    tail -n 20 "$LOG_FILE" >&2 || true
fi
exit 1