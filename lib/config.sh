#!/usr/bin/env bash

ep_core_path()
{
    local candidate suffix="" version
    version="$(tr -d '\r\n' < "$ENVPILOT_ROOT/VERSION")"
    case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) suffix=.exe ;; esac
    for candidate in "${ENVPILOT_CORE:-}" "$ENVPILOT_ROOT/bin/envpilot-core$suffix" "$HOME/.local/lib/envpilot/$version/envpilot-core$suffix"; do
        if [ -n "$candidate" ] && [ -x "$candidate" ] && [ "$("$candidate" version 2>/dev/null)" = "$version" ]; then
            printf '%s' "$candidate"; return 0
        fi
    done
    return 1
}

ep_core_sha256()
{
    if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{print $1}'
    elif command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | awk '{print $1}'
    else openssl dgst -sha256 "$1" | awk '{print $NF}'; fi
}

ep_ensure_core()
{
    ep_core_path >/dev/null && return 0
    local version platform arch suffix="" name base directory tmp expected binary_url checksum_url release_id binary_id checksum_id
    version="$(cat "$ENVPILOT_ROOT/VERSION")"
    case "$(uname -s)" in Linux) platform=linux ;; Darwin) platform=darwin ;; MINGW*|MSYS*|CYGWIN*) platform=windows; suffix=.exe ;; *) ep_die 'Unsupported platform for envpilot-core.' ;; esac
    arch="$(ep_normalize_arch "$(uname -m)")"
    name="envpilot-core-$version-$platform-$arch$suffix"
    directory="$HOME/.local/lib/envpilot/$version"
    if [ "${EP_MODE:-online}" = offline ]; then ep_die 'Offline configuration requires the matching envpilot platform package (including bin/envpilot-core).'; fi
    mkdir -p "$directory"
    tmp="$(mktemp -d "$directory/.download.XXXXXX")" || return 1
    case "${ENVPILOT_RELEASE_SOURCE:-github}" in
        gitee)
            base='https://gitee.com/api/v5/repos/zhangyehao0422/envpilot'
            if ! curl -fsSL --connect-timeout 10 --max-time 90 --retry 3 "$base/releases/tags/v$version" -o "$tmp/release.json"; then rm -rf "$tmp"; ep_die 'Could not resolve the Gitee release.'; fi
            release_id="$(awk -v mode=release -f "$ENVPILOT_ROOT/lib/bootstrap-json.awk" "$tmp/release.json")"
            [ "$(awk -v mode=tag -f "$ENVPILOT_ROOT/lib/bootstrap-json.awk" "$tmp/release.json")" = "v$version" ] || { rm -rf "$tmp"; ep_die 'Gitee release tag mismatch.'; }
            case "$release_id" in ''|*[!0-9]*) rm -rf "$tmp"; ep_die 'Invalid Gitee release ID.' ;; esac
            if ! curl -fsSL --connect-timeout 10 --max-time 90 --retry 3 "$base/releases/$release_id/attach_files?per_page=100" -o "$tmp/assets.json"; then rm -rf "$tmp"; ep_die 'Could not resolve Gitee attachments.'; fi
            binary_id="$(awk -v mode=asset -v wanted="$name" -f "$ENVPILOT_ROOT/lib/bootstrap-json.awk" "$tmp/assets.json")"
            checksum_id="$(awk -v mode=asset -v wanted=SHA256SUMS -f "$ENVPILOT_ROOT/lib/bootstrap-json.awk" "$tmp/assets.json")"
            case "$binary_id:$checksum_id" in *[!0-9:]*|:*|*:) rm -rf "$tmp"; ep_die 'Required Gitee attachments are missing; use a complete platform package.' ;; esac
            binary_url="$base/releases/$release_id/attach_files/$binary_id/download"
            checksum_url="$base/releases/$release_id/attach_files/$checksum_id/download"
            ;;
        *)
            base="https://github.com/zhangyehao/envpilot/releases/download/v$version"
            binary_url="$base/$name"; checksum_url="$base/SHA256SUMS"
            ;;
    esac
    if ! curl -fSL --connect-timeout 10 --max-time 180 --retry 3 "$binary_url" -o "$tmp/$name" || ! curl -fsSL --connect-timeout 10 --max-time 90 --retry 3 "$checksum_url" -o "$tmp/SHA256SUMS"; then rm -rf "$tmp"; ep_die 'Could not fetch envpilot-core; use a complete platform package.'; fi
    expected="$(awk -v name="$name" '$2 == name { print $1 }' "$tmp/SHA256SUMS")"
    if [ -z "$expected" ] || [ "$(ep_core_sha256 "$tmp/$name")" != "$expected" ]; then rm -rf "$tmp"; ep_die 'envpilot-core checksum verification failed.'; fi
    chmod 700 "$tmp/$name"
    mv "$tmp/$name" "$directory/envpilot-core$suffix"
    rm -rf "$tmp"
    [ "$("$directory/envpilot-core$suffix" version)" = "$version" ] || ep_die 'envpilot-core version mismatch.'
}

