#!/usr/bin/env bash
set -euo pipefail

if [ -d /usr/bin ]; then
    PATH="/usr/bin:/bin:$PATH"
fi

ROOT="$(cd "${BASH_SOURCE[0]%/*}/.." && pwd)"
PYTHON_BIN="${PYTHON_BIN:-$(command -v python3 || command -v python || true)}"
if [ -z "$PYTHON_BIN" ]; then
    echo "python3 or python is required for test checks" >&2
    exit 1
fi

echo "[TEST] bash syntax"
bash -n "$ROOT/envpilot.sh"
for file in "$ROOT"/lib/*.sh "$ROOT"/components/*.sh "$ROOT"/scripts/*.sh "$ROOT"/templates/*.sh "$ROOT"/templates/bashrc "$ROOT"/templates/zshrc "$ROOT/bootstrap.sh"; do
    bash -n "$file"
done
"$PYTHON_BIN" -c 'import pathlib, sys; path = pathlib.Path(sys.argv[1]); compile(path.read_text(encoding="utf-8"), str(path), "exec")' "$ROOT/scripts/update-manifests.py"
"$PYTHON_BIN" -c 'import pathlib, sys; path = pathlib.Path(sys.argv[1]); compile(path.read_text(encoding="utf-8"), str(path), "exec")' "$ROOT/scripts/update-mihomo-cache.py"
"$PYTHON_BIN" "$ROOT/scripts/update-manifests.py" --check >/tmp/envpilot-manifest-check.out
"$PYTHON_BIN" "$ROOT/scripts/update-mihomo-cache.py" --check >/tmp/envpilot-mihomo-cache-check.out

echo "[TEST] workflow semantics"
grep -q 'git archive' "$ROOT/.github/workflows/release-assets.yml"
! grep -q 'files: downloads/\*' "$ROOT/.github/workflows/release-assets.yml"
grep -q 'actions/checkout@v7' "$ROOT/.github/workflows/release-assets.yml"
grep -q 'softprops/action-gh-release@v3' "$ROOT/.github/workflows/release-assets.yml"
grep -q 'push:' "$ROOT/.github/workflows/release-assets.yml"
grep -q 'tags:' "$ROOT/.github/workflows/release-assets.yml"
grep -q 'generate_release_notes: true' "$ROOT/.github/workflows/release-assets.yml"
grep -q 'refs/tags/v' "$ROOT/.github/workflows/release-assets.yml"
grep -q 'scripts/\*.sh' "$ROOT/.github/workflows/test.yml"
grep -q 'actions/checkout@v7' "$ROOT/.github/workflows/update-manifests.yml"
grep -q 'scripts/update-manifests.py --check' "$ROOT/.github/workflows/update-manifests.yml"
grep -q 'peter-evans/create-pull-request@v8' "$ROOT/.github/workflows/update-manifests.yml"
grep -q 'scripts/update-mihomo-cache.py --check' "$ROOT/.github/workflows/update-mihomo-cache.yml"
grep -q 'scripts/update-mihomo-cache.py' "$ROOT/.github/workflows/update-mihomo-cache.yml"
grep -q 'country.mmdb' "$ROOT/.github/workflows/update-mihomo-cache.yml"
grep -q 'peter-evans/create-pull-request@v8' "$ROOT/.github/workflows/update-mihomo-cache.yml"

echo "[TEST] install order and resolver policy"
grep -q 'for component in mihomo git python conda mamba codex github tmux' "$ROOT/envpilot.sh"
grep -q 'update|upgrade) run_update' "$ROOT/envpilot.sh"
grep -q 'EP_UPGRADE="1"' "$ROOT/envpilot.sh"
grep -q 'BASHRC_PROXY_ENABLE_SOCKS="${BASHRC_PROXY_ENABLE_SOCKS:-0}"' "$ROOT/templates/bashrc"
grep -q 'proxy_no_proxy_add()' "$ROOT/templates/bashrc"
grep -q 'Proxy is not listening at %s:%s' "$ROOT/templates/bashrc"
grep -q 'ep_tmux_target_version' "$ROOT/components/tmux.sh"
grep -q 'ep_update_conda' "$ROOT/components/conda.sh"
grep -q 'action=updated' "$ROOT/components/mamba.sh" "$ROOT/components/codex.sh"
grep -q '"update","upgrade"' "$ROOT/envpilot.ps1"
grep -q '$Script:Upgrade' "$ROOT/envpilot.ps1"
grep -q 'Add-EnvpilotNoProxy' "$ROOT/templates/Microsoft.PowerShell_profile.ps1"
grep -q 'Proxy is not listening at' "$ROOT/templates/Microsoft.PowerShell_profile.ps1"
grep -q 'update-mihomo-cache' "$ROOT/envpilot.sh"
grep -q 'restore) run_restore' "$ROOT/envpilot.sh"
grep -q 'mihomo) run_mihomo' "$ROOT/envpilot.sh"
grep -q 'port PORT' "$ROOT/envpilot.sh"
grep -q 'EP_MIHOMO_ACTION' "$ROOT/lib/common.sh"
grep -q 'ep_mihomo_cli' "$ROOT/components/mihomo.sh"
grep -q 'ep_switch_mihomo_port' "$ROOT/components/mihomo.sh"
grep -q 'ep_find_cached_asset' "$ROOT/lib/download.sh"
grep -q 'ep_capture_doctor_baseline' "$ROOT/lib/baseline.sh"
grep -q 'ep_restore_doctor_baseline' "$ROOT/lib/baseline.sh"
grep -q 'mihomo-bin' "$ROOT/lib/baseline.sh"
grep -q 'Using bundled downloads/ Mihomo asset for' "$ROOT/components/mihomo.sh"
grep -q 'ep_mihomo_set_shell_local_ports "$proxy_port" "$api_port"' "$ROOT/components/mihomo.sh"
grep -q 'Using bundled downloads/ mihomo data asset before network' "$ROOT/components/mihomo.sh"
grep -q 'meta-rules-dat' "$ROOT/components/mihomo.sh"
grep -q 'Find-CachedAsset' "$ROOT/envpilot.ps1"
grep -q 'Install-MihomoDataAssets' "$ROOT/envpilot.ps1"
grep -q 'EP_LEGACY_MINICONDA_VERSION' "$ROOT/components/conda.sh"
grep -q 'ep_mihomo_offline_pattern' "$ROOT/components/mihomo.sh"
grep -q 'MIHOMO_API_PORT' "$ROOT/templates/bashrc"
grep -q 'mihomo_ports()' "$ROOT/templates/bashrc"
grep -q 'mihomo_update_subscription()' "$ROOT/templates/bashrc"
grep -q 'envpilot_restore()' "$ROOT/templates/bashrc"
grep -q 'mihomo_ports()' "$ROOT/templates/zshrc"
grep -q 'mihomo_update_subscription()' "$ROOT/templates/zshrc"
grep -q 'envpilot_restore()' "$ROOT/templates/zshrc"
grep -q 'codex_remote()' "$ROOT/templates/bashrc" "$ROOT/templates/zshrc"
grep -q 'codex_ready()' "$ROOT/templates/bashrc" "$ROOT/templates/zshrc"
grep -q 'codex remote' "$ROOT/envpilot.sh"
grep -q 'ep_codex_remote_cli' "$ROOT/components/codex.sh"
grep -q 'envpilot-managed-codex-wrapper' "$ROOT/templates/codex-wrapper.sh"
grep -q 'Staging Codex runtime' "$ROOT/templates/codex-remote.sh"
grep -q 'app-server --listen unix://' "$ROOT/templates/codex-remote.sh"
grep -qi 'control directory must stay on persistent storage' "$ROOT/templates/codex-remote.sh"
grep -q 'MIHOMO_RUNTIME_DIR="/tmp/' "$ROOT/templates/mihomo_common.sh"
grep -q 'MIHOMO_START_LOCK_DIR="\${MIHOMO_RUNTIME_DIR}.start.lock"' "$ROOT/templates/mihomo_common.sh"
! grep -q 'MIHOMO_START_LOCK_DIR="\${MIHOMO_RUNTIME_DIR}/' "$ROOT/templates/mihomo_common.sh"
grep -q 'MIHOMO_QUIET_START=1' "$ROOT/templates/bashrc" "$ROOT/templates/zshrc"
grep -q 'envpilot_prepare_noninteractive_proxy' "$ROOT/templates/bashrc" "$ROOT/templates/zshrc"
grep -q 'envpilot_export_proxy_if_ready' "$ROOT/templates/bashrc" "$ROOT/templates/zshrc"
grep -q 'timeout 1 bash -c ": </dev/tcp/\$host/\$port"' "$ROOT/templates/zshrc"
grep -q 'BASHRC_USE_NODE_LOCAL_TMP' "$ROOT/templates/shell.local.example"
grep -q 'install-time proxy preparation trust an already-listening port' "$ROOT/CHANGELOG.md"
grep -q 'API .* was not ready' "$ROOT/templates/start_mihomo.sh"
grep -q 'update-subscription' "$ROOT/envpilot.sh"
grep -q 'partial clone' "$ROOT/README.md"
grep -q 'sparse-checkout' "$ROOT/bootstrap.sh"
grep -q 'Source URL:' "$ROOT/lib/download.sh"
! grep -qi 'miniforge' "$ROOT/components/conda.sh" "$ROOT/manifests/conda.json" "$ROOT/templates/bashrc" "$ROOT/templates/zshrc" "$ROOT/scripts/collect-assets.sh" "$ROOT/scripts/collect-assets.ps1"

echo "[TEST] portable JSON escaping"
(
    . "$ROOT/lib/common.sh"
    escaped="$(printf 'path\\value\n"quoted"' | ep_json_escape)"
    [ "$escaped" = 'path\\value\n\"quoted\"' ]
)

echo "[TEST] Git/Python minimum-version fixtures"
fixture_home="$(mktemp -d)"
fixture_bin="$(mktemp -d)"
cat > "$fixture_bin/git" <<'EOF'
#!/usr/bin/env bash
printf 'git version %s\n' "${FIXTURE_GIT_VERSION:-2.30.0}"
EOF
cat > "$fixture_bin/python3" <<'EOF'
#!/usr/bin/env bash
if [ "$1" = "--version" ]; then
    printf 'Python %s\n' "${FIXTURE_PYTHON_VERSION:-3.9.0}"
elif [ "$1" = "-c" ]; then
    case "${FIXTURE_PYTHON_VERSION:-3.9.0}" in
        3.8*) exit 1 ;;
        *) exit 0 ;;
    esac
fi
EOF
cat > "$fixture_bin/make" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
cp "$fixture_bin/python3" "$fixture_bin/python"
cp "$fixture_bin/make" "$fixture_bin/cc"
chmod +x "$fixture_bin/git" "$fixture_bin/python3" "$fixture_bin/python" "$fixture_bin/make" "$fixture_bin/cc"
: > "$fixture_home/git-2.29.0.tar.xz"
: > "$fixture_home/cpython-3.8.0+fixture-x86_64-unknown-linux-gnu-install_only.tar.gz"
(
    export HOME="$fixture_home"
    export PATH="$fixture_bin:/usr/bin:/bin"
    export FIXTURE_GIT_VERSION=2.30.0
    export ENVPILOT_ROOT="$ROOT" EP_PREFIX="$fixture_home/software"
    export EP_LIBC=glibc EP_GLIBC_VERSION=2.17 EP_MODE=offline EP_ASSUME_YES=1
    . "$ROOT/lib/common.sh"
    . "$ROOT/lib/download.sh"
    . "$ROOT/lib/platform.sh"
    export EP_OS=linux EP_ARCH=amd64 EP_LIBC=glibc EP_GLIBC_VERSION=2.17
    . "$ROOT/components/git.sh"
    ep_init
    ep_report_start install git
    ep_install_git
    ep_report_finish
)
grep -q '^git=done:' "$fixture_home/.config/envpilot/state"
test ! -e "$fixture_home/software/git/current/bin/git"
set +e
(
    export HOME="$fixture_home"
    export PATH="$fixture_bin:/usr/bin:/bin"
    export FIXTURE_GIT_VERSION=2.29.0
    export EP_ASSET_PATH="$fixture_home/git-2.29.0.tar.xz"
    export ENVPILOT_ROOT="$ROOT" EP_PREFIX="$fixture_home/software"
    export EP_LIBC=glibc EP_GLIBC_VERSION=2.17 EP_MODE=offline EP_ASSUME_YES=1
    . "$ROOT/lib/common.sh"
    . "$ROOT/lib/download.sh"
    . "$ROOT/lib/platform.sh"
    export EP_OS=linux EP_ARCH=amd64 EP_LIBC=glibc EP_GLIBC_VERSION=2.17
    . "$ROOT/components/git.sh"
    ep_init
    ep_report_start install git
    ep_install_git
) > "$fixture_home/git-2.29.out" 2>&1
status=$?
set -e
[ "$status" -eq 1 ]
grep -q 'Selected Git source 2.29.0 is below' "$fixture_home/git-2.29.out"
(
    export HOME="$fixture_home"
    export PATH="$fixture_bin:/usr/bin:/bin"
    export FIXTURE_PYTHON_VERSION=3.9.0
    export ENVPILOT_ROOT="$ROOT" EP_PREFIX="$fixture_home/software"
    export EP_LIBC=glibc EP_GLIBC_VERSION=2.17 EP_MODE=offline EP_ASSUME_YES=1
    . "$ROOT/lib/common.sh"
    . "$ROOT/lib/download.sh"
    . "$ROOT/lib/platform.sh"
    export EP_OS=linux EP_ARCH=amd64 EP_LIBC=glibc EP_GLIBC_VERSION=2.17
    . "$ROOT/components/python.sh"
    ep_init
    ep_report_start install python
    ep_install_python
    ep_report_finish
)
grep -q '^python=done:' "$fixture_home/.config/envpilot/state"
test ! -e "$fixture_home/software/python/current/bin/python3"
set +e
(
    export HOME="$fixture_home"
    export PATH="$fixture_bin:/usr/bin:/bin"
    export FIXTURE_PYTHON_VERSION=3.8.0
    export EP_ASSET_PATH="$fixture_home/cpython-3.8.0+fixture-x86_64-unknown-linux-gnu-install_only.tar.gz"
    export ENVPILOT_ROOT="$ROOT" EP_PREFIX="$fixture_home/software"
    export EP_LIBC=glibc EP_GLIBC_VERSION=2.17 EP_MODE=offline EP_ASSUME_YES=1
    . "$ROOT/lib/common.sh"
    . "$ROOT/lib/download.sh"
    . "$ROOT/lib/platform.sh"
    export EP_OS=linux EP_ARCH=amd64 EP_LIBC=glibc EP_GLIBC_VERSION=2.17
    . "$ROOT/components/python.sh"
    ep_init
    ep_report_start install python
    ep_install_python
) > "$fixture_home/python-3.8.out" 2>&1
status=$?
set -e
[ "$status" -eq 1 ]
grep -q 'Selected Python version 3.8.0 is below' "$fixture_home/python-3.8.out"
rm -rf "$fixture_home" "$fixture_bin"
echo "[TEST] missing nvm installation reaches explained Node.js setup"
tmp_home="$(mktemp -d)"
codex_output="$tmp_home/codex-node.out"
set +e
(
    set -euo pipefail
    HOME="$tmp_home"
    NVM_DIR="$tmp_home/.nvm"
    ENVPILOT_ROOT="$ROOT"
    # shellcheck source=/dev/null
    . "$ROOT/lib/common.sh"
    # shellcheck source=/dev/null
    . "$ROOT/components/codex.sh"
    ep_command_exists()
    {
        case "$1" in
            node|nvm) return 1 ;;
            curl) return 0 ;;
            *) command -v "$1" >/dev/null 2>&1 ;;
        esac
    }
    ep_confirm()
    {
        return 1
    }
    ep_ensure_node
) >"$codex_output" 2>&1
codex_status=$?
set -e
if [ "$codex_status" -ne 1 ]; then
    echo "Expected declined Node.js setup to exit 1, got: $codex_status" >&2
    cat "$codex_output" >&2
    exit 1
fi
grep -q 'Node.js: not found' "$codex_output"
grep -q 'Node.js source: nvm' "$codex_output"
grep -q 'Node.js target:' "$codex_output"
grep -q 'Node.js 22+ is required for Codex' "$codex_output"
grep -q 'Installing the latest compatible Codex CLI from the npm registry' "$ROOT/components/codex.sh"
grep -q 'official standalone installer' "$ROOT/components/codex.sh"

echo "[TEST] existing Codex bypasses Node setup"
tmp_home="$(mktemp -d)"
tmp_bin="$(mktemp -d)"
cat > "$tmp_bin/codex" <<'EOF'
#!/usr/bin/env bash
printf 'codex-cli 0.147.0\n'
EOF
chmod +x "$tmp_bin/codex"
codex_existing_output="$tmp_home/codex-existing.out"
(
    set -euo pipefail
    export HOME="$tmp_home"
    export PATH="$tmp_bin:/usr/bin:/bin"
    export ENVPILOT_ROOT="$ROOT"
    export EP_MODE=online EP_ASSUME_YES=1 EP_UPGRADE=0
    # shellcheck source=/dev/null
    . "$ROOT/lib/common.sh"
    # shellcheck source=/dev/null
    . "$ROOT/lib/platform.sh"
    # shellcheck source=/dev/null
    . "$ROOT/lib/shell.sh"
    # shellcheck source=/dev/null
    . "$ROOT/components/codex.sh"
    export EP_OS=linux EP_ARCH=amd64 EP_LIBC=glibc EP_GLIBC_VERSION=2.17
    ep_init
    ep_report_start install codex
    ep_ensure_node()
    {
        printf 'unexpected Node.js setup\n' >&2
        return 99
    }
    ep_codex_configure_auth() { :; }
    ep_install_codex
    ep_report_finish
) >"$codex_existing_output" 2>&1
grep -q 'Node.js and npm are not required for configuration' "$codex_existing_output"
! grep -q 'unexpected Node.js setup' "$codex_existing_output"
grep -q '^codex=done:' "$tmp_home/.config/envpilot/state"
rm -rf "$tmp_home" "$tmp_bin"

echo "[TEST] legacy glibc selects the compatible Node.js 22 build"
tmp_home="$(mktemp -d)"
tmp_bin="$(mktemp -d)"
cat > "$tmp_bin/curl" <<'EOF'
#!/usr/bin/env bash
output=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        -o) output="$2"; shift 2 ;;
        *) shift ;;
    esac
done
cat > "$output" <<'INSTALL'
#!/usr/bin/env bash
target=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        --dir) target="$2"; shift 2 ;;
        *) shift ;;
    esac
done
mkdir -p "$target/bin"
cat > "$target/bin/node" <<'NODE'
#!/usr/bin/env bash
printf 'v22.19.0\n'
NODE
chmod +x "$target/bin/node"
INSTALL
chmod +x "$output"
EOF
chmod +x "$tmp_bin/curl"
legacy_node_output="$tmp_home/legacy-node.out"
(
    set -euo pipefail
    export HOME="$tmp_home"
    export PATH="$tmp_bin:/usr/bin:/bin"
    export ENVPILOT_ROOT="$ROOT"
    export EP_MODE=online EP_ASSUME_YES=1
    # shellcheck source=/dev/null
    . "$ROOT/lib/common.sh"
    # shellcheck source=/dev/null
    . "$ROOT/lib/platform.sh"
    # shellcheck source=/dev/null
    . "$ROOT/components/codex.sh"
    export EP_OS=linux EP_ARCH=amd64 EP_LIBC=glibc EP_GLIBC_VERSION=2.17
    ep_command_exists()
    {
        case "$1" in
            node|nvm) return 1 ;;
            curl) return 0 ;;
            *) command -v "$1" >/dev/null 2>&1 ;;
        esac
    }
    ep_ensure_node
    printf 'node=%s\n' "$(command -v node)"
) >"$legacy_node_output" 2>&1
grep -q 'glibc-217' "$legacy_node_output"
grep -q 'Node.js source: unofficial-builds x64-glibc-217' "$legacy_node_output"
grep -q "node=$tmp_home/software/node22/bin/node" "$legacy_node_output"
! grep -q 'Downloading nvm installer' "$legacy_node_output"
rm -rf "$tmp_home" "$tmp_bin"

echo "[TEST] failed Node.js probe preserves the GLIBC diagnostic"
tmp_home="$(mktemp -d)"
tmp_bin="$(mktemp -d)"
cat > "$tmp_bin/node" <<'EOF'
#!/usr/bin/env bash
printf 'node: /lib64/libc.so.6: version GLIBC_2.28 not found\n' >&2
exit 127
EOF
chmod +x "$tmp_bin/node"
node_probe_output="$tmp_home/node-probe.out"
(
    set -euo pipefail
    export HOME="$tmp_home"
    export PATH="$tmp_bin:/usr/bin:/bin"
    # shellcheck source=/dev/null
    . "$ROOT/lib/common.sh"
    # shellcheck source=/dev/null
    . "$ROOT/components/codex.sh"
    if ep_node_probe; then
        exit 1
    fi
    printf '%s\n' "$EP_NODE_PROBE_ERROR"
) >"$node_probe_output" 2>&1
grep -q 'GLIBC_2.28 not found' "$node_probe_output"
rm -rf "$tmp_home" "$tmp_bin"

echo "[TEST] Codex remote runtime stages a persistent release and keeps exec output clean"
tmp_remote_home="$(mktemp -d)"
tmp_remote_source="$tmp_remote_home/.codex/packages/standalone/releases/0.147.0/bin"
tmp_remote_runtime="/tmp/envpilot-codex-remote-test-$$"
mkdir -p "$tmp_remote_source"
cat > "$tmp_remote_source/codex" <<'EOF'
#!/usr/bin/env bash
if [ "${1:-}" = "--version" ]; then
    printf 'codex-cli 0.147.0\n'
    exit 0
fi
printf 'fake codex\n'
EOF
chmod 700 "$tmp_remote_source/codex"
(
    set -euo pipefail
    export HOME="$tmp_remote_home"
    export CODEX_HOME="$tmp_remote_home/.codex"
    export ENVPILOT_CODEX_SOURCE_BIN="$tmp_remote_source"
    export ENVPILOT_CODEX_RUNTIME_DIR="$tmp_remote_runtime"
    bash "$ROOT/templates/codex-remote.sh" stage
    test -x "$tmp_remote_runtime/current/bin/codex"
    result="$(bash "$ROOT/templates/codex-remote.sh" exec --version)"
    [ "$result" = "codex-cli 0.147.0" ]
    bash "$ROOT/templates/codex-remote.sh" status >"$tmp_remote_home/remote-status.out"
    grep -q 'Persistent source:' "$tmp_remote_home/remote-status.out"
    grep -q 'Local runtime:' "$tmp_remote_home/remote-status.out"
)
rm -rf "$tmp_remote_home" "$tmp_remote_runtime"

echo "[TEST] Codex probe is bounded on a slow shared-filesystem executable"
tmp_slow_home="$(mktemp -d)"
tmp_slow_bin="$(mktemp -d)"
cat > "$tmp_slow_bin/codex" <<'EOF'
#!/usr/bin/env bash
sleep 10
EOF
chmod 700 "$tmp_slow_bin/codex"
(
    set -euo pipefail
    export HOME="$tmp_slow_home"
    export PATH="$tmp_slow_bin:/usr/bin:/bin"
    export EP_CODEX_PROBE_TIMEOUT=1
    . "$ROOT/lib/common.sh"
    . "$ROOT/components/codex.sh"
    ep_command_exists()
    {
        case "$1" in
            timeout|gtimeout|perl) return 1 ;;
            *) command -v "$1" >/dev/null 2>&1 ;;
        esac
    }
    if ep_codex_probe; then
        exit 1
    fi
    printf '%s\n' "$EP_CODEX_PROBE_ERROR" | grep -q 'timed out after 1s'
)
rm -rf "$tmp_slow_home" "$tmp_slow_bin"

grep -q '^!downloads/mihomo-linux-amd64-compatible-\*\.gz$' "$ROOT/.gitignore"
grep -q '^!downloads/mihomo-windows-amd64-compatible-\*\.zip$' "$ROOT/.gitignore"
grep -q '^!downloads/country\.mmdb$' "$ROOT/.gitignore"
grep -q '^!downloads/geoip\.metadb$' "$ROOT/.gitignore"

(
    ENVPILOT_ROOT="$ROOT"
    # shellcheck source=/dev/null
    . "$ROOT/lib/common.sh"
    # shellcheck source=/dev/null
    . "$ROOT/lib/platform.sh"
    # shellcheck source=/dev/null
    . "$ROOT/components/conda.sh"
    EP_OS="linux"
    EP_ARCH="amd64"
    EP_LIBC="glibc"
    EP_GLIBC_VERSION="2.17"
    EP_CONDA_DISTRIBUTION="miniconda"
    legacy_url="$(ep_conda_installer_url)"
    case "$legacy_url" in
        *Miniconda3-py312_24.11.1-0-Linux-x86_64.sh) ;;
        *) echo "Expected archived Miniconda for glibc 2.17, got: $legacy_url" >&2; exit 1 ;;
    esac
    EP_CONDA_DISTRIBUTION="anaconda"
    anaconda_url="$(ep_conda_installer_url)"
    case "$anaconda_url" in
        *Anaconda3-2025.06-1-Linux-x86_64.sh) ;;
        *) echo "Expected Anaconda installer URL, got: $anaconda_url" >&2; exit 1 ;;
    esac

    EP_GLIBC_VERSION="2.28"
    anaconda_latest_url="$(ep_conda_installer_url)"
    case "$anaconda_latest_url" in
        *Anaconda3-2025.12-2-Linux-x86_64.sh) ;;
        *) echo "Expected current Anaconda installer URL, got: $anaconda_latest_url" >&2; exit 1 ;;
    esac
)

echo "[TEST] shell.local migration keeps safe environment and excludes old proxy"
tmp_home="$(mktemp -d)"
mkdir -p "$tmp_home/.config/envpilot"
cat > "$tmp_home/.bashrc" <<'EOF'
export PATH="$HOME/bin:$PATH"
export GOPATH="$HOME/software/go"
export SINGULARITY_CACHEDIR="$HOME/singularity_cache"
export http_proxy="http://127.0.0.1:7890"
export OPENAI_API_KEY="should-not-migrate"
export MIHOMO_PROXY_PORT=7890
for conda_sh in \
    "$HOME/software/miniconda3/etc/profile.d/conda.sh" \
    "$HOME/software/anaconda3/etc/profile.d/conda.sh" \
    /opt/conda/etc/profile.d/conda.sh; do
    [ -r "$conda_sh" ] && . "$conda_sh" && return 0
done
EOF
(
    HOME="$tmp_home"
    ENVPILOT_ROOT="$ROOT"
    # shellcheck source=/dev/null
    . "$ROOT/lib/common.sh"
    # shellcheck source=/dev/null
    . "$ROOT/lib/shell.sh"
    EP_CONFIG_DIR="$tmp_home/.config/envpilot"
    ep_migrate_shell_local "$tmp_home/.bashrc" >/dev/null
)
shell_local="$tmp_home/.config/envpilot/shell.local"
if grep -q 'conda\.sh' "$shell_local"; then
    echo "shell.local migration must not copy conda.sh fragments" >&2
    cat "$shell_local" >&2
    exit 1
fi
grep -q 'export PATH=' "$shell_local"
grep -q 'export GOPATH=' "$shell_local"
grep -q 'export SINGULARITY_CACHEDIR=' "$shell_local"
! grep -qE '(^|[[:space:]])(http_proxy|OPENAI_API_KEY|MIHOMO_PROXY_PORT)=' "$shell_local"
bash --noprofile --norc -c '. "'"$shell_local"'"'

echo "[TEST] Mihomo takeover report"
tmp_home="$(mktemp -d)"
(
    HOME="$tmp_home"
    USER="envpilot-test"
    HOSTNAME="envpilot-host"
    ENVPILOT_ROOT="$ROOT"
    . "$ROOT/lib/common.sh"
    . "$ROOT/lib/platform.sh"
    . "$ROOT/components/mihomo.sh"
    EP_OS="linux"
    EP_ARCH="amd64"
    EP_IS_ROOT="false"
    ep_init
    EP_MIHOMO_TAKEOVER_EXISTING_PROCESSES='123 /work/old/Mihomo/bin/mihomo -d /work/old/config'
    EP_MIHOMO_TAKEOVER_EXISTING_PROCESS_VERSIONS='pid=123 version=v1.18.0'
    EP_MIHOMO_TAKEOVER_EXISTING_DETECTED=true
    EP_MIHOMO_TAKEOVER_EXISTING_MANAGED=true
    EP_MIHOMO_TAKEOVER_MANAGED_RUNTIME_WAS_RUNNING=true
    EP_MIHOMO_TAKEOVER_MANAGED_RUNTIME_RESTARTED=true
    EP_MIHOMO_TAKEOVER_EXISTING_CONFIG_PRESERVED=true
    EP_MIHOMO_TAKEOVER_EXISTING_STOPPED=true
    EP_MIHOMO_TAKEOVER_STOP_SIGNALS=TERM,KILL
    EP_MIHOMO_TAKEOVER_PROXY_ENV_WAS_SET=true
    EP_MIHOMO_TAKEOVER_PROXY_ENV_CLEARED=true
    EP_MIHOMO_TAKEOVER_BEFORE_PROXY_LISTENING=true
    EP_MIHOMO_TAKEOVER_BEFORE_API_LISTENING=true
    EP_MIHOMO_TAKEOVER_AFTER_PROXY_LISTENING=false
    EP_MIHOMO_TAKEOVER_AFTER_API_LISTENING=false
    EP_MIHOMO_TAKEOVER_PROXY_PORT=42290
    EP_MIHOMO_TAKEOVER_API_PORT=60290
    EP_MIHOMO_TAKEOVER_BINARY_BEFORE_VERSION=v1.18.0
    EP_MIHOMO_TAKEOVER_SELECTED_SOURCE="downloads/mihomo-linux-amd64-compatible-v1.19.29.gz"
    EP_MIHOMO_TAKEOVER_SELECTED_VERSION=v1.19.29
    EP_MIHOMO_TAKEOVER_BINARY_ACTION=installed-or-updated
    ep_mihomo_write_takeover_report completed
)
"$PYTHON_BIN" - "$tmp_home/.config/envpilot/mihomo-takeover-report.json" <<'PY'
import json
import sys
report = json.load(open(sys.argv[1], encoding="utf-8"))
assert report["existing_processes_detected"] is True
assert report["existing_processes_envpilot_managed"] is True
assert report["managed_runtime_was_running"] is True
assert report["managed_runtime_restarted"] is True
assert report["existing_config_preserved"] is True
assert report["existing_processes_stopped"] is True
assert report["before_ports"]["proxy_listening"] is True
assert report["after_stop_ports"]["proxy_listening"] is False
assert report["selected_version"] == "v1.19.29"
assert report["binary_action"] == "installed-or-updated"
PY

echo "[TEST] Mihomo version probe executes a node-local temporary copy"
tmp_home="$(mktemp -d)"
mkdir -p "$tmp_home/software/mihomo"
cat > "$tmp_home/software/mihomo/mihomo" <<'EOF'
#!/usr/bin/env bash
case "$0" in
    /tmp/envpilot-mihomo-version.*/mihomo) ;;
    *) exit 97 ;;
