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
START_LOCK="$CONTROL_DIR/.envpilot-app-server-start.lock"
READY_TIMEOUT="${ENVPILOT_CODEX_REMOTE_READY_TIMEOUT:-60}"
RUNTIME_ROOT="${ENVPILOT_CODEX_RUNTIME_DIR:-}"
QUIET="${ENVPILOT_CODEX_REMOTE_QUIET:-0}"
CORE_BIN="${ENVPILOT_CORE:-$HOME/.local/lib/envpilot/0.4.1/envpilot-core}"
SOURCE_RECORD="${ENVPILOT_CONFIG_DIR:-$HOME/.config/envpilot}/codex-source"
if [ -z "${ENVPILOT_CORE:-}" ] && [ -r "${ENVPILOT_CONFIG_DIR:-$HOME/.config/envpilot}/core-path" ]; then
    IFS= read -r CORE_BIN < "${ENVPILOT_CONFIG_DIR:-$HOME/.config/envpilot}/core-path" || true
fi
SECRETS_FILE="${ENVPILOT_CODEX_SECRETS_FILE:-$HOME/.config/secrets/api.env}"
LOAD_SECRETS="${ENVPILOT_CODEX_LOAD_SECRETS:-${ENVPILOT_CODEX_LOAD_API_KEY:-1}}"
MANAGER_LANGUAGE="${ENVPILOT_LANG:-auto}"
if [ "$MANAGER_LANGUAGE" = auto ]; then MANAGER_LANGUAGE="${LC_ALL:-${LC_MESSAGES:-${LANG:-en}}}"; fi

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
    runtime_home_id="$(printf '%s' "$CODEX_HOME_DIR" | cksum | awk '{print $1}')"
    RUNTIME_ROOT="/tmp/${runtime_user}-envpilot-codex-${runtime_host}-${runtime_home_id}"
fi

translate_message()
{
    case "$MANAGER_LANGUAGE" in
        zh*) if [ -x "$CORE_BIN" ]; then printf '%s' "$*" | "$CORE_BIN" message --lang zh-CN; return; fi ;;
    esac
    printf '%s' "$*"
}

log()
{
    [ "$QUIET" = "1" ] && return 0
    printf '[envpilot-codex] %s\n' "$(translate_message "$*")" >&2
}

warn()
{
    printf '[envpilot-codex] WARNING: %s\n' "$(translate_message "$*")" >&2
}

die()
{
    printf '[envpilot-codex] ERROR: %s\n' "$(translate_message "$*")" >&2
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
    local safe_file="" key_env="" key_file=""
    if [ "$LOAD_SECRETS" = 1 ]; then
        if secret_file_is_safe "$SECRETS_FILE"; then safe_file="$SECRETS_FILE"; fi
        key_env="${ENVPILOT_API_KEY_ENV:-}"
        key_file="${ENVPILOT_API_KEY_FILE:-}"
    fi
    __envpilot_exec_args=("$CORE_BIN" exec-with-env --env-file "$safe_file" --key-env "$key_env" --key-file "$key_file" --target "$(local_bin)")
}

