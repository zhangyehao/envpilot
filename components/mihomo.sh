#!/usr/bin/env bash

ep_mihomo_bin()
{
    printf '%s/software/mihomo/mihomo' "$HOME"
}

ep_mihomo_config_file()
{
    printf '%s/.config/mihomo/config.yaml' "$HOME"
}

ep_mihomo_shell_local_file()
{
    printf '%s/shell.local' "${EP_CONFIG_DIR:-$HOME/.config/envpilot}"
}

ep_mihomo_script()
{
    printf '%s/software/mihomo/%s' "$HOME" "$1"
}

ep_mihomo_runtime_dir()
{
    local user_name host_name
    user_name="${USER:-$(id -un 2>/dev/null || true)}"
    host_name="${HOSTNAME:-$(hostname 2>/dev/null || true)}"
    [ -n "$user_name" ] || ep_die "Cannot determine current user for Mihomo runtime."
    [ -n "$host_name" ] || ep_die "Cannot determine current host for Mihomo runtime."
    case "$user_name" in
        *[!A-Za-z0-9_.-]*|*..*) ep_die "Unsafe user name for Mihomo runtime directory: $user_name" ;;
    esac
    case "$host_name" in
        *[!A-Za-z0-9_.-]*|*..*) ep_die "Unsafe host name for Mihomo runtime directory: $host_name" ;;
    esac
    printf '/tmp/%s_mihomo_%s' "$user_name" "$host_name"
}

ep_mihomo_runtime_bin()
{
    printf '%s/mihomo' "$(ep_mihomo_runtime_dir)"
}

ep_port_is_valid()
{
    case "${1:-}" in
        ''|*[!0-9]*) return 1 ;;
    esac
    [ "$1" -ge 1 ] && [ "$1" -le 65535 ] 2>/dev/null
}

ep_require_port()
{
    local port="${1:-}"
    ep_port_is_valid "$port" || ep_die "Invalid port: ${port:-empty}. Use an integer from 1 to 65535."
    if [ "${EP_IS_ROOT:-false}" != "true" ] && [ "$port" -le 1024 ]; then
        ep_die "Port $port requires elevated privileges; choose a port greater than 1024."
    fi
    printf '%s' "$port"
}

ep_require_mihomo_ports()
{
    local proxy_port api_port
    proxy_port="$(ep_require_port "${1:-}")"
    api_port="$(ep_require_port "${2:-}")"
    [ "$proxy_port" != "$api_port" ] ||
        ep_die "Proxy and API ports must be different."
    printf '%s %s' "$proxy_port" "$api_port"
}

ep_mihomo_config_proxy_port()
{
    local config value
    config="$(ep_mihomo_config_file)"
    [ -r "$config" ] || return 1
    value="$(grep -E '^[[:space:]]*mixed-port:[[:space:]]*[0-9]+' "$config" 2>/dev/null | tail -n 1 | sed -E 's/^[^:]+:[[:space:]]*([0-9]+).*/\1/' || true)"
    ep_port_is_valid "$value" || return 1
    printf '%s' "$value"
}

ep_mihomo_config_api_port()
{
    local config value
    config="$(ep_mihomo_config_file)"
    [ -r "$config" ] || return 1
    value="$(grep -E '^[[:space:]]*external-controller:[[:space:]]*(127\.0\.0\.1|localhost):[0-9]+' "$config" 2>/dev/null | tail -n 1 | sed -E 's|^.*:([0-9]+)[[:space:]]*$|\1|' || true)"
    ep_port_is_valid "$value" || return 1
    printf '%s' "$value"
}

ep_mihomo_shell_local_port()
{
    local key="$1"
    local file value
    file="$(ep_mihomo_shell_local_file)"
    [ -r "$file" ] || return 1
    value="$(grep -E "^[[:space:]]*(export[[:space:]]+)?${key}=" "$file" 2>/dev/null | tail -n 1 | sed -E "s/^[[:space:]]*(export[[:space:]]+)?${key}=//" | tr -d "\"'[:space:]" || true)"
    ep_port_is_valid "$value" || return 1
    printf '%s' "$value"
}

ep_mihomo_proxy_port()
{
    local port
    if ep_port_is_valid "${MIHOMO_PROXY_PORT:-}"; then
        printf '%s' "$MIHOMO_PROXY_PORT"
    elif ep_port_is_valid "${BASHRC_PROXY_PORT:-}"; then
        printf '%s' "$BASHRC_PROXY_PORT"
    elif port="$(ep_mihomo_shell_local_port MIHOMO_PROXY_PORT 2>/dev/null)"; then
        printf '%s' "$port"
    elif port="$(ep_mihomo_shell_local_port BASHRC_PROXY_PORT 2>/dev/null)"; then
        printf '%s' "$port"
    elif port="$(ep_mihomo_config_proxy_port 2>/dev/null)"; then
        printf '%s' "$port"
    else
        printf '42290'
    fi
}

ep_mihomo_api_port()
{
    local port
    if ep_port_is_valid "${MIHOMO_API_PORT:-}"; then
        printf '%s' "$MIHOMO_API_PORT"
    elif port="$(ep_mihomo_shell_local_port MIHOMO_API_PORT 2>/dev/null)"; then
        printf '%s' "$port"
    elif port="$(ep_mihomo_config_api_port 2>/dev/null)"; then
        printf '%s' "$port"
    else
        printf '60290'
    fi
}

ep_mihomo_set_shell_local_ports()
{
    local proxy_port api_port file tmp
    read -r proxy_port api_port <<EOF
$(ep_require_mihomo_ports "${1:-}" "${2:-}")
EOF
    file="$(ep_mihomo_shell_local_file)"
    mkdir -p "$(dirname "$file")"
    [ -e "$file" ] && ep_backup_file "$file"
    tmp="$(mktemp "${file}.tmp.XXXXXX")"
    if [ -f "$file" ]; then
        awk -v proxy="$proxy_port" -v api="$api_port" '
            BEGIN { proxy_done = 0; api_done = 0 }
            /^[[:space:]]*(export[[:space:]]+)?BASHRC_PROXY_PORT=/ { next }
            /^[[:space:]]*(export[[:space:]]+)?MIHOMO_PROXY_PORT=/ {
                if (!proxy_done) print "MIHOMO_PROXY_PORT=" proxy
                proxy_done = 1
                next
            }
            /^[[:space:]]*(export[[:space:]]+)?MIHOMO_API_PORT=/ {
                if (!api_done) print "MIHOMO_API_PORT=" api
                api_done = 1
                next
            }
            { print }
            END {
                if (!proxy_done) print "MIHOMO_PROXY_PORT=" proxy
                if (!api_done) print "MIHOMO_API_PORT=" api
            }
        ' "$file" > "$tmp"
    else
        printf '# envpilot shell.local\nMIHOMO_PROXY_PORT=%s\nMIHOMO_API_PORT=%s\n' "$proxy_port" "$api_port" > "$tmp"
    fi
    mv "$tmp" "$file"
    chmod 600 "$file" 2>/dev/null || true
    ep_log "Wrote Mihomo ports to $file: proxy=$proxy_port API=$api_port"
}

