#!/usr/bin/env bash

EP_CODEX_BASE_URL="${EP_CODEX_BASE_URL:-https://yanhuoapi.com/v1}"
EP_CODEX_PACKAGE="${EP_CODEX_PACKAGE:-@openai/codex}"
EP_CODEX_INSTALL_URL="${EP_CODEX_INSTALL_URL:-https://chatgpt.com/codex/install.sh}"
EP_MIN_NODE_MAJOR="${EP_MIN_NODE_MAJOR:-22}"
EP_NVM_VERSION="${EP_NVM_VERSION:-v0.40.1}"
EP_NODE_NVM_MIN_GLIBC="${EP_NODE_NVM_MIN_GLIBC:-2.28}"
EP_NODE_LEGACY_LINE="${EP_NODE_LEGACY_LINE:-22}"
EP_NODE_LEGACY_PLATFORM="${EP_NODE_LEGACY_PLATFORM:-x64-glibc-217}"
EP_NODE_LEGACY_INSTALL_URL="${EP_NODE_LEGACY_INSTALL_URL:-https://unofficial-builds.nodejs.org/install-node.sh}"
EP_CODEX_PROBE_TIMEOUT="${EP_CODEX_PROBE_TIMEOUT:-5}"
EP_CODEX_REMOTE_READY_TIMEOUT="${EP_CODEX_REMOTE_READY_TIMEOUT:-60}"

EP_NODE_VERSION=""
EP_NODE_PROBE_ERROR=""
EP_CODEX_BIN=""
EP_CODEX_VERSION=""
EP_CODEX_PROBE_ERROR=""
EP_CODEX_PROBE_STATE="missing"
EP_CODEX_INSTALL_METHOD="none"
EP_CODEX_INSTALLED_BIN=""
EP_CODEX_PROBE_BIN=""
EP_CODEX_STANDALONE_BIN=""
EP_CODEX_NPM_BIN=""

ep_node_major_from_version()
{
    local version="${1:-}"
    if [[ "$version" =~ ^v([0-9]+)\. ]]; then
        printf '%s' "${BASH_REMATCH[1]}"
        return 0
    fi
    return 1
}

ep_node_probe()
{
    local output status
    EP_NODE_VERSION=""
    EP_NODE_PROBE_ERROR=""
    if output="$(node -v 2>&1)"; then
        output="${output%%$'\n'*}"
        if [[ "$output" =~ ^v[0-9]+\.[0-9]+\.[0-9]+([[:space:]]|$) ]]; then
            EP_NODE_VERSION="$output"
            return 0
        fi
        EP_NODE_PROBE_ERROR="${output:-invalid version output}"
        return 1
    else
        status=$?
        EP_NODE_PROBE_ERROR="${output:-node exited with status $status}"
        return 1
    fi
}

ep_node_major()
{
    local version
    version="$(node -v 2>/dev/null)" || return 1
    ep_node_major_from_version "$version"
}

ep_codex_command()
{
    local candidate
    if ep_command_exists codex; then
        command -v codex
        return 0
    fi
    for candidate in \
        "$HOME/.local/bin/codex" \
        "$HOME/.local/bin/codex.exe" \
        "$HOME/bin/codex" \
        "$HOME/bin/codex.exe" \
        "${CODEX_HOME:-$HOME/.codex}/packages/standalone/current/bin/codex" \
        "${CODEX_HOME:-$HOME/.codex}/packages/standalone/current/codex"; do
        if [ -x "$candidate" ]; then
            printf '%s' "$candidate"
            return 0
        fi
    done
    return 1
}

ep_codex_standalone_command()
{
    local root candidate
    root="${CODEX_HOME:-$HOME/.codex}/packages/standalone/current"
    for candidate in "$root/bin/codex" "$root/codex"; do
        if [ -x "$candidate" ]; then
            printf '%s' "$candidate"
            return 0
        fi
    done
    return 1
}

ep_codex_is_npm_command()
{
    local candidate="${1:-}"
    [ -n "$candidate" ] && [ -x "$candidate" ] || return 1
    [ "$(LC_ALL=C head -c 2 "$candidate" 2>/dev/null || true)" = '#!' ] || return 1
    LC_ALL=C head -c 256 "$candidate" 2>/dev/null |
        grep -Eq '^#!.*(^|[/[:space:]])node(js)?([[:space:]]|$)'
}