validate_runtime_root()
{
    local physical_home physical_tmp
    physical_home="$(cd -P "$HOME" 2>/dev/null && pwd)"
    physical_tmp="$(cd -P /tmp 2>/dev/null && pwd)"
    case "$RUNTIME_ROOT" in *'/../'*|*/..|*/.|/tmp|"$HOME"|/)
        die "Unsafe Codex runtime directory: $RUNTIME_ROOT" ;;
    esac
    [ ! -L "$RUNTIME_ROOT" ] || die "Codex runtime root must not be a symlink: $RUNTIME_ROOT"
    case "$RUNTIME_ROOT" in
        /tmp/*|"$HOME"/*|"$physical_home"/*|"$physical_tmp"/*) ;;
        *) die "ENVPILOT_CODEX_RUNTIME_DIR must be under /tmp or HOME: $RUNTIME_ROOT" ;;
    esac
}

ensure_runtime_root()
{
    validate_runtime_root
    mkdir -p "$RUNTIME_ROOT"
    RUNTIME_ROOT="$(cd -P "$RUNTIME_ROOT" && pwd)"
    validate_runtime_root
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
    [ -f "$1" ] || return 1
    [ ! -L "$1" ] || return 1
    [ "$(LC_ALL=C head -c 2 "$1" 2>/dev/null || true)" = '#!' ] || return 1
    LC_ALL=C head -c 512 "$1" 2>/dev/null |
        grep -Fq 'envpilot-managed-codex-wrapper'
}

source_bin()
{
    local candidate resolved releases

    if [ -n "${ENVPILOT_CODEX_SOURCE_BIN:-}" ]; then
        candidate="$ENVPILOT_CODEX_SOURCE_BIN/codex"
        [ -x "$candidate" ] && printf '%s' "$ENVPILOT_CODEX_SOURCE_BIN" && return 0
    fi

    candidate="$CODEX_HOME_DIR/packages/standalone/current/bin/codex"
    if [ -x "$CODEX_HOME_DIR/packages/standalone/current/codex" ]; then
        candidate="$CODEX_HOME_DIR/packages/standalone/current/codex"
    fi
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

    if [ -r "$SOURCE_RECORD" ]; then
        candidate="$(sed -n '1p' "$SOURCE_RECORD")"
        if [ -x "$candidate/codex" ]; then printf '%s' "$candidate"; return 0; fi
    fi

    candidate="$(command -v codex 2>/dev/null || true)"
    if [ -n "$candidate" ] && [ -x "$candidate" ] && ! managed_wrapper "$candidate"; then
        resolved="$(resolve_link "$candidate" 2>/dev/null || true)"
        [ -n "$resolved" ] && candidate="$resolved"
        if [ "$(LC_ALL=C head -c 2 "$candidate" 2>/dev/null || true)" = '#!' ] && LC_ALL=C head -c 256 "$candidate" | grep -Eq '^#!.*node'; then
            local package vendor native triple
            package="$(dirname "$(dirname "$candidate")")"
            case "$(uname -s):$(uname -m)" in
                Linux:x86_64) triple=x86_64-unknown-linux-musl ;;
                Linux:aarch64) triple=aarch64-unknown-linux-musl ;;
                Darwin:x86_64) triple=x86_64-apple-darwin ;;
                Darwin:arm64) triple=aarch64-apple-darwin ;;
                *) return 1 ;;
            esac
            for vendor in "$package/vendor" "$package"/../codex-*/vendor; do
                native="$vendor/$triple/codex/codex"
                if [ -x "$native" ]; then printf '%s' "$(dirname "$native")"; return 0; fi
            done
            return 1
        fi
        [ -x "$candidate" ] && printf '%s' "$(dirname "$candidate")" && return 0
    fi

    return 1
}

runtime_files()
{
    local source="$1" file
    for file in "$source"/codex "$source"/codex-* "$source"/rg "$source"/bwrap; do
        [ -f "$file" ] && printf '%s\n' "$file"
    done
}

source_metadata()
{
    local file
    while IFS= read -r file; do
        resolve_link "$file"
        stat -Lc '%s|%y|%z|%i' "$file" 2>/dev/null || stat -Lf '%z|%m|%c|%i' "$file"
    done < <(runtime_files "$1")
}

source_signature()
{
    local bin="$1" file
    [ -x "$bin/codex" ] || return 1
    while IFS= read -r file; do
        printf '%s|' "$(basename "$file")"
        if command_exists sha256sum; then sha256sum "$file" | awk '{print $1}'
        else shasum -a 256 "$file" | awk '{print $1}'; fi
    done < <(runtime_files "$bin") | {
        if command_exists sha256sum; then sha256sum | awk '{print $1}'
        else shasum -a 256 | awk '{print $1}'; fi
    }
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
    local resolved listing status=0
    resolved="$(resolve_link "$SOCKET" 2>/dev/null || printf '%s' "$SOCKET")"
    if [ -r /proc/net/unix ]; then
        [ -z "$(socket_listener_inodes)" ] || return 1
        return 0
    fi
    if command_exists lsof; then
        listing="$(run_bounded 2 lsof -nP -U -Fn 2>/dev/null)" || status=$?
        [ "$status" -le 1 ] || return 2
        if printf '%s\n' "$listing" | grep -Fx -e "n$SOCKET" -e "n$resolved" >/dev/null; then return 1; fi
        return 0
    fi
    return 2
}

