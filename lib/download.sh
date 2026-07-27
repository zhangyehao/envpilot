#!/usr/bin/env bash

ep_fetch_url()
{
    local url="$1"
    local dest="$2"
    mkdir -p "$(dirname "$dest")"
    if ep_command_exists curl; then
        curl -fsSL --retry 3 --connect-timeout 20 "$url" -o "$dest"
    elif ep_command_exists wget; then
        wget -q "$url" -O "$dest"
    else
        ep_die "Neither curl nor wget is available. Install one or use --mode offline."
    fi
}

ep_find_offline_asset()
{
    local pattern="$1"
    local candidate

    if [ -n "${EP_ASSET_PATH:-}" ]; then
        [ -f "$EP_ASSET_PATH" ] || ep_die "--asset-path does not exist: $EP_ASSET_PATH"
        printf '%s' "$EP_ASSET_PATH"
        return 0
    fi

    candidate="$(find "$ENVPILOT_ROOT/downloads" -maxdepth 1 -type f -name "$pattern" 2>/dev/null | sort -r | head -n 1 || true)"
    [ -n "$candidate" ] || ep_die "Offline asset not found in downloads/: $pattern"
    printf '%s' "$candidate"
}

ep_download_or_offline()
{
    local url="$1"
    local offline_pattern="$2"
    local dest="$3"

    if [ "$EP_MODE" = "offline" ]; then
        local asset
        asset="$(ep_find_offline_asset "$offline_pattern")"
        cp "$asset" "$dest"
        printf '%s' "$asset"
        return 0
    fi

    ep_fetch_url "$url" "$dest"
    printf '%s' "$url"
}

ep_github_asset_url()
{
    local owner="$1"
    local repo="$2"
    local asset_regex="$3"
    local api tmp url

    api="https://api.github.com/repos/$owner/$repo/releases"
    tmp="$(mktemp)"
    ep_fetch_url "$api" "$tmp"

    if ep_command_exists jq; then
        url="$(
            jq -r --arg re "$asset_regex" '
              [.[] |
                select(.draft == false) |
                select(.prerelease == false) |
                select((.tag_name | test("alpha|beta|rc|pre"; "i")) | not) |
                .assets[] |
                select(.name | test($re)) |
                select((.name | test("alpha|beta|rc|pre"; "i")) | not) |
                .browser_download_url
              ][0] // empty
            ' "$tmp"
        )"
    else
        url="$(
            grep -E '"browser_download_url":' "$tmp" |
                sed -E 's/.*"browser_download_url": "([^"]+)".*/\1/' |
                grep -E "$asset_regex" |
                grep -Evi 'alpha|beta|rc|pre' |
                head -n 1 || true
        )"
    fi

    rm -f "$tmp"
    [ -n "$url" ] || ep_die "Could not resolve stable GitHub asset for $owner/$repo matching $asset_regex"
    printf '%s' "$url"
}