esac
printf 'Mihomo Meta v9.9.9 linux amd64\n'
EOF
chmod +x "$tmp_home/software/mihomo/mihomo"
(
    HOME="$tmp_home"
    EP_MIHOMO_VERSION_PROBE_FORCE_COPY=1
    export EP_MIHOMO_VERSION_PROBE_FORCE_COPY
    # shellcheck source=/dev/null
    . "$ROOT/lib/common.sh"
    # shellcheck source=/dev/null
    . "$ROOT/components/mihomo.sh"
    [ "$(ep_mihomo_binary_version "$tmp_home/software/mihomo/mihomo")" = "v9.9.9" ]
    ep_command_exists()
    {
        case "$1" in
            timeout|gtimeout) return 1 ;;
            *) command -v "$1" >/dev/null 2>&1 ;;
        esac
    }
    [ "$(ep_mihomo_binary_version "$tmp_home/software/mihomo/mihomo")" = "v9.9.9" ]
)
rm -rf "$tmp_home"

echo "[TEST] Mihomo API warm-up polling remains quiet"
tmp_bin="$(mktemp -d)"
cat > "$tmp_bin/curl" <<'EOF'
#!/usr/bin/env bash
printf 'transient local API refusal\n' >&2
exit 7
EOF
chmod +x "$tmp_bin/curl"
health_output="$(
    (
        PATH="$tmp_bin:$PATH"
        export PATH
        # shellcheck source=/dev/null
        . "$ROOT/lib/common.sh"
        # shellcheck source=/dev/null
        . "$ROOT/components/mihomo.sh"
        # shellcheck source=/dev/null
        . "$ROOT/templates/mihomo_common.sh"
        ep_mihomo_api_healthy 60290 || true
        mihomo_api_healthy || true
    ) 2>&1
)"
if [ -n "$health_output" ]; then
    printf 'Expected quiet Mihomo health polling, got: %s\n' "$health_output" >&2
    exit 1
