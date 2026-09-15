#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT
export HOME="$fixture/home" SHELL=/bin/bash ENVPILOT_LANG=en ENVPILOT_MODE=offline
export ENVPILOT_CONFIG_DIR="$HOME/.config/envpilot"
mkdir -p "$HOME" "$fixture/no-network"
for name in python python3 curl wget; do
    printf '#!/bin/sh\necho forbidden-tool-invocation >&2\nexit 99\n' > "$fixture/no-network/$name"
    chmod 700 "$fixture/no-network/$name"
done
export PATH="$fixture/no-network:$PATH"
original="$fixture/original-profile"
printf '%s\n' '# custom profile' 'original_command() { printf original; }' 'alias existing_alias="printf original"' > "$original"
cp "$original" "$HOME/.bashrc"
bash "$ROOT/envpilot.sh" init --lang en
bash "$ROOT/envpilot.sh" config validate
translated="$(bash "$ROOT/envpilot.sh" plan --lang zh-CN)"
case "$translated" in *配置文件*) ;; *) exit 1 ;; esac
bash "$ROOT/envpilot.sh" apply --yes --non-interactive
cp "$HOME/.bashrc" "$fixture/applied"
bash "$ROOT/envpilot.sh" apply --yes --non-interactive
cmp "$fixture/applied" "$HOME/.bashrc"
actual="$(bash --noprofile --norc -c '. "$HOME/.bashrc"; original_command')"
[ "$actual" = original ]
before="$(cat "$ENVPILOT_CONFIG_DIR/latest-snapshot")"
bash "$ROOT/envpilot.sh" doctor >/dev/null 2>&1
[ "$before" = "$(cat "$ENVPILOT_CONFIG_DIR/latest-snapshot")" ]
bash "$ROOT/envpilot.sh" shell remove
cmp "$original" "$HOME/.bashrc"
status=0
bash "$ROOT/envpilot.sh" run -- bash -c 'exit 23' || status=$?
[ "$status" = 23 ]
printf 'version: 1\nunknown_field: true\n' > "$ENVPILOT_CONFIG_DIR/config.yaml"
if bash "$ROOT/envpilot.sh" apply --yes --non-interactive > "$fixture/error" 2>&1; then exit 1; fi
cmp "$original" "$HOME/.bashrc"
printf '%s' '{"author":{"id":999},"tag_name":"v0.4.0","id":123}' > "$fixture/release.json"
[ "$(awk -v mode=release -f "$ROOT/lib/bootstrap-json.awk" "$fixture/release.json")" = 123 ]
[ "$(awk -v mode=tag -f "$ROOT/lib/bootstrap-json.awk" "$fixture/release.json")" = v0.4.0 ]
printf '%s' '[{"uploader":{"id":999,"name":"SHA256SUMS"},"id":42,"name":"envpilot-core-0.4.0-linux-amd64"},{"name":"SHA256SUMS","id":43}]' > "$fixture/assets.json"
[ "$(awk -v mode=asset -v wanted=envpilot-core-0.4.0-linux-amd64 -f "$ROOT/lib/bootstrap-json.awk" "$fixture/assets.json")" = 42 ]
[ "$(awk -v mode=asset -v wanted=SHA256SUMS -f "$ROOT/lib/bootstrap-json.awk" "$fixture/assets.json")" = 43 ]
echo '[TEST] configuration, no-runtime bootstrap, profile preservation and child exit status passed'
