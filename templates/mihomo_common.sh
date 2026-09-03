#!/usr/bin/env bash
# shellcheck disable=SC2034 # Shared constants are consumed by the management scripts.

MIHOMO_SOURCE_BIN="${HOME}/software/mihomo/mihomo"
MIHOMO_SOURCE_CONFIG="${HOME}/.config/mihomo"
MIHOMO_SUBSCRIPTION_FILE="${ENVPILOT_MIHOMO_SUBSCRIPTION_FILE:-${MIHOMO_SOURCE_CONFIG}/subscription.url}"
MIHOMO_PROXY_HOST="${MIHOMO_PROXY_HOST:-127.0.0.1}"

mihomo_persisted_port()
{
    local key="$1" config_key="$2" file value
    file="${HOME}/.config/envpilot/shell.local"
    if [ -r "$file" ]; then
        value="$(grep -E "^[[:space:]]*(export[[:space:]]+)?${key}=" "$file" 2>/dev/null | tail -n 1 | sed -E "s/^[[:space:]]*(export[[:space:]]+)?${key}=//" | tr -d "\"'[:space:]" || true)"
        case "$value" in ''|*[!0-9]*) ;; *) printf '%s' "$value"; return 0 ;; esac
    fi
    file="${MIHOMO_SOURCE_CONFIG}/config.yaml"
    [ -r "$file" ] || return 1
    case "$config_key" in
        mixed-port)
            value="$(grep -E '^[[:space:]]*mixed-port:[[:space:]]*[0-9]+' "$file" 2>/dev/null | tail -n 1 | sed -E 's/^[^:]+:[[:space:]]*([0-9]+).*/\1/' || true)"
            ;;
        external-controller)
            value="$(grep -E '^[[:space:]]*external-controller:[[:space:]]*(127\.0\.0\.1|localhost):[0-9]+' "$file" 2>/dev/null | tail -n 1 | sed -E 's|^.*:([0-9]+)[[:space:]]*$|\1|' || true)"
            ;;
    esac
    case "$value" in ''|*[!0-9]*) return 1 ;; *) printf '%s' "$value" ;; esac
}

MIHOMO_PROXY_PORT="${MIHOMO_PROXY_PORT:-$(mihomo_persisted_port MIHOMO_PROXY_PORT mixed-port 2>/dev/null || printf '42290')}"
MIHOMO_API_PORT="${MIHOMO_API_PORT:-$(mihomo_persisted_port MIHOMO_API_PORT external-controller 2>/dev/null || printf '60290')}"
MIHOMO_STARTUP_TIMEOUT="${MIHOMO_STARTUP_TIMEOUT:-30}"

mihomo_die()
{
    printf '[ERROR] %s\n' "$*" >&2
    exit 1
}

mihomo_command_exists()
{
    command -v "$1" >/dev/null 2>&1
}

mihomo_port_is_valid()
{
    case "${1:-}" in
        ''|*[!0-9]*) return 1 ;;
    esac
    [ "$1" -ge 1 ] && [ "$1" -le 65535 ] 2>/dev/null
}

mihomo_init_runtime()
{
    local user_name host_name

    mihomo_port_is_valid "$MIHOMO_PROXY_PORT" ||
        mihomo_die "invalid MIHOMO_PROXY_PORT: $MIHOMO_PROXY_PORT"
    mihomo_port_is_valid "$MIHOMO_API_PORT" ||
        mihomo_die "invalid MIHOMO_API_PORT: $MIHOMO_API_PORT"
    [ "$MIHOMO_PROXY_PORT" != "$MIHOMO_API_PORT" ] ||
        mihomo_die "MIHOMO_PROXY_PORT and MIHOMO_API_PORT must be different"
    [ "$MIHOMO_PROXY_HOST" = "127.0.0.1" ] ||
        mihomo_die "MIHOMO_PROXY_HOST must remain 127.0.0.1"

    if [ "$(id -u 2>/dev/null || printf '1')" != "0" ]; then
        [ "$MIHOMO_PROXY_PORT" -gt 1024 ] ||
            mihomo_die "MIHOMO_PROXY_PORT must be greater than 1024 for a non-root user"
        [ "$MIHOMO_API_PORT" -gt 1024 ] ||
            mihomo_die "MIHOMO_API_PORT must be greater than 1024 for a non-root user"
    fi

    user_name="${USER:-$(id -un 2>/dev/null || true)}"
    host_name="${HOSTNAME:-$(hostname 2>/dev/null || true)}"
    [ -n "$user_name" ] || mihomo_die "cannot determine current user"
    [ -n "$host_name" ] || mihomo_die "cannot determine current host"
    case "$user_name" in
        *[!A-Za-z0-9_.-]*|*..*) mihomo_die "unsafe user name for runtime directory: $user_name" ;;
    esac
    case "$host_name" in
        *[!A-Za-z0-9_.-]*|*..*) mihomo_die "unsafe host name for runtime directory: $host_name" ;;
    esac

    MIHOMO_RUNTIME_DIR="/tmp/${user_name}_mihomo_${host_name}"
    MIHOMO_RUNTIME_BIN="${MIHOMO_RUNTIME_DIR}/mihomo"
    MIHOMO_RUNTIME_LOG="${MIHOMO_RUNTIME_DIR}/mihomo.log"
    MIHOMO_PID_FILE="${MIHOMO_RUNTIME_DIR}/mihomo.pid"
    # Keep the lock beside the runtime directory. start_mihomo.sh removes the
    # runtime directory before copying a fresh node-local instance.
    MIHOMO_START_LOCK_DIR="${MIHOMO_RUNTIME_DIR}.start.lock"
    export MIHOMO_RUNTIME_DIR MIHOMO_RUNTIME_BIN MIHOMO_RUNTIME_LOG MIHOMO_PID_FILE MIHOMO_START_LOCK_DIR
}