ep_mihomo_refresh_scripts()
{
    local name target
    for name in mihomo_common.sh start_mihomo.sh stop_mihomo.sh status_mihomo.sh update_mihomo_subscription.sh; do
        target="$(ep_mihomo_script "$name")"
        if [ -f "$ENVPILOT_ROOT/templates/$name" ] && [ -d "$(dirname "$target")" ]; then
            cp "$ENVPILOT_ROOT/templates/$name" "$target"
            chmod 755 "$target"
        fi
    done
}

ep_mihomo_shell_reload_hint()
{
    case "${SHELL##*/}" in
        zsh) printf 'source ~/.zshrc' ;;
        *) printf 'source ~/.bashrc' ;;
    esac
}
ep_mihomo_asset_regex()
{
    case "$EP_OS:$EP_ARCH" in
        linux:amd64) printf 'mihomo-linux-amd64-compatible-.*\.gz$' ;;
        linux:arm64) printf 'mihomo-linux-arm64-.*\.gz$' ;;
        darwin:amd64) printf 'mihomo-darwin-amd64.*\.gz$' ;;
        darwin:arm64) printf 'mihomo-darwin-arm64.*\.gz$' ;;
        windows-unix:amd64) printf 'mihomo-windows-amd64-compatible-.*\.zip$' ;;
        windows-unix:arm64) printf 'mihomo-windows-arm64-.*\.zip$' ;;
        *) ep_die "No mihomo asset rule for $EP_OS/$EP_ARCH" ;;
    esac
}

ep_mihomo_offline_pattern()
{
    case "$EP_OS:$EP_ARCH" in
        linux:amd64) printf 'mihomo-linux-amd64-compatible-*.gz' ;;
        linux:arm64) printf 'mihomo-linux-arm64-*.gz' ;;
        darwin:amd64) printf 'mihomo-darwin-amd64*.gz' ;;
        darwin:arm64) printf 'mihomo-darwin-arm64*.gz' ;;
        windows-unix:amd64) printf 'mihomo-windows-amd64-compatible-*.zip' ;;
        windows-unix:arm64) printf 'mihomo-windows-arm64-*.zip' ;;
        *) ep_die "No mihomo offline asset pattern for $EP_OS/$EP_ARCH" ;;
    esac
}

ep_mihomo_data_asset_url()
{
    case "$1" in
        country.mmdb|geoip.metadb)
            printf 'https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/%s' "$1"
            ;;
        *) ep_die "No mihomo data asset rule for $1" ;;
    esac
}

ep_install_mihomo_data_asset()
{
    local name="$1"
    local config_dir="$2"
    local source target archive

    target="$config_dir/$name"
    archive="$(mktemp "${TMPDIR:-/tmp}/envpilot-mihomo-data.XXXXXX")"

    if [ "$EP_MODE" = "offline" ]; then
        source="$(ep_find_offline_asset "$name")"
    else
        source="$(ep_find_cached_asset "$name" 2>/dev/null || true)"
        if [ -n "$source" ]; then
            ep_log "Using bundled downloads/ mihomo data asset before network: $source"
        else
            source="$(ep_mihomo_data_asset_url "$name")"
        fi
    fi

    ep_log "Geodata asset: $name"
    ep_log "Source: $source"
    ep_log "Target: $target"
    ep_backup_file "$target"

    if [ -f "$source" ]; then
        cp "$source" "$target"
    else
        ep_fetch_url "$source" "$archive"
        mv "$archive" "$target"
        archive=""
    fi

    rm -f "$archive"
}

ep_install_mihomo_data_assets()
{
    local config_dir="$1"
    ep_install_mihomo_data_asset country.mmdb "$config_dir"
    ep_install_mihomo_data_asset geoip.metadb "$config_dir"
}

ep_proxy_port_socket_listening()
{
    local port="${1:-$(ep_mihomo_proxy_port)}"
    local line
    if ep_command_exists ss; then
        line="$(ss -lntH "sport = :$port" 2>/dev/null | head -n 1 || true)"
        [ -n "$line" ] && return 0
    fi
    return 1
}

ep_mihomo_run_bounded_port_probe()
{
    local seconds="$1"
    shift
    if ep_command_exists timeout; then
        timeout -k 1 "$seconds" "$@"
    elif ep_command_exists gtimeout; then
        gtimeout -k 1 "$seconds" "$@"
    elif ep_command_exists perl; then
        perl -e 'alarm shift; exec @ARGV' "$seconds" "$@"
    else
        return 125
    fi
}

ep_proxy_port_is_listening()
{
    local host="${1:-127.0.0.1}"
    local port="${2:-$(ep_mihomo_proxy_port)}"
    local line
    if ep_proxy_port_socket_listening "$port"; then
        return 0
    fi
    if ep_command_exists nc && nc -z -w 1 "$host" "$port" >/dev/null 2>&1; then
        return 0
    fi
    if ep_mihomo_run_bounded_port_probe 1 bash -c ": </dev/tcp/$host/$port" >/dev/null 2>&1; then
        return 0
    fi
    if ep_command_exists lsof; then
        line="$(
            ep_mihomo_run_bounded_port_probe 2 \
                lsof -nP -iTCP:"$port" -sTCP:LISTEN 2>/dev/null |
                awk 'NR == 2 { print; exit }' || true
        )"
        [ -n "$line" ] && return 0
    fi
    return 1
}

ep_mihomo_api_healthy()
{
    local api_port="${1:-$(ep_mihomo_api_port)}"
    ep_command_exists curl || return 1
    curl --noproxy '*' --connect-timeout 1 --max-time 2 \
        -fsS -o /dev/null "http://127.0.0.1:$api_port/version" 2>/dev/null
}

ep_mihomo_asset_version()
{
    local name
    name="$(basename "$1")"
    printf '%s' "$name" | sed -nE 's/.*-(v[0-9]+\.[0-9]+\.[0-9]+)\.(gz|zip)$/\1/p'
}

