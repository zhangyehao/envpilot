#!/usr/bin/env bash

EP_PYTHON_VERSION="${EP_PYTHON_VERSION:-}"
EP_PYTHON_MIN_VERSION="${EP_PYTHON_MIN_VERSION:-3.9}"

_ep_python_candidate_is_py3()
{
    "$1" -c 'import sys; raise SystemExit(0 if sys.version_info >= (3, 9) else 1)' >/dev/null 2>&1
}

ep_python_system_bin()
{
    local candidate
    for candidate in python3 python; do
        candidate="$(command -v "$candidate" 2>/dev/null || true)"
        if [ -n "$candidate" ] && _ep_python_candidate_is_py3 "$candidate"; then
            printf '%s' "$candidate"
            return 0
        fi
    done
    return 1
}

ep_python_managed_bin()
{
    printf '%s/python/current/bin/python3' "$EP_PREFIX"
}

ep_python_offline_pattern()
{
    case "$EP_OS:$EP_ARCH" in
        linux:amd64) printf 'cpython-*-x86_64-unknown-linux-gnu-install_only.tar.gz' ;;
        linux:arm64) printf 'cpython-*-aarch64-unknown-linux-gnu-install_only.tar.gz' ;;
        darwin:amd64) printf 'cpython-*-x86_64-apple-darwin-install_only.tar.gz' ;;
        darwin:arm64) printf 'cpython-*-aarch64-apple-darwin-install_only.tar.gz' ;;
        *) ep_die "No Python standalone asset rule for $EP_OS/$EP_ARCH." ;;
    esac
}

ep_python_asset_regex()
{
    case "$EP_OS:$EP_ARCH" in
        linux:amd64) printf 'cpython-[0-9]+\\.[0-9]+\\.[0-9]+\\+.*-x86_64-unknown-linux-gnu-install_only\\.tar\\.gz$' ;;
        linux:arm64) printf 'cpython-[0-9]+\\.[0-9]+\\.[0-9]+\\+.*-aarch64-unknown-linux-gnu-install_only\\.tar\\.gz$' ;;
        darwin:amd64) printf 'cpython-[0-9]+\\.[0-9]+\\.[0-9]+\\+.*-x86_64-apple-darwin-install_only\\.tar\\.gz$' ;;
        darwin:arm64) printf 'cpython-[0-9]+\\.[0-9]+\\.[0-9]+\\+.*-aarch64-apple-darwin-install_only\\.tar\\.gz$' ;;
        *) ep_die "No Python standalone asset rule for $EP_OS/$EP_ARCH." ;;
    esac
}

ep_python_conda_bin()
{
    local candidate
    for candidate in \
        "$EP_PREFIX/miniconda3/bin/python" \
        "$EP_PREFIX/anaconda3/bin/python" \
        "$HOME/miniconda3/bin/python" \
        "$HOME/anaconda3/bin/python"; do
        if [ -x "$candidate" ] && _ep_python_candidate_is_py3 "$candidate"; then
            printf '%s' "$candidate"
            return 0
        fi
    done
    return 1
}

ep_doctor_python()
{
    local python_path managed
    managed="$(ep_python_managed_bin)"
    if python_path="$(ep_python_system_bin 2>/dev/null)"; then
        ep_log "Python: found at $python_path"
        "$python_path" --version 2>&1 | sed 's/^/[INFO] Python version: /' || true
    elif python_path="$(ep_python_conda_bin 2>/dev/null)"; then
        ep_log "Python: found in Conda at $python_path"
        "$python_path" --version 2>&1 | sed 's/^/[INFO] Python version: /' || true
    elif [ -x "$managed" ]; then
        ep_log "Python: found at $managed"
        "$managed" --version 2>&1 | sed 's/^/[INFO] Python version: /' || true
    else
        ep_warn "Python 3: not found"
    fi
}