fi
rm -rf "$tmp_bin"

echo "[TEST] non-interactive bashrc is quiet"
tmp_home="$(mktemp -d)"
mkdir -p "$tmp_home/.config/envpilot"
output="$(
    HOME="$tmp_home" bash -c 'source "'"$ROOT/templates/bashrc"'"' 2>&1
)"
if [ -n "$output" ]; then
    echo "Expected no output from non-interactive bashrc, got:" >&2
    printf '%s\n' "$output" >&2
    exit 1
fi

echo "[TEST] non-interactive shell prepares a configured Mihomo proxy"
tmp_home="$(mktemp -d)"
tmp_bin="$(mktemp -d)"
tmp_root="/tmp/envpilot-codex-tmp-$$"
marker="$tmp_home/mihomo-started"
mkdir -p "$tmp_home/.config/mihomo" "$tmp_home/.config/envpilot" "$tmp_home/software/mihomo"
printf 'mixed-port: 43333\n' > "$tmp_home/.config/mihomo/config.yaml"
cat > "$tmp_home/.config/envpilot/shell.local" <<'EOF'
MIHOMO_PROXY_PORT=43333
MIHOMO_API_PORT=43334
BASHRC_PROXY_PRESTART_NONINTERACTIVE=1
EOF
cat > "$tmp_home/software/mihomo/start_mihomo.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$MIHOMO_PROXY_PORT" > "$ENVPILOT_TEST_MARKER"
EOF
cat > "$tmp_bin/ss" <<'EOF'
#!/usr/bin/env bash
if [ -f "$ENVPILOT_TEST_MARKER" ]; then
    printf 'LISTEN 0 128 127.0.0.1:%s 0.0.0.0:*\n' "$MIHOMO_PROXY_PORT"
