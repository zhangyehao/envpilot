#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT
mkdir -p "$fixture/repo" "$fixture/home" "$fixture/config" "$fixture/caller"
cp "$ROOT/envpilot.sh" "$ROOT/VERSION" "$fixture/repo/"
cp -R "$ROOT/lib" "$ROOT/components" "$fixture/repo/"
export HOME="$fixture/home" ENVPILOT_CONFIG_DIR="$fixture/config"
export ENVPILOT_CORE="$fixture/missing-core" ENVPILOT_MODE=offline ENVPILOT_LANG=en
printf 'invalid: [\n' > "$ENVPILOT_CONFIG_DIR/config.yaml"
version="$(tr -d '\r\n' < "$ROOT/VERSION")"
cd "$fixture/caller"
for option in version -v -V -version --version; do
    test "$(bash "$fixture/repo/envpilot.sh" "$option")" = "envpilot $version"
done
for option in help -h -H -help --help; do
    bash "$fixture/repo/envpilot.sh" "$option" | grep -F 'envpilot version' >/dev/null
done
test "$(bash "$fixture/repo/envpilot.sh" install --version)" = "envpilot $version"
bash "$fixture/repo/envpilot.sh" install --help | grep -F 'envpilot version' >/dev/null
test -z "$(find "$HOME" -mindepth 1 -print)"
test "$(find "$ENVPILOT_CONFIG_DIR" -mindepth 1 -type f | wc -l | tr -d ' ')" = 1
echo '[TEST] help/version work offline without a helper, valid YAML or setup side effects'
