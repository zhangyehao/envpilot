#!/usr/bin/env bash

ep_mihomo_bin()
{
    printf '%s/software/mihomo/mihomo' "$HOME"
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
    local port="${1:-7890}"
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
    local port="${2:-7890}"
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

ep_stop_mihomo()
{
    local bin user_name pids pid stopped i
    bin="$(ep_mihomo_bin)"
    user_name="${USER:-$(id -un 2>/dev/null || true)}"
    stopped="0"

    [ -n "$user_name" ] || return 0

    if ep_command_exists pkill; then
        if pkill -u "$user_name" -f "$bin" >/dev/null 2>&1; then
            stopped="1"
        fi
    else
        pids="$(ps -u "$user_name" -o pid=,args= 2>/dev/null | awk -v pat="$bin" 'index($0, pat) { print $1 }' || true)"
        for pid in $pids; do
            kill "$pid" >/dev/null 2>&1 && stopped="1"
        done
    fi

    if [ "$stopped" = "1" ]; then
        i=0
        while [ "$i" -lt 10 ]; do
            if ! ep_proxy_port_is_listening 127.0.0.1 7890; then
                ep_log "Stopped mihomo: $bin"
                return 0
            fi
            sleep 1
            i=$((i + 1))
        done
        ep_warn "mihomo stop was requested, but proxy port 127.0.0.1:7890 is still reachable. Another process may be listening."
    else
        ep_log "No envpilot-managed mihomo process found."
    fi
}

ep_start_mihomo()
{
    local bin start_script log_file i
    bin="$(ep_mihomo_bin)"
    start_script="$(dirname "$bin")/start_mihomo.sh"
    log_file="$HOME/logs/mihomo.log"

    ep_require_unix_runtime
    if ep_proxy_port_is_listening 127.0.0.1 7890; then
        ep_log "Proxy port 127.0.0.1:7890 is already listening."
        return 0
    fi
    if [ -x "$start_script" ]; then
        "$start_script"
    elif [ -x "$bin" ]; then
        [ -s "$HOME/.config/mihomo/config.yaml" ] || ep_die "mihomo config not found: $HOME/.config/mihomo/config.yaml"
        mkdir -p "$(dirname "$log_file")"
        nohup "$bin" -d "$HOME/.config/mihomo" >> "$log_file" 2>&1 < /dev/null &
    else
        ep_die "mihomo executable not found: $bin"
    fi

    i=0
    while [ "$i" -lt 20 ]; do
        if ep_proxy_port_is_listening 127.0.0.1 7890; then
            ep_log "mihomo proxy port is listening: 127.0.0.1:7890"
            return 0
        fi
        sleep 1
        i=$((i + 1))
    done
    ep_die "mihomo did not open proxy port 127.0.0.1:7890 within 20 seconds. Check: $log_file"
}

ep_status_mihomo()
{
    local bin user_name pids
    bin="$(ep_mihomo_bin)"
    user_name="${USER:-$(id -un 2>/dev/null || true)}"

    printf 'envpilot mihomo binary:\n'
    if [ -x "$bin" ]; then
        printf '  %s\n' "$bin"
    else
        printf '  not found: %s\n' "$bin"
    fi
    printf '\nmihomo process:\n'
    if [ -n "$user_name" ] && ep_command_exists pgrep; then
        pgrep -u "$user_name" -af "$bin" || printf '  not running\n'
    elif [ -n "$user_name" ]; then
        pids="$(ps -u "$user_name" -o pid=,args= 2>/dev/null | awk -v pat="$bin" 'index($0, pat) { print }' || true)"
        if [ -n "$pids" ]; then
            printf '%s\n' "$pids"
        else
            printf '  not running\n'
        fi
    else
        printf '  not running\n'
    fi
    printf '\nproxy port:\n'
    if ep_proxy_port_socket_listening 7890; then
        printf '  127.0.0.1:7890 listening\n'
    elif ep_proxy_port_is_listening 127.0.0.1 7890; then
        printf '  127.0.0.1:7890 reachable via TCP connect\n'
    else
        printf '  127.0.0.1:7890 not detected\n'
    fi
}

ep_mihomo_cli()
{
    local action="${1:-status}"
    case "$action" in
        start) ep_start_mihomo ;;
        stop) ep_stop_mihomo ;;
        status) ep_status_mihomo ;;
        *) ep_die "Unknown mihomo action: $action. Use start, stop, or status." ;;
    esac
}

