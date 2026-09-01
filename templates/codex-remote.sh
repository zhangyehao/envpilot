#!/usr/bin/env bash

# envpilot Codex remote runtime manager.
# Keep this script self-contained: it is copied to ~/.local/bin so a remote
# SSH bootstrap does not depend on the envpilot checkout being available.
set -euo pipefail
umask 077

CODEX_HOME_DIR="${CODEX_HOME:-$HOME/.codex}"
CONTROL_DIR="$CODEX_HOME_DIR/app-server-control"
SOCKET="$CONTROL_DIR/app-server-control.sock"
PID_FILE="$CONTROL_DIR/envpilot-app-server.pid"
SERVER_LOG="$CONTROL_DIR/app-server.log"
READY_TIMEOUT="${ENVPILOT_CODEX_REMOTE_READY_TIMEOUT:-60}"
RUNTIME_ROOT="${ENVPILOT_CODEX_RUNTIME_DIR:-}"
QUIET="${ENVPILOT_CODEX_REMOTE_QUIET:-0}"
SECRETS_FILE="${ENVPILOT_CODEX_SECRETS_FILE:-$HOME/.config/secrets/api.env}"
LOAD_SECRETS="${ENVPILOT_CODEX_LOAD_SECRETS:-${ENVPILOT_CODEX_LOAD_API_KEY:-1}}"

safe_component()
{
    case "${1:-}" in
        ''|*[!A-Za-z0-9_.-]*|*..*) return 1 ;;
        *) return 0 ;;
    esac
}

current_user()
{
    printf '%s' "${USER:-$(id -un 2>/dev/null || printf unknown)}"
}

current_host()
{
    printf '%s' "${HOSTNAME:-$(hostname 2>/dev/null || printf unknown)}"
}

if [ -z "$RUNTIME_ROOT" ]; then
    runtime_user="$(current_user)"
    runtime_host="$(current_host)"
    safe_component "$runtime_user" || runtime_user="user"
    safe_component "$runtime_host" || runtime_host="host"
    RUNTIME_ROOT="/tmp/${runtime_user}-envpilot-codex-${runtime_host}"
fi

log()
{
    [ "$QUIET" = "1" ] && return 0
    printf '[envpilot-codex] %s\n' "$*" >&2
}

warn()
{
    printf '[envpilot-codex] WARNING: %s\n' "$*" >&2
}

die()
{
    printf '[envpilot-codex] ERROR: %s\n' "$*" >&2
    exit 1
}

command_exists()
{
    command -v "$1" >/dev/null 2>&1
}

secret_file_mode()
{
    stat -c '%a' "$1" 2>/dev/null || stat -f '%Lp' "$1" 2>/dev/null || true
}

secret_file_is_safe()
{
    local secret_file="$1" mode owner current
    [ -f "$secret_file" ] || return 1
    current="$(id -u)"
    owner="$(stat -c '%u' "$secret_file" 2>/dev/null || stat -f '%u' "$secret_file" 2>/dev/null || printf '%s' "$current")"
    [ "$owner" = "$current" ] || return 1
    mode="$(secret_file_mode "$secret_file")"
    case "$mode" in
        400|600) return 0 ;;
        *) return 1 ;;
    esac
}

load_codex_environment()
{
    local allexport_was_set=0 status=0
    local openai_was_set="${OPENAI_API_KEY+x}" openai_value="${OPENAI_API_KEY:-}"
    [ "$LOAD_SECRETS" = "1" ] || return 0
    secret_file_is_safe "$SECRETS_FILE" || return 0
    case $- in
        *a*) allexport_was_set=1 ;;
        *) set -a ;;
    esac
    # The user-owned file is loaded only after ownership and mode checks.
    # shellcheck disable=SC1090
    . "$SECRETS_FILE" >/dev/null 2>&1 || status=$?
    [ "$allexport_was_set" = "1" ] || set +a
    if [ -n "$openai_was_set" ]; then
        export OPENAI_API_KEY="$openai_value"
    fi
    return "$status"
}