fi
EOF
chmod +x "$tmp_home/software/mihomo/start_mihomo.sh" "$tmp_bin/ss"
configured_proxy="$(
    BASH_ENV=/dev/null bash --noprofile --norc -c '
        unset MIHOMO_PROXY_HOST MIHOMO_PROXY_PORT MIHOMO_API_PORT \
            BASHRC_PROXY_HOST BASHRC_PROXY_PORT BASHRC_PROXY_ENABLE_SOCKS \
            BASHRC_PROXY_PRESTART_NONINTERACTIVE BASHRC_USE_NODE_LOCAL_TMP \
            BASHRC_CODEX_TMP_ROOT BASHRC_LOCAL_FILE ENVPILOT_PROFILE_ACTIVE \
            ENVPILOT_LAST_MIHOMO_PROXY_HOST ENVPILOT_LAST_MIHOMO_PROXY_PORT \
            ENVPILOT_LAST_MIHOMO_API_PORT ENVPILOT_LAST_BASHRC_PROXY_ENABLE_SOCKS \
            ENVPILOT_LAST_BASHRC_PROXY_PRESTART_NONINTERACTIVE \
            ENVPILOT_LAST_BASHRC_USE_NODE_LOCAL_TMP ENVPILOT_LAST_BASHRC_CODEX_TMP_ROOT
        export HOME="$1"
        export PATH="$2"
        export ENVPILOT_TEST_MARKER="$3"
        export BASHRC_LOCAL_FILE="$4"
        export BASHRC_CODEX_TMP_ROOT="$5"
        export BASHRC_AUTO_START_MIHOMO=0 BASHRC_AUTO_ENABLE_PROXY=0
        export BASHRC_AUTO_LOAD_MODULES=0 BASHRC_AUTO_LOAD_SECRETS=0
        . "$4"
        source "$6"
        printf "%s|%s|%s|%s|%s|%s|%s" "$MIHOMO_PROXY_PORT" "$MIHOMO_API_PORT" "$http_proxy" "$https_proxy" "${all_proxy-unset}" "$TMPDIR" "$(cat "$ENVPILOT_TEST_MARKER")"
    ' bash "$tmp_home" "$tmp_bin:$PATH" "$marker" \
        "$tmp_home/.config/envpilot/shell.local" "$tmp_root" "$ROOT/templates/bashrc" 2>/dev/null
)"
case "$configured_proxy" in
    "43333|43334|http://127.0.0.1:43333|http://127.0.0.1:43333|unset|$tmp_root|43333") ;;
    *) echo "Unexpected non-interactive proxy environment: $configured_proxy" >&2; exit 1 ;;
