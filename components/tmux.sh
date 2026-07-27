#!/usr/bin/env bash

ep_doctor_tmux()
{
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
        brew install tmux
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
    tmux_v="${EP_TMUX_VERSION:-3.5a}"

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
        PKG_CONFIG_PATH="$prefix/lib/pkgconfig" CPPFLAGS="-I$prefix/include -I$prefix/include/ncursesw" LDFLAGS="-L$prefix/lib" ./configure --prefix="$prefix"
        make -j "$jobs"
        make install
    )

    ep_symlink_or_copy "$prefix/bin/tmux" "$HOME/.local/bin/tmux"
    rm -rf "$build_root"
}

ep_install_tmux()
{
    ep_require_unix_runtime
    ep_log "Component: tmux"
    ep_log "tmux will be available as a direct command, not inside a Conda environment."

    ep_try_load_tmux_module
    if ep_command_exists tmux; then
        ep_log "tmux already available: $(command -v tmux)"
        ep_state_mark_done tmux
        ep_report_event tmux skipped "already available" "$(tmux -V 2>/dev/null || true)" "" "$(command -v tmux)"
        return 0
    fi

    ep_confirm "Install tmux as a direct user command?" "yes" || {
        ep_report_event tmux skipped "user declined" "" "" ""
        return 0
    }

    if ! ep_install_tmux_with_package_manager; then
        ep_build_tmux_user_space
    fi

    ep_state_mark_done tmux
    ep_report_event tmux installed "installed direct tmux command" "$(tmux -V 2>/dev/null || true)" "package-manager-or-source" "$(command -v tmux 2>/dev/null || true)"
}