socket_listener_inodes()
{
    # Newer Codex versions publish a persistent symlink to a node-local socket.
    # /proc records the bound target, not the public control socket alias.
    local resolved
    resolved="$(resolve_link "$SOCKET" 2>/dev/null || printf '%s' "$SOCKET")"
    awk -v socket="$SOCKET" -v resolved="$resolved" '
        $6 == "01" {
            path = $8
            for (i = 9; i <= NF; i++) path = path " " $i
            if (path == socket || path == resolved) print $7
        }
    ' /proc/net/unix
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

process_identity()
{
    local pid="$1"
    if [ -r "/proc/$pid/stat" ]; then
        sed 's/.*) //' "/proc/$pid/stat" | awk '{print $20}'
    else
        ps -p "$pid" -o lstart= 2>/dev/null
    fi
}

pid_owns_socket()
{
    local pid="$1" inodes inode fd target resolved
    if [ -r /proc/net/unix ]; then
        inodes="$(socket_listener_inodes)"
        [ -n "$inodes" ] || return 1
        for fd in /proc/"$pid"/fd/*; do
            target="$(readlink "$fd" 2>/dev/null || true)"
            while IFS= read -r inode; do
                [ "$target" != "socket:[$inode]" ] || return 0
            done <<< "$inodes"
        done
        return 1
    fi
    command_exists lsof || return 1
    resolved="$(resolve_link "$SOCKET" 2>/dev/null || printf '%s' "$SOCKET")"
    run_bounded 2 lsof -nP -a -p "$pid" -U -Fn 2>/dev/null | grep -Fx -e "n$SOCKET" -e "n$resolved" >/dev/null
}

pid_is_server()
{
    local pid="$1" args uid state home
    case "$pid" in ''|*[!0-9]*) return 1 ;; esac
    kill -0 "$pid" 2>/dev/null || return 1
    uid="$(ps -p "$pid" -o uid= 2>/dev/null | tr -d ' ')"
    [ "$uid" = "$(id -u)" ] || return 1
    state="$(ps -p "$pid" -o stat= 2>/dev/null)"
    case "$state" in Z*|'') return 1 ;; esac
    args="$(ps -p "$pid" -o args= 2>/dev/null || true)"
    case "$args" in codex\ *|*/codex\ *) ;; *) return 1 ;; esac
    case "$args" in *app-server*) ;; *) return 1 ;; esac
    pid_owns_socket "$pid" && return 0
    if [ -r /proc/net/unix ]; then
        # Before a new server binds, require its exact home and default endpoint.
        home="$(tr '\0' '\n' < "/proc/$pid/environ" 2>/dev/null | sed -n 's/^CODEX_HOME=//p' | head -n 1)"
        [ "$home" = "$CODEX_HOME_DIR" ] || return 1
        case "$args " in *'--listen unix:// '*) return 0 ;; esac
        return 1
    fi
    [ "$(sed -n '1p' "$PID_FILE" 2>/dev/null)" = "$pid" ] &&
        [ "$(cat "$PID_FILE.identity" 2>/dev/null)" = "$(process_identity "$pid")" ]
}

find_existing_server_pid()
{
    local pid
    while IFS= read -r pid; do
        pid="$(printf '%s' "$pid" | tr -d ' ')"
        pid_is_server "$pid" && { printf '%s' "$pid"; return 0; }
    done < <(ps -u "$(id -u)" -o pid= 2>/dev/null)
    return 1
}

read_server_pid()
{
    local pid saved
    pid="$(sed -n '1p' "$PID_FILE" 2>/dev/null || true)"
    saved="$(cat "$PID_FILE.identity" 2>/dev/null || true)"
    if pid_is_server "$pid" && { [ -z "$saved" ] || [ "$saved" = "$(process_identity "$pid")" ]; }; then
        printf '%s' "$pid"
    else
        find_existing_server_pid
    fi
}

record_server()
{
    printf '%s\n' "$1" > "$PID_FILE"
    process_identity "$1" > "$PID_FILE.identity"
    cat "$(signature_file)" > "$PID_FILE.signature"
    current_host > "$PID_FILE.host"
}

native_daemon()
{
    local help
    help="$(run_bounded 5 "$(local_bin)" app-server daemon --help 2>/dev/null)" || return 1
    case "$help" in *restart*) return 0 ;; *) return 1 ;; esac
}

