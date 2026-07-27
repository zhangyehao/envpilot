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
grep -q 'scripts/update-manifests.py --check' "$ROOT/.github/workflows/update-manifests.yml"
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

echo "[TEST] doctor works with isolated HOME"
HOME="$tmp_home" bash "$ROOT/envpilot.sh" doctor >/tmp/envpilot-doctor.out 2>&1
grep -q 'envpilot doctor' /tmp/envpilot-doctor.out

echo "[TEST] manifest prerelease policy is documented"
grep -Rqi 'alpha.*beta.*rc\|alpha, beta, rc' "$ROOT/manifests"

echo "[TEST] codex config template uses env_key"
grep -q 'env_key = "OPENAI_API_KEY"' "$ROOT/components/codex.sh"
! grep -q 'requires_openai_auth = true' "$ROOT/components/codex.sh"

echo "[TEST] version"
grep -q '^0\.1\.1$' "$ROOT/VERSION"

echo "[TEST] secret patterns are ignored"
grep -q '^api.env$' "$ROOT/.gitignore"
grep -q '^config.yaml$' "$ROOT/.gitignore"

rm -rf "$tmp_home"
echo "[TEST] ok"