validate_runtime_root()
{
    case "$RUNTIME_ROOT" in
        /tmp/*|"$HOME"/*) ;;
        *) die "ENVPILOT_CODEX_RUNTIME_DIR must be under /tmp or HOME: $RUNTIME_ROOT" ;;
    esac
}

ensure_runtime_root()
{
    validate_runtime_root
    mkdir -p "$RUNTIME_ROOT"
    chmod 700 "$RUNTIME_ROOT" 2>/dev/null || true
}

local_current_dir()
{
    printf '%s/current' "$RUNTIME_ROOT"
}

local_bin()
{
    printf '%s/current/bin/codex' "$RUNTIME_ROOT"
}

signature_file()
{
    printf '%s/current/.source.signature' "$RUNTIME_ROOT"
}

stage_lock_dir()
{
    printf '%s/.stage.lock' "$RUNTIME_ROOT"
}

resolve_link()
{
    local path="$1"
    local target dir base
    if command_exists readlink; then
        target="$(readlink -f "$path" 2>/dev/null || true)"
        [ -n "$target" ] && {
            printf '%s' "$target"
            return 0
        }
    fi
    while [ -L "$path" ]; do
        target="$(readlink "$path" 2>/dev/null || true)"
        [ -n "$target" ] || break
        case "$target" in
            /*) path="$target" ;;
            *) path="$(dirname "$path")/$target" ;;
        esac
    done
    dir="$(cd -P "$(dirname "$path")" 2>/dev/null && pwd -P)" || return 1
    base="$(basename "$path")"
    printf '%s/%s' "$dir" "$base"
}

managed_wrapper()
{
    [ -f "$1" ] && grep -q 'envpilot-managed-codex-wrapper' "$1" 2>/dev/null
}

source_bin()
{
    local candidate resolved releases

    if [ -n "${ENVPILOT_CODEX_SOURCE_BIN:-}" ]; then
        candidate="$ENVPILOT_CODEX_SOURCE_BIN/codex"
        [ -x "$candidate" ] && printf '%s' "$ENVPILOT_CODEX_SOURCE_BIN" && return 0
    fi

    candidate="$CODEX_HOME_DIR/packages/standalone/current/bin/codex"
    if [ -x "$candidate" ]; then
        printf '%s' "$(dirname "$candidate")"
        return 0
    fi

    releases="$CODEX_HOME_DIR/packages/standalone/releases"
    if [ -d "$releases" ]; then
        candidate="$(find "$releases" -type f -name codex -print 2>/dev/null | sort -r | head -n 1 || true)"
        if [ -n "$candidate" ] && [ -x "$candidate" ]; then
            printf '%s' "$(dirname "$candidate")"
            return 0
        fi
    fi

    candidate="$(command -v codex 2>/dev/null || true)"
    if [ -n "$candidate" ] && [ -x "$candidate" ] && ! managed_wrapper "$candidate"; then
        resolved="$(resolve_link "$candidate" 2>/dev/null || true)"
        [ -n "$resolved" ] && candidate="$resolved"
        [ -x "$candidate" ] && printf '%s' "$(dirname "$candidate")" && return 0
    fi

    return 1
}

source_signature()
{
    local bin="$1"
    local file="$bin/codex"
    local metadata
    [ -x "$file" ] || return 1
    metadata="$(stat -c '%s|%Y|%i' "$file" 2>/dev/null || stat -f '%z|%m|%i' "$file" 2>/dev/null || true)"
    [ -n "$metadata" ] || return 1
    printf '%s|%s' "$bin" "$metadata"
}

kill_process_tree()
{
    local pid="${1:-}" child
    case "$pid" in
        ''|*[!0-9]*) return 0 ;;
    esac
    if command_exists pgrep; then
        while IFS= read -r child; do
            [ -n "$child" ] || continue
            kill_process_tree "$child"
        done < <(pgrep -P "$pid" 2>/dev/null || true)
    elif command_exists pkill; then
        pkill -TERM -P "$pid" 2>/dev/null || true
    fi
    kill -TERM "$pid" 2>/dev/null || true
    sleep 0.1
    kill -KILL "$pid" 2>/dev/null || true
}

run_bounded()
{
    local seconds="$1"
    shift
    if command_exists timeout; then
        timeout -k 1 "$seconds" "$@"
    elif command_exists gtimeout; then
        gtimeout -k 1 "$seconds" "$@"
    elif command_exists perl; then
        perl -e 'alarm shift; exec @ARGV' "$seconds" "$@"
    else
        local output_file pid elapsed=0 status
        output_file="$(mktemp "${TMPDIR:-/tmp}/envpilot-codex-probe.XXXXXX")" || {
            "$@"
            return
        }
        ("$@" >"$output_file" 2>&1) &
        pid=$!
        while kill -0 "$pid" 2>/dev/null; do
            if [ "$elapsed" -ge "$seconds" ]; then
                kill_process_tree "$pid"
                wait "$pid" 2>/dev/null || true
                cat "$output_file"
                rm -f "$output_file"
                return 124
            fi
            sleep 1
            elapsed=$((elapsed + 1))
        done
        status=0
        wait "$pid" || status=$?
        cat "$output_file"
        rm -f "$output_file"
        return "$status"
    fi
}

local_version()
{
    local output version
    output="$(run_bounded 5 "$(local_bin)" --version 2>&1 || true)"
    version="$(printf '%s\n' "$output" | sed -n '/^codex-cli[[:space:]]/{p;q;}')"
    if [ -n "$version" ]; then
        printf '%s\n' "$version"
    else
        printf '%s\n' "$output" | sed -n '1p'
    fi
}

ensure_control_dir()
{
    if [ -L "$CONTROL_DIR" ]; then
        die "Codex control directory must stay on persistent storage; refusing symlink: $CONTROL_DIR"
    fi
    mkdir -p "$CONTROL_DIR"
    chmod 700 "$CONTROL_DIR" 2>/dev/null || true
}

socket_listener_state()
{
    # 0 = known absent, 1 = found, 2 = cannot inspect.
    local line
    if command_exists ss; then
        line="$(ss -xlpn 2>/dev/null | grep -F "$SOCKET" | head -n 1 || true)"
        [ -n "$line" ] && return 1
        return 0
    fi
    if command_exists lsof; then
        line="$(run_bounded 2 lsof -nP -U 2>/dev/null | grep -F "$SOCKET" | head -n 1 || true)"
        [ -n "$line" ] && return 1
        return 0
    fi
    return 2
}

socket_ready()
{
    local state=0
    [ -S "$SOCKET" ] || return 1
    socket_listener_state || state=$?
    case "$state" in
        0) return 1 ;;
        1|2) return 0 ;;
    esac
}

pid_is_server()
{
    local pid="$1"
    local args
    case "$pid" in
        ''|*[!0-9]*) return 1 ;;
    esac
    kill -0 "$pid" 2>/dev/null || return 1
    args="$(ps -p "$pid" -o args= 2>/dev/null || true)"
    case "$args" in
        *app-server*) return 0 ;;
        *) return 1 ;;
    esac
}

read_server_pid()
{
    local pid
    [ -r "$PID_FILE" ] || return 1
    pid="$(sed -n '1p' "$PID_FILE" 2>/dev/null || true)"
    pid_is_server "$pid" || return 1
    printf '%s' "$pid"
}

acquire_stage_lock()
{
    local lock attempts=0 lock_pid
    lock="$(stage_lock_dir)"
    ensure_runtime_root
    while ! mkdir "$lock" 2>/dev/null; do
        attempts=$((attempts + 1))
        if [ "$attempts" -ge 300 ]; then
            lock_pid="$(cat "$lock/pid" 2>/dev/null || true)"
            if [ -n "$lock_pid" ] && ! kill -0 "$lock_pid" 2>/dev/null; then
                rm -rf "$lock"
                attempts=0
                continue
            fi
            die "Timed out waiting for Codex runtime staging lock: $lock"
        fi
        sleep 0.1
    done
    printf '%s\n' "$$" > "$lock/pid"
}

release_stage_lock()
{
    rm -rf "$(stage_lock_dir)"
}

stage_runtime()
{
    local force="${1:-0}"
    local source signature current existing staged previous

    ensure_runtime_root
    acquire_stage_lock
    trap release_stage_lock EXIT

    source="$(source_bin 2>/dev/null || true)"
    if [ -z "$source" ]; then
        existing="$(local_bin)"
        if [ -x "$existing" ] && [ -f "$(signature_file)" ]; then
            log "Persistent source is unavailable; using the existing node-local Codex runtime."
            trap - EXIT
            release_stage_lock
            return 0
        fi
        trap - EXIT
        release_stage_lock
        die "No persistent Codex executable was found under $CODEX_HOME_DIR/packages/standalone or PATH."
    fi
    signature="$(source_signature "$source" || true)"
    [ -n "$signature" ] || {
        trap - EXIT
        release_stage_lock
        die "Codex source is not executable: $source/codex"
    }

    current="$(local_current_dir)"
    if [ "$force" != "1" ] && [ -x "$(local_bin)" ] && [ -f "$(signature_file)" ] &&
        [ "$(cat "$(signature_file)")" = "$signature" ]; then
        trap - EXIT
        release_stage_lock
        return 0
    fi

    staged="$RUNTIME_ROOT/.staging.$$"
    previous="$RUNTIME_ROOT/.previous.$$"
    rm -rf "$staged" "$previous"
    mkdir -p "$staged/bin"
    chmod 700 "$staged" "$staged/bin" 2>/dev/null || true
    log "Staging Codex runtime from $source to $RUNTIME_ROOT"
    cp -a "$source/." "$staged/bin/"
    [ -x "$staged/bin/codex" ] || {
        rm -rf "$staged"
        trap - EXIT
        release_stage_lock
        die "Staged Codex runtime has no executable bin/codex."
    }
    printf '%s\n' "$signature" > "$staged/.source.signature"
    if [ -e "$current" ] || [ -L "$current" ]; then
        mv "$current" "$previous"
    fi
    mv "$staged" "$current"
    rm -rf "$previous"
    trap - EXIT
    release_stage_lock
}

wait_for_socket()
{
    local pid="${1:-}" i=0 max
    max=$((READY_TIMEOUT * 5))
    while [ "$i" -lt "$max" ]; do
        if socket_ready; then
            printf '%s\n' "$(date '+%F %T')" > "$CONTROL_DIR/envpilot-app-server.ready"
            return 0
        fi
        if [ -n "$pid" ] && ! pid_is_server "$pid"; then
            return 1
        fi
        sleep 0.2
        i=$((i + 1))
    done
    return 1
}

start_server()
{
    local pid existing_state=0
    ensure_control_dir
    stage_runtime 0

    if socket_ready; then
        log "Codex app-server is already ready: $SOCKET"
        return 0
    fi
    pid="$(read_server_pid 2>/dev/null || true)"
    if [ -n "$pid" ]; then
        if wait_for_socket "$pid"; then
            log "Codex app-server became ready: $SOCKET"
            return 0
        fi
        rm -f "$PID_FILE"
    fi

    if [ -S "$SOCKET" ]; then
        socket_listener_state || existing_state=$?
        if [ "$existing_state" = "1" ]; then
            log "Reusing an existing Codex app-server on $SOCKET"
            return 0
        fi
        if [ "$existing_state" = "0" ]; then
            rm -f "$SOCKET"
        else
            log "Cannot inspect the Unix socket listener; preserving the existing socket."
            return 0
        fi
    fi

    rm -f "$CONTROL_DIR/envpilot-app-server.ready"
    log "Starting Codex app-server; cold start may take several seconds."
    load_codex_environment || true
    nohup env CODEX_HOME="$CODEX_HOME_DIR" "$(local_bin)" \
        -c features.code_mode_host=true app-server --listen unix:// \
        >>"$SERVER_LOG" 2>&1 < /dev/null &
    pid=$!
    printf '%s\n' "$pid" > "$PID_FILE"
    if wait_for_socket "$pid"; then
        log "Codex app-server is ready: $SOCKET"
        return 0
    fi
    rm -f "$PID_FILE"
    warn "Codex app-server did not become ready within ${READY_TIMEOUT}s."
    if [ -f "$SERVER_LOG" ]; then
        tail -n 30 "$SERVER_LOG" >&2 || true
    fi
    return 1
}

stop_server()
{
    local pid i=0
    pid="$(sed -n '1p' "$PID_FILE" 2>/dev/null || true)"
    if ! pid_is_server "$pid"; then
        rm -f "$PID_FILE"
        printf '%s\n' 'No envpilot-managed Codex app-server is running.'
        return 0
    fi
    kill -TERM "$pid" 2>/dev/null || true
    while pid_is_server "$pid" && [ "$i" -lt 50 ]; do
        sleep 0.1
        i=$((i + 1))
    done
    if pid_is_server "$pid"; then
        kill -KILL "$pid" 2>/dev/null || true
    fi
    rm -f "$PID_FILE" "$CONTROL_DIR/envpilot-app-server.ready"
    printf 'Stopped envpilot-managed Codex app-server: %s\n' "$pid"
}

repair_runtime()
{
    local state=0
    stop_server >/dev/null
    if [ -S "$SOCKET" ]; then
        socket_listener_state || state=$?
        [ "$state" = "0" ] && rm -f "$SOCKET"
    fi
    rm -rf "$(local_current_dir)"
    start_server
}

clean_runtime()
{
    ensure_runtime_root
    rm -rf "$(local_current_dir)" "$RUNTIME_ROOT/.staging.$$" "$RUNTIME_ROOT/.previous.$$"
    printf 'Removed node-local Codex runtime: %s\n' "$RUNTIME_ROOT"
}

status_report()
{
    local source="" version="" pid="" wrapper="$HOME/.local/bin/codex"
    source="$(source_bin 2>/dev/null || true)"
    printf 'Persistent source:\n'
    if [ -n "$source" ]; then printf '  %s\n' "$source"; else printf '  not found\n'; fi
    printf 'Local runtime:\n  %s\n' "$RUNTIME_ROOT"
    if [ -x "$(local_bin)" ]; then
        version="$(local_version)"
        printf '  %s (%s)\n' "$(local_bin)" "${version:-probe failed}"
    else
        printf '  not staged\n'
    fi
    printf 'Wrapper:\n'
    if managed_wrapper "$wrapper"; then printf '  enabled: %s\n' "$wrapper"; else printf '  not enabled\n'; fi
    printf 'Control directory:\n  %s\n' "$CONTROL_DIR"
    if [ -L "$CONTROL_DIR" ]; then
        printf '  ERROR: symlink; keep this directory on persistent storage\n'
    elif [ -S "$SOCKET" ] && socket_ready; then
        printf '  socket: READY (%s)\n' "$SOCKET"
    else
        printf '  socket: NOT READY (%s)\n' "$SOCKET"
    fi
    pid="$(read_server_pid 2>/dev/null || true)"
    if [ -n "$pid" ]; then printf 'App-server:\n  managed PID %s\n' "$pid"; else printf 'App-server:\n  not managed by envpilot\n'; fi
    printf 'Protected environment injection:\n'
    if [ "$LOAD_SECRETS" != "1" ]; then
        printf '  disabled by ENVPILOT_CODEX_LOAD_SECRETS=%s\n' "$LOAD_SECRETS"
    elif secret_file_is_safe "$SECRETS_FILE"; then
        printf '  ready from protected %s (all variables)\n' "$SECRETS_FILE"
    else
        if [ -e "$SECRETS_FILE" ]; then
            printf '  unavailable: file must belong to the current user and use mode 600 or 400: %s\n' "$SECRETS_FILE"
        else
            printf '  unavailable: %s not found\n' "$SECRETS_FILE"
        fi
    fi
    if [ -n "${OPENAI_API_KEY:-}" ]; then
        printf '  OPENAI_API_KEY: present in current environment\n'
    fi
}

exec_codex()
{
    QUIET=1
    stage_runtime 0
    load_codex_environment || true
    exec "$(local_bin)" "$@"
}

plan_report()
{
    local source
    source="$(source_bin 2>/dev/null || true)"
    printf 'Persistent source: %s\n' "${source:-not found}"
    printf 'Local runtime: %s\n' "$RUNTIME_ROOT"
    printf 'Control directory: %s\n' "$CONTROL_DIR"
    printf 'Codex secret file: %s (load-all=%s)\n' "$SECRETS_FILE" "$LOAD_SECRETS"
}

action="${1:-status}"
shift || true
case "$action" in
    source)
        source_bin
        ;;
    plan)
        plan_report
        ;;
    stage|prepare)
        stage_runtime 0
        ;;
    warm|ready)
        start_server
        ;;
    status)
        status_report
        ;;
    stop)
        stop_server
        ;;
    repair)
        repair_runtime
        ;;
    clean)
        clean_runtime
        ;;
    exec)
        exec_codex "$@"
        ;;
    help|-h|--help)
        cat <<'EOF'
Usage: codex-remote {status|stage|ready|warm|stop|repair|exec [ARGS...]}
EOF
        ;;
    *)
        die "Unknown Codex remote action: $action"
        ;;
esac
