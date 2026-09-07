#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT
export HOME="$fixture/home"
export ENVPILOT_ROOT="$ROOT"
mkdir -p "$HOME"
. "$ROOT/lib/common.sh"
. "$ROOT/lib/shell.sh"
ep_init
echo '[TEST] command setup preserves profiles and refuses unrelated commands'
printf 'keep profile\n' > "$HOME/.bashrc"
mkdir -p "$HOME/.local/bin"
printf 'foreign command\n' > "$HOME/.local/bin/envpilot"
if ep_setup_command; then exit 1; fi
grep -qx 'foreign command' "$HOME/.local/bin/envpilot"
rm "$HOME/.local/bin/envpilot"
ep_setup_command
grep -qx 'keep profile' "$HOME/.bashrc"

echo '[TEST] launcher forwards cwd, spaced arguments, exit codes and relocated registration'
repo="$fixture/repo with spaces"
mkdir -p "$repo/lib" "$repo/templates" "$fixture/caller"
cp "$ROOT/templates/envpilot-command.sh" "$repo/templates/"
touch "$repo/lib/common.sh"
cat > "$repo/envpilot.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$PWD" "$@"
exit 23
EOF
ENVPILOT_ROOT="$repo" ep_setup_command
printf '%s\n' "$ROOT" > "$HOME/.config/envpilot/repo-root"
status=0
(cd "$fixture/caller"; bash "$HOME/.local/bin/envpilot" 'a b' '*.txt') > "$fixture/output" || status=$?
[ "$status" = 23 ]
[ "$(sed -n '1p' "$fixture/output")" = "$fixture/caller" ]
[ "$(sed -n '2p' "$fixture/output")" = 'a b' ]
[ "$(sed -n '3p' "$fixture/output")" = '*.txt' ]
mv "$repo" "$fixture/moved repo"
if bash "$HOME/.local/bin/envpilot" help; then exit 1; fi
ENVPILOT_ROOT="$fixture/moved repo" ep_setup_command
status=0
bash "$HOME/.local/bin/envpilot" help > /dev/null || status=$?
[ "$status" = 23 ]

if [ "$(uname -s)" != Linux ]; then
    echo '[TEST] real restart PID/socket integration requires Linux'
    exit 0
fi
echo '[TEST] restart creates a different PID and refuses an external server'
source_dir="$fixture/source"
runtime="/tmp/envpilot-restart-test-$$"
mkdir -p "$source_dir"
export CODEX_HOME="$HOME/.codex" ENVPILOT_CODEX_SOURCE_BIN="$source_dir"
export ENVPILOT_CODEX_RUNTIME_DIR="$runtime" ENVPILOT_CODEX_REMOTE_READY_TIMEOUT=5
export ENVPILOT_TEST_PYTHON="$(command -v python3)"
cat > "$source_dir/codex" <<'EOF'
#!/usr/bin/env bash
if [ "${1:-}" = --version ]; then echo 'codex-cli 0.153.0'; exit 0; fi
exec -a codex "$ENVPILOT_TEST_PYTHON" - "$CODEX_HOME/app-server-control/app-server-control.sock" app-server --listen unix:// <<'PY'
import os, socket, sys, time
path = sys.argv[1]
if os.path.exists(path):
    os.unlink(path)
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
s.bind(path)
s.listen(1)
time.sleep(120)
PY
EOF
chmod 700 "$source_dir/codex"
manager="$ROOT/templates/codex-remote.sh"
external=""
trap 'bash "$manager" stop >/dev/null 2>&1 || true; if [ -n "$external" ]; then kill "$external" 2>/dev/null || true; wait "$external" 2>/dev/null || true; fi; rm -rf "$fixture" "$runtime"' EXIT
bash "$manager" ready
pid_file="$CODEX_HOME/app-server-control/envpilot-app-server.pid"
old="$(cat "$pid_file")"
bash "$manager" restart
new="$(cat "$pid_file")"
[ "$old" != "$new" ]
kill -0 "$new"
! ps -p "$old" -o args= | grep -q 'app-server.*--listen'
bash "$manager" stop
"$source_dir/codex" app-server --listen unix:// &
external=$!
sleep 1
if bash "$manager" restart; then exit 1; fi
kill -0 "$external"
test ! -f "$pid_file"
test ! -d "$CODEX_HOME/app-server-control/.envpilot-app-server-start.lock"