protocol_ready()
{
    local expected actual
    [ -x "$CORE_BIN" ] || { warn "envpilot-core is required to verify the app-server protocol."; return 1; }
    expected="$(cat "$(local_current_dir)/.version" 2>/dev/null || true)"
    [ -n "$expected" ] || expected="$(local_version | awk '{print $2}')"
    actual="$("$CORE_BIN" probe --socket "$SOCKET" --format version 2>/dev/null)" || return 1
    [ -n "$expected" ] && [ "$actual" = "$expected" ]
}

runtime_matches_server()
{
    local pid="$1" exe expected
    if [ -r "/proc/$pid/exe" ]; then
        exe="$(readlink "/proc/$pid/exe" 2>/dev/null || true)"
        expected="$(resolve_link "$(local_bin)")"
        [ "$exe" = "$expected" ] && return 0
        case "$(basename "$exe")" in codex|codex\ \(deleted\)) return 1 ;; esac
    fi
    [ -f "$PID_FILE.signature" ] && [ "$(cat "$PID_FILE.signature")" = "$(cat "$(signature_file)")" ] &&
        [ "$(cat "$PID_FILE.identity" 2>/dev/null)" = "$(process_identity "$pid")" ]
}

acquire_server_start_lock()
{
    local attempts=0 lock_pid max lock_host
    max=$((READY_TIMEOUT * 5))
    while ! mkdir "$START_LOCK" 2>/dev/null; do
        lock_pid="$(sed -n '1p' "$START_LOCK/pid" 2>/dev/null || true)"
        lock_host="$(cat "$START_LOCK/host" 2>/dev/null || true)"
        if [ "$lock_host" = "$(current_host)" ] && [ -n "$lock_pid" ] && ! kill -0 "$lock_pid" 2>/dev/null; then
            rm -rf "$START_LOCK"
            continue
        fi
        attempts=$((attempts + 1))
        [ "$attempts" -lt "$max" ] || die "Timed out waiting for Codex app-server start lock: $START_LOCK"
        sleep 0.2
    done
    printf '%s\n' "$$" > "$START_LOCK/pid"
    current_host > "$START_LOCK/host"
}

