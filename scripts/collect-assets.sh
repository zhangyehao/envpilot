#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "${BASH_SOURCE[0]%/*}/.." && pwd)"
DESTINATION="${ENVPILOT_ASSET_DESTINATION:-$ROOT/downloads}"
MAX_DEPTH="${ENVPILOT_ASSET_MAX_DEPTH:-5}"
DRY_RUN="0"
UPLOAD_RELEASE="0"
TAG="${ENVPILOT_RELEASE_TAG:-offline-cache-manual}"
REPO="${ENVPILOT_REPO:-zhangyehao/envpilot}"
MAX_SIZE_MB="${ENVPILOT_ASSET_MAX_SIZE_MB:-1300}"

while [ "$#" -gt 0 ]; do
    case "$1" in
        --destination) DESTINATION="$2"; shift 2 ;;
        --max-depth) MAX_DEPTH="$2"; shift 2 ;;
        --dry-run) DRY_RUN="1"; shift ;;
        --upload-release) UPLOAD_RELEASE="1"; shift ;;
        --tag) TAG="$2"; shift 2 ;;
        --repo) REPO="$2"; shift 2 ;;
        *) break ;;
    esac
done

if [ "$#" -gt 0 ]; then
    ROOTS=("$@")
else
    ROOTS=(
        "$HOME/Downloads"
        "$HOME/software"
        "/tmp"
        "/mnt/d/software"
        "/mnt/d/downloads"
        "/mnt/e/software"
        "/mnt/e/downloads"
        "/mnt/e/mihomo"
    )
fi

mkdir -p "$DESTINATION"

is_stable_name()
{
    case "$1" in
        *alpha*|*Alpha*|*ALPHA*|*beta*|*Beta*|*BETA*|*rc*|*RC*|*pre*|*PRE*|*nightly*|*snapshot*) return 1 ;;
        *) return 0 ;;
    esac
}

matches_asset_pattern()
{
    case "$1" in
        Miniconda3-*.sh|Miniconda3-*.exe|Anaconda3-*.sh|Anaconda3-*.exe|mihomo-*.gz|mihomo-*.zip|gh_*_linux_*.tar.gz|gh_*_macOS_*.zip|gh_*_windows_*.zip|GitHubCLI*.msi|node-v*.tar.gz|node-v*.tar.xz|node-v*.pkg|node-v*.msi) return 0 ;;
        *) return 1 ;;
    esac
}

copied_files=""
for root in "${ROOTS[@]}"; do
    [ -d "$root" ] || {
        printf '[INFO] Skip missing root: %s\n' "$root"
        continue
    }
    printf '[INFO] Scan root: %s\n' "$root"
    while IFS= read -r -d '' file; do
        name="$(basename "$file")"
        matches_asset_pattern "$name" || continue
        is_stable_name "$name" || continue
        size_mb=$(( ($(wc -c < "$file") + 1048575) / 1048576 ))
        if [ "$size_mb" -gt "$MAX_SIZE_MB" ]; then
            printf '[WARN] Skip large asset > %sMB: %s\n' "$MAX_SIZE_MB" "$file" >&2
            continue
        fi
        target="$DESTINATION/$name"
        if [ "$DRY_RUN" = "1" ]; then
            printf '[DRYRUN] %s -> %s\n' "$file" "$target"
        else
            if [ -e "$target" ]; then
                printf '[INFO] Exists, skip: %s\n' "$target"
            else
                cp "$file" "$target"
                printf '[INFO] Copied: %s\n' "$target"
            fi
        fi
        copied_files="${copied_files}${target}"$'\n'
    done < <(find "$root" -maxdepth "$MAX_DEPTH" -type f -print0 2>/dev/null)
done

if [ "$DRY_RUN" = "0" ]; then
    {
        printf '[\n'
        first="1"
        while IFS= read -r file; do
            [ -n "$file" ] || continue
            [ -f "$file" ] || continue
            [ "$first" = "1" ] || printf ',\n'
            first="0"
            printf '  {"name": "%s", "path": "%s"}' "$(basename "$file")" "$file"
        done <<< "$copied_files"
        printf '\n]\n'
    } > "$DESTINATION/assets-index.json"
fi

if [ "$UPLOAD_RELEASE" = "1" ] && [ "$DRY_RUN" = "0" ]; then
    if [ "$REPO" = "zhangyehao/envpilot" ]; then
        case "$TAG" in
            v[0-9]*.[0-9]*.[0-9]*)
                printf '[ERROR] Do not upload third-party installers to normal envpilot version releases. Use a dedicated offline-cache tag or a separate cache repository.\n' >&2
                exit 1
                ;;
        esac
    fi
    command -v gh >/dev/null 2>&1 || {
        printf '[ERROR] gh not found; cannot upload release assets.\n' >&2
        exit 1
    }
    while IFS= read -r file; do
        [ -n "$file" ] || continue
        [ -f "$file" ] || continue
        gh release upload "$TAG" "$file" --repo "$REPO" --clobber
    done <<< "$copied_files"
fi

