#!/usr/bin/env bash

ep_tmux_manifest_version()
{
    local manifest version
    manifest="$(ep_manifest_path tmux)"
    version="$(sed -n '/"latest"[[:space:]]*:/,/^[[:space:]]*}[[:space:]]*$/ s/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$manifest" | head -n 1)"
    [ -n "$version" ] || ep_die "tmux latest stable version is missing from $manifest"
    printf '%s' "$version"
}

ep_tmux_target_version()
{
    if [ -n "${EP_TMUX_VERSION:-}" ]; then
        printf '%s' "$EP_TMUX_VERSION"
    else
        ep_tmux_manifest_version
    fi
}

ep_tmux_current_version()
{
    local binary="${1:-tmux}"
    "$binary" -V 2>/dev/null | sed -nE 's/^tmux[[:space:]]+([^[:space:]]+).*/\1/p'
}

ep_tmux_effective_path()
{
    if [ -x "$HOME/.local/bin/tmux" ]; then
        printf '%s' "$HOME/.local/bin/tmux"
    elif ep_command_exists tmux; then
        command -v tmux
    else
        return 1
    fi
}


ep_doctor_tmux()
{
    local target_version
    target_version="$(ep_tmux_target_version)"
    ep_log "tmux target stable version: $target_version"
    if ep_command_exists tmux; then
        ep_log "tmux: found at $(command -v tmux)"
        tmux -V 2>/dev/null | sed 's/^/[INFO] tmux version: /' || true
    else
        ep_warn "tmux: not found"
    fi
}

ep_try_load_tmux_module()
{
    if type module >/dev/null 2>&1; then
        module load tmux >/dev/null 2>&1 || module load tmux/3.2 >/dev/null 2>&1 || true
    fi
}

ep_install_tmux_with_package_manager()
{
    if [ "$EP_OS" = "darwin" ] && ep_command_exists brew; then
        brew upgrade tmux || brew install tmux
        return 0
    fi
    if [ "$EP_IS_ROOT" = "true" ]; then
        if ep_command_exists apt-get; then
            apt-get update && apt-get install -y tmux
            return 0
        fi
        if ep_command_exists dnf; then
            dnf install -y tmux
            return 0
        fi
        if ep_command_exists yum; then
            yum install -y tmux
            return 0
        fi
    fi
    return 1
}

ep_build_tmux_user_space()
{
    local build_root prefix jobs ncurses_v libevent_v tmux_v
    build_root="${TMPDIR:-/tmp}/envpilot-tmux-build-$(ep_timestamp)"
    prefix="$HOME/.local/envpilot"
    jobs="${EP_MAKE_JOBS:-2}"
    ncurses_v="${EP_NCURSES_VERSION:-6.5}"
    libevent_v="${EP_LIBEVENT_VERSION:-2.1.12-stable}"
    tmux_v="${1:-$(ep_tmux_target_version)}"

    for cmd in curl tar make gcc; do
        ep_command_exists "$cmd" || ep_die "User-space tmux build requires $cmd"
    done

    mkdir -p "$build_root" "$prefix" "$HOME/.local/bin"
    ep_log "Building ncurses $ncurses_v, libevent $libevent_v, tmux $tmux_v under $prefix"

    (
        set -e
        cd "$build_root"
        ep_fetch_url "https://invisible-mirror.net/archives/ncurses/ncurses-$ncurses_v.tar.gz" "ncurses.tar.gz"
        tar -xzf ncurses.tar.gz
        cd "ncurses-$ncurses_v"
        ./configure --prefix="$prefix" --with-shared --without-debug --without-ada --enable-widec
        make -j "$jobs"
        make install
    )

    (
        set -e
        cd "$build_root"
        ep_fetch_url "https://github.com/libevent/libevent/releases/download/release-$libevent_v/libevent-$libevent_v.tar.gz" "libevent.tar.gz"
        tar -xzf libevent.tar.gz
        cd "libevent-$libevent_v"
        PKG_CONFIG_PATH="$prefix/lib/pkgconfig" CPPFLAGS="-I$prefix/include" LDFLAGS="-L$prefix/lib" ./configure --prefix="$prefix"
        make -j "$jobs"
        make install
    )

    (
        set -e
        cd "$build_root"
        ep_fetch_url "https://github.com/tmux/tmux/releases/download/$tmux_v/tmux-$tmux_v.tar.gz" "tmux.tar.gz"
        tar -xzf tmux.tar.gz
        cd "tmux-$tmux_v"
        PKG_CONFIG_PATH="$prefix/lib/pkgconfig" CPPFLAGS="-I$prefix/include -I$prefix/include/ncursesw" LDFLAGS="-Wl,-rpath,$prefix/lib -L$prefix/lib" ./configure --prefix="$prefix"
        make -j "$jobs"
        make install
    )

    ep_symlink_or_copy "$prefix/bin/tmux" "$HOME/.local/bin/tmux"
    rm -rf "$build_root"
}