ep_mihomo_binary_version()
{
    local binary="$1"
    local probe_binary="$binary"
    local probe_dir=""
    local output=""
    local timeout_seconds="${EP_MIHOMO_VERSION_TIMEOUT:-5}"
    local copy_probe=false
    [ -x "$binary" ] || return 1

    case "$timeout_seconds" in
        ''|*[!0-9]*) timeout_seconds=5 ;;
    esac
    [ "$timeout_seconds" -ge 1 ] 2>/dev/null || timeout_seconds=5

    case "$binary" in
        /tmp/*) ;;
        *) copy_probe=true ;;
    esac
    [ "${EP_MIHOMO_VERSION_PROBE_FORCE_COPY:-0}" = "1" ] && copy_probe=true
    if [ "$copy_probe" = true ]; then
        [ -d /tmp ] && [ -w /tmp ] || return 1
        probe_dir="$(mktemp -d /tmp/envpilot-mihomo-version.XXXXXX 2>/dev/null || true)"
        [ -n "$probe_dir" ] || return 1
        probe_binary="$probe_dir/mihomo"
        if ! cp "$binary" "$probe_binary" 2>/dev/null; then
            rm -rf "$probe_dir"
            return 1
        fi
        chmod 700 "$probe_binary" 2>/dev/null || {
            rm -rf "$probe_dir"
            return 1
        }
    fi

    if ep_command_exists timeout; then
        output="$(timeout -k 1 "$timeout_seconds" "$probe_binary" -v 2>/dev/null || true)"
    elif ep_command_exists gtimeout; then
        output="$(gtimeout -k 1 "$timeout_seconds" "$probe_binary" -v 2>/dev/null || true)"
    elif ep_command_exists perl; then
        output="$(perl -e '
            my $seconds = shift @ARGV;
            alarm $seconds;
            exec @ARGV;
            exit 126;
        ' "$timeout_seconds" "$probe_binary" -v 2>/dev/null || true)"
    else
        [ -n "$probe_dir" ] && rm -rf "$probe_dir"
        return 1
    fi
    [ -n "$probe_dir" ] && rm -rf "$probe_dir"

    printf '%s\n' "$output" |
        head -n 1 |
        sed -nE 's/.*(v[0-9]+\.[0-9]+\.[0-9]+).*/\1/p'
}

ep_mihomo_process_pattern()
{
    printf '%s' '(^|/)[Mm]ihomo([[:space:]]|$)'
}

ep_mihomo_existing_processes()
{
    local user_name pattern
    user_name="${USER:-$(id -un 2>/dev/null || true)}"
    pattern="$(ep_mihomo_process_pattern)"
    [ -n "$user_name" ] || return 0
    if ! ep_command_exists pgrep; then
        return 0
    fi
    pgrep -u "$user_name" -af "$pattern" 2>/dev/null || true
}

ep_mihomo_processes_are_managed()
{
    local processes="$1"
    local managed_bin runtime_bin line pid exe

    [ -n "$processes" ] || return 1
    managed_bin="$(ep_mihomo_bin)"
    runtime_bin="$(ep_mihomo_runtime_bin)"
    while IFS= read -r line; do
        [ -n "$line" ] || continue
        pid="$(printf '%s\n' "$line" | awk '{print $1}')"
        exe=""
        if [ -n "$pid" ] && [ -e "/proc/$pid/exe" ] && ep_command_exists readlink; then
            exe="$(readlink -f "/proc/$pid/exe" 2>/dev/null || true)"
        fi
        if [ -n "$exe" ]; then
            case "$exe" in
                "$managed_bin"|"$runtime_bin") ;;
                *) return 1 ;;
            esac
        else
            case "$line" in
                *"$managed_bin"*|*"$runtime_bin"*) ;;
                *) return 1 ;;
            esac
        fi
    done <<EOF
$processes
EOF
    return 0
}

ep_mihomo_existing_process_versions()
{
    local processes="$1"
    local line pid exe version
    while IFS= read -r line; do
        [ -n "$line" ] || continue
        pid="$(printf '%s\n' "$line" | awk '{print $1}')"
        exe=""
        if [ -n "$pid" ] && [ -e "/proc/$pid/exe" ] && ep_command_exists readlink; then
            exe="$(readlink -f "/proc/$pid/exe" 2>/dev/null || true)"
        fi
        if [ -n "$exe" ] && [ -x "$exe" ]; then
            version="$(ep_mihomo_binary_version "$exe" 2>/dev/null || true)"
        else
            version="unknown"
        fi
        printf 'pid=%s version=%s\n' "$pid" "${version:-unknown}"
    done <<EOF
$processes
EOF
}

ep_mihomo_port_state()
{
    if ep_proxy_port_is_listening 127.0.0.1 "$1"; then
        printf 'true'
    else
        printf 'false'
    fi
}

ep_mihomo_clear_proxy_environment()
{
    local was_set=false
    [ -n "${http_proxy:-}" ] && was_set=true
    [ -n "${https_proxy:-}" ] && was_set=true
    [ -n "${HTTP_PROXY:-}" ] && was_set=true
    [ -n "${HTTPS_PROXY:-}" ] && was_set=true
    [ -n "${all_proxy:-}" ] && was_set=true
    [ -n "${ALL_PROXY:-}" ] && was_set=true
    [ -n "${no_proxy:-}" ] && was_set=true
    [ -n "${NO_PROXY:-}" ] && was_set=true
    EP_MIHOMO_TAKEOVER_PROXY_ENV_WAS_SET="$was_set"
    unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY all_proxy ALL_PROXY no_proxy NO_PROXY
    EP_MIHOMO_TAKEOVER_PROXY_ENV_CLEARED=true
    if [ "$was_set" = true ]; then
        ep_log "Cleared inherited proxy environment for the takeover; old proxy variables will not be used."
    fi
}

