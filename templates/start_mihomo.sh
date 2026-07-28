#!/usr/bin/env bash
set -euo pipefail

MIHOMO_BIN="${HOME}/software/mihomo/mihomo"
CONFIG_DIR="${HOME}/.config/mihomo"
LOG_FILE="${HOME}/logs/mihomo.log"

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

if pgrep -u "$USER" -f "$MIHOMO_BIN" >/dev/null 2>&1; then
    echo "[INFO] mihomo already running."
    pgrep -u "$USER" -af "$MIHOMO_BIN"
    exit 0
fi

nohup "$MIHOMO_BIN" -d "$CONFIG_DIR" >> "$LOG_FILE" 2>&1 &
echo "[INFO] mihomo started. PID=$!"
echo "[INFO] log file: $LOG_FILE"
echo "[INFO] proxy: http://127.0.0.1:7890"