esac

echo "[TEST] shell.local overrides prior envpilot-managed settings"
cat > "$tmp_home/.config/envpilot/shell.local" <<'EOF'
  export MIHOMO_PROXY_PORT="43336"
MIHOMO_API_PORT='43337'
BASHRC_PROXY_PRESTART_NONINTERACTIVE=0
MIHOMO_PROXY_PORT=$(invalid-command)
EOF
override_fixture="$tmp_home/override-fixture.sh"
cat > "$override_fixture" <<'EOF'
. "$ENVPILOT_FIXTURE_TEMPLATE"
EOF
updated_settings="$(
    env -i \
        HOME="$tmp_home" \
        PATH="$tmp_bin:$PATH" \
        BASHRC_LOCAL_FILE="$tmp_home/.config/envpilot/shell.local" \
        BASHRC_AUTO_START_MIHOMO=0 \
        BASHRC_AUTO_ENABLE_PROXY=0 \
        BASHRC_AUTO_LOAD_MODULES=0 \
        BASHRC_AUTO_LOAD_SECRETS=0 \
        BASHRC_CODEX_TMP_ROOT="/tmp/envpilot-override-codex-tmp-$$" \
        MIHOMO_PROXY_PORT=43333 \
        MIHOMO_API_PORT=43334 \
        ENVPILOT_PROFILE_ACTIVE=1 \
        ENVPILOT_LAST_MIHOMO_PROXY_HOST=127.0.0.1 \
        ENVPILOT_LAST_MIHOMO_PROXY_PORT=43333 \
        ENVPILOT_LAST_MIHOMO_API_PORT=43334 \
        ENVPILOT_LAST_BASHRC_PROXY_ENABLE_SOCKS=0 \
        ENVPILOT_LAST_BASHRC_PROXY_PRESTART_NONINTERACTIVE=1 \
        ENVPILOT_FIXTURE_TEMPLATE="$ROOT/templates/bashrc" \
        BASH_ENV=/dev/null \
        bash --noprofile --norc -c '
            . "$1"
            printf "%s|%s|%s" "$MIHOMO_PROXY_PORT" "$MIHOMO_API_PORT" "$BASHRC_PROXY_PRESTART_NONINTERACTIVE"
        ' bash "$override_fixture" 2>/dev/null
)"
if [ "$updated_settings" != "43336|43337|0" ]; then
    printf 'Unexpected shell.local override environment: %s\n' "$updated_settings" >&2
    exit 1
fi
rm -rf "$tmp_home" "$tmp_bin" "$tmp_root"

echo "[TEST] non-interactive proxy startup failure remains quiet and unset"
tmp_home="$(mktemp -d)"
tmp_bin="$(mktemp -d)"
mkdir -p "$tmp_home/.config/mihomo" "$tmp_home/software/mihomo"
printf 'mixed-port: 43335\n' > "$tmp_home/.config/mihomo/config.yaml"
cat > "$tmp_home/software/mihomo/start_mihomo.sh" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
cat > "$tmp_bin/ss" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$tmp_home/software/mihomo/start_mihomo.sh" "$tmp_bin/ss"
failed_noninteractive="$(
    HOME="$tmp_home" \
    PATH="$tmp_bin:$PATH" \
    BASHRC_AUTO_START_MIHOMO=0 \
    BASHRC_AUTO_ENABLE_PROXY=0 \
    BASHRC_AUTO_LOAD_MODULES=0 \
    BASHRC_AUTO_LOAD_SECRETS=0 \
    bash -c 'source "'"$ROOT/templates/bashrc"'"; printf "%s|%s" "${http_proxy-unset}" "${https_proxy-unset}"' 2>&1
)"
[ "$failed_noninteractive" = "unset|unset" ]
rm -rf "$tmp_home" "$tmp_bin"

echo "[TEST] proxy port detection accepts IPv6 wildcard"
tmp_home="$(mktemp -d)"
tmp_bin="$(mktemp -d)"
cat > "$tmp_bin/ss" <<'EOF'
#!/usr/bin/env bash
cat <<'OUT'
State      Recv-Q Send-Q     Local Address:Port                    Peer Address:Port
LISTEN     0      128                   :::42290                              :::*
OUT
EOF
chmod +x "$tmp_bin/ss"
awk 'BEGIN { skip = 0 } /^# No real TTY:/ { skip = 1; next } skip && /^fi$/ { skip = 0; next } !skip { print }' "$ROOT/templates/bashrc" > "$tmp_bin/bashrc-test"
chmod +x "$tmp_bin/bashrc-test"
proxy_check="$(
    HOME="$tmp_home" \
    PATH="$tmp_bin:$PATH" \
    BASHRC_AUTO_START_MIHOMO=0 \
    BASHRC_AUTO_ENABLE_PROXY=0 \
    BASHRC_AUTO_LOAD_MODULES=0 \
    BASHRC_AUTO_LOAD_SECRETS=0 \
    bash --noprofile --norc -ic '. "'"$tmp_bin/bashrc-test"'"; if proxy_port_is_listening; then printf yes; else printf no; fi' 2>/dev/null | tail -n 1
)"
if [ "$proxy_check" != "yes" ]; then
    echo "Expected proxy_port_is_listening to accept :::42290, got: $proxy_check" >&2
    exit 1
fi

echo "[TEST] proxy status uses TCP fallback when ss is silent"
tmp_home="$(mktemp -d)"
tmp_bin="$(mktemp -d)"
cat > "$tmp_bin/ss" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
cat > "$tmp_bin/nc" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$tmp_bin/ss" "$tmp_bin/nc"
awk 'BEGIN { skip = 0 } /^# No real TTY:/ { skip = 1; next } skip && /^fi$/ { skip = 0; next } !skip { print }' "$ROOT/templates/bashrc" > "$tmp_bin/bashrc-test"
chmod +x "$tmp_bin/bashrc-test"
status_check="$(
    HOME="$tmp_home" \
    PATH="$tmp_bin:$PATH" \
    BASHRC_AUTO_START_MIHOMO=0 \
    BASHRC_AUTO_ENABLE_PROXY=0 \
    BASHRC_AUTO_LOAD_MODULES=0 \
    BASHRC_AUTO_LOAD_SECRETS=0 \
    bash --noprofile --norc -ic '. "'"$tmp_bin/bashrc-test"'"; if proxy_port_is_listening; then printf yes; else printf no; fi' 2>/dev/null | tail -n 1
)"
[ "$status_check" = "yes" ]

echo "[TEST] proxy helpers preserve no_proxy and gate SOCKS"
tmp_home="$(mktemp -d)"
tmp_bin="$(mktemp -d)"
cat > "$tmp_bin/ss" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
cat > "$tmp_bin/nc" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$tmp_bin/ss" "$tmp_bin/nc"
awk 'BEGIN { skip = 0 } /^# No real TTY:/ { skip = 1; next } skip && /^fi$/ { skip = 0; next } !skip { print }' "$ROOT/templates/bashrc" > "$tmp_bin/bashrc-test"
chmod +x "$tmp_bin/bashrc-test"
proxy_values="$(
    HOME="$tmp_home" \
    PATH="$tmp_bin:$PATH" \
    no_proxy="login,compute,10.0.0.0/8" \
    BASHRC_AUTO_START_MIHOMO=0 \
    BASHRC_AUTO_ENABLE_PROXY=0 \
    BASHRC_AUTO_LOAD_MODULES=0 \
    BASHRC_AUTO_LOAD_SECRETS=0 \
    bash --noprofile --norc -ic '. "'"$tmp_bin/bashrc-test"'"; proxy_on; printf "%s|%s|%s" "$http_proxy" "${all_proxy-unset}" "$no_proxy"' 2>/dev/null | tail -n 1
)"
case "$proxy_values" in
    "http://127.0.0.1:42290|unset|"*"login"*"compute"*"10.0.0.0/8"*"localhost"*"127.0.0.1"*"::1"*) ;;
    *) echo "Unexpected proxy environment: $proxy_values" >&2; exit 1 ;;
