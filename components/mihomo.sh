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

ep_doctor_mihomo()
{
    local bin cached offline_pattern

    bin="$(ep_mihomo_bin)"
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
    if ep_command_exists ss && ss -lntH "sport = :7890" 2>/dev/null | grep -q .; then
        ep_log "Proxy port: 7890 is listening"
    else
        ep_warn "Proxy port: 7890 not detected"
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
    local bin install_dir config_dir asset_regex offline_pattern asset archive source version
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