release_server_start_lock()
{
    local lock_pid
    lock_pid="$(sed -n '1p' "$START_LOCK/pid" 2>/dev/null || true)"
    [ -z "$lock_pid" ] || [ "$lock_pid" = "$$" ] || return 0
    rm -rf "$START_LOCK"
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
(
    local force="${1:-0}" source signature current staged generation file metadata needs_copy=0 probe
    ensure_runtime_root
    acquire_stage_lock
    trap release_stage_lock EXIT
    source="$(source_bin 2>/dev/null || true)"
    [ -n "$source" ] || die "Persistent Codex source is unavailable; refusing to silently reuse an unverified cache."
    metadata="$(source_metadata "$source")"
    if [ "$force" = 0 ] && [ -s "$RUNTIME_ROOT/.source-digest" ] && [ "$metadata" = "$(cat "$RUNTIME_ROOT/.source-metadata" 2>/dev/null || true)" ]; then
        signature="$(cat "$RUNTIME_ROOT/.source-digest" 2>/dev/null || true)"
    else
        signature="$(source_signature "$source")"
    fi
    [ -n "$signature" ] || die "Could not fingerprint the Codex source."
    case "$signature" in *[!0-9a-f]*|'') die 'Invalid runtime digest.' ;; esac
    [ "${#signature}" = 64 ] || die 'Invalid runtime digest.'
    current="$(local_current_dir)"
    generation="$RUNTIME_ROOT/releases/$signature"
    if [ -r "$current/.source.signature" ] && [ "$(cat "$current/.source.signature")" = "$signature" ]; then
        generation="$(resolve_link "$current")"
    fi
    if [ "$force" = 1 ] || [ ! -x "$generation/bin/codex" ]; then
        needs_copy=1
    elif [ "$(source_metadata "$generation/bin")" != "$(cat "$generation/.runtime-metadata" 2>/dev/null || true)" ]; then
        needs_copy=1
    elif [ "$force" != 0 ] && [ "$(source_signature "$generation/bin")" != "$signature" ]; then
        needs_copy=1
    fi
    if [ "$needs_copy" = 1 ]; then
        staged="$(mktemp -d "$RUNTIME_ROOT/.staging.XXXXXX")"
        mkdir -p "$staged/bin"
        log "Staging Codex runtime from $source to $generation"
        while IFS= read -r file; do cp -pL "$file" "$staged/bin/"; done < <(runtime_files "$source")
        [ -x "$staged/bin/codex" ] || die "Staged runtime has no executable codex."
        if [ "$(source_signature "$staged/bin")" != "$signature" ] || [ "$(source_metadata "$source")" != "$metadata" ]; then
            rm -rf "$staged"
            die "Codex source changed while staging; retry after the installer finishes."
        fi
        if ! probe="$(run_bounded 5 "$staged/bin/codex" --version 2>&1)" || ! printf '%s\n' "$probe" | grep -q '^codex-cli '; then
            rm -rf "$staged"
            die 'The staged Codex executable failed its version probe; the running server was preserved.'
        fi
        printf '%s\n' "$probe" | awk '/^codex-cli / {print $2;exit}' > "$staged/.version"
        printf '%s\n' "$signature" > "$staged/.source.signature"
        mkdir -p "$RUNTIME_ROOT/releases"
        if [ -d "$generation" ]; then generation="$generation-repair-$$"; fi
        mv "$staged" "$generation"
        source_metadata "$generation/bin" > "$generation/.runtime-metadata"
    fi
    if [ -d "$current" ] && [ ! -L "$current" ]; then mv "$current" "$RUNTIME_ROOT/releases/legacy-$(date +%s)-$$"; fi
    ln -s "$generation" "$RUNTIME_ROOT/.current.$$"
    # mv must replace the symlink itself, not move into its target directory.
    if [ -L "$current" ]; then
        if [ "$(uname -s)" = Darwin ]; then mv -fh "$RUNTIME_ROOT/.current.$$" "$current"
        else mv -fT "$RUNTIME_ROOT/.current.$$" "$current"; fi
    else mv "$RUNTIME_ROOT/.current.$$" "$current"; fi
    printf '%s\n' "$metadata" > "$RUNTIME_ROOT/.source-metadata.tmp.$$"
    printf '%s\n' "$signature" > "$RUNTIME_ROOT/.source-digest.tmp.$$"
    mv "$RUNTIME_ROOT/.source-metadata.tmp.$$" "$RUNTIME_ROOT/.source-metadata"
    mv "$RUNTIME_ROOT/.source-digest.tmp.$$" "$RUNTIME_ROOT/.source-digest"
)

wait_for_socket()
{
    local pid="${1:-}" seconds="${2:-$READY_TIMEOUT}" i=0 max
    max=$((seconds * 5))
    while [ "$i" -lt "$max" ]; do
        if socket_ready && protocol_ready && { [ -z "$pid" ] || pid_owns_socket "$pid"; }; then
            printf '%s\n' "$(date '+%F %T')" > "$CONTROL_DIR/envpilot-app-server.ready"
            return 0
        fi
        if [ -n "$pid" ] && ! kill -0 "$pid" 2>/dev/null; then
            return 1
        fi
        sleep 0.2
        i=$((i + 1))
    done
    return 1
}

start_server_locked()
{
    local require_new="${1:-0}" pid state=0 attempts=0
    pid="$(read_server_pid 2>/dev/null || true)"
    if [ -n "$pid" ]; then
        if [ "$require_new" != 1 ] && runtime_matches_server "$pid" && wait_for_socket "$pid"; then
            log "Codex app-server is ready: PID $pid"
            return 0
        fi
        stop_server || return 1
    fi
    if [ -S "$SOCKET" ] || [ -L "$SOCKET" ]; then
        socket_listener_state || state=$?
        if [ "$state" != 0 ]; then warn "Cannot verify the owner of the active control socket: $SOCKET"; return 1; fi
        rm -f "$SOCKET"
    fi
    load_codex_environment
    log "Starting Codex app-server from the verified runtime."
    if native_daemon && [ "$(resolve_link "$CODEX_HOME_DIR/packages/standalone/current/codex" 2>/dev/null || true)" = "$(resolve_link "$(local_bin)")" ]; then
        if ! CODEX_HOME="$CODEX_HOME_DIR" run_bounded "$READY_TIMEOUT" "${__envpilot_exec_args[@]}" -- app-server daemon start >>"$SERVER_LOG" 2>&1; then
            warn "Native daemon start failed; see $SERVER_LOG"
            return 1
        fi
        while [ "$attempts" -lt "$((READY_TIMEOUT * 5))" ]; do
            pid="$(find_existing_server_pid 2>/dev/null || true)"
            [ -z "$pid" ] || break
            sleep 0.2
            attempts=$((attempts + 1))
        done
    else
        CODEX_HOME="$CODEX_HOME_DIR" nohup "${__envpilot_exec_args[@]}" -- app-server --listen unix:// >>"$SERVER_LOG" 2>&1 < /dev/null &
        pid=$!
        printf '%s\n' "$pid" > "$PID_FILE"
        process_identity "$pid" > "$PID_FILE.identity"
    fi
    if [ -n "$pid" ] && wait_for_socket "$pid"; then
        record_server "$pid"
        if runtime_matches_server "$pid"; then
            log "Codex app-server is ready: PID $pid ($(local_version))"
            return 0
        fi
    fi
    warn "App-server startup or version verification failed; see $SERVER_LOG"
    return 1
}