mihomo_release_start_lock()
{
    local owner=""
    [ -d "${MIHOMO_START_LOCK_DIR:-}" ] || return 0
    owner="$(cat "$MIHOMO_START_LOCK_DIR/pid" 2>/dev/null || true)"
    [ "$owner" = "$$" ] || return 0
    rm -rf -- "$MIHOMO_START_LOCK_DIR" 2>/dev/null || true
}

mihomo_acquire_start_lock()
{
    local attempts=0
    local max_attempts="${MIHOMO_START_LOCK_TIMEOUT:-${MIHOMO_STARTUP_TIMEOUT:-30}}"
    local owner=""

    case "$MIHOMO_RUNTIME_DIR" in
        /tmp/*_mihomo_*) ;;
        *) mihomo_die "unsafe runtime directory for start lock: $MIHOMO_RUNTIME_DIR" ;;
    esac
    while ! mkdir "$MIHOMO_START_LOCK_DIR" 2>/dev/null; do
        owner="$(cat "$MIHOMO_START_LOCK_DIR/pid" 2>/dev/null || true)"
        if [ -n "$owner" ] && ! kill -0 "$owner" 2>/dev/null; then
            rm -rf -- "$MIHOMO_START_LOCK_DIR" 2>/dev/null || true
            continue
        fi
        if [ -z "$owner" ] && [ "$attempts" -ge 2 ]; then
            rm -rf -- "$MIHOMO_START_LOCK_DIR" 2>/dev/null || true
            continue
        fi
        if [ "$attempts" -ge "$max_attempts" ]; then
            return 1
        fi
        sleep 1
        attempts=$((attempts + 1))
    done
    if ! printf '%s\n' "$$" > "$MIHOMO_START_LOCK_DIR/pid"; then
        rm -rf -- "$MIHOMO_START_LOCK_DIR" 2>/dev/null || true
        return 1
    fi
    trap 'mihomo_release_start_lock' EXIT
    return 0
}

mihomo_port_socket_listening()
{
    local port="$1"
    local line
    if mihomo_command_exists ss; then
        line="$(ss -lntH "sport = :$port" 2>/dev/null | head -n 1 || true)"
        [ -n "$line" ] && return 0
    fi
    return 1
}

mihomo_run_bounded_port_probe()
{
    local seconds="$1"
    shift
    if mihomo_command_exists timeout; then
        timeout -k 1 "$seconds" "$@"
    elif mihomo_command_exists gtimeout; then
        gtimeout -k 1 "$seconds" "$@"
    elif mihomo_command_exists perl; then
        perl -e 'alarm shift; exec @ARGV' "$seconds" "$@"
    else
        return 125
    fi
}

mihomo_port_reachable()
{
    local port="$1"
    local line
    if mihomo_port_socket_listening "$port"; then
        return 0
    fi
    if mihomo_command_exists nc && nc -z -w 1 "$MIHOMO_PROXY_HOST" "$port" >/dev/null 2>&1; then
        return 0
    fi
    if mihomo_run_bounded_port_probe 1 bash -c ": </dev/tcp/$MIHOMO_PROXY_HOST/$port" >/dev/null 2>&1; then
        return 0
    fi
    if mihomo_command_exists lsof; then
        line="$(
            mihomo_run_bounded_port_probe 2 \
                lsof -nP -iTCP:"$port" -sTCP:LISTEN 2>/dev/null |
                awk 'NR == 2 { print; exit }' || true
        )"
        [ -n "$line" ] && return 0
    fi
    return 1
}

mihomo_runtime_running()
{
    pgrep -u "${USER:-$(id -un)}" -f "$MIHOMO_RUNTIME_BIN" >/dev/null 2>&1
}

mihomo_api_healthy()
{
    mihomo_command_exists curl || return 1
    curl \
        --noproxy '*' \
        --connect-timeout 1 \
        --max-time 2 \
        -sS \
        -o /dev/null \
        "http://${MIHOMO_PROXY_HOST}:${MIHOMO_API_PORT}/version" 2>/dev/null
}

mihomo_set_yaml_key()
{
    local key="$1"
    local value="$2"
    local file="$3"
    local tmp

    tmp="$(mktemp "${file}.tmp.XXXXXX")"
    awk -v key="$key" -v value="$value" '
        BEGIN { done = 0 }
        $0 ~ "^[[:space:]]*" key ":[[:space:]]*" {
            if (!done) print key ": " value
            done = 1
            next
        }
        { print }
        END { if (!done) print key ": " value }
    ' "$file" > "$tmp"
    mv "$tmp" "$file"
}

mihomo_apply_local_config()
{
    local file="$1"
    mihomo_set_yaml_key "mixed-port" "$MIHOMO_PROXY_PORT" "$file"
    mihomo_set_yaml_key "allow-lan" "false" "$file"
    mihomo_set_yaml_key "bind-address" "$MIHOMO_PROXY_HOST" "$file"
    mihomo_set_yaml_key "external-controller" "$MIHOMO_PROXY_HOST:$MIHOMO_API_PORT" "$file"
}

mihomo_saved_subscription_url()
{
    local url
    mihomo_subscription_file_is_safe "$MIHOMO_SUBSCRIPTION_FILE" || return 1
    url="$(sed -n '1p' "$MIHOMO_SUBSCRIPTION_FILE" 2>/dev/null || true)"
    case "$url" in
        http://*|https://*) printf '%s' "$url" ;;
        *) return 1 ;;
    esac
}

mihomo_subscription_file_is_safe()
{
    local file="$1" mode owner_uid current_uid
    [ -f "$file" ] || return 1
    current_uid="$(id -u 2>/dev/null || true)"
    owner_uid="$(stat -c '%u' "$file" 2>/dev/null || stat -f '%u' "$file" 2>/dev/null || true)"
    [ -z "$current_uid" ] || [ "$owner_uid" = "$current_uid" ] || return 1
    case "$(uname -s 2>/dev/null || true)" in
        MINGW*|MSYS*|CYGWIN*) return 0 ;;
    esac
    mode="$(stat -c '%a' "$file" 2>/dev/null || stat -f '%Lp' "$file" 2>/dev/null || true)"
    case "$mode" in
        400|600) return 0 ;;
        *) return 1 ;;
    esac
}

mihomo_save_subscription_url()
{
    local url="$1" tmp backup
    case "$url" in
        http://*|https://*) ;;
        *) mihomo_die "invalid subscription URL" ;;
    esac
    case "$url" in
        *$'\n'*|*$'\r'*) mihomo_die "subscription URL must be one line" ;;
    esac
    mkdir -p "$(dirname "$MIHOMO_SUBSCRIPTION_FILE")"
    chmod 700 "$(dirname "$MIHOMO_SUBSCRIPTION_FILE")" 2>/dev/null || true
    tmp="$(mktemp "${MIHOMO_SUBSCRIPTION_FILE}.tmp.XXXXXX")"
    printf '%s\n' "$url" > "$tmp"
    chmod 600 "$tmp" || mihomo_die "could not protect subscription URL file"
    if [ -e "$MIHOMO_SUBSCRIPTION_FILE" ]; then
        if cmp -s "$MIHOMO_SUBSCRIPTION_FILE" "$tmp"; then
            chmod 600 "$MIHOMO_SUBSCRIPTION_FILE" ||
                mihomo_die "could not protect subscription URL file"
            rm -f "$tmp"
            return 0
        fi
        backup="$MIHOMO_SUBSCRIPTION_FILE.bak.$(date +%Y%m%d%H%M%S)"
        cp -p "$MIHOMO_SUBSCRIPTION_FILE" "$backup"
        chmod 600 "$backup" || mihomo_die "could not protect subscription URL backup"
        printf '[INFO] subscription source backup: %s\n' "$backup"
    fi
    mv "$tmp" "$MIHOMO_SUBSCRIPTION_FILE"
}