ep_doctor_mihomo()
{
    local bin cached offline_pattern config_dir geo_path

    bin="$(ep_mihomo_bin)"
    config_dir="$HOME/.config/mihomo"
    offline_pattern="$(ep_mihomo_offline_pattern)"
    if [ -x "$bin" ]; then
        ep_log "mihomo: found at $bin"
    else
        ep_warn "mihomo: not found at $bin"
    fi
    cached="$(ep_find_cached_asset "$offline_pattern" 2>/dev/null || true)"
    if [ -n "$cached" ]; then
        ep_log "mihomo cache: found at $cached"
    else
        ep_warn "mihomo cache: not found in downloads/"
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
    if ep_proxy_port_socket_listening 7890; then
        ep_log "Proxy port: 127.0.0.1:7890 listening"
    elif ep_proxy_port_is_listening 127.0.0.1 7890; then
        ep_log "Proxy port: 127.0.0.1:7890 reachable via TCP connect"
    else
        ep_warn "Proxy port: 127.0.0.1:7890 not detected"
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
    ep_yaml_set_scalar "$config" "allow-lan" "false"
    ep_yaml_set_scalar "$config" "mixed-port" "7890"
    ep_yaml_set_scalar "$config" "bind-address" "127.0.0.1"
}

ep_install_mihomo()
{
    ep_require_unix_runtime
    local bin install_dir config_dir asset_regex offline_pattern archive source version
    bin="$(ep_mihomo_bin)"
    install_dir="$(dirname "$bin")"
    config_dir="$HOME/.config/mihomo"
    asset_regex="$(ep_mihomo_asset_regex)"
    offline_pattern="$(ep_mihomo_offline_pattern)"
    archive="$(mktemp "${TMPDIR:-/tmp}/envpilot-mihomo.XXXXXX")"
    source=""

    ep_log "Component: mihomo"
    ep_log "Selected stable asset rule for $EP_OS/$EP_ARCH: $asset_regex"
    ep_log "Offline asset pattern: $offline_pattern"
    ep_log "Before config download, register at https://proxy.yanhuoapi.com/ and copy the Clash/Mihomo subscription URL."

    if [ "$EP_MODE" = "offline" ]; then
        source="$(ep_find_offline_asset "$offline_pattern")"
    else
        source="$(ep_find_cached_asset "$offline_pattern" 2>/dev/null || true)"
        if [ -n "$source" ]; then
            ep_log "Using bundled downloads/ mihomo asset before network: $source"
        else
            source="$(ep_github_asset_url MetaCubeX mihomo "$asset_regex")"
        fi
    fi
    ep_log "Plan: install mihomo"
    ep_log "Source: $source"
    ep_log "Target: $bin"
    ep_log "Will write: $install_dir/start_mihomo.sh"
    ep_log "Will hydrate data: $config_dir/country.mmdb and $config_dir/geoip.metadb"
    ep_log "Optional config: $config_dir/config.yaml"
    ep_log "Proxy defaults: 127.0.0.1:7890, allow-lan=false, bind-address=127.0.0.1"

    ep_confirm "Install mihomo from the source above to $bin?" "yes" || {
        ep_report_event mihomo skipped "user declined" "" "$source" "$bin"
        rm -f "$archive"
        return 0
    }

    mkdir -p "$install_dir" "$config_dir" "$HOME/logs"
    if [ -f "$source" ]; then
        cp "$source" "$archive"
    else
        ep_fetch_url "$source" "$archive"
    fi

    case "$source" in
        *.zip)
            ep_command_exists unzip || ep_die "unzip is required for Windows mihomo archives"
            unzip -p "$archive" '*mihomo*.exe' > "$bin" || ep_die "Could not extract mihomo from $source"
            ;;
        *)
            gzip -dc "$archive" > "$bin" || ep_die "Could not extract gzip mihomo asset: $source"
            ;;
    esac
    chmod 755 "$bin"
    cp "$ENVPILOT_ROOT/templates/start_mihomo.sh" "$install_dir/start_mihomo.sh"
    chmod 755 "$install_dir/start_mihomo.sh"
    ep_install_mihomo_data_assets "$config_dir"

    version=""
    subscription="${ENVPILOT_MIHOMO_SUBSCRIPTION_URL:-}"
    if [ -z "$subscription" ] && [ "$EP_ASSUME_YES" != "1" ]; then
        ep_prompt_optional_url subscription "Paste Clash/Mihomo subscription URL"
    fi

    if [ -n "$subscription" ]; then
        ep_backup_file "$config_dir/config.yaml"
        ep_fetch_url "$subscription" "$config_dir/config.yaml.tmp"
        mv "$config_dir/config.yaml.tmp" "$config_dir/config.yaml"
        ep_patch_mihomo_config "$config_dir/config.yaml"
        ep_log "Wrote mihomo config: $config_dir/config.yaml"
        ep_log "Forced mihomo security defaults: allow-lan=false, bind-address=127.0.0.1, mixed-port=7890"
    else
        ep_warn "No subscription URL provided; mihomo binary installed but config.yaml was not written."
        ep_warn "Later run: ENVPILOT_MIHOMO_SUBSCRIPTION_URL='<Clash/Mihomo URL>' bash envpilot.sh install mihomo"
    fi

    rm -f "$archive"
    ep_state_mark_done mihomo
    version="$("$bin" -v 2>/dev/null | head -n 1 || true)"
    ep_report_event mihomo installed "installed mihomo; config may require subscription" "$version" "$source" "$bin"
}