stop_server()
{
    local pid identity i=0 state=0
    pid="$(read_server_pid 2>/dev/null || true)"
    if [ -z "$pid" ]; then
        if [ -S "$SOCKET" ] || [ -L "$SOCKET" ]; then
            socket_listener_state || state=$?
            [ "$state" = 0 ] || { warn "Control socket owner is unknown; no process was stopped."; return 1; }
        fi
        rm -f "$SOCKET" "$PID_FILE" "$PID_FILE.identity" "$PID_FILE.signature" "$PID_FILE.host" "$CONTROL_DIR/envpilot-app-server.ready"
        log "No matching Codex app-server is running."
        return 0
    fi
    identity="$(process_identity "$pid")"
    if [ -x "$(local_bin)" ] && native_daemon; then
        run_bounded 10 env CODEX_HOME="$CODEX_HOME_DIR" "$(local_bin)" app-server daemon stop >>"$SERVER_LOG" 2>&1 || true
    fi
    if pid_is_server "$pid" && [ "$(process_identity "$pid")" = "$identity" ]; then kill -TERM "$pid" 2>/dev/null || true; fi
    while pid_is_server "$pid" && [ "$i" -lt 50 ]; do sleep 0.1; i=$((i+1)); done
    if pid_is_server "$pid" && [ "$(process_identity "$pid")" = "$identity" ]; then kill -KILL "$pid" 2>/dev/null || true; fi
    i=0
    while pid_is_server "$pid" && [ "$i" -lt 20 ]; do sleep 0.1; i=$((i+1)); done
    if [ -n "$(find_existing_server_pid 2>/dev/null || true)" ]; then
        warn "A matching app-server is still running or its supervisor restarted it; preserving state."
        return 1
    fi
    rm -f "$PID_FILE" "$PID_FILE.identity" "$PID_FILE.signature" "$PID_FILE.host" "$CONTROL_DIR/envpilot-app-server.ready"
    state=0
    socket_listener_state || state=$?
    [ "$state" != 0 ] || rm -f "$SOCKET"
    log "Stopped Codex app-server: PID $pid"
}

