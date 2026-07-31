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
    if ep_command_exists lsof; then
        line="$(lsof -nP -iTCP:"$port" -sTCP:LISTEN 2>/dev/null | awk 'NR == 2 { print; exit }' || true)"
        [ -n "$line" ] && return 0
    fi
    if ep_command_exists netstat; then
        line="$(netstat -an 2>/dev/null | grep -E "[.:]${port}[[:space:]].*LISTEN" | head -n 1 || true)"
        [ -n "$line" ] && return 0
    fi
    return 1
}

ep_proxy_port_is_listening()
{
    local host="${1:-127.0.0.1}"
    local port="${2:-$(ep_mihomo_proxy_port)}"
    if ep_proxy_port_socket_listening "$port"; then
        return 0
    fi
    if ep_command_exists nc && nc -z -w 1 "$host" "$port" >/dev/null 2>&1; then
        return 0
    fi
    if ep_command_exists timeout && timeout 1 bash -c ": </dev/tcp/$host/$port" >/dev/null 2>&1; then
        return 0
    fi
    return 1
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
    local runtime_dir
    runtime_dir="$(ep_mihomo_runtime_dir)"
    case "$runtime_dir" in
        /tmp/*_mihomo_*) ;;
        *) ep_warn "Skip unsafe Mihomo runtime cleanup target: $runtime_dir"; return 0 ;;
    esac
    if [ -d "$runtime_dir" ]; then
        rm -rf -- "$runtime_dir"
        ep_log "Removed Mihomo runtime directory: $runtime_dir"
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
    local proxy_port api_port subscription
    bin="$(ep_mihomo_bin)"
    install_dir="$(dirname "$bin")"
    config_dir="$HOME/.config/mihomo"
    asset_regex="$(ep_mihomo_asset_regex)"
    offline_pattern="$(ep_mihomo_offline_pattern)"
    archive="$(mktemp "${TMPDIR:-/tmp}/envpilot-mihomo.XXXXXX")"
    source=""
    proxy_port="$(ep_mihomo_proxy_port)"
    api_port="$(ep_mihomo_api_port)"
    read -r proxy_port api_port <<EOF
$(ep_require_mihomo_ports "$proxy_port" "$api_port")
EOF

    ep_log "Component: mihomo"
    ep_log "Selected stable asset rule for $EP_OS/$EP_ARCH: $asset_regex"
    ep_log "Offline asset pattern: $offline_pattern"
    ep_log "Before config download, register at https://proxy.yanhuoapi.com/ and copy the Clash/Mihomo subscription URL."

    if [ "$EP_MODE" = "offline" ]; then
        source="$(ep_find_offline_asset "$offline_pattern")"
    else
        source="$(ep_find_cached_asset "$offline_pattern" 2>/dev/null || true)"
        if [ -n "$source" ]; then
            ep_log "Using bundled downloads/ Mihomo asset for $EP_OS/$EP_ARCH before network: $source"
        else
            source="$(ep_github_asset_url MetaCubeX mihomo "$asset_regex")"
        fi
    fi
    ep_log "Plan: install Mihomo"
    ep_log "Source: $source"
    ep_log "Persistent binary: $bin"
    ep_log "Persistent config: $config_dir/config.yaml"
    ep_log "Runtime directory: $(ep_mihomo_runtime_dir)"
    ep_log "Will install start/stop/status/update-subscription scripts in $install_dir"
    ep_log "Will hydrate data: $config_dir/country.mmdb and $config_dir/geoip.metadb"
    ep_log "Ports: proxy=127.0.0.1:$proxy_port API=127.0.0.1:$api_port"
    ep_log "Security: allow-lan=false, bind-address=127.0.0.1"
    if ep_proxy_port_is_listening 127.0.0.1 "$proxy_port"; then
        ep_warn "Proxy port 127.0.0.1:$proxy_port is currently in use. Installation can continue, but Mihomo cannot start on this port."
    else
        ep_log "Proxy port availability: 127.0.0.1:$proxy_port is available"
    fi
    if ep_proxy_port_is_listening 127.0.0.1 "$api_port"; then
        ep_warn "API port 127.0.0.1:$api_port is currently in use. Installation can continue, but Mihomo cannot start on this port."
    else
        ep_log "API port availability: 127.0.0.1:$api_port is available"
    fi

    ep_confirm "Install Mihomo from the source above to $bin?" "yes" || {
        ep_report_event mihomo skipped "user declined" "" "$source" "$bin"
        rm -f "$archive"
        return 0
    }

    mkdir -p "$install_dir" "$config_dir"
    chmod 700 "$config_dir"
    ep_mihomo_set_shell_local_ports "$proxy_port" "$api_port"
    if [ -f "$source" ]; then
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
    ep_mihomo_refresh_scripts
    ep_install_mihomo_data_assets "$config_dir"

    subscription="${ENVPILOT_MIHOMO_SUBSCRIPTION_URL:-}"
    if [ -z "$subscription" ] && [ "$EP_ASSUME_YES" != "1" ]; then
        ep_prompt_optional_url subscription "Paste Clash/Mihomo subscription URL"
    fi

    if [ -n "$subscription" ]; then
        ep_backup_file "$config_dir/config.yaml"
        ep_fetch_url "$subscription" "$config_dir/config.yaml.tmp"
        mv "$config_dir/config.yaml.tmp" "$config_dir/config.yaml"
        ep_patch_mihomo_config "$config_dir/config.yaml" "$proxy_port" "$api_port"
        chmod 600 "$config_dir/config.yaml"
        ep_log "Wrote Mihomo config: $config_dir/config.yaml"
        ep_log "Applied local-only ports: proxy=$proxy_port API=$api_port"
    else
        ep_warn "No subscription URL provided; Mihomo binary installed but config.yaml was not written."
        ep_warn "Later run: mihomo update-subscription '<Clash/Mihomo URL>'"
    fi

    rm -f "$archive"
    ep_state_mark_done mihomo
    version="$("$bin" -v 2>/dev/null | head -n 1 || true)"
    ep_report_event mihomo installed "installed Mihomo with node-local runtime scripts; config may require subscription" "$version" "$source" "$bin"
    ep_log "Mihomo is not auto-started. After apply-shell, run: mihomo start"
}
