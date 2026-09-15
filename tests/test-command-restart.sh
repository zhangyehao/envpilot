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
echo '[TEST] restart replaces the matching Desktop server and preserves unrelated servers'
source_dir="$fixture/source"
runtime="/tmp/envpilot-restart-test-$$"
mkdir -p "$source_dir"
export CODEX_HOME="$HOME/.codex" ENVPILOT_CODEX_SOURCE_BIN="$source_dir"
export ENVPILOT_CODEX_RUNTIME_DIR="$runtime" ENVPILOT_CODEX_REMOTE_READY_TIMEOUT=5
export ENVPILOT_TEST_PYTHON="$(command -v python3)"
export ENVPILOT_CORE="$ROOT/bin/envpilot-core"
export ENVPILOT_TEST_SERVER="$ROOT/tests/fake-codex-server.py"
cat > "$source_dir/codex" <<'EOF'
#!/usr/bin/env bash
if [ "${1:-}" = --version ]; then echo "codex-cli ${FAKE_CODEX_VERSION:-0.153.0}"; exit 0; fi
if [ "${2:-}" = daemon ]; then exit 2; fi
exec -a codex "$ENVPILOT_TEST_PYTHON" "$ENVPILOT_TEST_SERVER" app-server --listen unix://
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
bash "$manager" restart
wait "$external" 2>/dev/null || true
! kill -0 "$external" 2>/dev/null
[ -s "$pid_file" ]
other_home="$fixture/other-codex"
CODEX_HOME="$other_home" "$source_dir/codex" app-server --listen unix:// &
external=$!
sleep 1
bash "$manager" restart
kill -0 "$external"
bash "$manager" stop
kill -0 "$external"
bash "$manager" ready
rm -f "$pid_file" "$pid_file.identity"
bash "$manager" stop
! ENVPILOT_CODEX_REMOTE_QUIET=1 bash "$manager" running
# Two simultaneous requests serialize and leave one healthy instance.
bash "$manager" ready &
first=$!
bash "$manager" ready &
second=$!
wait "$first"
wait "$second"
bash "$manager" running
echo '[TEST] updates invalidate runtime and restart repairs a corrupt cache'
before="$(cat "$pid_file")"
sed 's/0.153.0/0.154.0/g' "$source_dir/codex" > "$source_dir/codex.new"
mv "$source_dir/codex.new" "$source_dir/codex"
chmod 700 "$source_dir/codex"
export FAKE_CODEX_VERSION=0.154.0
bash "$manager" ready
[ "$(cat "$pid_file")" != "$before" ]
[ "$("$runtime/current/bin/codex" --version)" = 'codex-cli 0.154.0' ]
before="$(cat "$pid_file")"
printf '#!/bin/sh\nexit 1\n' > "$runtime/current/bin/codex"
bash "$manager" restart
[ "$(cat "$pid_file")" != "$before" ]
[ "$("$runtime/current/bin/codex" --version)" = 'codex-cli 0.154.0' ]
echo '[TEST] an invalid new source preserves the healthy running server'
mkdir -p "$fixture/bad-source"
printf '#!/bin/sh\nexit 1\n' > "$fixture/bad-source/codex"
chmod 700 "$fixture/bad-source/codex"
before="$(cat "$pid_file")"
if ENVPILOT_CODEX_SOURCE_BIN="$fixture/bad-source" bash "$manager" restart; then exit 1; fi
kill -0 "$before"
[ "$(cat "$pid_file")" = "$before" ]
bash "$manager" stop
echo '[TEST] native lifecycle adapter is used when its fixed path matches the runtime'
export FAKE_NATIVE_STATE="$fixture/native"
mkdir -p "$CODEX_HOME/packages/standalone/current"
ln -s "$runtime/current/bin/codex" "$CODEX_HOME/packages/standalone/current/codex"
cat > "$source_dir/codex" <<'EOF'
#!/usr/bin/env bash
if [ "${1:-}" = --version ]; then echo 'codex-cli 0.154.0'; exit 0; fi
if [ "${2:-}" = daemon ]; then
    case "${3:-}" in
        --help) echo 'start stop restart version'; exit 0 ;;
        start)
            echo start >> "$FAKE_NATIVE_STATE.calls"
            nohup "$0" app-server --listen unix:// >/dev/null 2>&1 < /dev/null &
            echo "$!" > "$FAKE_NATIVE_STATE.pid"
            exit 0 ;;
        stop)
            echo stop >> "$FAKE_NATIVE_STATE.calls"
            if [ -f "$FAKE_NATIVE_STATE.pid" ]; then kill -TERM "$(cat "$FAKE_NATIVE_STATE.pid")" 2>/dev/null || true; fi
            exit 0 ;;
    esac
fi
exec -a codex "$ENVPILOT_TEST_PYTHON" "$ENVPILOT_TEST_SERVER" app-server --listen unix://
EOF
chmod 700 "$source_dir/codex"
bash "$manager" ready
bash "$manager" restart
bash "$manager" stop
grep -q '^start$' "$FAKE_NATIVE_STATE.calls"
grep -q '^stop$' "$FAKE_NATIVE_STATE.calls"
test ! -d "$CODEX_HOME/app-server-control/.envpilot-app-server-start.lock"