clean_unused_generations()
{
    local generation current pid executable active
    [ -d /proc ] || return 0
    current="$(resolve_link "$(local_current_dir)")"
    for generation in "$RUNTIME_ROOT"/releases/*; do
        if [ ! -d "$generation" ] || [ -L "$generation" ] || [ ! -f "$generation/.source.signature" ]; then continue; fi
        [ "$generation" != "$current" ] || continue
        active=0
        while IFS= read -r pid; do
            pid="$(printf '%s' "$pid" | tr -d ' ')"
            executable="$(readlink "/proc/$pid/exe" 2>/dev/null || true)"
            case "$executable" in "$generation"/*) active=1; break ;; esac
        done < <(ps -u "$(id -u)" -o pid= 2>/dev/null)
        [ "$active" != 0 ] || rm -rf -- "$generation"
    done
}

server_operation()
{
    local operation="$1" old_pid new_pid status=0 stage_mode=0
    ensure_control_dir
    acquire_server_start_lock
    trap release_server_start_lock EXIT
    if [ -r "$PID_FILE.host" ] && [ "$(cat "$PID_FILE.host")" != "$(current_host)" ]; then
        die 'The control directory belongs to another node; select a node-specific CODEX_HOME before changing its service.'
    fi
    old_pid="$(read_server_pid 2>/dev/null || true)"
    case "$operation" in restart) stage_mode=verify ;; repair) stage_mode=1 ;; esac
    if [ "$operation" = stop ]; then
        stop_server || status=$?
    elif stage_runtime "$stage_mode"; then
        load_codex_environment
        if ! CODEX_HOME="$CODEX_HOME_DIR" "${__envpilot_exec_args[@]}" --check; then
            release_server_start_lock
            trap - EXIT
            return 1
        fi
        if [ "$operation" = restart ] || [ "$operation" = repair ]; then
            log "Restarting Codex app-server; connected tasks may be interrupted."
            stop_server || status=$?
        fi
        if [ "$status" = 0 ]; then start_server_locked 0 || status=$?; fi
        new_pid="$(read_server_pid 2>/dev/null || true)"
        if [ "$status" = 0 ] && { [ "$operation" = restart ] || [ "$operation" = repair ]; }; then
            if [ -z "$new_pid" ] || [ "$new_pid" = "$old_pid" ]; then status=1; warn "A new app-server process was not verified."; fi
        fi
        [ "$status" != 0 ] || clean_unused_generations
    else
        status=1
    fi
    release_server_start_lock
    trap - EXIT
    return "$status"
}
start_server() { server_operation ready; }
restart_server() { server_operation restart; }
repair_runtime() { server_operation repair; }
stop_server_serialized() { server_operation stop; }

clean_runtime()
{
    ensure_runtime_root
    rm -rf "$(local_current_dir)" "$RUNTIME_ROOT/.staging.$$" "$RUNTIME_ROOT/.previous.$$"
    printf 'Removed node-local Codex runtime: %s\n' "$RUNTIME_ROOT"
}

status_report()
{
    local source="" version="" pid="" existing_pid="" wrapper="$HOME/.local/bin/codex"
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
    elif [ -S "$SOCKET" ] && socket_ready && protocol_ready; then
        printf '  socket: READY (%s)\n' "$SOCKET"
    else
        printf '  socket: NOT READY (%s)\n' "$SOCKET"
    fi
    pid="$(read_server_pid 2>/dev/null || true)"
    if [ -n "$pid" ]; then
        printf 'App-server:\n  managed PID %s\n' "$pid"
        if [ -f "$(signature_file)" ] && ! runtime_matches_server "$pid"; then
            printf '  VERSION MISMATCH: run envpilot codex remote restart\n'
        elif [ -n "$source" ] && [ -f "$RUNTIME_ROOT/.source-metadata" ] && [ "$(source_metadata "$source")" != "$(cat "$RUNTIME_ROOT/.source-metadata")" ]; then
            printf '  SOURCE UPDATED: run envpilot codex remote restart\n'
        fi
    else
        existing_pid="$(find_existing_server_pid 2>/dev/null || true)"
        if [ -n "$existing_pid" ]; then
            printf 'App-server:\n  matching Desktop/SSH PID %s\n' "$existing_pid"
        else
            printf 'App-server:\n  not running or not detectable\n'
        fi
    fi
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
    load_codex_environment
    CODEX_HOME="$CODEX_HOME_DIR" exec "${__envpilot_exec_args[@]}" -- "$@"
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

if [ -d "$CODEX_HOME_DIR" ]; then
    CODEX_HOME_DIR="$(cd -P "$CODEX_HOME_DIR" && pwd)"
    CONTROL_DIR="$CODEX_HOME_DIR/app-server-control"
    SOCKET="$CONTROL_DIR/app-server-control.sock"
    PID_FILE="$CONTROL_DIR/envpilot-app-server.pid"
    SERVER_LOG="$CONTROL_DIR/app-server.log"
    START_LOCK="$CONTROL_DIR/.envpilot-app-server-start.lock"
fi
action="${1:-status}"
shift || true
case "$action" in
    running)
        read_server_pid >/dev/null
        ;;
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
        case "$MANAGER_LANGUAGE" in
            zh*) status_report | "$CORE_BIN" message --stream --lang zh-CN ;;
            *) status_report ;;
        esac
        ;;
    stop)
        stop_server_serialized
        ;;
    restart)
        restart_server
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
Usage: codex-remote {status|stage|ready|warm|restart|stop|repair|exec [ARGS...]}
EOF
        ;;
    *)
        die "Unknown Codex remote action: $action"
        ;;
esac
