#!/usr/bin/env bash
# Real cached Mihomo, isolated HOME/controller/runtime, and no Internet requests.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
case "$(uname -s):$(uname -m)" in
    Linux:x86_64|Linux:amd64) ;;
    *) printf '[SKIP] real Mihomo integration requires Linux amd64 and its bundled cache.\n'; exit 0 ;;
esac
for tool in python3 curl gzip timeout; do
    command -v "$tool" >/dev/null 2>&1 || { printf '[ERROR] test dependency missing: %s\n' "$tool" >&2; exit 1; }
done
assets=("$ROOT"/downloads/mihomo-linux-amd64-compatible-*.gz)
[ -f "${assets[0]}" ] || { printf '[ERROR] bundled Linux amd64 Mihomo is missing.\n' >&2; exit 1; }
[ -x "$ROOT/bin/envpilot-core" ] || { printf '[ERROR] build bin/envpilot-core before this test.\n' >&2; exit 1; }
fixture="$(mktemp -d /tmp/envpilot-mihomo-test.XXXXXX)"
USER="$(id -un)"
export HOME="$fixture/home" USER HOSTNAME="envpilot-test-${fixture##*.}"
runtime="/tmp/${USER}_mihomo_${HOSTNAME}"
[ ! -e "$runtime" ] || { printf '[ERROR] test runtime unexpectedly exists: %s\n' "$runtime" >&2; exit 1; }