ep_codex_npm_command()
{
    local visible candidate
    visible="$(command -v codex 2>/dev/null || true)"
    if ep_codex_is_npm_command "$visible"; then
        printf '%s' "$visible"
        return 0
    fi
    candidate="$HOME/software/node22/bin/codex"
    if ep_codex_is_npm_command "$candidate"; then
        printf '%s' "$candidate"
        return 0
    fi
    if [ -n "${NVM_BIN:-}" ]; then
        candidate="$NVM_BIN/codex"
        if ep_codex_is_npm_command "$candidate"; then
            printf '%s' "$candidate"
            return 0
        fi
    fi
    for candidate in "$HOME"/.nvm/versions/node/*/bin/codex; do
        [ -e "$candidate" ] || continue
        if ep_codex_is_npm_command "$candidate"; then
            printf '%s' "$candidate"
            return 0
        fi
    done
    return 1
}

ep_codex_detect_installation()
{
    local visible
    EP_CODEX_INSTALL_METHOD=none
    EP_CODEX_INSTALLED_BIN=""
    EP_CODEX_PROBE_BIN=""
    EP_CODEX_STANDALONE_BIN="$(ep_codex_standalone_command 2>/dev/null || true)"
    EP_CODEX_NPM_BIN="$(ep_codex_npm_command 2>/dev/null || true)"
    visible="$(ep_codex_command 2>/dev/null || true)"

    if [ -n "$EP_CODEX_STANDALONE_BIN" ]; then
        EP_CODEX_INSTALL_METHOD=standalone
        EP_CODEX_INSTALLED_BIN="$EP_CODEX_STANDALONE_BIN"
        EP_CODEX_PROBE_BIN="$EP_CODEX_STANDALONE_BIN"
        if [ -n "$visible" ] && declare -F ep_codex_remote_is_managed_wrapper >/dev/null 2>&1 &&
           ep_codex_remote_is_managed_wrapper "$visible"; then
            EP_CODEX_PROBE_BIN="$visible"
        fi
    elif [ -n "$EP_CODEX_NPM_BIN" ]; then
        EP_CODEX_INSTALL_METHOD=npm
        EP_CODEX_INSTALLED_BIN="$EP_CODEX_NPM_BIN"
        EP_CODEX_PROBE_BIN="$EP_CODEX_NPM_BIN"
    elif [ -n "$visible" ]; then
        EP_CODEX_INSTALL_METHOD=unknown
        EP_CODEX_INSTALLED_BIN="$visible"
        EP_CODEX_PROBE_BIN="$visible"
    fi
}

ep_codex_warn_duplicate_installation()
{
    if [ -n "$EP_CODEX_STANDALONE_BIN" ] && [ -n "$EP_CODEX_NPM_BIN" ]; then
        ep_warn "Both standalone and npm-managed Codex installations were found."
        ep_warn "Standalone is the envpilot default: $EP_CODEX_STANDALONE_BIN"
        ep_warn "The npm installation is preserved and will not be uninstalled automatically: $EP_CODEX_NPM_BIN"
        ep_warn "Start a new shell or source the envpilot profile so $HOME/.local/bin takes precedence."
    fi
}

ep_codex_kill_process_tree()
{
    local pid="${1:-}" child
    case "$pid" in
        ''|*[!0-9]*) return 0 ;;
    esac
    if ep_command_exists pgrep; then
        while IFS= read -r child; do
            [ -n "$child" ] || continue
            ep_codex_kill_process_tree "$child"
        done < <(pgrep -P "$pid" 2>/dev/null || true)
    elif ep_command_exists pkill; then
        pkill -TERM -P "$pid" 2>/dev/null || true
    fi
    kill -TERM "$pid" 2>/dev/null || true
    sleep 0.1
    kill -KILL "$pid" 2>/dev/null || true
}

ep_codex_run_bounded()
{
    local seconds="${1:-$EP_CODEX_PROBE_TIMEOUT}"
    local output_file pid elapsed=0 status
    shift || true
    output_file="$(mktemp "${TMPDIR:-/tmp}/envpilot-codex-probe.XXXXXX")" || {
        "$@"
        return
    }
    ("$@" >"$output_file" 2>&1) &
    pid=$!
    while kill -0 "$pid" 2>/dev/null; do
        if [ "$elapsed" -ge "$seconds" ]; then
            ep_codex_kill_process_tree "$pid"
            wait "$pid" 2>/dev/null || true
            cat "$output_file"
            rm -f "$output_file"
            return 124
        fi
        sleep 1
        elapsed=$((elapsed + 1))
    done
    status=0
    wait "$pid" || status=$?
    cat "$output_file"
    rm -f "$output_file"
    return "$status"
}

ep_codex_probe_path()
{
    local path="${1:-}" output status version
    EP_CODEX_BIN="$path"
    EP_CODEX_VERSION=""
    EP_CODEX_PROBE_ERROR=""
    EP_CODEX_PROBE_STATE=missing
    [ -n "$EP_CODEX_BIN" ] && [ -x "$EP_CODEX_BIN" ] || return 1
    if output="$(ep_codex_run_bounded "$EP_CODEX_PROBE_TIMEOUT" "$EP_CODEX_BIN" --version 2>&1)"; then
        version="$(printf '%s\n' "$output" | sed -n '/^codex-cli[[:space:]]/{p;q;}')"
        [ -n "$version" ] || {
            EP_CODEX_PROBE_ERROR="${output:-empty version output}"
            EP_CODEX_PROBE_STATE=failed
            return 1
        }
        EP_CODEX_VERSION="$version"
        EP_CODEX_PROBE_STATE=ready
        return 0
    else
        status=$?
        if [ "$status" = "124" ]; then
            EP_CODEX_PROBE_ERROR="codex --version timed out after ${EP_CODEX_PROBE_TIMEOUT}s on the current filesystem"
            EP_CODEX_PROBE_STATE=timeout
        else
            EP_CODEX_PROBE_ERROR="${output:-codex exited with status $status}"
            EP_CODEX_PROBE_STATE=failed
        fi
        return 1
    fi
}

ep_codex_probe()
{
    local command_path
    command_path="$(ep_codex_command 2>/dev/null || true)"
    ep_codex_probe_path "$command_path"
}

ep_codex_warn_slow_probe()
{
    local path="${1:-$EP_CODEX_BIN}"
    ep_warn "Codex is installed at $path, but codex --version did not finish within ${EP_CODEX_PROBE_TIMEOUT}s on the shared filesystem."
    ep_warn "The installation is retained; this timeout is not treated as a missing executable, and npm fallback is skipped."
    ep_warn "Use the node-local runtime for fast startup: bash envpilot.sh codex remote enable"
}

ep_doctor_codex()
{
    local secret_file legacy_target

    ep_codex_detect_installation
    ep_codex_warn_duplicate_installation
    if ep_node_probe; then
        ep_log "Node.js: found at $(command -v node)"
        ep_log "Node.js version: $EP_NODE_VERSION"
    elif ep_command_exists node; then
        if [ "$EP_CODEX_INSTALL_METHOD" = "npm" ]; then
            ep_warn "Node.js found at $(command -v node) but could not execute: $(printf '%s\n' "$EP_NODE_PROBE_ERROR" | sed -n '1p')"
            ep_node_nvm_compatibility_warning
        else
            ep_log "Node.js: present but unusable and not required by the $EP_CODEX_INSTALL_METHOD Codex path: $(printf '%s\n' "$EP_NODE_PROBE_ERROR" | sed -n '1p')"
        fi
    else
        legacy_target="$(ep_node_legacy_target_dir)"
        if [ -x "$legacy_target/bin/node" ]; then
            ep_log "Node.js legacy candidate: $legacy_target/bin/node"
        elif [ "$EP_CODEX_INSTALL_METHOD" = "npm" ]; then
            ep_warn "Node.js: not found; the detected npm Codex installation requires Node.js $EP_MIN_NODE_MAJOR+"
        else
            ep_log "Node.js: not found (optional; only required for the legacy npm Codex path)"
        fi
    fi

    if [ -z "$EP_CODEX_INSTALLED_BIN" ]; then
        ep_warn "Codex: not found"
    elif ep_codex_probe_path "$EP_CODEX_PROBE_BIN"; then
        ep_log "Codex: found at $EP_CODEX_BIN"
        ep_log "Codex install method: $EP_CODEX_INSTALL_METHOD"
        ep_log "Codex version: $EP_CODEX_VERSION"
    elif [ "$EP_CODEX_PROBE_STATE" = "timeout" ]; then
        ep_log "Codex: installed at $EP_CODEX_BIN"
        ep_log "Codex install method: $EP_CODEX_INSTALL_METHOD"
        ep_codex_warn_slow_probe "$EP_CODEX_BIN"
    else
        ep_warn "Codex found at $EP_CODEX_BIN but could not execute: $(printf '%s\n' "$EP_CODEX_PROBE_ERROR" | sed -n '1p')"
    fi
    if [ "${EP_OS:-}" = "linux" ]; then
        if ep_command_exists bwrap; then
            ep_log "Codex sandbox helper: found at $(command -v bwrap)"
        else
            ep_warn "Codex sandbox helper: bubblewrap not found on PATH; Codex may fall back to its bundled helper, but the system package is recommended when the cluster permits it."
        fi
    fi
    if [ -f "$HOME/.codex/config.toml" ]; then
        ep_log "Codex config: $HOME/.codex/config.toml"
    else
        ep_warn "Codex config: not found"
    fi
    if [ -f "$HOME/.codex/auth.json" ]; then
        ep_log "Codex auth: found at $HOME/.codex/auth.json (value not displayed)"
    else
        ep_warn "Codex auth: not found; install will ask before creating it"
    fi
    secret_file="$(ep_secrets_file)"
    if [ -f "$secret_file" ]; then
        if ep_codex_secret_file_is_safe "$secret_file"; then
            ep_log "Codex secrets: protected file at $secret_file"
        else
            ep_warn "Codex secrets: $secret_file exists but is not owned by the current user or is not mode 600/400"
        fi
    else
        ep_warn "Codex secrets: not found; install or apply-shell will create a protected scaffold"
    fi
    ep_doctor_codex_remote
}

ep_load_nvm()
{
    export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
    if [ -s "$NVM_DIR/nvm.sh" ]; then
        # shellcheck disable=SC1091
        . "$NVM_DIR/nvm.sh" || ep_die "Failed to load nvm from $NVM_DIR/nvm.sh"
    fi
    return 0
}

ep_node_nvm_is_compatible()
{
    case "${EP_OS:-unknown}:${EP_LIBC:-unknown}" in
        linux:glibc)
            [ "${EP_GLIBC_VERSION:-unknown}" != "unknown" ] || return 1
            ep_version_at_least "$EP_GLIBC_VERSION" "$EP_NODE_NVM_MIN_GLIBC"
            ;;
        linux:*) return 1 ;;
        darwin:*|windows-unix:*) return 0 ;;
        *) return 0 ;;
    esac
}

ep_node_nvm_compatibility_warning()
{
    if [ "${EP_OS:-unknown}" = "linux" ]; then
        ep_warn "The current automatic Node.js path uses official nvm binaries, which require glibc >= $EP_NODE_NVM_MIN_GLIBC for Node.js $EP_MIN_NODE_MAJOR+ on Linux."
        ep_warn "Detected libc=${EP_LIBC:-unknown}, glibc=${EP_GLIBC_VERSION:-unknown}; envpilot will not select an incompatible Node.js binary."
        ep_warn "The standalone Codex installer does not require Node.js. Linux amd64 glibc 2.17-2.27 uses the unofficial glibc-217 Node.js fallback; otherwise provide a compatible Node.js module/Conda runtime and rerun."
    fi
}

ep_node_legacy_is_supported()
{
    local glibc="${EP_GLIBC_VERSION:-unknown}"
    case "${EP_OS:-unknown}:${EP_ARCH:-unknown}:${EP_LIBC:-unknown}" in
        linux:amd64:glibc)
            [ "$glibc" != "unknown" ] || return 1
            ep_version_at_least "$glibc" "2.17" || return 1
            if ep_version_at_least "$glibc" "$EP_NODE_NVM_MIN_GLIBC"; then
                return 1
            fi
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

ep_node_legacy_target_dir()
{
    printf '%s' "${EP_NODE_LEGACY_DIR:-${EP_PREFIX:-$HOME/software}/node${EP_NODE_LEGACY_LINE}}"
}

ep_node_activate_dir()
{
    local directory="$1/bin"
    [ -d "$directory" ] || return 1
    PATH="$directory${PATH:+:$PATH}"
    export PATH
    hash -r 2>/dev/null || true
}

ep_node_legacy_probe()
{
    local directory="$1"
    local node_bin="$directory/bin/node"
    local output status
    [ -x "$node_bin" ] || return 1
    if output="$("$node_bin" -v 2>&1)"; then
        output="${output%%$'\n'*}"
        if [[ "$output" =~ ^v[0-9]+\.[0-9]+\.[0-9]+([[:space:]]|$) ]]; then
            EP_NODE_VERSION="$output"
            ep_node_activate_dir "$directory"
            return 0
        fi
    else
        status=$?
        EP_NODE_PROBE_ERROR="${output:-node exited with status $status}"
    fi
    return 1
}

ep_install_node_legacy()
{
    local target installer platform
    platform="$EP_NODE_LEGACY_PLATFORM"
    target="$(ep_node_legacy_target_dir)"
    if ep_node_legacy_probe "$target"; then
        ep_log "Compatible Node.js already available: $EP_NODE_VERSION at $target/bin/node"
        return 0
    fi
    ep_command_exists curl || ep_die "curl is required to install a compatible Node.js runtime"
    ep_log "Node.js source: unofficial-builds $platform, Node.js line $EP_NODE_LEGACY_LINE"
    ep_log "Node.js installer: $EP_NODE_LEGACY_INSTALL_URL"
    ep_log "Node.js target: $target (user space; no root required)"
    ep_confirm "Install Node.js $EP_NODE_LEGACY_LINE compatible with glibc $EP_GLIBC_VERSION under $target?" "yes" ||
        ep_die "Node.js $EP_MIN_NODE_MAJOR+ is required for Codex"
    mkdir -p "$target"
    installer="$(mktemp "${TMPDIR:-/tmp}/envpilot-node-installer.XXXXXX")" ||
        ep_die "Could not create a temporary Node.js installer file"
    if ! curl -fsSL "$EP_NODE_LEGACY_INSTALL_URL" -o "$installer"; then
        rm -f "$installer"
        ep_die "Could not download the compatible Node.js installer: $EP_NODE_LEGACY_INSTALL_URL"
    fi
    if ! bash "$installer" \
        --line "$EP_NODE_LEGACY_LINE" \
        --platform "$platform" \
        --dir "$target" \
        --yes; then
        rm -f "$installer"
        ep_die "The compatible Node.js installer failed for platform $platform"
    fi
    rm -f "$installer"
    if ! ep_node_legacy_probe "$target"; then
        ep_die "Node.js was downloaded to $target, but it could not execute: $(printf '%s\n' "${EP_NODE_PROBE_ERROR:-unknown error}" | sed -n '1p')"
    fi
    ep_log "Node.js ready: $EP_NODE_VERSION at $target/bin/node"
}

ep_ensure_node()
{
    local major nvm_installer_url
    ep_load_nvm
    if ep_command_exists node; then
        if ep_node_probe; then
            major="$(ep_node_major_from_version "$EP_NODE_VERSION")"
            if [ -n "$major" ] && [ "$major" -ge "$EP_MIN_NODE_MAJOR" ]; then
                ep_log "Node.js satisfies requirement: $EP_NODE_VERSION"
                return 0
            fi
            ep_warn "Node.js $EP_NODE_VERSION is lower than required v$EP_MIN_NODE_MAJOR"
        else
            ep_warn "Node.js command found at $(command -v node) but could not execute: $(printf '%s\n' "$EP_NODE_PROBE_ERROR" | sed -n '1p')"
        fi
    else
        ep_warn "Node.js: not found"
    fi

    if ep_node_legacy_is_supported; then
        ep_log "Detected Linux glibc $EP_GLIBC_VERSION below $EP_NODE_NVM_MIN_GLIBC; selecting a glibc-217 Node.js build instead of an incompatible official nvm binary."
        ep_install_node_legacy
        return 0
    fi

    if ! ep_node_nvm_is_compatible; then
        ep_node_nvm_compatibility_warning
        ep_die "No compatible automatic Node.js $EP_MIN_NODE_MAJOR+ runtime is available for this host. Use the official standalone Codex installer or provide a compatible Node.js runtime."
    fi

    ep_command_exists curl || ep_die "curl is required to install nvm/Node.js automatically"
    nvm_installer_url="https://raw.githubusercontent.com/nvm-sh/nvm/$EP_NVM_VERSION/install.sh"
    ep_log "Node.js source: nvm $EP_NVM_VERSION, then the latest Node.js LTS"
    ep_log "Node.js target: $HOME/.nvm (user space; no root required)"
    ep_confirm "Install Node.js LTS via nvm under $HOME/.nvm?" "yes" || ep_die "Node.js $EP_MIN_NODE_MAJOR+ is required for Codex"
    export NVM_DIR="$HOME/.nvm"
    if [ ! -s "$NVM_DIR/nvm.sh" ]; then
        ep_log "Downloading nvm installer: $nvm_installer_url"
        if ! curl -fsSL "$nvm_installer_url" | bash; then
            ep_die "Failed to download or install nvm from $nvm_installer_url"
        fi
    fi
    ep_load_nvm
    ep_command_exists nvm || ep_die "nvm did not load; reopen shell and retry"
    ep_log "Installing the latest Node.js LTS through nvm. This may download an archive and take several minutes."
    nvm install 'lts/*' || ep_die "nvm failed to install the latest Node.js LTS"
    nvm alias default 'lts/*' || ep_die "nvm failed to set the default Node.js LTS alias"
    nvm use default || ep_die "nvm failed to activate the default Node.js version"
    if ! ep_node_probe; then
        ep_warn "nvm selected $(command -v node), but Node.js could not execute: $(printf '%s\n' "$EP_NODE_PROBE_ERROR" | sed -n '1p')"
        ep_node_nvm_compatibility_warning
        ep_die "Node.js installation completed, but the selected runtime is not executable. Check the compatibility error above."
    fi
    major="$(ep_node_major_from_version "$EP_NODE_VERSION")"
    if [ -z "$major" ] || [ "$major" -lt "$EP_MIN_NODE_MAJOR" ]; then
        ep_die "Node.js installation completed, but $EP_NODE_VERSION is below the required v$EP_MIN_NODE_MAJOR"
    fi
    ep_log "Node.js ready: $EP_NODE_VERSION at $(command -v node)"
}

ep_npm_probe()
{
    local output status
    EP_NPM_VERSION=""
    EP_NPM_PROBE_ERROR=""
    if output="$(npm --version 2>&1)"; then
        EP_NPM_VERSION="$(printf '%s\n' "$output" | sed -n '1p')"
        if [ -n "$EP_NPM_VERSION" ]; then
            return 0
        fi
        EP_NPM_PROBE_ERROR="empty version output"
        return 1
    else
        status=$?
        EP_NPM_PROBE_ERROR="${output:-npm exited with status $status}"
        return 1
    fi
}

ep_install_codex_official()
{
    local installer
    [ "$EP_MODE" = "online" ] || return 1
    ep_command_exists curl || {
        ep_warn "curl is unavailable; cannot use the official standalone Codex installer."
        return 1
    }
    installer="$(mktemp "${TMPDIR:-/tmp}/envpilot-codex-installer.XXXXXX")" || return 1
    ep_log "Codex source: official standalone installer $EP_CODEX_INSTALL_URL"
    if ! curl -fsSL "$EP_CODEX_INSTALL_URL" -o "$installer"; then
        rm -f "$installer"
        ep_warn "Could not download the official Codex installer. No npm or Node.js fallback has been started."
        return 1
    fi
    ep_log "The official installer will run non-interactively; it will not launch Codex or uninstall another installation method."
    if ! CODEX_NON_INTERACTIVE=1 sh "$installer"; then
        rm -f "$installer"
        ep_warn "The official Codex installer failed. No npm or Node.js fallback has been started."
        return 1
    fi
    rm -f "$installer"
    hash -r
    ep_codex_detect_installation
    if [ -z "$EP_CODEX_STANDALONE_BIN" ]; then
        ep_warn "The official installer exited successfully, but the standalone Codex artifact was not found under ${CODEX_HOME:-$HOME/.codex}/packages/standalone/current."
        return 1
    fi
    EP_CODEX_INSTALL_METHOD=standalone
    EP_CODEX_INSTALLED_BIN="$EP_CODEX_STANDALONE_BIN"
    if ep_codex_probe_path "$EP_CODEX_STANDALONE_BIN"; then
        ep_log "Codex CLI ready: $EP_CODEX_VERSION at $EP_CODEX_BIN"
    elif [ "$EP_CODEX_PROBE_STATE" = "timeout" ]; then
        ep_codex_warn_slow_probe "$EP_CODEX_STANDALONE_BIN"
    else
        ep_warn "The official installer succeeded and the standalone artifact exists, but the bounded post-install probe failed: $(printf '%s\n' "$EP_CODEX_PROBE_ERROR" | sed -n '1p')"
        ep_warn "The standalone installation is preserved; envpilot will not replace it with npm automatically."
    fi
    ep_codex_warn_duplicate_installation
    return 0
}

ep_install_codex_npm()
{
    local existing="$1"
    ep_ensure_node
    if ! ep_command_exists npm; then
        ep_die "npm is required after Node.js installation"
    fi
    if ! ep_npm_probe; then
        ep_die "npm was found at $(command -v npm) but could not execute: $(printf '%s\n' "$EP_NPM_PROBE_ERROR" | sed -n '1p')"
    fi
    ep_log "Installing the latest compatible Codex CLI from the npm registry: $EP_CODEX_PACKAGE"
    ep_log "Node.js: $EP_NODE_VERSION"
    ep_log "npm: $EP_NPM_VERSION at $(command -v npm)"
    ep_log "npm global prefix: $(npm config get prefix 2>/dev/null || printf unknown)"
    if [ "$existing" = "1" ]; then
        ep_log "Updating the existing Codex CLI through npm."
    fi
    if ! npm install -g "$EP_CODEX_PACKAGE"; then
        ep_die "npm failed to install/update $EP_CODEX_PACKAGE"
    fi
    hash -r
    EP_CODEX_NPM_BIN="$(ep_codex_npm_command 2>/dev/null || true)"
    [ -n "$EP_CODEX_NPM_BIN" ] || ep_die "npm completed, but no npm-managed Codex launcher was found."
    EP_CODEX_INSTALL_METHOD=npm
    EP_CODEX_INSTALLED_BIN="$EP_CODEX_NPM_BIN"
    EP_CODEX_PROBE_BIN="$EP_CODEX_NPM_BIN"
    if ep_codex_probe_path "$EP_CODEX_NPM_BIN"; then
        ep_log "Codex CLI ready: $EP_CODEX_VERSION at $EP_CODEX_BIN"
    elif [ "$EP_CODEX_PROBE_STATE" = "timeout" ]; then
        ep_codex_warn_slow_probe "$EP_CODEX_NPM_BIN"
    else
        ep_die "npm completed but the installed Codex command failed immediately: $(printf '%s\n' "$EP_CODEX_PROBE_ERROR" | sed -n '1p')"
    fi
}

ep_write_codex_config()
{
    local config_dir="$HOME/.codex"
    local config_file="$config_dir/config.toml"
    mkdir -p "$config_dir"
    ep_backup_file "$config_file"
    cat > "$config_file.tmp" <<EOF
model_provider = "codex"
model = "gpt-5.5"
review_model = "gpt-5.5"
model_reasoning_effort = "high"
disable_response_storage = true
network_access = "enabled"
model_context_window = 270000
model_auto_compact_token_limit = 270000
effective_context_window_percent = 95

[model_providers.codex]
name = "codex"
base_url = "$EP_CODEX_BASE_URL"
wire_api = "responses"
env_key = "OPENAI_API_KEY"
EOF
    mv "$config_file.tmp" "$config_file"
    chmod 600 "$config_file" 2>/dev/null || true
    ep_log "Wrote Codex config using env_key=OPENAI_API_KEY: $config_file"
}

ep_codex_secret_file_mode()
{
    local secret_file="$1"
    stat -c '%a' "$secret_file" 2>/dev/null || stat -f '%Lp' "$secret_file" 2>/dev/null || true
}

ep_codex_secret_file_is_safe()
{
    local secret_file="$1"
    local mode owner current
    [ -f "$secret_file" ] || return 1
    current="$(id -u)"
    owner="$(stat -c '%u' "$secret_file" 2>/dev/null || stat -f '%u' "$secret_file" 2>/dev/null || printf '%s' "$current")"
    [ "$owner" = "$current" ] || return 1
    mode="$(ep_codex_secret_file_mode "$secret_file")"
    case "$mode" in
        400|600) return 0 ;;
        *) return 1 ;;
    esac
}

ep_codex_key_from_secret_file()
{
    local secret_file="$1"
    EP_CODEX_API_KEY=""
    if ! ep_codex_secret_file_is_safe "$secret_file"; then
        return 1
    fi
    EP_CODEX_API_KEY="$(
        set +e
        # The path is user-specific and validated above.
        # shellcheck disable=SC1090
        . "$secret_file" >/dev/null 2>&1
        printenv OPENAI_API_KEY 2>/dev/null || true
    )"
    [ -n "$EP_CODEX_API_KEY" ]
}

ep_codex_prompt_api_key()
{
    local value
    if [ ! -t 0 ] && [ ! -r /dev/tty ]; then
        return 1
    fi
    if [ -r /dev/tty ]; then
        exec 9</dev/tty
    else
        exec 9<&0
    fi
    printf 'Enter an OpenAI-compatible API key (press Enter to skip): '
    IFS= read -r -s value <&9 || value=""
    printf '\n'
    exec 9<&-
    if [ -n "$value" ]; then
        EP_CODEX_API_KEY="$value"
        return 0
    fi
    unset value
    return 1
}

ep_codex_write_auth()
{
    local auth_file="$HOME/.codex/auth.json"
    local tmp escaped_key

    # Existing auth may be a user login or API-key file. Never replace it
    # during an ordinary install/configure run.
    if [ -e "$auth_file" ] && [ "${EP_FORCE_CODEX_AUTH_WRITE:-0}" != "1" ]; then
        ep_log "Existing Codex auth file preserved: $auth_file"
        return 0
    fi

    ep_confirm "Create $auth_file from the detected API key with mode 600?" "yes" || {
        ep_warn "auth.json was not changed. Use: chmod 600 $HOME/.config/secrets/api.env; with_secrets codex"
        return 0
    }
    mkdir -p "$HOME/.codex"
    ep_backup_file "$auth_file"
    escaped_key="$(printf '%s' "$EP_CODEX_API_KEY" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')"
    tmp="$auth_file.tmp.$$"
    printf '{\n  "OPENAI_API_KEY": "%s"\n}\n' "$escaped_key" > "$tmp"
    chmod 600 "$tmp" 2>/dev/null || true
    mv "$tmp" "$auth_file"
    chmod 600 "$auth_file" 2>/dev/null || true
    ep_log "Wrote Codex auth file without printing its value: $auth_file"
}

ep_codex_shell_quote()
{
    printf '%q' "$1"
}

ep_codex_persist_api_key()
{
    local secret_file="$HOME/.config/secrets/api.env"
    local tmp line quoted written=0

    ep_ensure_secrets_file
    quoted="$(ep_codex_shell_quote "$1")"
    ep_backup_file "$secret_file"
    tmp="$secret_file.tmp.$$"
    : > "$tmp"
    while IFS= read -r line || [ -n "$line" ]; do
        if [[ "$line" =~ ^[[:space:]]*(export[[:space:]]+)?OPENAI_API_KEY= ]]; then
            if [ "$written" = "0" ]; then
                printf 'export OPENAI_API_KEY=%s\n' "$quoted" >> "$tmp"
                written=1
            fi
        else
            printf '%s\n' "$line" >> "$tmp"
        fi
    done < "$secret_file"
    if [ "$written" = "0" ]; then
        printf '\nexport OPENAI_API_KEY=%s\n' "$quoted" >> "$tmp"
    fi
    chmod 600 "$tmp" || ep_die "Could not restrict secrets file: $secret_file"
    mv "$tmp" "$secret_file" || ep_die "Could not save API key to: $secret_file"
    ep_log "Saved OPENAI_API_KEY to protected secrets file: $secret_file"
}

ep_codex_offer_secret_persistence()
{
    local source="$1"
    local secret_file="$HOME/.config/secrets/api.env"

    [ "$source" = "secret-file" ] && return 0
    if ep_confirm "Save OPENAI_API_KEY to protected $secret_file?" "yes"; then
        ep_codex_persist_api_key "$EP_CODEX_API_KEY"
    else
        ep_warn "API key will remain available only in the current process; no persistent api.env key was written."
    fi
}

ep_codex_configure_auth()
{
    local auth_file secret_file
    local key_source=none

    secret_file="$HOME/.config/secrets/api.env"
    ep_ensure_secrets_file
    auth_file="$HOME/.codex/auth.json"
    EP_CODEX_API_KEY=""
    if [ -e "$auth_file" ] && [ "${EP_FORCE_CODEX_AUTH_WRITE:-0}" != "1" ]; then
        ep_log "Existing Codex auth file detected; preserving it and skipping API-key import: $auth_file"
        return 0
    fi

    if [ -n "$(printenv OPENAI_API_KEY 2>/dev/null || true)" ]; then
        EP_CODEX_API_KEY="$(printenv OPENAI_API_KEY)"
        key_source="current-environment"
        ep_log "Codex API key source: current OPENAI_API_KEY environment variable."
    elif ep_codex_key_from_secret_file "$secret_file"; then
        key_source="secret-file"
        ep_log "Codex API key source: protected $secret_file."
    elif [ -n "$(printenv env_key 2>/dev/null || true)" ]; then
        ep_warn "Found lowercase env_key in the environment. The correct variable name is OPENAI_API_KEY."
        if ep_confirm "Use the detected lowercase env_key value as OPENAI_API_KEY?" "yes"; then
            EP_CODEX_API_KEY="$(printenv env_key)"
            key_source="corrected-environment"
            ep_log "Codex API key source: corrected lowercase env_key environment variable."
        fi
    fi
    if [ -z "$EP_CODEX_API_KEY" ]; then
        ep_warn "No OPENAI_API_KEY was detected. Obtain an OpenAI-compatible key from your provider, for example YanHuoAPI, and put it in $secret_file or enter it now."
        ep_codex_prompt_api_key || {
            ep_warn "Codex CLI was installed/configured, but no API key was saved and auth.json was not generated. Put a key in $secret_file, then run: with_secrets codex"
            return 0
        }
        key_source="interactive"
        ep_log "Codex API key source: interactive input."
    fi
    ep_codex_offer_secret_persistence "$key_source"
    ep_codex_write_auth
    unset EP_CODEX_API_KEY
}

ep_codex_remote_template()
{
    printf '%s/templates/codex-remote.sh' "$ENVPILOT_ROOT"
}

ep_codex_remote_manager_path()
{
    printf '%s/.local/bin/codex-remote' "$HOME"
}

ep_codex_remote_wrapper_path()
{
    printf '%s/.local/bin/codex' "$HOME"
}

ep_codex_remote_is_managed_wrapper()
{
    local path="${1:-$(ep_codex_remote_wrapper_path)}"
    [ -f "$path" ] || return 1
    [ ! -L "$path" ] || return 1
    [ "$(LC_ALL=C head -c 2 "$path" 2>/dev/null || true)" = '#!' ] || return 1
    LC_ALL=C head -c 512 "$path" 2>/dev/null |
        grep -Fq 'envpilot-managed-codex-wrapper'
}

ep_codex_remote_install_manager()
{
    local template manager tmp
    template="$(ep_codex_remote_template)"
    manager="$(ep_codex_remote_manager_path)"
    [ -f "$template" ] || ep_die "Codex remote template is missing: $template"
    mkdir -p "$(dirname "$manager")"
    if [ -e "$manager" ] || [ -L "$manager" ]; then
        if ! grep -q 'envpilot Codex remote runtime manager' "$manager" 2>/dev/null; then
            ep_backup_file "$manager"
        fi
    fi
    tmp="$manager.tmp.$$"
    cp "$template" "$tmp"
    chmod 700 "$tmp"
    mv "$tmp" "$manager"
    ep_log "Installed Codex remote manager: $manager"
}

ep_codex_remote_install_wrapper()
{
    local wrapper tmp
    wrapper="$(ep_codex_remote_wrapper_path)"
    mkdir -p "$(dirname "$wrapper")"
    tmp="$wrapper.tmp.$$"
    cp "$ENVPILOT_ROOT/templates/codex-wrapper.sh" "$tmp"
    chmod 700 "$tmp"
    mv "$tmp" "$wrapper"
    ep_log "Enabled Codex wrapper: $wrapper"
}

ep_codex_remote_invoke()
{
    local action="${1:-status}"
    shift || true
    local template
    template="$(ep_codex_remote_template)"
    [ -f "$template" ] || ep_die "Codex remote template is missing: $template"
    ENVPILOT_CODEX_REMOTE_READY_TIMEOUT="$EP_CODEX_REMOTE_READY_TIMEOUT" \
        bash "$template" "$action" "$@"
}

ep_codex_remote_enable()
{
    ep_require_unix_runtime
    local template manager wrapper source
    template="$(ep_codex_remote_template)"
    manager="$(ep_codex_remote_manager_path)"
    wrapper="$(ep_codex_remote_wrapper_path)"
    source="$(bash "$template" source 2>/dev/null || true)"
    [ -n "$source" ] || ep_die "No persistent Codex source found. Install Codex first, then retry."

    ep_log "Persistent Codex source: $source"
    ep_log "Node-local runtime: ${ENVPILOT_CODEX_RUNTIME_DIR:-/tmp/${USER:-user}-envpilot-codex-${HOSTNAME:-host}}"
    ep_log "Control directory (must remain persistent): ${CODEX_HOME:-$HOME/.codex}/app-server-control"
    ep_log "Wrapper target: $wrapper"
    ep_confirm "Enable the envpilot Codex node-local runtime and replace the wrapper target if needed?" "yes" || {
        ep_warn "Codex remote runtime unchanged."
        return 0
    }

    ep_codex_remote_install_manager
    mkdir -p "$(dirname "$wrapper")"
    if [ -e "$wrapper" ] || [ -L "$wrapper" ]; then
        if ! ep_codex_remote_is_managed_wrapper "$wrapper"; then
            ep_backup_file "$wrapper"
        fi
    fi
    ep_codex_remote_install_wrapper
    if ep_codex_remote_invoke ready; then
        ep_log "Codex remote runtime is ready for Desktop."
    else
        ep_warn "Codex wrapper and node-local runtime were enabled, but app-server is not ready."
        ep_warn "Inspect with: bash envpilot.sh codex remote status"
        ep_warn "After resolving the reported process/socket conflict, run: bash envpilot.sh codex remote repair"
        return 1
    fi
}

ep_codex_remote_disable()
{
    ep_require_unix_runtime
    local manager wrapper backup
    manager="$(ep_codex_remote_manager_path)"
    wrapper="$(ep_codex_remote_wrapper_path)"
    ep_log "This stops only the envpilot-managed Codex app-server and restores the previous codex command when a backup exists."
    ep_confirm "Disable the envpilot Codex remote wrapper?" "no" || {
        ep_warn "Codex remote runtime unchanged."
        return 0
    }
    ep_codex_remote_invoke stop >/dev/null 2>&1 || true
    ep_codex_remote_invoke clean >/dev/null 2>&1 || true
    if ep_codex_remote_is_managed_wrapper "$wrapper"; then
        backup=""
        local candidate
        for candidate in "${wrapper}.bak."*; do
            [ -e "$candidate" ] || continue
            if [ -z "$backup" ] || [ "$candidate" -nt "$backup" ]; then
                backup="$candidate"
            fi
        done
        if [ -n "$backup" ] && [ -e "$backup" ]; then
            rm -f "$wrapper"
            cp -a "$backup" "$wrapper"
            ep_log "Restored previous Codex command: $wrapper"
        else
            rm -f "$wrapper"
            ep_log "Removed envpilot Codex wrapper: $wrapper"
        fi
    fi
    if [ -f "$manager" ] && grep -q 'envpilot Codex remote runtime manager' "$manager" 2>/dev/null; then
        rm -f "$manager"
        ep_log "Removed Codex remote manager: $manager"
    fi
}

ep_codex_remote_cli()
{
    ep_require_unix_runtime
    local action="${1:-status}" value="${2:-}"
    case "$action:$value" in
        remote:enable) ep_codex_remote_enable ;;
        remote:status|remote:) ep_codex_remote_invoke status ;;
        remote:stage|remote:prepare) ep_codex_remote_invoke stage ;;
        remote:ready|remote:warm) ep_codex_remote_invoke ready ;;
        remote:stop) ep_codex_remote_invoke stop ;;
        remote:repair) ep_codex_remote_invoke repair ;;
        remote:disable) ep_codex_remote_disable ;;
        status:*|stage:*|prepare:*|ready:*|warm:*|stop:*|repair:*)
            ep_codex_remote_invoke "$action" ;;
        disable:*) ep_codex_remote_disable ;;
        *) ep_die "Usage: bash envpilot.sh codex remote {status|enable|stage|ready|warm|stop|repair|disable}" ;;
    esac
}

ep_doctor_codex_remote()
{
    local template wrapper
    template="$(ep_codex_remote_template)"
    wrapper="$(ep_codex_remote_wrapper_path)"
    [ -f "$template" ] || return 0
    if ep_codex_remote_is_managed_wrapper "$wrapper"; then
        ep_log "Codex remote: wrapper enabled at $wrapper"
    else
        ep_log "Codex remote: wrapper not enabled; use: bash envpilot.sh codex remote enable"
    fi
    if [ -n "$EP_CODEX_PROBE_ERROR" ] && [[ "$EP_CODEX_PROBE_ERROR" == *"timed out"* ]]; then
        ep_warn "Codex --version is slow on the current filesystem; use: bash envpilot.sh codex remote ready"
    fi
}

ep_install_codex()
{
    ep_require_unix_runtime
    local action existing probe_ready install_source remote_wrapper_enabled
    action=configured
    install_source=existing
    remote_wrapper_enabled=0
    if ep_codex_remote_is_managed_wrapper "$(ep_codex_remote_wrapper_path)"; then
        remote_wrapper_enabled=1
    fi
    ep_log "Component: codex"
    ep_log "Package: $EP_CODEX_PACKAGE"
    ep_log "Default install method: official standalone; Node.js and npm are not required."
    ep_log "Codex config uses env_key=OPENAI_API_KEY; existing auth.json is preserved, and a missing file may be created from a detected key."
    ep_confirm "Install/update and configure Codex CLI?" "yes" || {
        ep_report_event codex skipped "user declined" "" "" ""
        return 0
    }

    existing=0
    probe_ready=0
    ep_codex_detect_installation
    ep_codex_warn_duplicate_installation
    if [ -n "$EP_CODEX_INSTALLED_BIN" ]; then
        existing=1
        if ep_codex_probe_path "$EP_CODEX_PROBE_BIN"; then
            probe_ready=1
        fi
    fi

    if [ "$existing" = "1" ] && [ "$EP_UPGRADE" != "1" ] && [ "$probe_ready" = "1" ]; then
        ep_log "Existing $EP_CODEX_INSTALL_METHOD Codex CLI is usable at $EP_CODEX_BIN; installation is unchanged."
    elif [ "$existing" = "1" ] && [ "$EP_UPGRADE" != "1" ] && [ "$EP_CODEX_PROBE_STATE" = "timeout" ]; then
        ep_log "Existing $EP_CODEX_INSTALL_METHOD Codex installation found at $EP_CODEX_INSTALLED_BIN; installation is unchanged."
        ep_codex_warn_slow_probe "$EP_CODEX_INSTALLED_BIN"
    else
        if [ "$EP_MODE" = "offline" ]; then
            if [ "$existing" = "1" ]; then
                ep_die "Codex requires repair/update, but offline mode cannot reach its existing $EP_CODEX_INSTALL_METHOD installer source. Existing files were not changed."
            fi
            ep_die "Codex is not installed and offline mode has no standalone package source. Run online mode."
        fi

        case "$EP_CODEX_INSTALL_METHOD" in
            npm)
                ep_log "Preserving the existing npm installation method for this Codex update."
                ep_install_codex_npm 1
                install_source="npm:$EP_CODEX_PACKAGE"
                ;;
            standalone|unknown)
                [ "$EP_CODEX_PROBE_STATE" != "failed" ] ||
                    ep_warn "The existing $EP_CODEX_INSTALL_METHOD Codex command failed its bounded probe; reinstalling with the official standalone installer."
                ep_install_codex_official ||
                    ep_die "The official standalone Codex install/update failed. Existing Codex files, if any, were preserved; npm fallback was not started."
                install_source="$EP_CODEX_INSTALL_URL"
                ;;
            none)
                if ep_install_codex_official; then
                    install_source="$EP_CODEX_INSTALL_URL"
                elif ep_confirm "The official standalone installer failed. Try the legacy npm method, which may install Node.js first?" "no"; then
                    ep_install_codex_npm 0
                    install_source="npm:$EP_CODEX_PACKAGE"
                else
                    ep_die "Codex was not installed. The official installer failed, and the optional npm fallback was not selected."
                fi
                ;;
        esac
        if [ "$existing" = "1" ]; then
            action=updated
        else
            action=installed
        fi
    fi
    ep_write_codex_config
    ep_codex_configure_auth
    ep_state_mark_done codex
    ep_codex_detect_installation
    if [ "$remote_wrapper_enabled" = "1" ]; then
        ep_codex_remote_install_manager
        ep_codex_remote_install_wrapper
        ep_log "Restored the envpilot Codex remote wrapper after the CLI install/update."
    elif [ -f "$(ep_codex_remote_manager_path)" ] && grep -q 'envpilot Codex remote runtime manager' "$(ep_codex_remote_manager_path)" 2>/dev/null; then
        ep_codex_remote_install_manager
    fi
    ep_report_event codex "$action" "preserved the Codex install method and configured env_key" "$EP_CODEX_VERSION" "$install_source" "${EP_CODEX_INSTALLED_BIN:-$EP_CODEX_BIN}"
}