ep_mihomo_write_takeover_report()
{
    local result="${1:-${EP_MIHOMO_TAKEOVER_RESULT:-in_progress}}"
    local report="${EP_MIHOMO_TAKEOVER_REPORT_FILE:-$HOME/.config/envpilot/mihomo-takeover-report.json}"
    local existing_processes="${EP_MIHOMO_TAKEOVER_EXISTING_PROCESSES:-}"
    local existing_versions="${EP_MIHOMO_TAKEOVER_EXISTING_PROCESS_VERSIONS:-}"
    local selected_source="${EP_MIHOMO_TAKEOVER_SELECTED_SOURCE:-}"
    local selected_version="${EP_MIHOMO_TAKEOVER_SELECTED_VERSION:-}"
    local binary_before="${EP_MIHOMO_TAKEOVER_BINARY_BEFORE_VERSION:-}"
    local binary_action="${EP_MIHOMO_TAKEOVER_BINARY_ACTION:-not_selected}"
    local proxy_port="${EP_MIHOMO_TAKEOVER_PROXY_PORT:-$(ep_mihomo_proxy_port)}"
    local api_port="${EP_MIHOMO_TAKEOVER_API_PORT:-$(ep_mihomo_api_port)}"
    mkdir -p "$(dirname "$report")"
    cat > "$report.tmp" <<EOF
{
  "run_id": "$(printf '%s' "${EP_RUN_ID:-unknown}" | ep_json_escape)",
  "generated_at": "$(ep_iso_now)",
  "action": "mihomo_takeover",
  "result": "$(printf '%s' "$result" | ep_json_escape)",
  "target_binary": "$(printf '%s' "$(ep_mihomo_bin)" | ep_json_escape)",
  "target_config": "$(printf '%s' "$(ep_mihomo_config_file)" | ep_json_escape)",
  "target_ports": {
    "proxy": $proxy_port,
    "api": $api_port
  },
  "before_ports": {
    "proxy_listening": ${EP_MIHOMO_TAKEOVER_BEFORE_PROXY_LISTENING:-false},
    "api_listening": ${EP_MIHOMO_TAKEOVER_BEFORE_API_LISTENING:-false}
  },
  "after_stop_ports": {
    "proxy_listening": ${EP_MIHOMO_TAKEOVER_AFTER_PROXY_LISTENING:-false},
    "api_listening": ${EP_MIHOMO_TAKEOVER_AFTER_API_LISTENING:-false}
  },
  "existing_processes": "$(printf '%s' "$existing_processes" | ep_json_escape)",
  "existing_process_versions": "$(printf '%s' "$existing_versions" | ep_json_escape)",
  "existing_processes_detected": ${EP_MIHOMO_TAKEOVER_EXISTING_DETECTED:-false},
  "existing_processes_envpilot_managed": ${EP_MIHOMO_TAKEOVER_EXISTING_MANAGED:-false},
  "managed_runtime_was_running": ${EP_MIHOMO_TAKEOVER_MANAGED_RUNTIME_WAS_RUNNING:-false},
  "existing_processes_stopped": ${EP_MIHOMO_TAKEOVER_EXISTING_STOPPED:-false},
  "stop_signals": "$(printf '%s' "${EP_MIHOMO_TAKEOVER_STOP_SIGNALS:-none}" | ep_json_escape)",
  "proxy_environment_was_set": ${EP_MIHOMO_TAKEOVER_PROXY_ENV_WAS_SET:-false},
  "proxy_environment_cleared_for_install": ${EP_MIHOMO_TAKEOVER_PROXY_ENV_CLEARED:-false},
  "binary_before_version": "$(printf '%s' "$binary_before" | ep_json_escape)",
  "selected_source": "$(printf '%s' "$selected_source" | ep_json_escape)",
  "selected_version": "$(printf '%s' "$selected_version" | ep_json_escape)",
  "selected_source_version": "$(printf '%s' "$selected_version" | ep_json_escape)",
  "binary_action": "$(printf '%s' "$binary_action" | ep_json_escape)",
  "previous_config_disabled": ${EP_MIHOMO_TAKEOVER_PREVIOUS_CONFIG_DISABLED:-false},
  "existing_config_preserved": ${EP_MIHOMO_TAKEOVER_EXISTING_CONFIG_PRESERVED:-false},
  "managed_runtime_restarted": ${EP_MIHOMO_TAKEOVER_MANAGED_RUNTIME_RESTARTED:-false}
}
EOF
    mv "$report.tmp" "$report"
    EP_MIHOMO_TAKEOVER_REPORT_FILE="$report"
    ep_log "Mihomo takeover report: $report"
}

ep_mihomo_stop_existing_processes()
{
    local processes remaining user_name pattern count
    user_name="${USER:-$(id -un 2>/dev/null || true)}"
    pattern="$(ep_mihomo_process_pattern)"
    processes="${EP_MIHOMO_TAKEOVER_EXISTING_PROCESSES:-$(ep_mihomo_existing_processes)}"
    if [ -z "$processes" ]; then
        EP_MIHOMO_TAKEOVER_EXISTING_STOPPED=true
        EP_MIHOMO_TAKEOVER_STOP_SIGNALS=none
        ep_log "No existing user-owned Mihomo process found."
        return 0
    fi
    EP_MIHOMO_TAKEOVER_EXISTING_DETECTED=true
    if [ "${EP_MIHOMO_TAKEOVER_EXISTING_MANAGED:-false}" = true ]; then
        ep_log "Stopping the existing envpilot-managed Mihomo runtime before update:"
        printf '%s\n' "$processes" | sed 's/^/[INFO]   /'
    else
        ep_warn "Existing user-owned Mihomo process(es) detected; they will be stopped before envpilot takeover:"
        printf '%s\n' "$processes" | sed 's/^/[WARN]   /' >&2
    fi
    if ! ep_command_exists pkill; then
        EP_MIHOMO_TAKEOVER_EXISTING_STOPPED=false
        EP_MIHOMO_TAKEOVER_STOP_SIGNALS=unavailable
        ep_mihomo_write_takeover_report stop_failed
        ep_die "pkill is required to stop existing Mihomo processes safely."
    fi
    ep_log "Sending SIGTERM to existing Mihomo process(es) and waiting ${EP_MIHOMO_TAKEOVER_WAIT_SECONDS:-5}s."
    pkill -TERM -u "$user_name" -f "$pattern" 2>/dev/null || true
    EP_MIHOMO_TAKEOVER_STOP_SIGNALS=TERM
    count=0
    while [ "$count" -lt "${EP_MIHOMO_TAKEOVER_WAIT_SECONDS:-5}" ]; do
        remaining="$(ep_mihomo_existing_processes)"
        [ -z "$remaining" ] && break
        sleep 1
        count=$((count + 1))
    done
    remaining="$(ep_mihomo_existing_processes)"
    if [ -n "$remaining" ]; then
        ep_warn "Some Mihomo process(es) did not stop after SIGTERM; sending SIGKILL."
        pkill -KILL -u "$user_name" -f "$pattern" 2>/dev/null || true
        EP_MIHOMO_TAKEOVER_STOP_SIGNALS=TERM,KILL
        sleep 1
        remaining="$(ep_mihomo_existing_processes)"
    fi
    if [ -n "$remaining" ]; then
        EP_MIHOMO_TAKEOVER_EXISTING_STOPPED=false
        ep_mihomo_write_takeover_report stop_failed
        ep_die "Could not stop all existing user-owned Mihomo processes."
    fi
    EP_MIHOMO_TAKEOVER_EXISTING_STOPPED=true
    ep_log "Existing Mihomo process(es) stopped."
}
ep_mihomo_runtime_running()
{
    local runtime_bin user_name
    runtime_bin="$(ep_mihomo_runtime_bin)"
    user_name="${USER:-$(id -un 2>/dev/null || true)}"
    [ -n "$user_name" ] || return 1
    pgrep -u "$user_name" -f "$runtime_bin" >/dev/null 2>&1
}