esac
socks_value="$(
    HOME="$tmp_home" \
    PATH="$tmp_bin:$PATH" \
    BASHRC_PROXY_ENABLE_SOCKS=1 \
    BASHRC_AUTO_START_MIHOMO=0 \
    BASHRC_AUTO_ENABLE_PROXY=0 \
    BASHRC_AUTO_LOAD_MODULES=0 \
    BASHRC_AUTO_LOAD_SECRETS=0 \
    bash --noprofile --norc -ic '. "'"$tmp_bin/bashrc-test"'"; proxy_on; printf "%s" "$all_proxy"' 2>/dev/null | tail -n 1
)"
[ "$socks_value" = "socks5h://127.0.0.1:42290" ]
cat > "$tmp_bin/nc" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
failed_proxy="$(
    HOME="$tmp_home" \
    PATH="$tmp_bin:$PATH" \
    BASHRC_AUTO_START_MIHOMO=0 \
    BASHRC_AUTO_ENABLE_PROXY=0 \
    BASHRC_AUTO_LOAD_MODULES=0 \
    BASHRC_AUTO_LOAD_SECRETS=0 \
    bash --noprofile --norc -ic '. "'"$tmp_bin/bashrc-test"'"; unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY; proxy_on >/dev/null 2>&1 || true; printf "%s" "${http_proxy-unset}"' 2>/dev/null | tail -n 1
)"
[ "$failed_proxy" = "unset" ]
rm -rf "$tmp_home" "$tmp_bin"

echo "[TEST] mihomo dual-port switch updates config and shell.local"
tmp_home="$(mktemp -d)"
mkdir -p "$tmp_home/.config/mihomo" "$tmp_home/software/mihomo"
cat > "$tmp_home/.config/mihomo/config.yaml" <<'EOF'
allow-lan: true
mixed-port: 7890
bind-address: 0.0.0.0
external-controller: 127.0.0.1:9090
EOF
printf '%s\n' '#!/usr/bin/env sh' > "$tmp_home/software/mihomo/mihomo"
chmod +x "$tmp_home/software/mihomo/mihomo"
(
    HOME="$tmp_home"
    ENVPILOT_ROOT="$ROOT"
    # shellcheck source=/dev/null
    . "$ROOT/lib/common.sh"
    # shellcheck source=/dev/null
    . "$ROOT/lib/platform.sh"
    # shellcheck source=/dev/null
    . "$ROOT/lib/download.sh"
    # shellcheck source=/dev/null
    . "$ROOT/components/mihomo.sh"
    ep_init
    ep_platform_detect >/dev/null
    ep_stop_mihomo() { :; }
    ep_start_mihomo() { :; }
    ep_proxy_port_is_listening() { return 1; }
    ep_switch_mihomo_ports 7891 9091 >/tmp/envpilot-port-switch.out
)
grep -q 'mixed-port: 7891' "$tmp_home/.config/mihomo/config.yaml"
grep -q 'external-controller: 127.0.0.1:9091' "$tmp_home/.config/mihomo/config.yaml"
grep -q 'allow-lan: false' "$tmp_home/.config/mihomo/config.yaml"
grep -q 'bind-address: 127.0.0.1' "$tmp_home/.config/mihomo/config.yaml"
grep -q '^MIHOMO_PROXY_PORT=7891$' "$tmp_home/.config/envpilot/shell.local"
grep -q '^MIHOMO_API_PORT=9091$' "$tmp_home/.config/envpilot/shell.local"
rm -rf "$tmp_home"
echo "[TEST] node-local Mihomo runtime and subscription update"
if command -v pgrep >/dev/null 2>&1 && command -v pkill >/dev/null 2>&1 && [ -n "${USER:-}" ]; then
    tmp_home="$(mktemp -d)"
    tmp_bin="$(mktemp -d)"
    test_host="envpilot-test-$$"
    marker="$tmp_home/mihomo-started"
    runtime_dir="/tmp/${USER}_mihomo_${test_host}"
    mkdir -p "$tmp_home/software/mihomo" "$tmp_home/.config/mihomo"
    cat > "$tmp_home/software/mihomo/mihomo" <<'EOF'
#!/usr/bin/env bash
: > "$MIHOMO_TEST_MARKER"
trap 'rm -f "$MIHOMO_TEST_MARKER"' EXIT
trap 'rm -f "$MIHOMO_TEST_MARKER"; exit 0' INT TERM
while :; do sleep 1; done
EOF
    chmod +x "$tmp_home/software/mihomo/mihomo"
    cat > "$tmp_home/.config/mihomo/config.yaml" <<'EOF'
mixed-port: 7890
external-controller: 127.0.0.1:9090
allow-lan: true
bind-address: 0.0.0.0
EOF
    printf 'geo\n' > "$tmp_home/.config/mihomo/geoip.metadb"
    cat > "$tmp_bin/ss" <<'EOF'
#!/usr/bin/env bash
if [ -f "$MIHOMO_TEST_MARKER" ]; then
    printf 'LISTEN 0 128 127.0.0.1:42290 0.0.0.0:*\n'
fi
EOF
    cat > "$tmp_bin/curl" <<'EOF'
#!/usr/bin/env bash
[ -f "$MIHOMO_TEST_MARKER" ]
EOF
    chmod +x "$tmp_bin/ss" "$tmp_bin/curl"
    HOME="$tmp_home" HOSTNAME="$test_host" PATH="$tmp_bin:$PATH" MIHOMO_TEST_MARKER="$marker"         MIHOMO_PROXY_PORT=42290 MIHOMO_API_PORT=60290         bash "$ROOT/templates/start_mihomo.sh" >/tmp/envpilot-mihomo-start.out
    test -x "$runtime_dir/mihomo"
    test -f "$runtime_dir/geoip.metadb"
    grep -q '^mixed-port: 42290$' "$runtime_dir/config.yaml"
    grep -q '^external-controller: 127.0.0.1:60290$' "$runtime_dir/config.yaml"
    HOME="$tmp_home" HOSTNAME="$test_host" PATH="$tmp_bin:$PATH" MIHOMO_TEST_MARKER="$marker"         MIHOMO_PROXY_PORT=42290 MIHOMO_API_PORT=60290         bash "$ROOT/templates/status_mihomo.sh" >/tmp/envpilot-mihomo-status.out
    grep -q 'API: OK' /tmp/envpilot-mihomo-status.out
    HOME="$tmp_home" HOSTNAME="$test_host" PATH="$tmp_bin:$PATH" MIHOMO_TEST_MARKER="$marker"         MIHOMO_PROXY_PORT=42290 MIHOMO_API_PORT=60290         bash "$ROOT/templates/stop_mihomo.sh" >/tmp/envpilot-mihomo-stop.out
    ! pgrep -u "$USER" -f "$runtime_dir/mihomo" >/dev/null 2>&1

    cat > "$tmp_bin/curl" <<'EOF'
#!/usr/bin/env bash
destination=""
while [ "$#" -gt 0 ]; do
    if [ "$1" = "-o" ]; then
        destination="$2"
        shift 2
    else
        shift
    fi
done
[ -n "$destination" ] || exit 1
printf 'proxies: []\nrules: []\n' > "$destination"
EOF
    chmod +x "$tmp_bin/curl"
    HOME="$tmp_home" HOSTNAME="$test_host" PATH="$tmp_bin:$PATH"         MIHOMO_PROXY_PORT=42291 MIHOMO_API_PORT=60291         bash "$ROOT/templates/update_mihomo_subscription.sh" "https://example.invalid/clash-meta"         >/tmp/envpilot-mihomo-subscription.out
    grep -q '^mixed-port: 42291$' "$tmp_home/.config/mihomo/config.yaml"
    grep -q '^external-controller: 127.0.0.1:60291$' "$tmp_home/.config/mihomo/config.yaml"
    rm -rf "$runtime_dir" "$tmp_home" "$tmp_bin"
else
    echo "[TEST] skip node-local runtime fixture: pgrep/pkill unavailable"
fi

