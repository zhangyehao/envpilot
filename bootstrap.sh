#!/usr/bin/env bash
set -euo pipefail

REPO_URL="${ENVPILOT_REPO_URL:-https://github.com/zhangyehao/envpilot.git}"
TARGET_DIR="${1:-envpilot}"

command -v git >/dev/null 2>&1 || {
    printf '[ERROR] git is required.\n' >&2
    exit 1
}
[ ! -e "$TARGET_DIR" ] || {
    printf '[ERROR] target already exists: %s\n' "$TARGET_DIR" >&2
    exit 1
}

case "$(uname -s 2>/dev/null || true)" in
    Linux) platform="linux" ;;
    Darwin) platform="darwin" ;;
    MINGW*|MSYS*|CYGWIN*) platform="windows" ;;
    *) platform="unknown" ;;
esac
case "$(uname -m 2>/dev/null || true)" in
    x86_64|amd64) arch="amd64" ;;
    aarch64|arm64) arch="arm64" ;;
    *) arch="unknown" ;;
esac

asset_pattern=""
case "$platform:$arch" in
    linux:amd64) asset_pattern="/downloads/mihomo-linux-amd64-compatible-*.gz" ;;
    windows:amd64) asset_pattern="/downloads/mihomo-windows-amd64-compatible-*.zip" ;;
esac

git_version="$(git --version | awk '{print $3}')"
git_major="${git_version%%.*}"
git_rest="${git_version#*.}"
git_minor="${git_rest%%.*}"
if [ "$git_major" -gt 2 ] || { [ "$git_major" -eq 2 ] && [ "$git_minor" -ge 25 ]; }; then
    printf '[INFO] detected platform: %s/%s\n' "$platform" "$arch"
    printf '[INFO] cloning scripts and only the matching bundled Mihomo cache.\n'
    git clone --filter=blob:none --no-checkout "$REPO_URL" "$TARGET_DIR"
    git -C "$TARGET_DIR" sparse-checkout init --no-cone
    sparse_file="$(git -C "$TARGET_DIR" rev-parse --git-path info/sparse-checkout)"
    {
        printf '/*\n'
        printf '!/downloads/*\n'
        printf '/downloads/.gitkeep\n'
        printf '/downloads/country.mmdb\n'
        printf '/downloads/geoip.metadb\n'
        [ -n "$asset_pattern" ] && printf '%s\n' "$asset_pattern"
    } > "$TARGET_DIR/$sparse_file"
    git -C "$TARGET_DIR" checkout main
else
    printf '[WARN] this Git version lacks partial clone/sparse checkout support.\n' >&2
    printf '[WARN] falling back to a normal HTTPS clone, which downloads every tracked cache.\n' >&2
    git clone "$REPO_URL" "$TARGET_DIR"
fi

printf '[OK] envpilot is ready: %s\n' "$TARGET_DIR"
printf '[INFO] next: cd %s && bash envpilot.sh doctor\n' "$TARGET_DIR"