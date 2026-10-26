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
echo '[TEST] Mihomo options accept interleaved values and never echo subscription credentials'
subscription='https://example.invalid/subscription?token=SYNTHETIC-DO-NOT-LOG'
test "$(bash "$fixture/repo/envpilot.sh" mihomo update-subscription --network direct "$subscription" --version)" = "envpilot $version"
test "$(bash "$fixture/repo/envpilot.sh" mihomo select --non-interactive 'Group with spaces' --json 'Node with spaces' --version)" = "envpilot $version"
if bash "$fixture/repo/envpilot.sh" mihomo update-subscription --network direct "$subscription" "$subscription" > "$fixture/parse.log" 2>&1; then
    printf '[ERROR] extra subscription arguments unexpectedly accepted\n' >&2
    exit 1
fi
grep -F 'Unexpected extra argument' "$fixture/parse.log" >/dev/null
if grep -F SYNTHETIC-DO-NOT-LOG "$fixture/parse.log"; then exit 1; fi
if bash "$fixture/repo/envpilot.sh" mihomo update-subscription "--unexpected=$subscription" > "$fixture/unknown.log" 2>&1; then
    printf '[ERROR] unknown option unexpectedly accepted\n' >&2
    exit 1
fi
if grep -F SYNTHETIC-DO-NOT-LOG "$fixture/unknown.log"; then exit 1; fi