echo "[TEST] architecture-aware sparse clone"
fixture_repo="$(mktemp -d)"
clone_parent="$(mktemp -d)"
mkdir -p "$fixture_repo/downloads"
printf 'fixture\n' > "$fixture_repo/README.md"
printf 'linux\n' > "$fixture_repo/downloads/mihomo-linux-amd64-compatible-vTEST.gz"
printf 'windows\n' > "$fixture_repo/downloads/mihomo-windows-amd64-compatible-vTEST.zip"
printf 'country\n' > "$fixture_repo/downloads/country.mmdb"
printf 'geoip\n' > "$fixture_repo/downloads/geoip.metadb"
: > "$fixture_repo/downloads/.gitkeep"
git -C "$fixture_repo" init -q
git -C "$fixture_repo" branch -M main
git -C "$fixture_repo" config user.name envpilot-test
git -C "$fixture_repo" config user.email envpilot-test@example.invalid
git -C "$fixture_repo" config uploadpack.allowFilter true
git -C "$fixture_repo" config uploadpack.allowAnySHA1InWant true
git -C "$fixture_repo" add .
git -C "$fixture_repo" commit -qm fixture
if ! ENVPILOT_REPO_URL="file://$fixture_repo" bash "$ROOT/bootstrap.sh" "$clone_parent/envpilot" >/tmp/envpilot-bootstrap.out 2>&1; then
    cat /tmp/envpilot-bootstrap.out >&2
    exit 1
fi
case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*)
        compgen -G "$clone_parent/envpilot/downloads/mihomo-windows-amd64-compatible-*.zip" >/dev/null
        ! compgen -G "$clone_parent/envpilot/downloads/mihomo-linux-amd64-compatible-*.gz" >/dev/null
        ;;
    Linux)
        compgen -G "$clone_parent/envpilot/downloads/mihomo-linux-amd64-compatible-*.gz" >/dev/null
        ! compgen -G "$clone_parent/envpilot/downloads/mihomo-windows-amd64-compatible-*.zip" >/dev/null
        ;;
    Darwin)
        ! compgen -G "$clone_parent/envpilot/downloads/mihomo-linux-amd64-compatible-*.gz" >/dev/null
        ! compgen -G "$clone_parent/envpilot/downloads/mihomo-windows-amd64-compatible-*.zip" >/dev/null
        ;;
esac
test -f "$clone_parent/envpilot/downloads/country.mmdb"
test -f "$clone_parent/envpilot/downloads/geoip.metadb"
rm -rf "$clone_parent" "$fixture_repo"

echo "[TEST] doctor baseline restore"
tmp_home="$(mktemp -d)"
mkdir -p "$tmp_home/.config/envpilot" "$tmp_home/.config/mihomo"
cat > "$tmp_home/.bashrc" <<'EOF'
export PATH="$HOME/bin:$PATH"
EOF
cat > "$tmp_home/.condarc" <<'EOF'
channels:
  - defaults
EOF
cat > "$tmp_home/.config/mihomo/config.yaml" <<'EOF'
mixed-port: 7890
EOF
cat > "$tmp_home/.config/envpilot/shell.local" <<'EOF'
BASHRC_UMASK=027
EOF
mkdir -p "$tmp_home/software/mihomo"
printf '%s\n' keep > "$tmp_home/software/mihomo/keep.txt"
(
    HOME="$tmp_home"
    ENVPILOT_ROOT="$ROOT"
    # shellcheck source=/dev/null
    . "$ROOT/lib/common.sh"
    # shellcheck source=/dev/null
    . "$ROOT/lib/platform.sh"
    # shellcheck source=/dev/null
    . "$ROOT/lib/shell.sh"
    # shellcheck source=/dev/null
    . "$ROOT/lib/baseline.sh"
    # shellcheck source=/dev/null
    . "$ROOT/components/mihomo.sh"
    EP_PREFIX="$tmp_home/software"
    EP_OS="linux"
    EP_ARCH="amd64"
    EP_LIBC="glibc"
    EP_SHELL_NAME="bash"
    EP_CONFIG_DIR="$tmp_home/.config/envpilot"
    EP_BASELINE_DIR="$tmp_home/.config/envpilot/baseline"
    EP_BASELINE_FILE="$tmp_home/.config/envpilot/baseline/baseline.tsv"
    ep_capture_doctor_baseline >/dev/null
)
printf 'changed\n' > "$tmp_home/.bashrc"
rm -f "$tmp_home/.condarc"
printf 'changed\n' > "$tmp_home/.config/mihomo/config.yaml"
printf '%s\n' '#!/usr/bin/env sh' > "$tmp_home/software/mihomo/mihomo"
chmod +x "$tmp_home/software/mihomo/mihomo"
printf 'changed\n' > "$tmp_home/.config/envpilot/shell.local"
(
    HOME="$tmp_home"
    ENVPILOT_ROOT="$ROOT"
    # shellcheck source=/dev/null
    . "$ROOT/lib/common.sh"
    # shellcheck source=/dev/null
    . "$ROOT/lib/platform.sh"
    # shellcheck source=/dev/null
    . "$ROOT/lib/shell.sh"
    # shellcheck source=/dev/null
    . "$ROOT/lib/baseline.sh"
    # shellcheck source=/dev/null
    . "$ROOT/components/mihomo.sh"
    EP_PREFIX="$tmp_home/software"
    EP_OS="linux"
    EP_ARCH="amd64"
    EP_LIBC="glibc"
    EP_SHELL_NAME="bash"
    EP_CONFIG_DIR="$tmp_home/.config/envpilot"
    EP_BASELINE_DIR="$tmp_home/.config/envpilot/baseline"
    EP_BASELINE_FILE="$tmp_home/.config/envpilot/baseline/baseline.tsv"
    ep_restore_doctor_baseline >/tmp/envpilot-restore.out 2>&1
)
grep -q 'export PATH' "$tmp_home/.bashrc"
grep -q 'channels:' "$tmp_home/.condarc"
grep -q 'mixed-port: 7890' "$tmp_home/.config/mihomo/config.yaml"
test ! -e "$tmp_home/software/mihomo/mihomo"
grep -q 'keep' "$tmp_home/software/mihomo/keep.txt"
grep -q 'BASHRC_UMASK=027' "$tmp_home/.config/envpilot/shell.local"
rm -rf "$tmp_home"
echo "[TEST] doctor works with isolated HOME"
HOME="$tmp_home" bash "$ROOT/envpilot.sh" doctor >/tmp/envpilot-doctor.out 2>&1
grep -q 'envpilot doctor' /tmp/envpilot-doctor.out

echo "[TEST] manifest prerelease policy is documented"
grep -Rqi 'alpha.*beta.*rc\|alpha, beta, rc' "$ROOT/manifests"

echo "[TEST] codex config template uses env_key"
grep -q 'env_key = "OPENAI_API_KEY"' "$ROOT/components/codex.sh"
! grep -q 'requires_openai_auth = true' "$ROOT/components/codex.sh"

echo "[TEST] protected Codex secret file lifecycle"
tmp_secrets_home="$(mktemp -d)"
(
    HOME="$tmp_secrets_home"
    ENVPILOT_ROOT="$ROOT"
    . "$ROOT/lib/common.sh"
    . "$ROOT/lib/shell.sh"
    . "$ROOT/components/codex.sh"
    EP_ROLLBACK_LOG="$tmp_secrets_home/rollback.log"
    ep_ensure_secrets_file >/dev/null
    secret_file="$HOME/.config/secrets/api.env"
    test -f "$secret_file"
    case "$(uname -s)" in
        MINGW*|MSYS*|CYGWIN*) ;;
        *)
            mode="$(stat -c '%a' "$secret_file" 2>/dev/null || stat -f '%Lp' "$secret_file")"
            case "$mode" in 600|400) ;; *) exit 1 ;; esac
            ;;
    esac
    printf 'export NCBI_API_KEY=preserved\n' > "$secret_file"
    chmod 600 "$secret_file"
    ep_codex_persist_api_key "test-key-'quoted"
)
grep -q '^export NCBI_API_KEY=preserved$' "$tmp_secrets_home/.config/secrets/api.env"
grep -q '^export OPENAI_API_KEY=' "$tmp_secrets_home/.config/secrets/api.env"
bash_bin="$(command -v bash)"
stored_key="$(env -i HOME="$tmp_secrets_home" PATH=/usr/bin:/bin "$bash_bin" --noprofile --norc -c '. "$HOME/.config/secrets/api.env"; printf "%s" "$OPENAI_API_KEY"')"
[ "$stored_key" = "test-key-'quoted" ]
rm -rf "$tmp_secrets_home"

echo "[TEST] existing Codex auth is preserved"
tmp_existing_auth_home="$(mktemp -d)"
existing_auth_output="$tmp_existing_auth_home/auth-output"
(
    set -euo pipefail
    export HOME="$tmp_existing_auth_home"
    export ENVPILOT_ROOT="$ROOT"
    export OPENAI_API_KEY='replacement-key-must-not-be-used'
    . "$ROOT/lib/common.sh"
    . "$ROOT/lib/shell.sh"
    . "$ROOT/components/codex.sh"
    EP_ROLLBACK_LOG="$HOME/rollback.log"
    mkdir -p "$HOME/.codex"
    printf '{\n  "OPENAI_API_KEY": "existing-key"\n}\n' > "$HOME/.codex/auth.json"
    chmod 600 "$HOME/.codex/auth.json"
    ep_confirm() { printf 'unexpected auth prompt\n' >&2; return 1; }
    ep_codex_configure_auth
    cat "$HOME/.codex/auth.json" > "$existing_auth_output"
)
grep -q 'existing-key' "$existing_auth_output"
! grep -q 'replacement-key-must-not-be-used' "$existing_auth_output"
! find "$tmp_existing_auth_home/.codex" -maxdepth 1 -name 'auth.json.bak.*' -print -quit | grep -q .
rm -rf "$tmp_existing_auth_home"

