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
        darwin:amd64) printf 'mihomo-darwin-amd64-.*\.gz$' ;;
        darwin:arm64) printf 'mihomo-darwin-arm64-.*\.gz$' ;;
        windows-unix:amd64) printf 'mihomo-windows-amd64-compatible-.*\.zip$' ;;
        *) ep_die "No mihomo asset rule for $EP_OS/$EP_ARCH" ;;
    esac
}

ep_doctor_mihomo()
{
    local bin
    bin="$(ep_mihomo_bin)"
    if [ -x "$bin" ]; then
        ep_log "mihomo: found at $bin"
    else
        ep_warn "mihomo: not found at $bin"
    fi
    if ep_command_exists ss && ss -lnt 2>/dev/null | grep -q '127\.0\.0\.1:7890'; then
        ep_log "Proxy port: 127.0.0.1:7890 is listening"
    else
        ep_warn "Proxy port: 127.0.0.1:7890 not detected"
    fi
}

ep_patch_mihomo_config()
{
    local config="$1"
    if grep -q '^allow-lan:' "$config" 2>/dev/null; then
        sed -i.bak 's/^allow-lan:.*/allow-lan: false/' "$config"
    else
        sed -i.bak '1iallow-lan: false' "$config"
    fi
    rm -f "$config.bak"
}

ep_install_mihomo()
{
    ep_require_unix_runtime
    local bin install_dir config_dir asset_regex asset archive source subscription
    bin="$(ep_mihomo_bin)"
    install_dir="$(dirname "$bin")"
    config_dir="$HOME/.config/mihomo"
    asset_regex="$(ep_mihomo_asset_regex)"
    archive="$(mktemp "${TMPDIR:-/tmp}/envpilot-mihomo.XXXXXX")"

    ep_log "Component: mihomo"
    ep_log "Selected asset rule for $EP_OS/$EP_ARCH: $asset_regex"
    ep_log "Install target: $bin"
    ep_log "Config target: $config_dir/config.yaml"
    ep_log "User must provide a Clash/Mihomo subscription URL from https://proxy.yanhuoapi.com/"
    ep_confirm "Install mihomo user-space proxy?" "yes" || {
        ep_report_event mihomo skipped "user declined" "" "" "$bin"
        return 0
    }

    mkdir -p "$install_dir" "$config_dir" "$HOME/logs"
    if [ "$EP_MODE" = "offline" ]; then
        asset="$(ep_find_offline_asset 'mihomo-*')"
        cp "$asset" "$archive"
        source="$asset"
    else
        source="$(ep_github_asset_url MetaCubeX mihomo "$asset_regex")"
        ep_fetch_url "$source" "$archive"
    fi

    case "$source" in
        *.zip)
            ep_command_exists unzip || ep_die "unzip is required for Windows mihomo archives"
            unzip -p "$archive" '*mihomo*.exe' > "$bin" || ep_die "Could not extract mihomo from $source"
            ;;
        *)
            gzip -dc "$archive" > "$bin"
            ;;
    esac
    chmod 755 "$bin"
    cp "$ENVPILOT_ROOT/templates/start_mihomo.sh" "$install_dir/start_mihomo.sh"
    chmod 755 "$install_dir/start_mihomo.sh"

    subscription="${ENVPILOT_MIHOMO_SUBSCRIPTION_URL:-}"
    if [ -z "$subscription" ] && [ "$EP_ASSUME_YES" != "1" ]; then
        ep_prompt_nonempty subscription "Paste Clash/Mihomo subscription URL"
    fi

    if [ -n "$subscription" ]; then
        ep_backup_file "$config_dir/config.yaml"
        ep_fetch_url "$subscription" "$config_dir/config.yaml.tmp"
        mv "$config_dir/config.yaml.tmp" "$config_dir/config.yaml"
        ep_patch_mihomo_config "$config_dir/config.yaml"
        ep_log "Wrote mihomo config with allow-lan=false"
    else
        ep_warn "No subscription URL provided; mihomo binary installed but config.yaml was not written."
    fi

    rm -f "$archive"
    ep_state_mark_done mihomo
    ep_report_event mihomo installed "installed mihomo; config may require subscription" "$("$bin" -v 2>/dev/null | head -n 1 || true)" "$source" "$bin"
}