ep_core()
{
    local executable
    executable="$(ep_core_path)" || { ep_ensure_core; executable="$(ep_core_path)"; }
    "$executable" "$@" --config "${EP_CONFIG_FILE:-${ENVPILOT_CONFIG_DIR:-$HOME/.config/envpilot}/config.yaml}" --root "$ENVPILOT_ROOT"
}

ep_config_load()
{
    local key value file
    file="$(mktemp)" || return 1
    if ! ep_core export --format nul > "$file"; then rm -f "$file"; return 1; fi
    while IFS= read -r -d '' key && IFS= read -r -d '' value; do
        printf -v "$key" '%s' "$value"
        export "${key?}"
    done < "$file"
    rm -f "$file"
}

ep_snapshot()
{
    local snapshot
    snapshot="$(ep_core snapshot)" || return 1
    ep_log "Snapshot: $snapshot"
}

ep_apply_config()
{
    ep_core plan
    ep_core preflight
    if [ "${EP_ASSUME_YES:-0}" != 1 ]; then
        ep_confirm "Apply this configuration?" no || return 0
    fi
    ep_snapshot
    EP_CONFIG_APPLY=1
    export EP_CONFIG_APPLY
    local component
    for component in mihomo git python conda mamba codex github tmux; do
        case " ${ENVPILOT_COMPONENTS:-} " in *" $component "*) export EP_COMPONENT="$component"; run_install ;; esac
    done
    if [ "${ENVPILOT_SHELL_ENABLED:-1}" = 1 ]; then run_apply_shell; fi
    if [ "${ENVPILOT_CODEX_ENABLED:-0}" = 1 ]; then run_codex_enable; fi
}

run_codex_enable() { ep_init; ep_platform_detect; ep_codex_remote_enable; }

ep_self_update()
{
    local tag previous manager
    ep_init
    if [ ! -d "$ENVPILOT_ROOT/.git" ] && [ ! -f "$ENVPILOT_ROOT/.git" ]; then
        ep_core self-update
        return
    fi
    [ -z "$(git -C "$ENVPILOT_ROOT" status --porcelain)" ] || ep_die 'Commit or save local changes before self-update.'
    git -C "$ENVPILOT_ROOT" fetch origin --tags
    tag="$(git -C "$ENVPILOT_ROOT" tag --list 'v[0-9]*' --sort=-version:refname | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | head -n 1)"
    [ -n "$tag" ] || ep_die 'No stable envpilot tag found.'
    previous="$(git -C "$ENVPILOT_ROOT" rev-parse HEAD)"
    git -C "$ENVPILOT_ROOT" merge-base --is-ancestor HEAD "$tag" || ep_die 'The checkout is ahead of or diverged from the stable release; no files were changed.'
    ep_snapshot
    git -C "$ENVPILOT_ROOT" merge --ff-only "$tag"
    ep_setup_command
    manager="$(ep_codex_remote_manager_path)"
    if [ -f "$manager" ]; then ep_codex_remote_install_manager; fi
    # Execute the updated entrypoint so copied scripts use the new implementation.
    if ! EP_CONFIG_APPLY=1 bash "$ENVPILOT_ROOT/envpilot.sh" apply-shell --yes --non-interactive; then
        ep_warn "Shell migration needs review. Previous source commit: $previous; managed-file snapshot is available through envpilot restore."
        return 1
    fi
    ep_core refresh
    ep_log "envpilot updated to $tag."
}