ep_install_python()
{
    ep_require_unix_runtime
    local existing managed source archive source_version version target_dir python_bin python_root current_dir action
    if existing="$(ep_python_system_bin 2>/dev/null)"; then
        ep_log "Python 3 already available at $existing; envpilot will not replace the system interpreter."
        ep_state_mark_done python
        ep_report_event python skipped "existing Python 3 retained; system installation was not modified" "$("$existing" --version 2>&1 || true)" "system PATH" "$existing"
        return 0
    fi
    if existing="$(ep_python_conda_bin 2>/dev/null)"; then
        ep_log "Python 3 already available in Conda at $existing; envpilot will not create a second interpreter."
        ep_state_mark_done python
        ep_report_event python skipped "Conda Python retained" "$("$existing" --version 2>&1 || true)" "Conda base" "$existing"
        return 0
    fi
    managed="$(ep_python_managed_bin)"
    if [ -x "$managed" ] && [ "$EP_UPGRADE" != "1" ]; then
        ep_log "envpilot-managed Python already exists at $managed."
        ep_state_mark_done python
        ep_report_event python skipped "already installed; use update python to resolve a newer compatible asset" "$("$managed" --version 2>&1 || true)" "envpilot" "$managed"
        return 0
    fi
    [ "$EP_OS" != "windows-unix" ] || ep_die "Use envpilot.ps1 install python on native Windows, or install Python in WSL/MSYS2."
    [ "$EP_OS" != "linux" ] || [ "$EP_LIBC" = "glibc" ] || ep_die "Automatic Python standalone installation currently requires glibc; use a module, Conda, or --asset-path on musl."
    if [ "$EP_OS" = "linux" ] && ! ep_version_at_least "$EP_GLIBC_VERSION" "2.17"; then
        ep_die "Detected glibc $EP_GLIBC_VERSION, below the supported Python standalone floor 2.17. Use a compatible module or Conda installation."
    fi
    ep_command_exists tar || ep_die "tar is required to install user-space Python."
    if [ "$EP_MODE" = "offline" ]; then
        source="$(ep_find_offline_asset "$(ep_python_offline_pattern)")"
    else
        source="$(ep_find_cached_asset "$(ep_python_offline_pattern)" 2>/dev/null || true)"
        [ -n "$source" ] || source="$(ep_github_asset_url astral-sh python-build-standalone "$(ep_python_asset_regex)")"
    fi
    source_version="$(basename "$source" 2>/dev/null | sed -n -E "s/^cpython-([0-9]+\.[0-9]+\.[0-9]+).*/\1/p")"
    version="${EP_PYTHON_VERSION:-$source_version}"
    [ -z "$source_version" ] || version="$source_version"
    if ! ep_version_at_least "$version" "$EP_PYTHON_MIN_VERSION"; then
        ep_die "Selected Python version $version is below the envpilot minimum $EP_PYTHON_MIN_VERSION. Provide a newer compatible standalone asset."
    fi
    ep_log "Component: python"
    ep_log "Selected Python standalone asset: ${version:-unknown}"
    ep_log "Compatibility floor: Python $EP_PYTHON_MIN_VERSION; existing system/Conda interpreters below this floor are not selected."
    ep_log "Compatibility: matched OS=$EP_OS arch=$EP_ARCH libc=$EP_LIBC glibc=${EP_GLIBC_VERSION:-na}; no system Python will be overwritten."
    ep_log "Source: $source"
    ep_log "Target: $EP_PREFIX/python/current/bin/python3"
    ep_log "PATH on the next shell: $HOME/software/python/current/bin"
    ep_confirm "Install compatible Python 3 under $EP_PREFIX/python?" "yes" || {
        ep_report_event python skipped "user declined" "" "$source" "$managed"
        return 0
    }

    archive="$(mktemp "${TMPDIR:-/tmp}/envpilot-python.XXXXXX.tar.gz")"
    target_dir="$EP_PREFIX/python/${version:-standalone-$EP_ARCH}"
    mkdir -p "$target_dir"
    if [ -f "$source" ]; then cp "$source" "$archive"; else ep_fetch_url "$source" "$archive"; fi
    tar -xzf "$archive" -C "$target_dir"
    python_bin="$(find "$target_dir" -type f -name python3 -perm -u+x 2>/dev/null | head -n 1 || true)"
    [ -n "$python_bin" ] || ep_die "Python archive did not contain an executable bin/python3."
    python_root="$(cd "$(dirname "$python_bin")/.." && pwd)"
    current_dir="$EP_PREFIX/python/current"
    rm -rf -- "$current_dir"
    if ! ln -s "$python_root" "$current_dir" 2>/dev/null; then
        cp -R "$python_root" "$current_dir"
    fi
    rm -f "$archive"
    managed="$(ep_python_managed_bin)"
    [ -x "$managed" ] || ep_die "Python installation completed but $managed was not created."
    action=installed
    [ "$EP_UPGRADE" = "1" ] && action=updated
    ep_state_mark_done python
    ep_report_event python "$action" "installed compatible user-space Python without replacing system Python" "$("$managed" --version 2>&1 || true)" "$source" "$managed"
    ep_log "Python ready: $managed"
}
