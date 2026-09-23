#!/usr/bin/env bash
# Opt-in integration with a real Codex binary; no provider requests or user state.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
binary="${1:?usage: test-codex-real.sh /absolute/path/to/package-or-codex}"
fixture="$(mktemp -d /tmp/ep-real.XXXXXX)"
export HOME="$fixture/home" CODEX_HOME="$fixture/home/.codex"
export XDG_CONFIG_HOME="$fixture/config" XDG_STATE_HOME="$fixture/state" XDG_RUNTIME_DIR="$fixture/runtime"
export ENVPILOT_CORE="$ROOT/bin/envpilot-core" ENVPILOT_CODEX_SOURCE_BIN="$fixture/source"
export ENVPILOT_CODEX_RUNTIME_DIR="$fixture/cache" ENVPILOT_CODEX_REMOTE_READY_TIMEOUT=15
export ENVPILOT_CONFIG_DIR="$fixture/envpilot" ENVPILOT_LANG=en ENVPILOT_CODEX_LOAD_SECRETS=0
unset OPENAI_API_KEY OPENAI_BASE_URL
mkdir -p "$CODEX_HOME" "$ENVPILOT_CODEX_SOURCE_BIN" "$XDG_RUNTIME_DIR"
chmod 700 "$XDG_RUNTIME_DIR"
if [ -d "$binary" ]; then
    cp -a "$binary/." "$ENVPILOT_CODEX_SOURCE_BIN/"
    [ -e "$ENVPILOT_CODEX_SOURCE_BIN/codex" ] || ln -s bin/codex "$ENVPILOT_CODEX_SOURCE_BIN/codex"
else
    cp "$binary" "$ENVPILOT_CODEX_SOURCE_BIN/codex"
fi
chmod 700 "$ENVPILOT_CODEX_SOURCE_BIN/codex"
manager="$ROOT/templates/codex-remote.sh"
external=""
desktop_pid_file="$fixture/desktop.pid"
trap 'bash "$manager" stop >/dev/null 2>&1 || true; for child in "$external" "$(cat "$desktop_pid_file" 2>/dev/null || true)"; do if [ -n "$child" ]; then kill "$child" 2>/dev/null || true; wait "$child" 2>/dev/null || true; fi; done; rm -rf "$fixture"' EXIT
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
if [ -f "$ENVPILOT_CODEX_SOURCE_BIN/codex-package.json" ]; then
    echo '[TEST] complete package, nested resources and real helper executables'
    "$ENVPILOT_CORE" runtime-verify --source "$ENVPILOT_CODEX_SOURCE_BIN" --target "$ENVPILOT_CODEX_RUNTIME_DIR/current"
    "$ENVPILOT_CODEX_RUNTIME_DIR/current/bin/codex-code-mode-host" --help >/dev/null
    "$ENVPILOT_CODEX_RUNTIME_DIR/current/codex-path/rg" --version >/dev/null
    "$ENVPILOT_CODEX_RUNTIME_DIR/current/codex-resources/bwrap" --version >/dev/null
    "$ENVPILOT_CODEX_RUNTIME_DIR/current/codex-resources/zsh/bin/zsh" --version >/dev/null
    # Voice host is an IPC worker, not a CLI with --help. Verify its packaged
    # dynamic dependencies instead of assuming a command-line interface.
    ldd "$ENVPILOT_CODEX_RUNTIME_DIR/current/codex-resources/voice/bin/codex-voice-host" > "$fixture/voice-libraries"
    if grep -F 'not found' "$fixture/voice-libraries"; then exit 1; fi
fi
before="$(cat "$pid_file")"
bash "$manager" ready
test "$(cat "$pid_file")" = "$before"
bash "$manager" restart
test "$(cat "$pid_file")" != "$before"
echo '[TEST] Desktop wins the spawn race; restart verifies and records the replacement'
export ENVPILOT_TEST_REAL_NOHUP="$(command -v nohup)"
export ENVPILOT_TEST_DESKTOP_GATE="$fixture/desktop.gate" ENVPILOT_TEST_DESKTOP_PID="$desktop_pid_file"
mkdir -p "$fixture/shims"
cat > "$fixture/shims/nohup" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [ -f "$ENVPILOT_TEST_DESKTOP_GATE" ]; then
    rm "$ENVPILOT_TEST_DESKTOP_GATE"
    CODEX_INTERNAL_ORIGINATOR_OVERRIDE='Codex Desktop' \
        "$ENVPILOT_CODEX_RUNTIME_DIR/current/bin/codex" -c features.code_mode_host=true app-server --listen unix:// &
    echo "$!" > "$ENVPILOT_TEST_DESKTOP_PID"
    for ((i=0; i<100; i++)); do
        if "$ENVPILOT_CORE" probe --socket "$CODEX_HOME/app-server-control/app-server-control.sock" >/dev/null 2>&1; then break; fi
        sleep 0.05
    done
fi
exec "$ENVPILOT_TEST_REAL_NOHUP" "$@"
EOF
chmod 700 "$fixture/shims/nohup"
touch "$ENVPILOT_TEST_DESKTOP_GATE"
before="$(cat "$pid_file")"
PATH="$fixture/shims:$PATH" bash "$manager" restart
test "$(cat "$pid_file")" != "$before"
test "$(cat "$pid_file")" = "$(cat "$desktop_pid_file")"
"$ENVPILOT_CORE" probe --socket "$socket" | grep -F 'Codex Desktop/' >/dev/null
test "$("$ENVPILOT_CORE" probe --socket "$socket" --format version)" = "$version"
bash "$manager" status | grep -F 'socket: READY' >/dev/null
rm -f "$pid_file" "$pid_file.identity"
bash "$manager" stop
! "$ENVPILOT_CORE" probe --socket "$socket" >/dev/null 2>&1
bash "$manager" ready
bash "$manager" stop
echo "[TEST] real Codex $version passed"
