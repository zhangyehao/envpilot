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

ep_python_preflight()
(
    ep_require_unix_runtime
    case "$EP_OS:$EP_ARCH" in
        linux:amd64|linux:arm64|darwin:amd64|darwin:arm64) ;;
        *) ep_die "No Python standalone asset rule for $EP_OS/$EP_ARCH." ;;
    esac
    [ "$EP_OS" != linux ] || [ "$EP_LIBC" = glibc ] || ep_die "Managed Python requires glibc on Linux; use a module or Conda on this host."
    if [ "$EP_OS" = linux ] && ! ep_version_at_least "$EP_GLIBC_VERSION" 2.17; then
        ep_die "Detected glibc $EP_GLIBC_VERSION, below the supported Python standalone floor 2.17. Use a compatible module or Conda installation."
    fi
    ep_command_exists tar || ep_die "tar is required to install user-space Python."
    if ! ep_command_exists sha256sum && ! ep_command_exists shasum && ! ep_command_exists openssl; then
        ep_die "Managed Python requires sha256sum, shasum or openssl."
    fi
    local parent="$EP_PREFIX/python" probe
    while [ ! -d "$parent" ]; do
        if [ -e "$parent" ] || [ -L "$parent" ]; then ep_die "Invalid Python installation directory: $parent"; fi
        parent="$(dirname "$parent")"
    done
    probe="$(mktemp -d "$parent/.envpilot-python-check.XXXXXXXX")" || ep_die "Python storage is not writable: $parent"
    trap 'rm -rf -- "$probe"' EXIT
    if ! printf '#!/bin/sh\nexit 0\n' > "$probe/program" || ! chmod 700 "$probe/program" ||
       ! ln -s program "$probe/python3" || ! "$probe/python3"; then
        ep_die "Python storage must support executable files and symbolic links: $parent"
    fi
    ep_log "Python storage supports executable files and symbolic links: $parent"
)

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
    local existing managed source source_version version action descriptor expected
    managed="$(ep_python_managed_bin)"
    if [[ " ${ENVPILOT_PREFER_MANAGED_TOOLS:-} " != *" python "* ]] &&
       { [ "$EP_UPGRADE" != 1 ] || [ ! -x "$managed" ]; } && existing="$(ep_python_system_bin 2>/dev/null)"; then
        ep_log "Python 3 already available at $existing; envpilot will not replace the system interpreter."
        ep_state_mark_done python
        ep_report_event python skipped "existing Python 3 retained; system installation was not modified" "$("$existing" --version 2>&1 || true)" "system PATH" "$existing"
        return 0
    fi
    if [[ " ${ENVPILOT_PREFER_MANAGED_TOOLS:-} " != *" python "* ]] &&
       { [ "$EP_UPGRADE" != 1 ] || [ ! -x "$managed" ]; } && existing="$(ep_python_conda_bin 2>/dev/null)"; then
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
    ep_python_preflight || return 1
    source=""
    if [ "$EP_MODE" = offline ]; then
        source="$(ep_find_offline_asset "$(ep_python_offline_pattern)")" || return 1
    elif [ "$EP_UPGRADE" != 1 ]; then
        source="$(ep_find_cached_asset "$(ep_python_offline_pattern)" 2>/dev/null || true)"
    fi
    if [ -n "$source" ]; then
        source_version="$(basename "$source" | sed -n -E 's/^cpython-([0-9]+\.[0-9]+\.[0-9]+).*/\1/p')"
        [ -n "$source_version" ] || ep_die "Unrecognized Python archive filename."
        if [ -n "$EP_PYTHON_VERSION" ] && [ "$source_version" != "$EP_PYTHON_VERSION" ]; then
            ep_die "Selected Python archive does not match requested version $EP_PYTHON_VERSION."
        fi
        version="$source_version"
    else
        descriptor="$(ep_core python-asset -- "$EP_PYTHON_VERSION")" || return 1
        IFS=$'\t' read -r version source expected <<< "$descriptor"
    fi
    if ! ep_version_at_least "$version" "$EP_PYTHON_MIN_VERSION"; then
        ep_die "Selected Python version $version is below the envpilot minimum $EP_PYTHON_MIN_VERSION. Provide a newer compatible standalone asset."
    fi
    if [ -f "$source" ]; then
        expected="$(ep_core python-local-digest -- "$source" "$ENVPILOT_ROOT/manifests/python.json" "$EP_MODE")" ||
            ep_die "No trusted Python checksum. Place the upstream SHA256SUMS beside the archive."
    fi
    [[ "$expected" =~ ^[0-9a-f]{64}$ ]] || ep_die "Missing SHA-256 for the selected Python archive."
    ep_log "Component: python"
    ep_log "Selected Python standalone asset: ${version:-unknown}"
    ep_log "Compatibility floor: Python $EP_PYTHON_MIN_VERSION; existing system/Conda interpreters below this floor are not selected."
    ep_log "Compatibility: matched OS=$EP_OS arch=$EP_ARCH libc=$EP_LIBC glibc=${EP_GLIBC_VERSION:-na}; no system Python will be overwritten."
    ep_log "Source: $source"
    ep_log "Target: $EP_PREFIX/python/current/bin/python3"
    ep_log "Shell priority: set shell.prefer_managed: [python] and run envpilot apply-shell."
    ep_confirm "Install compatible Python 3 under $EP_PREFIX/python?" "yes" || {
        ep_report_event python skipped "user declined" "" "$source" "$managed"
        return 0
    }

    (
        local base="$EP_PREFIX/python" staging archive
        mkdir -p "$base" || exit 1
        staging="$(mktemp -d "$base/$version.XXXXXXXX")" || exit 1
        trap 'rm -rf -- "$staging"' EXIT
        archive="$staging/.download.tar.gz"
        if [ -f "$source" ]; then cp "$source" "$archive" || exit 1; else ep_fetch_url "$source" "$archive" || exit 1; fi
        if [ "$(ep_core_sha256 "$archive")" != "$expected" ]; then
            ep_die "Python archive SHA-256 mismatch; the current interpreter was preserved."
        fi
        ep_log "Python archive SHA-256 verified."
        tar -xzf "$archive" -C "$staging" || exit 1
        rm -f "$archive" || exit 1
        # The helper verifies links, runs the staged interpreter, then publishes current.
        trap - EXIT
        if ! ep_core python-activate -- "$base" "$staging" "$version"; then
            rm -rf -- "$staging"
            exit 1
        fi
    ) || ep_die "Python installation failed; see the staged validation error above."
    managed="$(ep_python_managed_bin)"
    [ -x "$managed" ] || ep_die "Python installation completed but $managed was not created."
    action=installed
    [ "$EP_UPGRADE" = "1" ] && action=updated
    ep_state_mark_done python
    ep_report_event python "$action" "installed compatible user-space Python without replacing system Python" "$("$managed" --version 2>&1 || true)" "$source" "$managed"
    ep_log "Python ready: $managed"
}
