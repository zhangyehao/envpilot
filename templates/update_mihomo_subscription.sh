#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=templates/mihomo_common.sh
. "$SCRIPT_DIR/mihomo_common.sh"
mihomo_init_runtime

subscription_url="${1:-${ENVPILOT_MIHOMO_SUBSCRIPTION_URL:-}}"
if [ -z "$subscription_url" ] && [ -t 0 ]; then
    printf 'Paste Clash/Mihomo subscription URL: '
    IFS= read -r subscription_url
fi
case "$subscription_url" in
    http://*|https://*) ;;
    *) mihomo_die "provide a Clash/Mihomo subscription URL beginning with http:// or https://" ;;
esac

mkdir -p "$MIHOMO_SOURCE_CONFIG"
chmod 700 "$MIHOMO_SOURCE_CONFIG"
new_config="$(mktemp "$MIHOMO_SOURCE_CONFIG/config.yaml.new.XXXXXX")"
backup=""
was_running="0"
trap 'rm -f "$new_config"' EXIT

if mihomo_command_exists curl; then
    curl -fL --connect-timeout 15 --retry 2 --progress-bar \
        "$subscription_url" -o "$new_config"
elif mihomo_command_exists wget; then
    wget -O "$new_config" "$subscription_url"
else
    mihomo_die "curl or wget is required to update the subscription"
fi

[ -s "$new_config" ] || mihomo_die "downloaded subscription config is empty"
if grep -qiE '^[[:space:]]*<(html|!doctype)' "$new_config"; then
    mihomo_die "downloaded content looks like HTML, not a Mihomo configuration"
fi
mihomo_apply_local_config "$new_config"
chmod 600 "$new_config"

if [ -e "$MIHOMO_SOURCE_CONFIG/config.yaml" ]; then
    backup="$MIHOMO_SOURCE_CONFIG/config.yaml.bak.$(date +%Y%m%d%H%M%S)"
    cp -p "$MIHOMO_SOURCE_CONFIG/config.yaml" "$backup"
    printf '[INFO] backup: %s\n' "$backup"
fi
if mihomo_runtime_running; then
    was_running="1"
    "$SCRIPT_DIR/stop_mihomo.sh"
fi
mv "$new_config" "$MIHOMO_SOURCE_CONFIG/config.yaml"
trap - EXIT

if [ "$was_running" = "1" ]; then
    if ! "$SCRIPT_DIR/start_mihomo.sh"; then
        if [ -n "$backup" ] && [ -f "$backup" ]; then
            cp -p "$backup" "$MIHOMO_SOURCE_CONFIG/config.yaml"
            printf '[WARN] restored previous subscription after restart failure.\n' >&2
            "$SCRIPT_DIR/start_mihomo.sh" || true
        fi
        exit 1
    fi
fi

printf '[OK] Mihomo subscription updated.\n'
printf '[OK] proxy: %s:%s\n' "$MIHOMO_PROXY_HOST" "$MIHOMO_PROXY_PORT"
printf '[OK] API:   %s:%s\n' "$MIHOMO_PROXY_HOST" "$MIHOMO_API_PORT"