cleanup() {
    local result=$? process executable pid
    # Match the unique test executable before every signal, never a name-only
    # pgrep/pkill. This also finds a test child whose PID file was removed.
    for process in /proc/[0-9]*/exe; do
        executable="$(readlink "$process" 2>/dev/null || true)"
        case "$executable" in
            "$runtime/mihomo"|"$runtime/mihomo (deleted)")
                pid="${process#/proc/}"; pid="${pid%/exe}"
                kill -TERM "$pid" 2>/dev/null || true
                for ((attempt=0; attempt<30; attempt++)); do
                    kill -0 "$pid" 2>/dev/null || break
                    sleep 0.1
                done
                executable="$(readlink "/proc/$pid/exe" 2>/dev/null || true)"
                case "$executable" in
                    "$runtime/mihomo"|"$runtime/mihomo (deleted)") kill -KILL "$pid" 2>/dev/null || true ;;
                esac
                ;;
        esac
    done
    case "$runtime" in /tmp/*_mihomo_envpilot-test-*) rm -rf -- "$runtime" "$runtime.start.lock" ;; esac
    if [ "$result" != 0 ]; then
        printf '[ERROR] Mihomo integration failed; fixture: %s\n' "$fixture" >&2
    fi
    if [ "${ENVPILOT_TEST_KEEP_FIXTURE:-0}" != 1 ]; then
        case "$fixture" in /tmp/envpilot-mihomo-test.*) rm -rf -- "$fixture" ;; esac
    fi
}
trap cleanup EXIT
umask 077
unset ENVPILOT_CONFIG_FILE ENVPILOT_OVERRIDES ENVPILOT_MIHOMO_SUBSCRIPTION_URL
unset ENVPILOT_SUBSCRIPTION_ENV ENVPILOT_SUBSCRIPTION_FILE ENVPILOT_MIHOMO_IMPORT_FILE ENVPILOT_MIHOMO_SUBSCRIPTION_FILE
unset ENVPILOT_MIHOMO_SUBSCRIPTION_NETWORK EP_NON_INTERACTIVE EP_CONFIG_APPLY EP_PREFIX EP_CONFIG_FILE
unset MIHOMO_SOURCE_CONFIG MIHOMO_FORCE_RESTART ENVPILOT_CORE
export ENVPILOT_CONFIG_DIR="$HOME/.config/envpilot" ENVPILOT_LANG=en ENVPILOT_MODE=offline
export ENVPILOT_PREFIX="$HOME/software" SHELL=/bin/bash
export MIHOMO_RUNTIME_DIR="$runtime" MIHOMO_STARTUP_TIMEOUT=12 MIHOMO_PROXY_HOST=127.0.0.1
# The controller must ignore inherited proxy settings even with authentication.
export http_proxy=http://127.0.0.1:1 https_proxy=http://127.0.0.1:1
export HTTP_PROXY="$http_proxy" HTTPS_PROXY="$https_proxy"
export all_proxy=socks5://127.0.0.1:1 ALL_PROXY=socks5://127.0.0.1:1
export ENVPILOT_TEST_MIHOMO_SECRET='synthetic-controller-secret-do-not-print'
export ENVPILOT_TEST_MIHOMO_GROUP='手动 选择 🚀'
export ENVPILOT_TEST_MIHOMO_NODE='本地 直连 🌙'
mkdir -p "$HOME/software/mihomo" "$HOME/.config/mihomo" "$ENVPILOT_CONFIG_DIR" "$fixture/bin"
# Keep executable files off slow shared/Windows mounts.
cp "$ROOT/bin/envpilot-core" "$fixture/bin/envpilot-core"
chmod 700 "$fixture/bin/envpilot-core"
export ENVPILOT_CORE="$fixture/bin/envpilot-core"
gzip -dc "${assets[${#assets[@]}-1]}" > "$HOME/software/mihomo/mihomo"
chmod 700 "$HOME/software/mihomo/mihomo"

read -r MIHOMO_PROXY_PORT MIHOMO_API_PORT < <(python3 - <<'PY'
import socket
sockets = [socket.socket(), socket.socket()]
for s in sockets:
    s.bind(("127.0.0.1", 0))
print(*(s.getsockname()[1] for s in sockets))
for s in sockets:
    s.close()
PY
)
export MIHOMO_PROXY_PORT MIHOMO_API_PORT
cat > "$ENVPILOT_CONFIG_DIR/config.yaml" <<EOF
version: 1
language: en
install:
  mode: offline
  prefix: "$HOME/software"
mihomo:
  proxy_port: $MIHOMO_PROXY_PORT
  api_port: $MIHOMO_API_PORT
  subscription_network: auto
EOF
cat > "$HOME/.config/mihomo/config.yaml" <<EOF
mixed-port: $MIHOMO_PROXY_PORT
external-controller: 127.0.0.1:$MIHOMO_API_PORT
secret: "$ENVPILOT_TEST_MIHOMO_SECRET"
allow-lan: false
mode: rule
log-level: warning
ipv6: false
geo-auto-update: false
profile:
  store-selected: false
dns:
  enable: false
proxies:
  - name: Unused local fixture
    type: socks5
    server: 127.0.0.1
    port: 9
proxy-groups:
  - name: "$ENVPILOT_TEST_MIHOMO_GROUP"
    type: select
    proxies: [DIRECT, REJECT, "$ENVPILOT_TEST_MIHOMO_NODE"]
  - name: "$ENVPILOT_TEST_MIHOMO_NODE"
    type: select
    proxies: [DIRECT]
rules:
  - MATCH,REJECT
EOF
printf '%s\n' 'https://example.invalid/subscription?token=synthetic-protected-reference' > "$HOME/.config/mihomo/subscription.url"
cp "$HOME/.config/mihomo/subscription.url" "$fixture/original-subscription"
cp "$HOME/.config/mihomo/config.yaml" "$fixture/original.yaml"

ep() { timeout -k 2 45 bash "$ROOT/envpilot.sh" "$@"; }
expect_failure() {
    local log="$1" code="$2" result=0
    shift 2
    timeout -k 1 8 bash "$ROOT/envpilot.sh" "$@" </dev/null > "$log" 2>&1 || result=$?
    [ "$result" -ne 0 ] && [ "$result" -ne 124 ] && [ "$result" -ne 137 ] || {
        printf '[ERROR] expected timely failure: %s\n' "$*" >&2; return 1;
    }
    grep -F "$code" "$log" >/dev/null
}
assert_selection() {
    python3 - "$1" <<'PY'
import json, os, sys, urllib.parse, urllib.request
opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
group = urllib.parse.quote(os.environ["ENVPILOT_TEST_MIHOMO_GROUP"], safe="")
request = urllib.request.Request(
    "http://127.0.0.1:" + os.environ["MIHOMO_API_PORT"] + "/proxies/" + group,
    headers={"Authorization": "Bearer " + os.environ["ENVPILOT_TEST_MIHOMO_SECRET"]})
with opener.open(request, timeout=4) as response:
    actual = json.load(response)["now"]
assert actual == sys.argv[1], (actual, sys.argv[1])
PY
}
assert_state() {
    python3 - "$1" <<'PY'
import json, os, pathlib, stat, sys
paths = list((pathlib.Path(os.environ["ENVPILOT_CONFIG_DIR"]) / "mihomo-selections").glob("*.json"))
assert len(paths) == 1, paths
data = paths[0].read_text(encoding="utf-8")
state = json.loads(data)
assert state["selections"][os.environ["ENVPILOT_TEST_MIHOMO_GROUP"]] == sys.argv[1]
assert state["api_port"] == int(os.environ["MIHOMO_API_PORT"])
assert stat.S_IMODE(paths[0].stat().st_mode) == 0o600
assert os.environ["ENVPILOT_TEST_MIHOMO_SECRET"] not in data
PY
}

printf '[TEST] offline listing and non-interactive input validation\n'
ep mihomo nodes --json > "$fixture/offline.json"
python3 - "$fixture/offline.json" <<'PY'
import json, os, sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
assert data["running"] is False
assert data["source"] == "configuration"
assert any(g["name"] == os.environ["ENVPILOT_TEST_MIHOMO_GROUP"] for g in data["groups"])
PY
expect_failure "$fixture/noninteractive.log" E_INPUT_REQUIRED mihomo select --non-interactive
expect_failure "$fixture/json-input.log" E_INPUT_REQUIRED mihomo select --json

printf '[TEST] real engine, authenticated controller, Unicode names and JSON selection\n'
ep mihomo start > "$fixture/start.log" 2>&1
first_pid="$(cat "$runtime/mihomo.pid")"
python3 - <<'PY'
import os, urllib.error, urllib.request
opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
try:
    opener.open("http://127.0.0.1:" + os.environ["MIHOMO_API_PORT"] + "/version", timeout=4)
except urllib.error.HTTPError as e:
    assert e.code == 401, e.code
else:
    raise AssertionError("controller fixture unexpectedly accepted an unauthenticated request")
PY
ep mihomo nodes "$ENVPILOT_TEST_MIHOMO_GROUP" --json > "$fixture/online.json"
python3 - "$fixture/online.json" <<'PY'
import json, os, sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
assert data["running"] is True
assert len(data["groups"]) == 1
group = data["groups"][0]
assert group["name"] == os.environ["ENVPILOT_TEST_MIHOMO_GROUP"]
assert group["all"] == ["DIRECT", "REJECT", os.environ["ENVPILOT_TEST_MIHOMO_NODE"]]
PY
ep mihomo select --non-interactive --json -- "$ENVPILOT_TEST_MIHOMO_GROUP" REJECT > "$fixture/selected.json"
python3 - "$fixture/selected.json" <<'PY'
import json, os, sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
assert data == {"group": os.environ["ENVPILOT_TEST_MIHOMO_GROUP"], "node": "REJECT"}
PY
assert_selection REJECT
assert_state REJECT

printf '[TEST] interactive numbered selection through a real terminal\n'
python3 - "$ROOT/envpilot.sh" "$fixture/interactive.log" <<'PY'
import errno, json, os, pathlib, pty, select, signal, subprocess, sys, time, urllib.request
opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
request = urllib.request.Request(
    "http://127.0.0.1:" + os.environ["MIHOMO_API_PORT"] + "/proxies",
    headers={"Authorization": "Bearer " + os.environ["ENVPILOT_TEST_MIHOMO_SECRET"]})
with opener.open(request, timeout=4) as response:
    proxies = json.load(response)["proxies"]
groups = sorted(name for name, value in proxies.items() if value["type"] == "Selector" and name != "GLOBAL")
target = os.environ["ENVPILOT_TEST_MIHOMO_GROUP"]
answers = f"{groups.index(target)+1}\n3\n" if len(groups) > 1 else "3\n"
master, slave = pty.openpty()
environment = dict(os.environ)
environment.pop("EP_NON_INTERACTIVE", None)
process = subprocess.Popen(["bash", sys.argv[1], "mihomo", "select", "--lang", "en"],
    stdin=slave, stdout=slave, stderr=slave, env=environment, start_new_session=True)
os.close(slave)
output = bytearray()
sent = False
try:
    deadline = time.monotonic() + 12
    while time.monotonic() < deadline:
        ready, _, _ = select.select([master], [], [], 0.1)
        if ready:
            try:
                chunk = os.read(master, 65536)
            except OSError as e:
                if e.errno == errno.EIO:
                    break
                raise
            if not chunk:
                break
            output.extend(chunk)
            if not sent and b"> " in output:
                os.write(master, answers.encode())
                sent = True
        if process.poll() is not None and not ready:
            break
    assert process.wait(timeout=2) == 0
    assert sent and b"Selected and saved" in output
finally:
    if process.poll() is None:
        os.killpg(process.pid, signal.SIGKILL)
        process.wait()
    os.close(master)
    pathlib.Path(sys.argv[2]).write_bytes(output)
PY
assert_selection "$ENVPILOT_TEST_MIHOMO_NODE"
assert_state "$ENVPILOT_TEST_MIHOMO_NODE"

printf '[TEST] restart and stop/start preserve selections without Mihomo cache.db\n'
ep mihomo restart > "$fixture/restart.log" 2>&1
[ "$(cat "$runtime/mihomo.pid")" != "$first_pid" ]
assert_selection "$ENVPILOT_TEST_MIHOMO_NODE"
ep mihomo stop > "$fixture/stop.log" 2>&1
[ ! -e "$runtime/mihomo.pid" ]
ep mihomo nodes --json > "$fixture/stopped.json"
python3 - "$fixture/stopped.json" <<'PY'
import json, sys
assert json.load(open(sys.argv[1], encoding="utf-8"))["running"] is False
PY
ep mihomo start > "$fixture/start-again.log" 2>&1
assert_selection "$ENVPILOT_TEST_MIHOMO_NODE"

printf '[TEST] valid offline import preserves a stopped service and subscription reference\n'
ep mihomo stop > "$fixture/before-import.log" 2>&1
sed 's/log-level: warning/log-level: error/' "$fixture/original.yaml" > "$fixture/import.yaml"
ep mihomo update-subscription --file "$fixture/import.yaml" --non-interactive > "$fixture/import-stopped.log" 2>&1
[ ! -e "$runtime/mihomo.pid" ]
grep -F 'log-level: error' "$HOME/.config/mihomo/config.yaml" >/dev/null
cmp "$HOME/.config/mihomo/subscription.url" "$fixture/original-subscription"
ep mihomo nodes --json > "$fixture/import-stopped.json"
python3 - "$fixture/import-stopped.json" <<'PY'
import json, sys
assert json.load(open(sys.argv[1], encoding="utf-8"))["running"] is False
PY
ep mihomo start > "$fixture/import-start.log" 2>&1
assert_selection "$ENVPILOT_TEST_MIHOMO_NODE"
before_pid="$(cat "$runtime/mihomo.pid")"
ep mihomo update-subscription --file "$fixture/original.yaml" --non-interactive > "$fixture/import-running.log" 2>&1
[ "$(cat "$runtime/mihomo.pid")" != "$before_pid" ]
assert_selection "$ENVPILOT_TEST_MIHOMO_NODE"
cmp "$HOME/.config/mihomo/subscription.url" "$fixture/original-subscription"

printf '[TEST] semantic and YAML failures leave the working configuration and PID unchanged\n'
before_pid="$(cat "$runtime/mihomo.pid")"
cp "$HOME/.config/mihomo/config.yaml" "$fixture/before-invalid.yaml"
cat > "$fixture/invalid.yaml" <<'EOF'
proxies:
  - name: Unused local fixture
    type: socks5
    server: 127.0.0.1
    port: 9
proxy-groups:
  - name: Broken Group
    type: select
    proxies: [This node does not exist]
rules:
  - MATCH,REJECT
EOF
expect_failure "$fixture/invalid.log" E_MIHOMO_CONFIG mihomo update-subscription --file "$fixture/invalid.yaml" --non-interactive
cmp "$HOME/.config/mihomo/config.yaml" "$fixture/before-invalid.yaml"
[ "$(cat "$runtime/mihomo.pid")" = "$before_pid" ]
assert_selection "$ENVPILOT_TEST_MIHOMO_NODE"
printf '<html>synthetic failed subscription response</html>\n' > "$fixture/html.yaml"
expect_failure "$fixture/html.log" E_SUBSCRIPTION mihomo update-subscription --file "$fixture/html.yaml" --non-interactive
cmp "$HOME/.config/mihomo/config.yaml" "$fixture/before-invalid.yaml"
[ "$(cat "$runtime/mihomo.pid")" = "$before_pid" ]

printf '[TEST] removed node reports an unrestored choice without guessing a replacement\n'
python3 - "$fixture/original.yaml" "$fixture/renamed.yaml" <<'PY'
import os, pathlib, sys
data = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
pathlib.Path(sys.argv[2]).write_text(data.replace(os.environ["ENVPILOT_TEST_MIHOMO_NODE"], "本地 新名称 🌙"), encoding="utf-8")
PY
ep mihomo update-subscription --file "$fixture/renamed.yaml" --non-interactive > "$fixture/renamed.log" 2>&1
grep -F 'Saved group/node is missing' "$fixture/renamed.log" >/dev/null
assert_selection DIRECT
assert_state "$ENVPILOT_TEST_MIHOMO_NODE"
expect_failure "$fixture/old-node.log" E_MIHOMO_NODE mihomo select "$ENVPILOT_TEST_MIHOMO_GROUP" "$ENVPILOT_TEST_MIHOMO_NODE" --non-interactive
assert_selection DIRECT
ep mihomo select "$ENVPILOT_TEST_MIHOMO_GROUP" '本地 新名称 🌙' --non-interactive --json > "$fixture/new-node.json"
assert_selection '本地 新名称 🌙'
assert_state '本地 新名称 🌙'

printf '[TEST] a rejected probe never contacts the Internet or changes the selection\n'
result=0
ep mihomo test "$ENVPILOT_TEST_MIHOMO_GROUP" REJECT --json > "$fixture/probe.json" 2> "$fixture/probe.log" || result=$?
[ "$result" -eq 1 ]
grep -F E_MIHOMO_TEST_FAILED "$fixture/probe.log" >/dev/null
python3 - "$fixture/probe.json" <<'PY'
import json, sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
assert len(data["results"]) == 1
assert data["results"][0]["node"] == "REJECT"
assert data["results"][0]["ok"] is False
PY
assert_selection '本地 新名称 🌙'
python3 - "$fixture" <<'PY'
import os, pathlib, sys
root = pathlib.Path(sys.argv[1])
for path in [*root.glob("*.log"), *root.glob("*.json")]:
    data = path.read_text(encoding="utf-8", errors="replace")
    assert os.environ["ENVPILOT_TEST_MIHOMO_SECRET"] not in data, path
    assert "synthetic-protected-reference" not in data, path
PY
ep mihomo stop > "$fixture/final-stop.log" 2>&1
printf '[TEST] real Mihomo selection, persistence, protected controller and offline import passed\n'
