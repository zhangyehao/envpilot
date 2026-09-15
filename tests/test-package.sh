#!/usr/bin/env bash
set -euo pipefail
archive="$1"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
version="$(tr -d '\r\n' < "$ROOT/VERSION")"
fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT
tar -xzf "$archive" -C "$fixture"
package="$fixture/envpilot-$version"
export HOME="$fixture/home" SHELL=/bin/bash ENVPILOT_LANG=en ENVPILOT_MODE=offline
unset ENVPILOT_CORE ENVPILOT_CONFIG_DIR
mkdir -p "$HOME" "$fixture/caller"
test -x "$package/bin/envpilot-core"
bash "$package/envpilot.sh" init --lang en
bash "$package/envpilot.sh" setup-command
export PATH="$HOME/.local/bin:/usr/bin:/bin"
cd "$fixture/caller"
envpilot config validate
envpilot apply --yes --non-interactive
. "$HOME/.bashrc"
test "$(envpilot run -- pwd)" = "$fixture/caller"
test -s "$HOME/.config/envpilot/core-path"
envpilot shell remove
echo '[TEST] platform package installation passed'
