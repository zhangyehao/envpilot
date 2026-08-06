#!/usr/bin/env bash

EP_GIT_VERSION="${EP_GIT_VERSION:-}"
EP_GIT_MIN_VERSION="${EP_GIT_MIN_VERSION:-2.30}"
ep_git_version()
{
    "$1" --version 2>/dev/null | sed -n 's/.* \([0-9][0-9.]*\).*/\1/p' | head -n 1
}


ep_git_manifest_version()
{
    local manifest version
    manifest="$(ep_manifest_path git)"
    version="$(sed -n '/"latest"[[:space:]]*:/,/^[[:space:]]*}[[:space:]]*$/ s/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$manifest" | head -n 1)"
    [ -n "$version" ] || version="2.51.0"
    printf '%s' "$version"
}

ep_git_source_url()
{
    printf 'https://www.kernel.org/pub/software/scm/git/git-%s.tar.xz' "${EP_GIT_VERSION:-$(ep_git_manifest_version)}"
}

ep_git_offline_pattern()
{
    printf 'git-*.tar.xz'
}

ep_git_managed_bin()
{
    printf '%s/git/current/bin/git' "$EP_PREFIX"
}

ep_doctor_git()
{
    local managed current
    managed="$(ep_git_managed_bin)"
    if ep_command_exists git; then
        current="$(ep_git_version "$(command -v git)")"
        ep_log "Git: found at $(command -v git)"
        git --version 2>/dev/null | sed 's/^/[INFO] Git version: /' || true
        if [ -n "$current" ] && ! ep_version_at_least "$current" "$EP_GIT_MIN_VERSION"; then
            ep_warn "Git $current is below the envpilot minimum $EP_GIT_MIN_VERSION; a user-space Git will be preferred without changing the system Git."
        fi
    elif [ -x "$managed" ]; then
        current="$(ep_git_version "$managed")"
        ep_log "Git: found at $managed"
        "$managed" --version 2>/dev/null | sed 's/^/[INFO] Git version: /' || true
        if [ -z "$current" ] || ! ep_version_at_least "$current" "$EP_GIT_MIN_VERSION"; then
            ep_warn "Managed Git is below the minimum $EP_GIT_MIN_VERSION."
        fi
    else
        ep_warn "Git: not found"
    fi
}

