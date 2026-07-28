#!/usr/bin/env bash
set -euo pipefail

if [ -d /usr/bin ]; then
    PATH="/usr/bin:/bin:$PATH"
fi

ROOT="$(cd "${BASH_SOURCE[0]%/*}/.." && pwd)"

echo "[TEST] bash syntax"
bash -n "$ROOT/envpilot.sh"
for file in "$ROOT"/lib/*.sh "$ROOT"/components/*.sh "$ROOT"/scripts/*.sh "$ROOT"/templates/bashrc "$ROOT"/templates/zshrc "$ROOT"/templates/start_mihomo.sh; do
    bash -n "$file"
done
python -c 'import pathlib, sys; path = pathlib.Path(sys.argv[1]); compile(path.read_text(encoding="utf-8"), str(path), "exec")' "$ROOT/scripts/update-manifests.py"
python "$ROOT/scripts/update-manifests.py" --check >/tmp/envpilot-manifest-check.out

echo "[TEST] workflow semantics"
grep -q 'git archive' "$ROOT/.github/workflows/release-assets.yml"
! grep -q 'files: downloads/\*' "$ROOT/.github/workflows/release-assets.yml"
grep -q 'refs/tags/v' "$ROOT/.github/workflows/release-assets.yml"
grep -q 'scripts/update-manifests.py --check' "$ROOT/.github/workflows/update-manifests.yml"

echo "[TEST] install order and resolver policy"
grep -q 'for component in mihomo conda mamba codex github tmux' "$ROOT/envpilot.sh"
grep -q 'EP_LEGACY_MINICONDA_VERSION' "$ROOT/components/conda.sh"
grep -q 'ep_mihomo_offline_pattern' "$ROOT/components/mihomo.sh"
grep -q 'Source URL:' "$ROOT/lib/download.sh"
! grep -qi 'miniforge' "$ROOT/components/conda.sh" "$ROOT/manifests/conda.json" "$ROOT/templates/bashrc" "$ROOT/templates/zshrc" "$ROOT/scripts/collect-assets.sh" "$ROOT/scripts/collect-assets.ps1"

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
        *Miniconda3-py39_4.12.0-Linux-x86_64.sh) ;;
        *) echo "Expected archived Miniconda for glibc 2.17, got: $legacy_url" >&2; exit 1 ;;
    esac
    EP_CONDA_DISTRIBUTION="anaconda"
    anaconda_url="$(ep_conda_installer_url)"
    case "$anaconda_url" in
        *Anaconda3-2025.06-0-Linux-x86_64.sh) ;;
        *) echo "Expected Anaconda installer URL, got: $anaconda_url" >&2; exit 1 ;;
    esac
)

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
    bash --noprofile --norc -ic '. "'"$ROOT/templates/bashrc"'"; if proxy_port_is_listening; then printf yes; else printf no; fi' 2>/dev/null
)"
if [ "$proxy_check" != "yes" ]; then
    echo "Expected proxy_port_is_listening to accept :::7890, got: $proxy_check" >&2
    exit 1
fi

echo "[TEST] doctor works with isolated HOME"
HOME="$tmp_home" bash "$ROOT/envpilot.sh" doctor >/tmp/envpilot-doctor.out 2>&1
grep -q 'envpilot doctor' /tmp/envpilot-doctor.out

echo "[TEST] manifest prerelease policy is documented"
grep -Rqi 'alpha.*beta.*rc\|alpha, beta, rc' "$ROOT/manifests"

echo "[TEST] codex config template uses env_key"
grep -q 'env_key = "OPENAI_API_KEY"' "$ROOT/components/codex.sh"
! grep -q 'requires_openai_auth = true' "$ROOT/components/codex.sh"

echo "[TEST] version"
grep -q '^0\.1\.4$' "$ROOT/VERSION"

echo "[TEST] secret patterns are ignored"
grep -q '^api.env$' "$ROOT/.gitignore"
grep -q '^config.yaml$' "$ROOT/.gitignore"

rm -rf "$tmp_home"
echo "[TEST] ok"
