#!/usr/bin/env bash
# Opt-in integration with a real Codex binary; no provider requests or user state.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
binary="${1:?usage: test-codex-real.sh /absolute/path/to/codex}"
fixture="$(mktemp -d /tmp/ep-real.XXXXXX)"
export HOME="$fixture/home" CODEX_HOME="$fixture/home/.codex"
export XDG_CONFIG_HOME="$fixture/config" XDG_STATE_HOME="$fixture/state" XDG_RUNTIME_DIR="$fixture/runtime"
export ENVPILOT_CORE="$ROOT/bin/envpilot-core" ENVPILOT_CODEX_SOURCE_BIN="$fixture/source"
export ENVPILOT_CODEX_RUNTIME_DIR="$fixture/cache" ENVPILOT_CODEX_REMOTE_READY_TIMEOUT=15
export ENVPILOT_CONFIG_DIR="$fixture/envpilot" ENVPILOT_LANG=en ENVPILOT_CODEX_LOAD_SECRETS=0
unset OPENAI_API_KEY OPENAI_BASE_URL
mkdir -p "$CODEX_HOME" "$ENVPILOT_CODEX_SOURCE_BIN" "$XDG_RUNTIME_DIR"
chmod 700 "$XDG_RUNTIME_DIR"
cp "$binary" "$ENVPILOT_CODEX_SOURCE_BIN/codex"
chmod 700 "$ENVPILOT_CODEX_SOURCE_BIN/codex"
manager="$ROOT/templates/codex-remote.sh"
external=""
trap 'bash "$manager" stop >/dev/null 2>&1 || true; if [ -n "$external" ]; then kill "$external" 2>/dev/null || true; wait "$external" 2>/dev/null || true; fi; rm -rf "$fixture"' EXIT
version="$("$ENVPILOT_CODEX_SOURCE_BIN/codex" --version | awk '{print $2}')"
socket="$CODEX_HOME/app-server-control/app-server-control.sock"
pid_file="$CODEX_HOME/app-server-control/envpilot-app-server.pid"
echo "[TEST] real Codex $version: external instance, ready, restart and stop -> ready"
"$ENVPILOT_CODEX_SOURCE_BIN/codex" app-server --listen unix:// >"$fixture/external.log" 2>&1 &
external=$!
for ((i=0; i<100; i++)); do
    if "$ENVPILOT_CORE" probe --socket "$socket" >/dev/null 2>&1; then break; fi
    sleep 0.1
done
if ! "$ENVPILOT_CORE" probe --socket "$socket" >/dev/null; then cat "$fixture/external.log"; exit 1; fi
# No envpilot PID file exists for this externally launched server.
bash "$manager" restart
wait "$external" 2>/dev/null || true
! kill -0 "$external" 2>/dev/null
external=""
bash "$manager" status | grep -F 'socket: READY' >/dev/null
test "$("$ENVPILOT_CORE" probe --socket "$socket" --format version)" = "$version"
before="$(cat "$pid_file")"
bash "$manager" ready
test "$(cat "$pid_file")" = "$before"
bash "$manager" restart
test "$(cat "$pid_file")" != "$before"
rm -f "$pid_file" "$pid_file.identity"
bash "$manager" stop
! "$ENVPILOT_CORE" probe --socket "$socket" >/dev/null 2>&1
bash "$manager" ready
bash "$manager" stop
echo "[TEST] real Codex $version passed"