ep_install_git()
{
    ep_require_unix_runtime
    local system_git managed source archive version source_version source_dir target_dir current_dir jobs action system_version managed_version
    system_git="$(command -v git 2>/dev/null || true)"
    managed="$(ep_git_managed_bin)"
    system_version=""
    managed_version=""
    [ -n "$system_git" ] && system_version="$(ep_git_version "$system_git")"
    [ -x "$managed" ] && managed_version="$(ep_git_version "$managed")"
    if [ -n "$system_git" ] && [ "$system_git" != "$managed" ] && [ -n "$system_version" ] && ep_version_at_least "$system_version" "$EP_GIT_MIN_VERSION"; then
        ep_log "Git $system_version already satisfies the minimum $EP_GIT_MIN_VERSION at $system_git; envpilot will not overwrite it."
        ep_state_mark_done git
        ep_report_event git skipped "existing compatible Git retained; system installation was not modified" "$system_version" "system PATH" "$system_git"
        return 0
    fi
    if [ -n "$system_git" ] && [ -n "$system_version" ] && ! ep_version_at_least "$system_version" "$EP_GIT_MIN_VERSION"; then
        ep_warn "System Git $system_version is below $EP_GIT_MIN_VERSION; installing a user-space Git while leaving the system Git unchanged."
    fi
    if [ -x "$managed" ] && [ -n "$managed_version" ] && ep_version_at_least "$managed_version" "$EP_GIT_MIN_VERSION" && [ "$EP_UPGRADE" != "1" ]; then
        ep_log "envpilot-managed Git $managed_version already satisfies $EP_GIT_MIN_VERSION at $managed."
        ep_state_mark_done git
        ep_report_event git skipped "already installed; use update git to rebuild the manifest target" "$managed_version" "envpilot" "$managed"
        return 0
    fi
    [ "$EP_OS" != "windows-unix" ] || ep_die "Git is normally supplied by Git Bash/MSYS2 on Windows. Install Git for Windows and rerun doctor."
    ep_command_exists make || ep_die "Git is missing and make is unavailable. Install a compiler toolchain or provide --mode offline --asset-path git-<version>.tar.xz."
    ep_command_exists tar || ep_die "tar is required to build user-space Git."
    if ! ep_command_exists cc && ! ep_command_exists gcc; then
        ep_die "Git is missing and no C compiler was detected. Load a compiler module or install a user-space toolchain first."
    fi

    version="${EP_GIT_VERSION:-$(ep_git_manifest_version)}"
    if ! ep_version_at_least "$version" "$EP_GIT_MIN_VERSION"; then
        ep_die "Selected Git version $version is below the envpilot minimum $EP_GIT_MIN_VERSION. Update manifests or choose a compatible asset."
    fi
    source=""
    if [ "$EP_MODE" = "offline" ]; then
        source="$(ep_find_offline_asset "$(ep_git_offline_pattern)")"
    else
        source="$(ep_find_cached_asset "$(ep_git_offline_pattern)" 2>/dev/null || true)"
        [ -n "$source" ] || source="$(ep_git_source_url)"
    fi
    source_version="$(basename "$source" 2>/dev/null | sed -n -E 's/^git-([0-9]+(\.[0-9]+)+)\.tar\.xz$/\1/p')"
    if [ -n "$source_version" ] && ! ep_version_at_least "$source_version" "$EP_GIT_MIN_VERSION"; then
        if [ "$EP_MODE" = "online" ] && [ "$source" != "$(ep_git_source_url)" ]; then
            ep_warn "Cached Git source $source_version is below $EP_GIT_MIN_VERSION; resolving the online stable source instead."
            source="$(ep_git_source_url)"
            source_version=""
        else
            ep_die "Selected Git source $source_version is below the envpilot minimum $EP_GIT_MIN_VERSION. Provide a newer git-<version>.tar.xz."
        fi
    fi
    [ -z "$source_version" ] || version="$source_version"
    if ! ep_version_at_least "$version" "$EP_GIT_MIN_VERSION"; then
        ep_die "Selected Git version $version is below the envpilot minimum $EP_GIT_MIN_VERSION."
    fi
    ep_log "Component: git"
    ep_log "Selected stable Git source: $version"
    ep_log "Compatibility: build against the current OS/$EP_ARCH/$EP_LIBC toolchain; system Git will remain unchanged."
    ep_log "Source: $source"
    ep_log "Target: $EP_PREFIX/git/current/bin/git"
    ep_log "PATH on the next shell: $HOME/software/git/current/bin"
    ep_confirm "Install user-space Git $version under $EP_PREFIX/git?" "yes" || {
        ep_report_event git skipped "user declined" "" "$source" "$managed"
        return 0
    }

    archive="$(mktemp "${TMPDIR:-/tmp}/envpilot-git.XXXXXX.tar.xz")"
    source_dir="$(mktemp -d "${TMPDIR:-/tmp}/envpilot-git-src.XXXXXX")"
    if [ -f "$source" ]; then cp "$source" "$archive"; else ep_fetch_url "$source" "$archive"; fi
    tar -xf "$archive" -C "$source_dir"
    target_dir="$EP_PREFIX/git/$version"
    mkdir -p "$target_dir"
    source_dir="$(find "$source_dir" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
    [ -n "$source_dir" ] || ep_die "Git source archive did not contain a top-level directory."
    jobs="${ENVPILOT_BUILD_JOBS:-}"
    [ -n "$jobs" ] || jobs="$(getconf _NPROCESSORS_ONLN 2>/dev/null || printf 2)"
    ep_log "Building Git with $jobs job(s); this can take several minutes on a login node."
    (cd "$source_dir" && ./configure --prefix="$target_dir" --with-curl --with-openssl && make -j"$jobs" NO_GETTEXT=YesPlease NO_TCLTK=YesPlease NO_PERL=YesPlease NO_PYTHON=YesPlease all && make NO_GETTEXT=YesPlease NO_TCLTK=YesPlease NO_PERL=YesPlease NO_PYTHON=YesPlease install) || ep_die "User-space Git build failed. Check compiler/development libraries, or use a system/module Git."
    current_dir="$EP_PREFIX/git/current"
    rm -rf -- "$current_dir"
    if ! ln -s "$target_dir" "$current_dir" 2>/dev/null; then
        cp -R "$target_dir" "$current_dir"
    fi
    rm -rf "$source_dir" "$archive"
    [ -x "$managed" ] || ep_die "Git build completed but $managed was not created."
    action=installed
    [ "$EP_UPGRADE" = "1" ] && action=updated
    ep_state_mark_done git
    ep_report_event git "$action" "built a compatible user-space Git without modifying system Git" "$("$managed" --version 2>/dev/null || true)" "$source" "$managed"
    ep_log "Git ready: $managed"
}