echo "[TEST] new Codex auth imports current environment key"
tmp_new_auth_home="$(mktemp -d)"
(
    set -euo pipefail
    export HOME="$tmp_new_auth_home"
    export ENVPILOT_ROOT="$ROOT"
    export OPENAI_API_KEY='new-environment-key'
    . "$ROOT/lib/common.sh"
    . "$ROOT/lib/shell.sh"
    . "$ROOT/components/codex.sh"
    EP_ROLLBACK_LOG="$HOME/rollback.log"
    ep_confirm() { return 0; }
    ep_codex_configure_auth
)
grep -q 'new-environment-key' "$tmp_new_auth_home/.codex/auth.json"
rm -rf "$tmp_new_auth_home"

echo "[TEST] apply-shell creates the protected secrets scaffold"
tmp_apply_home="$(mktemp -d)"
(
    HOME="$tmp_apply_home"
    ENVPILOT_ROOT="$ROOT"
    . "$ROOT/lib/common.sh"
    . "$ROOT/lib/shell.sh"
    EP_CONFIG_DIR="$tmp_apply_home/.config/envpilot"
    EP_SHELL_NAME=bash
    ep_require_unix_runtime() { return 0; }
    ep_confirm() { return 0; }
    ep_apply_shell_profile >/dev/null
)
test -f "$tmp_apply_home/.config/secrets/api.env"
rm -rf "$tmp_apply_home"

echo "[TEST] mamba uses clean mirror-only Conda configuration"
grep -q '^default_channels: \[\]$' "$ROOT/templates/condarc"
! grep -q -- '-c conda-forge' "$ROOT/components/mamba.sh" "$ROOT/manifests/mamba.json" "$ROOT/envpilot.ps1"
grep -q 'unset LD_LIBRARY_PATH PYTHONHOME PYTHONPATH' "$ROOT/components/conda.sh"

tmp_mamba="$(mktemp -d)"
mkdir -p "$tmp_mamba/software/miniconda3/bin"
cat > "$tmp_mamba/software/miniconda3/.condarc" <<'EOF'
channels:
  - defaults
EOF
cat > "$tmp_mamba/software/miniconda3/bin/conda" <<'EOF'
#!/usr/bin/env bash
{
    printf 'LD_LIBRARY_PATH=%s\n' "${LD_LIBRARY_PATH-unset}"
    printf 'PYTHONHOME=%s\n' "${PYTHONHOME-unset}"
    printf 'PYTHONPATH=%s\n' "${PYTHONPATH-unset}"
    printf 'CONDARC=%s\n' "${CONDARC-unset}"
    printf 'args=%s\n' "$*"
} > "$HOME/conda-invocation.txt"
cat > "$(dirname "$0")/mamba" <<'MAMBA'
#!/usr/bin/env bash
printf '2.8.1\n'
MAMBA
chmod +x "$(dirname "$0")/mamba"
exit 39
EOF
chmod +x "$tmp_mamba/software/miniconda3/bin/conda"
(
    HOME="$tmp_mamba"
    PATH="/usr/bin:/bin"
    LD_LIBRARY_PATH="/cluster/lib"
    PYTHONHOME="/cluster/python"
    PYTHONPATH="/cluster/site-packages"
    ENVPILOT_ROOT="$ROOT"
    . "$ROOT/lib/common.sh"
    . "$ROOT/lib/platform.sh"
    . "$ROOT/components/conda.sh"
    . "$ROOT/components/mamba.sh"
    ep_command_exists()
    {
        case "$1" in
            conda|mamba) return 1 ;;
            *) command -v "$1" >/dev/null 2>&1 ;;
        esac
    }
    EP_PREFIX="$tmp_mamba/software"
    EP_OS="linux"
    EP_ARCH="amd64"
    EP_LIBC="glibc"
    EP_GLIBC_VERSION="2.17"
    EP_SHELL_NAME="bash"
    EP_IS_ROOT="false"
    EP_ASSUME_YES=1
    ep_init
    ep_report_start install mamba
    ep_install_mamba >"$tmp_mamba/mamba-install.out" 2>&1
    ep_report_finish
)
grep -q '^LD_LIBRARY_PATH=unset$' "$tmp_mamba/conda-invocation.txt"
grep -q '^PYTHONHOME=unset$' "$tmp_mamba/conda-invocation.txt"
grep -q '^PYTHONPATH=unset$' "$tmp_mamba/conda-invocation.txt"
grep -q "^CONDARC=$tmp_mamba/.condarc$" "$tmp_mamba/conda-invocation.txt"
grep -q '^args=install -n base -y mamba$' "$tmp_mamba/conda-invocation.txt"
grep -q 'installed mamba executable passed verification' "$tmp_mamba/mamba-install.out"
grep -q '^mamba=done:' "$tmp_mamba/.config/envpilot/state"
cmp -s "$ROOT/templates/condarc" "$tmp_mamba/.condarc"
test ! -e "$tmp_mamba/software/miniconda3/.condarc"
rm -rf "$tmp_mamba"

echo "[TEST] tmux manifest target and managed Mihomo detection"
(
    HOME="$(mktemp -d)"
    USER="envpilot-test"
    HOSTNAME="envpilot-host"
    ENVPILOT_ROOT="$ROOT"
    . "$ROOT/lib/common.sh"
    . "$ROOT/lib/platform.sh"
    . "$ROOT/lib/manifest.sh"
    . "$ROOT/components/mihomo.sh"
    . "$ROOT/components/tmux.sh"
    [ "$(ep_tmux_target_version)" = "3.7b" ]
    ep_version_at_least 3.7b 3.5a
    ep_version_at_least 3.10 3.7b
    ! ep_version_at_least 3.7 3.7b
    ! ep_version_at_least 3.5a 3.7b
    managed="$HOME/software/mihomo/mihomo"
    runtime="$(ep_mihomo_runtime_bin)"
    ep_mihomo_processes_are_managed "987654321 $managed -d $HOME/.config/mihomo"
    ep_mihomo_processes_are_managed "987654322 $runtime -d $(ep_mihomo_runtime_dir)"
    ! ep_mihomo_processes_are_managed "987654323 /opt/external/mihomo -d /opt/external/config"
)

echo "[TEST] version"
version="$(tr -d '\r\n' < "$ROOT/VERSION")"
printf '%s\n' "$version" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'
grep -q "^## $version - " "$ROOT/CHANGELOG.md"
grep -q 'EP_GIT_MIN_VERSION' "$ROOT/components/git.sh"
grep -q 'EP_PYTHON_MIN_VERSION' "$ROOT/components/python.sh"
grep -q 'No real TTY' "$ROOT/templates/bashrc"
! grep -q 'MIHMOMO' "$ROOT/templates/bashrc" "$ROOT/templates/zshrc"
grep -q 'ENVPILOT_LAST_MIHOMO_PROXY_PORT' "$ROOT/templates/bashrc" "$ROOT/templates/zshrc"
grep -q 'path_prepend "\$HOME/software/git/current/bin"' "$ROOT/templates/bashrc"
grep -q 'auth.json' "$ROOT/components/codex.sh"
"$PYTHON_BIN" -m json.tool "$ROOT/manifests/git.json" >/dev/null
"$PYTHON_BIN" -m json.tool "$ROOT/manifests/python.json" >/dev/null

echo "[TEST] repository license and mirror helpers"
grep -q '^MIT License$' "$ROOT/LICENSE"
grep -q 'git -C "$ROOT" push origin main --follow-tags' "$ROOT/scripts/push-mirrors.sh"
grep -q 'git -C "$ROOT" push gitee main --follow-tags' "$ROOT/scripts/push-mirrors.sh"

echo "[TEST] secret patterns are ignored"
grep -q '^api.env$' "$ROOT/.gitignore"
grep -q 'country.mmdb' "$ROOT/scripts/update-mihomo-cache.py"
grep -q 'geoip.metadb' "$ROOT/scripts/update-mihomo-cache.py"
grep -q 'country.mmdb' "$ROOT/scripts/collect-assets.sh"
grep -q 'geoip.metadb' "$ROOT/scripts/collect-assets.ps1"
grep -q 'function mihomo' "$ROOT/templates/Microsoft.PowerShell_profile.ps1"
grep -q 'Set-MihomoPort' "$ROOT/templates/Microsoft.PowerShell_profile.ps1"
grep -q 'Restore-Baseline' "$ROOT/envpilot.ps1"
grep -q '^config.yaml$' "$ROOT/.gitignore"

rm -rf "$tmp_home"
echo "[TEST] ok"
