#!/usr/bin/env bash

EP_OS="unknown"
EP_ARCH="unknown"
EP_LIBC="unknown"
EP_GLIBC_VERSION="unknown"
EP_IS_ROOT="false"
EP_SHELL_NAME="unknown"

ep_normalize_arch()
{
    case "$1" in
        x86_64|amd64) printf 'amd64' ;;
        aarch64|arm64) printf 'arm64' ;;
        armv7l) printf 'armv7' ;;
        *) printf '%s' "$1" ;;
    esac
}

ep_linux_glibc_version()
{
    local version=""
    if [ -n "${EP_GLIBC_VERSION_OVERRIDE:-}" ]; then
        printf '%s' "$EP_GLIBC_VERSION_OVERRIDE"
        return 0
    fi
    if ep_command_exists getconf; then
        version="$(getconf GNU_LIBC_VERSION 2>/dev/null | awk '{print $2}')"
        [ -n "$version" ] && { printf '%s' "$version"; return 0; }
    fi
    if ep_command_exists ldd; then
        version="$(ldd --version 2>&1 | awk 'NR==1 { for (i=1; i<=NF; i++) if ($i ~ /^[0-9][0-9.]*$/) { print $i; exit } }')"
        [ -n "$version" ] && { printf '%s' "$version"; return 0; }
    fi
    printf 'unknown'
}

ep_version_at_least()
{
    local current="$1"
    local minimum="$2"
    awk -v current="$current" -v minimum="$minimum" '
        function trim_prefix(value) {
            sub(/^[^0-9]*/, "", value)
            return value
        }
        function compare(left, right, left_parts, right_parts, left_count, right_count, count, i, left_num, right_num, left_suffix, right_suffix) {
            left = trim_prefix(left)
            right = trim_prefix(right)
            left_count = split(left, left_parts, /[._+-]/)
            right_count = split(right, right_parts, /[._+-]/)
            count = left_count > right_count ? left_count : right_count
            for (i = 1; i <= count; i++) {
                match(left_parts[i], /^[0-9]+/)
                left_num = RLENGTH ? substr(left_parts[i], 1, RLENGTH) + 0 : 0
                left_suffix = RLENGTH ? substr(left_parts[i], RLENGTH + 1) : left_parts[i]
                match(right_parts[i], /^[0-9]+/)
                right_num = RLENGTH ? substr(right_parts[i], 1, RLENGTH) + 0 : 0
                right_suffix = RLENGTH ? substr(right_parts[i], RLENGTH + 1) : right_parts[i]
                if (left_num != right_num) {
                    return left_num > right_num ? 1 : -1
                }
                if (left_suffix != right_suffix) {
                    if (left_suffix == "") return -1
                    if (right_suffix == "") return 1
                    return left_suffix > right_suffix ? 1 : -1
                }
            }
            return 0
        }
        BEGIN {
            exit(compare(current, minimum) >= 0 ? 0 : 1)
        }
    '
}

ep_platform_detect()
{
    local uname_s uname_m
    uname_s="$(uname -s 2>/dev/null || printf 'unknown')"
    uname_m="$(uname -m 2>/dev/null || printf 'unknown')"
    EP_ARCH="$(ep_normalize_arch "$uname_m")"
    EP_SHELL_NAME="$(basename "${SHELL:-unknown}")"

    case "$uname_s" in
        Linux) EP_OS="linux" ;;
        Darwin) EP_OS="darwin" ;;
        MINGW*|MSYS*|CYGWIN*) EP_OS="windows-unix" ;;
        *) EP_OS="$(printf '%s' "$uname_s" | tr '[:upper:]' '[:lower:]')" ;;
    esac

    if [ "$EP_OS" = "linux" ]; then
        if ldd --version 2>&1 | grep -qi musl; then
            EP_LIBC="musl"
        elif ldd --version 2>&1 | grep -qi 'gnu\|glibc'; then
            EP_LIBC="glibc"
        else
            EP_LIBC="unknown"
        fi
        if [ "$EP_LIBC" = "glibc" ]; then
            EP_GLIBC_VERSION="$(ep_linux_glibc_version)"
        fi
    else
        EP_LIBC="na"
        EP_GLIBC_VERSION="na"
    fi

    if [ "$(id -u 2>/dev/null || printf 1)" = "0" ]; then
        EP_IS_ROOT="true"
    else
        EP_IS_ROOT="false"
    fi
}

ep_platform_print()
{
    ep_log "OS: $EP_OS"
    ep_log "Architecture: $EP_ARCH"
    ep_log "libc: $EP_LIBC"
    if [ "$EP_OS" = "linux" ]; then
        ep_log "glibc version: $EP_GLIBC_VERSION"
    fi
    ep_log "Shell: $EP_SHELL_NAME"
    ep_log "Root user: $EP_IS_ROOT"
    ep_log "Install prefix: $EP_PREFIX"
}

ep_require_unix_runtime()
{
    case "$EP_OS" in
        linux|darwin|windows-unix) return 0 ;;
        *) ep_die "This shell entry supports Unix-like runtimes only. Use envpilot.ps1 on Windows." ;;
    esac
}