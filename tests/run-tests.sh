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
grep -q 'actions/checkout@v7' "$ROOT/.github/workflows/update-manifests.yml"
grep -q 'scripts/update-manifests.py --check' "$ROOT/.github/workflows/update-manifests.yml"
grep -q 'peter-evans/create-pull-request@v8' "$ROOT/.github/workflows/update-manifests.yml"
grep -q 'scripts/update-mihomo-cache.py --check' "$ROOT/.github/workflows/update-mihomo-cache.yml"
grep -q 'scripts/update-mihomo-cache.py' "$ROOT/.github/workflows/update-mihomo-cache.yml"
grep -q 'country.mmdb' "$ROOT/.github/workflows/update-mihomo-cache.yml"
grep -q 'peter-evans/create-pull-request@v8' "$ROOT/.github/workflows/update-mihomo-cache.yml"

echo "[TEST] install order and resolver policy"
grep -q 'for component in mihomo conda mamba codex github tmux' "$ROOT/envpilot.sh"
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
grep -q 'MIHOMO_RUNTIME_DIR="/tmp/' "$ROOT/templates/mihomo_common.sh"
grep -q 'API .* was not ready' "$ROOT/templates/start_mihomo.sh"
grep -q 'update-subscription' "$ROOT/envpilot.sh"
grep -q 'partial clone' "$ROOT/README.md"
grep -q 'sparse-checkout' "$ROOT/bootstrap.sh"
grep -q 'Source URL:' "$ROOT/lib/download.sh"
! grep -qi 'miniforge' "$ROOT/components/conda.sh" "$ROOT/manifests/conda.json" "$ROOT/templates/bashrc" "$ROOT/templates/zshrc" "$ROOT/scripts/collect-assets.sh" "$ROOT/scripts/collect-assets.ps1"

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

echo "[TEST] shell.local migration skips multiline conda init"
tmp_home="$(mktemp -d)"
mkdir -p "$tmp_home/.config/envpilot"
cat > "$tmp_home/.bashrc" <<'EOF'
export PATH="$HOME/bin:$PATH"
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
if grep -q 'conda\.sh' "$tmp_home/.config/envpilot/shell.local"; then
    echo "shell.local migration must not copy conda.sh fragments" >&2
    cat "$tmp_home/.config/envpilot/shell.local" >&2
    exit 1
fi
bash --noprofile --norc -c '. "'"$tmp_home/.config/envpilot/shell.local"'"'
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

echo "[TEST] proxy port detection accepts IPv6 wildcard"
tmp_home="$(mktemp -d)"
tmp_bin="$(mktemp -d)"
cat > "$tmp_bin/ss" <<'EOF'
#!/usr/bin/env bash
cat <<'OUT'
State      Recv-Q Send-Q     Local Address:Port                    Peer Address:Port
LISTEN     0      128                   :::7890                              :::*
OUT
EOF
chmod +x "$tmp_bin/ss"
proxy_check="$(
    HOME="$tmp_home" \
    PATH="$tmp_bin:$PATH" \
    BASHRC_AUTO_START_MIHOMO=0 \
    BASHRC_AUTO_ENABLE_PROXY=0 \
    BASHRC_AUTO_LOAD_MODULES=0 \
    BASHRC_AUTO_LOAD_SECRETS=0 \
    bash --noprofile --norc -ic '. "'"$ROOT/templates/bashrc"'"; if proxy_port_is_listening; then printf yes; else printf no; fi' 2>/dev/null | tail -n 1
)"
if [ "$proxy_check" != "yes" ]; then
    echo "Expected proxy_port_is_listening to accept :::7890, got: $proxy_check" >&2
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
status_check="$(
    HOME="$tmp_home" \
    PATH="$tmp_bin:$PATH" \
    BASHRC_AUTO_START_MIHOMO=0 \
    BASHRC_AUTO_ENABLE_PROXY=0 \
    BASHRC_AUTO_LOAD_MODULES=0 \
    BASHRC_AUTO_LOAD_SECRETS=0 \
    bash --noprofile --norc -ic '. "'"$ROOT/templates/bashrc"'"; if proxy_port_is_listening; then printf yes; else printf no; fi' 2>/dev/null | tail -n 1
)"
[ "$status_check" = "yes" ]

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

echo "[TEST] version"
grep -q '^0\.1\.10$' "$ROOT/VERSION"

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