ep_install_tmux()
{
    ep_require_unix_runtime
    local target_version current_path current_version result_action
    target_version="$(ep_tmux_target_version)"
    result_action=installed
    ep_log "Component: tmux"
    ep_log "tmux will be available as a direct command, not inside a Conda environment."
    ep_log "Target stable version: $target_version (manifest latest; override with EP_TMUX_VERSION)."

    ep_try_load_tmux_module
    current_path="$(ep_tmux_effective_path 2>/dev/null || true)"
    current_version=""
    if [ -n "$current_path" ]; then
        current_version="$(ep_tmux_current_version "$current_path")"
        ep_log "Current tmux: ${current_version:-unknown} at $current_path"
        if [ "$EP_UPGRADE" != "1" ]; then
            ep_state_mark_done tmux
            ep_report_event tmux skipped "already available; use update tmux to compare stable versions" "${current_version:-unknown}" "" "$current_path"
            return 0
        fi
        if [ -n "$current_version" ] && ep_version_at_least "$current_version" "$target_version"; then
            ep_log "tmux $current_version already meets target $target_version."
            ep_state_mark_done tmux
            ep_report_event tmux skipped "already at or above manifest target" "$current_version" "manifests/tmux.json" "$current_path"
            return 0
        fi
        result_action=updated
        ep_log "tmux ${current_version:-unknown} is below target $target_version; a newer user-visible command will be installed."
    fi

    ep_confirm "Install tmux $target_version as a direct user command?" "yes" || {
        ep_report_event tmux skipped "user declined" "" "" ""
        return 0
    }

    if ! ep_install_tmux_with_package_manager; then
        ep_build_tmux_user_space "$target_version"
    else
        current_path="$(ep_tmux_effective_path 2>/dev/null || true)"
        current_version="$(ep_tmux_current_version "$current_path" 2>/dev/null || true)"
        if [ -z "$current_version" ] || ! ep_version_at_least "$current_version" "$target_version"; then
            ep_warn "The package manager provided tmux ${current_version:-unknown}, below target $target_version; building the compatible user-space release."
            ep_build_tmux_user_space "$target_version"
        fi
    fi

    hash -r 2>/dev/null || true
    current_path="$(ep_tmux_effective_path 2>/dev/null || true)"
    [ -n "$current_path" ] || ep_die "tmux installation completed but no executable was found"
    current_version="$(ep_tmux_current_version "$current_path")"
    [ -n "$current_version" ] || ep_die "tmux executable did not report a version: $current_path"
    if ! ep_version_at_least "$current_version" "$target_version"; then
        ep_die "tmux $current_version is still below target $target_version after installation"
    fi
    ep_state_mark_done tmux
    ep_report_event tmux "$result_action" "installed compatible manifest target as a direct command" "$current_version" "manifests/tmux.json or upstream source" "$current_path"
}

