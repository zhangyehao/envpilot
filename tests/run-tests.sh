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
for file in "$ROOT"/lib/*.sh "$ROOT"/components/*.sh "$ROOT"/scripts/*.sh "$ROOT"/templates/bashrc "$ROOT"/templates/zshrc "$ROOT"/templates/start_mihomo.sh; do
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
grep -q 'EP_MIHOMO_ACTION' "$ROOT/lib/common.sh"
grep -q 'ep_mihomo_cli' "$ROOT/components/mihomo.sh"
grep -q 'ep_find_cached_asset' "$ROOT/lib/download.sh"
grep -q 'ep_capture_doctor_baseline' "$ROOT/lib/baseline.sh"
grep -q 'ep_restore_doctor_baseline' "$ROOT/lib/baseline.sh"
grep -q 'mihomo-bin' "$ROOT/lib/baseline.sh"
grep -q 'Using bundled downloads/ mihomo asset before network' "$ROOT/components/mihomo.sh"
grep -q 'Using bundled downloads/ mihomo data asset before network' "$ROOT/components/mihomo.sh"
grep -q 'meta-rules-dat' "$ROOT/components/mihomo.sh"
grep -q 'Find-CachedAsset' "$ROOT/envpilot.ps1"
grep -q 'Install-MihomoDataAssets' "$ROOT/envpilot.ps1"
grep -q 'EP_LEGACY_MINICONDA_VERSION' "$ROOT/components/conda.sh"
grep -q 'ep_mihomo_offline_pattern' "$ROOT/components/mihomo.sh"
grep -q 'mihomo_wait_for_port' "$ROOT/templates/bashrc"
grep -q 'mihomo()' "$ROOT/templates/bashrc"
grep -q 'envpilot_restore()' "$ROOT/templates/bashrc"
grep -q 'mihomo()' "$ROOT/templates/zshrc"
grep -q 'envpilot_restore()' "$ROOT/templates/zshrc"
grep -q 'did not open proxy port' "$ROOT/templates/start_mihomo.sh"
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
    bash --noprofile --norc -ic '. "'"$ROOT/templates/bashrc"'"; proxy_status' 2>/dev/null
)"
printf '%s\n' "$status_check" | grep -q 'reachable via TCP connect'
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
grep -q '^0\.1\.7$' "$ROOT/VERSION"

echo "[TEST] secret patterns are ignored"
grep -q '^api.env$' "$ROOT/.gitignore"
grep -q 'country.mmdb' "$ROOT/scripts/update-mihomo-cache.py"
grep -q 'geoip.metadb' "$ROOT/scripts/update-mihomo-cache.py"
grep -q 'country.mmdb' "$ROOT/scripts/collect-assets.sh"
grep -q 'geoip.metadb' "$ROOT/scripts/collect-assets.ps1"
grep -q 'function mihomo' "$ROOT/templates/Microsoft.PowerShell_profile.ps1"
grep -q 'Restore-Baseline' "$ROOT/envpilot.ps1"
grep -q '^config.yaml$' "$ROOT/.gitignore"

rm -rf "$tmp_home"
echo "[TEST] ok"
