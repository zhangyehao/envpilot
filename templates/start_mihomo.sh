#!/usr/bin/env bash
set -euo pipefail

MIHOMO_BIN="${HOME}/software/mihomo/mihomo"
CONFIG_DIR="${HOME}/.config/mihomo"
LOG_FILE="${HOME}/logs/mihomo.log"

mkdir -p "$(dirname "$LOG_FILE")"

if pgrep -u "$USER" -f "$MIHOMO_BIN" >/dev/null 2>&1; then
    echo "[INFO] mihomo already running."
    pgrep -u "$USER" -af "$MIHOMO_BIN"
    exit 0
fi

nohup "$MIHOMO_BIN" -d "$CONFIG_DIR" >> "$LOG_FILE" 2>&1 &
echo "[INFO] mihomo started. PID=$!"
echo "[INFO] log file: $LOG_FILE"