ep_cleanup_mihomo_runtime()
{
    local runtime_dir lock_dir
    runtime_dir="$(ep_mihomo_runtime_dir)"
    lock_dir="${runtime_dir}.start.lock"
    case "$runtime_dir" in
        /tmp/*_mihomo_*) ;;
        *) ep_warn "Skip unsafe Mihomo runtime cleanup target: $runtime_dir"; return 0 ;;
    esac
    if [ -d "$runtime_dir" ]; then
        rm -rf -- "$runtime_dir"
        ep_log "Removed Mihomo runtime directory: $runtime_dir"
    fi
    if [ -d "$lock_dir" ]; then
        rm -rf -- "$lock_dir"
        ep_log "Removed Mihomo start lock: $lock_dir"
    fi
}

ep_start_mihomo()
{
    local proxy_port api_port start_script
    proxy_port="$(ep_mihomo_proxy_port)"
    api_port="$(ep_mihomo_api_port)"
    read -r proxy_port api_port <<EOF
$(ep_require_mihomo_ports "$proxy_port" "$api_port")
EOF
    ep_mihomo_refresh_scripts
    start_script="$(ep_mihomo_script start_mihomo.sh)"
    [ -x "$start_script" ] || ep_die "Mihomo start script not found: $start_script"
    MIHOMO_PROXY_PORT="$proxy_port" MIHOMO_API_PORT="$api_port" "$start_script"
}

ep_stop_mihomo()
{
    local proxy_port api_port stop_script
    proxy_port="$(ep_mihomo_proxy_port)"
    api_port="$(ep_mihomo_api_port)"
    ep_mihomo_refresh_scripts
    stop_script="$(ep_mihomo_script stop_mihomo.sh)"
    if [ -x "$stop_script" ]; then
        MIHOMO_PROXY_PORT="$proxy_port" MIHOMO_API_PORT="$api_port" "$stop_script"
        return
    fi
    ep_log "No envpilot-managed mihomo process found."
}

ep_status_mihomo()
{
    local proxy_port api_port status_script
    proxy_port="$(ep_mihomo_proxy_port)"
    api_port="$(ep_mihomo_api_port)"
    ep_mihomo_refresh_scripts
    status_script="$(ep_mihomo_script status_mihomo.sh)"
    if [ -x "$status_script" ]; then
        MIHOMO_PROXY_PORT="$proxy_port" MIHOMO_API_PORT="$api_port" "$status_script"
        return
    fi
    ep_die "Mihomo status script not found: $status_script"
}

ep_update_mihomo_subscription()
{
    local subscription="${1:-}" proxy_port api_port update_script
    proxy_port="$(ep_mihomo_proxy_port)"
    api_port="$(ep_mihomo_api_port)"
    ep_mihomo_refresh_scripts
    update_script="$(ep_mihomo_script update_mihomo_subscription.sh)"
    [ -x "$update_script" ] || ep_die "Mihomo subscription update script not found: $update_script"
    MIHOMO_PROXY_PORT="$proxy_port" MIHOMO_API_PORT="$api_port" "$update_script" "$subscription"
}

ep_switch_mihomo_ports()
{
    local proxy_port api_port old_proxy old_api config bin reload_hint
    read -r proxy_port api_port <<EOF
$(ep_require_mihomo_ports "${1:-}" "${2:-}")
EOF
    config="$(ep_mihomo_config_file)"
    bin="$(ep_mihomo_bin)"
    [ -x "$bin" ] || ep_die "mihomo executable not found: $bin"
    [ -s "$config" ] || ep_die "mihomo config not found: $config. Run: bash envpilot.sh install mihomo"

    old_proxy="$(ep_mihomo_proxy_port)"
    old_api="$(ep_mihomo_api_port)"
    ep_log "Plan: switch Mihomo proxy and API ports"
    ep_log "Current: proxy=127.0.0.1:$old_proxy API=127.0.0.1:$old_api"
    ep_log "New:     proxy=127.0.0.1:$proxy_port API=127.0.0.1:$api_port"
    ep_log "Will update: $config"
    ep_log "Will update: $(ep_mihomo_shell_local_file)"
    ep_log "Will restart envpilot-managed Mihomo."

    ep_stop_mihomo
    if ep_proxy_port_is_listening 127.0.0.1 "$proxy_port"; then
        MIHOMO_PROXY_PORT="$old_proxy" MIHOMO_API_PORT="$old_api" ep_start_mihomo || true
        ep_die "Target proxy port 127.0.0.1:$proxy_port is already in use. Choose another port."
    fi
    if ep_proxy_port_is_listening 127.0.0.1 "$api_port"; then
        MIHOMO_PROXY_PORT="$old_proxy" MIHOMO_API_PORT="$old_api" ep_start_mihomo || true
        ep_die "Target API port 127.0.0.1:$api_port is already in use. Choose another port."
    fi

    ep_backup_file "$config"
    ep_patch_mihomo_config "$config" "$proxy_port" "$api_port"
    ep_mihomo_set_shell_local_ports "$proxy_port" "$api_port"
    ep_mihomo_refresh_scripts
    MIHOMO_PROXY_PORT="$proxy_port" MIHOMO_API_PORT="$api_port" ep_start_mihomo

    reload_hint="$(ep_mihomo_shell_reload_hint)"
    ep_log "Switched Mihomo ports: proxy=$proxy_port API=$api_port"
    ep_log "For current shell variables, run: proxy_off; $reload_hint; proxy_on"
}

ep_switch_mihomo_port()
{
    ep_switch_mihomo_ports "${1:-}" "$(ep_mihomo_api_port)"
}

ep_mihomo_cli()
{
    local action="${1:-status}"
    local value1="${2:-}"
    local value2="${3:-}"
    case "$action" in
        start) ep_start_mihomo ;;
        stop) ep_stop_mihomo ;;
        status) ep_status_mihomo ;;
        port) ep_switch_mihomo_port "$value1" ;;
        ports) ep_switch_mihomo_ports "$value1" "$value2" ;;
        update-subscription|subscription) ep_update_mihomo_subscription "$value1" ;;
        *) ep_die "Unknown Mihomo action: $action. Use start, stop, status, port PORT, ports PROXY_PORT API_PORT, or update-subscription [URL]." ;;
    esac
}
ep_doctor_mihomo()
{
    local bin cached offline_pattern config_dir geo_path proxy_port api_port runtime_bin

    bin="$(ep_mihomo_bin)"
    runtime_bin="$(ep_mihomo_runtime_bin)"
    config_dir="$HOME/.config/mihomo"
    offline_pattern="$(ep_mihomo_offline_pattern)"
    proxy_port="$(ep_mihomo_proxy_port)"
    api_port="$(ep_mihomo_api_port)"
    if [ -x "$bin" ]; then
        ep_log "mihomo: found at $bin"
    else
        ep_warn "mihomo: not found at $bin"
    fi
    cached="$(ep_find_cached_asset "$offline_pattern" 2>/dev/null || true)"
    if [ -n "$cached" ]; then
        ep_log "mihomo cache for $EP_OS/$EP_ARCH: found at $cached"
    else
        ep_warn "mihomo cache for $EP_OS/$EP_ARCH: not found in downloads/"
    fi
    for geo_path in country.mmdb geoip.metadb; do
        if [ -f "$config_dir/$geo_path" ]; then
            ep_log "mihomo data: found at $config_dir/$geo_path"
        else
            cached="$(ep_find_cached_asset "$geo_path" 2>/dev/null || true)"
            if [ -n "$cached" ]; then
                ep_log "mihomo data cache: found at $cached"
            else
                ep_warn "mihomo data: $geo_path not found in $config_dir or downloads/"
            fi
        fi
    done
    ep_log "Mihomo ports: proxy=127.0.0.1:$proxy_port API=127.0.0.1:$api_port"
    if ep_proxy_port_is_listening 127.0.0.1 "$proxy_port"; then
        ep_log "Proxy port: 127.0.0.1:$proxy_port listening"
    else
        ep_warn "Proxy port: 127.0.0.1:$proxy_port not detected"
    fi
    if ep_proxy_port_is_listening 127.0.0.1 "$api_port"; then
        ep_log "API port: 127.0.0.1:$api_port listening"
    else
        ep_warn "API port: 127.0.0.1:$api_port not detected"
    fi
    if ep_mihomo_runtime_running; then
        ep_log "Mihomo runtime: running from $runtime_bin"
    else
        ep_warn "Mihomo runtime: not running on this node ($runtime_bin)"
    fi
}
ep_yaml_set_scalar()
{
    local config="$1"
    local key="$2"
    local value="$3"
    local tmp
    if grep -q "^$key:" "$config" 2>/dev/null; then
        sed -i.bak -E "s|^$key:.*|$key: $value|" "$config"
        rm -f "$config.bak"
    else
        tmp="$(mktemp "${TMPDIR:-/tmp}/envpilot-mihomo-yaml.XXXXXX")"
        printf '%s: %s\n' "$key" "$value" > "$tmp"
        cat "$config" >> "$tmp"
        mv "$tmp" "$config"
    fi
}

ep_patch_mihomo_config()
{
    local config="$1"
    local proxy_port="${2:-$(ep_mihomo_proxy_port)}"
    local api_port="${3:-$(ep_mihomo_api_port)}"
    read -r proxy_port api_port <<EOF
$(ep_require_mihomo_ports "$proxy_port" "$api_port")
EOF
    ep_yaml_set_scalar "$config" "allow-lan" "false"
    ep_yaml_set_scalar "$config" "mixed-port" "$proxy_port"
    ep_yaml_set_scalar "$config" "bind-address" "127.0.0.1"
    ep_yaml_set_scalar "$config" "external-controller" "127.0.0.1:$api_port"
}
ep_install_mihomo()
{
    ep_require_unix_runtime
    local bin install_dir config_dir asset_regex offline_pattern archive source version
    local proxy_port api_port subscription source_version binary_before_version binary_action disabled_config
    local config_before_present report_action
    bin="$(ep_mihomo_bin)"
    install_dir="$(dirname "$bin")"
    config_dir="$HOME/.config/mihomo"
    config_before_present=false
    [ -f "$config_dir/config.yaml" ] && config_before_present=true
    asset_regex="$(ep_mihomo_asset_regex)"
    offline_pattern="$(ep_mihomo_offline_pattern)"
    archive="$(mktemp "${TMPDIR:-/tmp}/envpilot-mihomo.XXXXXX")"
    source=""
    subscription=""
    binary_action="not_selected"
    report_action=installed
    [ "$EP_UPGRADE" = "1" ] && report_action=updated
    EP_MIHOMO_TAKEOVER_RESULT=in_progress
    EP_MIHOMO_TAKEOVER_EXISTING_PROCESSES=""
    EP_MIHOMO_TAKEOVER_EXISTING_PROCESS_VERSIONS=""
    EP_MIHOMO_TAKEOVER_EXISTING_DETECTED=false
    EP_MIHOMO_TAKEOVER_EXISTING_STOPPED=false
    EP_MIHOMO_TAKEOVER_STOP_SIGNALS=none
    EP_MIHOMO_TAKEOVER_PROXY_ENV_WAS_SET=false
    EP_MIHOMO_TAKEOVER_PROXY_ENV_CLEARED=false
    EP_MIHOMO_TAKEOVER_PREVIOUS_CONFIG_DISABLED=false
    EP_MIHOMO_TAKEOVER_EXISTING_MANAGED=false
    EP_MIHOMO_TAKEOVER_MANAGED_RUNTIME_WAS_RUNNING=false
    EP_MIHOMO_TAKEOVER_MANAGED_RUNTIME_RESTARTED=false
    EP_MIHOMO_TAKEOVER_EXISTING_CONFIG_PRESERVED=false
    proxy_port="$(ep_mihomo_proxy_port)"
    api_port="$(ep_mihomo_api_port)"
    read -r proxy_port api_port <<EOF
$(ep_require_mihomo_ports "$proxy_port" "$api_port")
EOF
    EP_MIHOMO_TAKEOVER_PROXY_PORT="$proxy_port"
    EP_MIHOMO_TAKEOVER_API_PORT="$api_port"

    ep_log "Component: mihomo"
    ep_log "Selected stable asset rule for $EP_OS/$EP_ARCH: $asset_regex"
    ep_log "Offline asset pattern: $offline_pattern"
    ep_log "Before takeover, register at https://proxy.yanhuoapi.com/ and prepare a Clash/Mihomo subscription URL."
    EP_MIHOMO_TAKEOVER_EXISTING_PROCESSES="$(ep_mihomo_existing_processes)"
    EP_MIHOMO_TAKEOVER_EXISTING_PROCESS_VERSIONS="$(ep_mihomo_existing_process_versions "$EP_MIHOMO_TAKEOVER_EXISTING_PROCESSES")"
    if ep_mihomo_processes_are_managed "$EP_MIHOMO_TAKEOVER_EXISTING_PROCESSES"; then
        EP_MIHOMO_TAKEOVER_EXISTING_MANAGED=true
        EP_MIHOMO_TAKEOVER_MANAGED_RUNTIME_WAS_RUNNING=true
    fi
    EP_MIHOMO_TAKEOVER_BEFORE_PROXY_LISTENING="$(ep_mihomo_port_state "$proxy_port")"
    EP_MIHOMO_TAKEOVER_BEFORE_API_LISTENING="$(ep_mihomo_port_state "$api_port")"
    if [ -x "$bin" ]; then
        ep_log "Checking the existing target version from a bounded node-local probe."
    fi
    binary_before_version="$(ep_mihomo_binary_version "$bin" 2>/dev/null || true)"
    EP_MIHOMO_TAKEOVER_BINARY_BEFORE_VERSION="$binary_before_version"

    if [ -n "$EP_MIHOMO_TAKEOVER_EXISTING_PROCESSES" ]; then
        EP_MIHOMO_TAKEOVER_EXISTING_DETECTED=true
        if [ "$EP_MIHOMO_TAKEOVER_EXISTING_MANAGED" = true ]; then
            ep_log "Existing envpilot-managed Mihomo process(es) found; configuration and running state will be preserved."
            printf '%s\n' "$EP_MIHOMO_TAKEOVER_EXISTING_PROCESSES" | sed 's/^/[INFO]   /'
        else
            ep_warn "External Mihomo process(es) found; envpilot will take them over after confirmation:"
            printf '%s\n' "$EP_MIHOMO_TAKEOVER_EXISTING_PROCESSES" | sed 's/^/[WARN]   /' >&2
        fi
        if [ -n "$EP_MIHOMO_TAKEOVER_EXISTING_PROCESS_VERSIONS" ]; then
            ep_log "Existing Mihomo executable versions:"
            printf '%s\n' "$EP_MIHOMO_TAKEOVER_EXISTING_PROCESS_VERSIONS" | sed 's/^/[INFO]   /'
        fi
    else
        ep_log "No existing user-owned Mihomo process detected."
    fi
    if [ -n "$binary_before_version" ]; then
        ep_log "Existing envpilot target binary: $bin ($binary_before_version)"
    else
        ep_log "No usable envpilot target binary found at $bin; a compatible stable binary will be installed."
    fi

    if [ "$EP_MODE" = "offline" ]; then
        source="$(ep_find_offline_asset "$offline_pattern")"
    else
        source="$(ep_find_cached_asset "$offline_pattern" 2>/dev/null || true)"
        if [ -n "$source" ]; then
            ep_log "Using bundled downloads/ Mihomo asset for $EP_OS/$EP_ARCH before network: $source"
        else
            ep_log "No bundled Mihomo binary was found; the stable GitHub asset will be resolved after the old proxy is stopped."
        fi
    fi
    if [ -n "$source" ]; then
        ep_log "Candidate source: $source"
    fi
    ep_log "Target ports after takeover: proxy=127.0.0.1:$proxy_port API=127.0.0.1:$api_port"
    ep_log "The existing user-owned Mihomo process will be stopped, the target ports will be checked, and the takeover will be recorded."

    if ! ep_confirm "Take over Mihomo and install/update the envpilot-managed binary?" "yes"; then
        EP_MIHOMO_TAKEOVER_RESULT=user_declined
        ep_mihomo_write_takeover_report user_declined
        ep_report_event mihomo skipped "user declined Mihomo takeover" "" "$source" "$bin"
        rm -f "$archive"
        return 0
    fi

    ep_mihomo_stop_existing_processes
    ep_mihomo_clear_proxy_environment
    EP_MIHOMO_TAKEOVER_AFTER_PROXY_LISTENING="$(ep_mihomo_port_state "$proxy_port")"
    EP_MIHOMO_TAKEOVER_AFTER_API_LISTENING="$(ep_mihomo_port_state "$api_port")"
    if [ "$EP_MIHOMO_TAKEOVER_AFTER_PROXY_LISTENING" = true ]; then
        EP_MIHOMO_TAKEOVER_RESULT=proxy_port_blocked
        ep_mihomo_write_takeover_report proxy_port_blocked
        rm -f "$archive"
        ep_die "Target proxy port 127.0.0.1:$proxy_port remains occupied after stopping Mihomo. Choose another MIHOMO_PROXY_PORT."
    fi
    if [ "$EP_MIHOMO_TAKEOVER_AFTER_API_LISTENING" = true ]; then
        EP_MIHOMO_TAKEOVER_RESULT=api_port_blocked
        ep_mihomo_write_takeover_report api_port_blocked
        rm -f "$archive"
        ep_die "Target API port 127.0.0.1:$api_port remains occupied after stopping Mihomo. Choose another MIHOMO_API_PORT."
    fi

    if [ -z "$source" ]; then
        source="$(ep_github_asset_url MetaCubeX mihomo "$asset_regex")"
    fi
    source_version="$(ep_mihomo_asset_version "$source" 2>/dev/null || true)"
    EP_MIHOMO_TAKEOVER_SELECTED_SOURCE="$source"
    EP_MIHOMO_TAKEOVER_SELECTED_VERSION="$source_version"
    if [ -n "$binary_before_version" ] && [ -n "$source_version" ] && [ "$binary_before_version" = "$source_version" ]; then
        binary_action=kept-current
        ep_log "Existing target Mihomo binary is already current: $binary_before_version; binary replacement will be skipped."
    else
        binary_action=installed-or-updated
        if [ -n "$binary_before_version" ]; then
            ep_log "Existing target Mihomo binary is $binary_before_version; selected stable source is ${source_version:-unknown}, so it will be updated."
        else
            ep_log "No current target binary is available; selected stable source version is ${source_version:-unknown}."
        fi
    fi
    EP_MIHOMO_TAKEOVER_BINARY_ACTION="$binary_action"
    EP_MIHOMO_TAKEOVER_RESULT=ports_ready
    ep_mihomo_write_takeover_report ports_ready

    ep_log "Plan: install/update envpilot-managed Mihomo"
    ep_log "Source: $source"
    ep_log "Persistent binary: $bin"
    ep_log "Persistent config: $config_dir/config.yaml"
    ep_log "Runtime directory: $(ep_mihomo_runtime_dir)"
    ep_log "Scripts: $install_dir/start_mihomo.sh, stop_mihomo.sh, status_mihomo.sh, update_mihomo_subscription.sh"
    ep_log "Geodata: $config_dir/country.mmdb and $config_dir/geoip.metadb"
    ep_log "Ports: proxy=127.0.0.1:$proxy_port API=127.0.0.1:$api_port"
    ep_log "Security: allow-lan=false, bind-address=127.0.0.1"

    mkdir -p "$install_dir" "$config_dir"
    chmod 700 "$config_dir"
    ep_mihomo_set_shell_local_ports "$proxy_port" "$api_port"

    if [ "$binary_action" != kept-current ]; then
        if [ -f "$source" ]; then
            ep_download_note "Using local Mihomo source: $source"
            cp "$source" "$archive"
        else
            ep_fetch_url "$source" "$archive"
        fi
        case "$source" in
            *.zip)
                ep_command_exists unzip || ep_die "unzip is required for Windows Mihomo archives"
                unzip -p "$archive" '*mihomo*.exe' > "$bin" || ep_die "Could not extract Mihomo from $source"
                ;;
            *)
                gzip -dc "$archive" > "$bin" || ep_die "Could not extract gzip Mihomo asset: $source"
                ;;
        esac
        chmod 755 "$bin"
        ep_log "Installed Mihomo binary: $bin"
    fi

    ep_mihomo_refresh_scripts
    ep_install_mihomo_data_assets "$config_dir"

    subscription="${ENVPILOT_MIHOMO_SUBSCRIPTION_URL:-}"
    if [ -z "$subscription" ] &&
       [ "$EP_ASSUME_YES" != "1" ] &&
       { [ "$EP_UPGRADE" != "1" ] || [ "$config_before_present" != true ]; }; then
        ep_prompt_optional_url subscription "Paste Clash/Mihomo subscription URL"
    elif [ -z "$subscription" ] && [ "$config_before_present" = true ]; then
        ep_log "Existing envpilot Mihomo config detected; update will preserve it without requesting the subscription again."
    fi

    if [ -n "$subscription" ]; then
        ep_backup_file "$config_dir/config.yaml"
        ep_fetch_url "$subscription" "$config_dir/config.yaml.tmp"
        mv "$config_dir/config.yaml.tmp" "$config_dir/config.yaml"
        ep_patch_mihomo_config "$config_dir/config.yaml" "$proxy_port" "$api_port"
        chmod 600 "$config_dir/config.yaml"
        ep_log "Wrote Mihomo config: $config_dir/config.yaml"
        ep_log "Applied local-only ports: proxy=$proxy_port API=$api_port"
    elif [ "$config_before_present" = true ] && [ -f "$config_dir/config.yaml" ]; then
        EP_MIHOMO_TAKEOVER_EXISTING_CONFIG_PRESERVED=true
        ep_log "Preserved the existing envpilot-managed Mihomo subscription config: $config_dir/config.yaml"
    elif [ "$EP_MIHOMO_TAKEOVER_EXISTING_DETECTED" = true ] && [ -f "$config_dir/config.yaml" ]; then
        ep_backup_file "$config_dir/config.yaml"
        disabled_config="$config_dir/config.yaml.disabled.$(ep_timestamp)"
        mv "$config_dir/config.yaml" "$disabled_config"
        EP_MIHOMO_TAKEOVER_PREVIOUS_CONFIG_DISABLED=true
        ep_warn "Disabled the previous Mihomo config to prevent reuse of the old proxy channel: $disabled_config"
        ep_warn "Run: mihomo update-subscription '<Clash/Mihomo URL>'"
    else
        ep_warn "No subscription URL provided; Mihomo binary installed but config.yaml was not written."
        ep_warn "Later run: mihomo update-subscription '<Clash/Mihomo URL>'"
    fi

    rm -f "$archive"
    version="$source_version"
    if [ -z "$version" ]; then
        version="$(ep_mihomo_binary_version "$bin" 2>/dev/null || true)"
    fi
    if [ "$EP_MIHOMO_TAKEOVER_MANAGED_RUNTIME_WAS_RUNNING" = true ]; then
        if [ -s "$config_dir/config.yaml" ]; then
            ep_log "Restoring the envpilot-managed Mihomo runtime that was running before the update."
            if MIHOMO_PROXY_PORT="$proxy_port" MIHOMO_API_PORT="$api_port" ep_start_mihomo; then
                EP_MIHOMO_TAKEOVER_MANAGED_RUNTIME_RESTARTED=true
                ep_log "Restored envpilot-managed Mihomo on proxy port $proxy_port and API port $api_port."
            else
                EP_MIHOMO_TAKEOVER_RESULT=restart_failed
                ep_mihomo_write_takeover_report restart_failed
                ep_die "Mihomo update completed, but the previous envpilot-managed runtime could not be restarted."
            fi
        else
            ep_warn "Mihomo was previously running, but config.yaml is unavailable; runtime was not restarted."
        fi
    fi

    EP_MIHOMO_TAKEOVER_RESULT=completed
    ep_mihomo_write_takeover_report completed
    ep_state_mark_done mihomo
    ep_report_event mihomo "$report_action" "updated managed Mihomo or took over external Mihomo; preserved managed config and running state" "$version" "$source" "$bin"
    if [ "$EP_MIHOMO_TAKEOVER_MANAGED_RUNTIME_RESTARTED" = true ]; then
        ep_log "Mihomo update complete; the previously running envpilot-managed runtime is active again."
    else
        ep_log "Mihomo takeover complete. It is not auto-started; after a valid subscription config exists, run: mihomo start"
    fi
}
