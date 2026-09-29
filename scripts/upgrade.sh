#!/usr/bin/env bash
# One-time bridge for 0.3.0 (which has no self-update command).
set -euo pipefail
umask 077
root="${1:-$HOME/envpilot}"
config_dir="${ENVPILOT_CONFIG_DIR:-$HOME/.config/envpilot}"
config_file="${ENVPILOT_CONFIG_FILE:-$config_dir/config.yaml}"
if [ ! -f "$root/envpilot.sh" ] || [ ! -f "$root/VERSION" ]; then
    printf 'Not an envpilot source checkout / 不是 envpilot 源码目录: %s\n' "$root" >&2; exit 1
fi
root="$(cd "$root" && pwd)"
git -C "$root" rev-parse --git-dir >/dev/null
[ -z "$(git -C "$root" status --porcelain)" ] || {
    printf 'Save local changes first / 请先保存源码中的未提交修改。\n' >&2; exit 1
}
git -C "$root" fetch origin --tags
tag="$(git -C "$root" tag --list 'v[0-9]*' --sort=-version:refname | sed -n '/^v[0-9]*\.[0-9]*\.[0-9]*$/ {p;q;}')"
[ -n "$tag" ] || { printf 'No stable release / 未找到稳定版。\n' >&2; exit 1; }
git -C "$root" merge-base --is-ancestor HEAD "$tag" || {
    printf 'Checkout is ahead or diverged; preserved / 当前源码超前或有分叉，已保留。\n' >&2; exit 1
}
# Preserve the pre-migration files even when the old installer has no snapshots.
backup="$config_dir/upgrade-backups/$(date -u +%Y%m%dT%H%M%S)-$$"
mkdir -p "$backup"
for relative in .bashrc .zshrc .config/envpilot/shell.local .config/envpilot/config.yaml .local/bin/envpilot; do
    if [ -f "$HOME/$relative" ]; then
        mkdir -p "$backup/$(dirname "$relative")"
        cp -p "$HOME/$relative" "$backup/$relative"
    fi
done
git -C "$root" rev-parse HEAD > "$backup/source-commit"
git -C "$root" merge --ff-only "$tag"
bash "$root/envpilot.sh" setup-command --config "$config_file"
if [ ! -e "$config_file" ]; then bash "$root/envpilot.sh" init --config "$config_file"; fi
bash "$root/envpilot.sh" config validate --config "$config_file"
bash "$root/envpilot.sh" apply-shell --yes --non-interactive --config "$config_file"
# Refresh copied component managers using the new helper.
core_path="$config_dir/core-path"
[ -r "$core_path" ] || exit 1
IFS= read -r core < "$core_path"
"$core" refresh --root "$root" --config "$config_file"
bash "$root/envpilot.sh" version
printf 'Upgrade backup / 升级前备份: %s\n' "$backup"
printf 'Next / 后续: envpilot self-update; envpilot updates enable\n'
