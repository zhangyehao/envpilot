#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT
mkdir -p "$fixture/repo" "$fixture/home" "$fixture/config" "$fixture/caller"
cp "$ROOT/envpilot.sh" "$ROOT/VERSION" "$fixture/repo/"
cp -R "$ROOT/lib" "$ROOT/components" "$fixture/repo/"
export HOME="$fixture/home" ENVPILOT_CONFIG_DIR="$fixture/config"
export ENVPILOT_MODE=offline ENVPILOT_LANG=en
version="$(tr -d '\r\n' < "$ROOT/VERSION")"
cd "$fixture/caller"
echo "[TEST] optional Mihomo arguments and run dispatch under Bash $BASH_VERSION"
# Exercise the real entrypoint with an isolated home and a recording helper.
# No subscription, live controller, network or installed helper is accessed.
# Using $BASH also tests /bin/bash 3.2 when invoked explicitly on macOS.
export ENVPILOT_TEST_BASH="$BASH" ENVPILOT_TEST_VERSION="$version"
export ENVPILOT_TEST_ARGS="$fixture/core.args" EP_MODE=offline
export ENVPILOT_CORE="$fixture/recording-core"
unset ENVPILOT_UPDATE_LOCK_HELD
cat > "$ENVPILOT_CORE" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "${1:-}" in
    version) printf '%s\n' "$ENVPILOT_TEST_VERSION" ;;
    export) ;;
    update-lock)
        test "$2" = -- && test "$3" = bash
        shift 3
        export ENVPILOT_UPDATE_LOCK_HELD=1
        exec "$ENVPILOT_TEST_BASH" "$@"
        ;;
    mihomo|run)
        printf '%s\0' "$@" > "$ENVPILOT_TEST_ARGS"
        exit "${ENVPILOT_TEST_CORE_STATUS:-0}"
        ;;
    *) printf 'Unexpected fixture core command\n' >&2; exit 90 ;;
esac
EOF
chmod 700 "$ENVPILOT_CORE"
assert_mihomo_args() {
    local format="$1"
    shift
    printf '%s\0' mihomo --config "$ENVPILOT_CONFIG_DIR/config.yaml" \
        --root "$fixture/repo" --format "$format" -- "$@" > "$fixture/expected.args"
    cmp "$fixture/expected.args" "$ENVPILOT_TEST_ARGS"
}
for action in nodes select test; do
    "$BASH" "$fixture/repo/envpilot.sh" mihomo "$action" --json --non-interactive
    assert_mihomo_args json "$action"
    "$BASH" "$fixture/repo/envpilot.sh" mihomo "$action"
    assert_mihomo_args text "$action"
    "$BASH" "$fixture/repo/envpilot.sh" mihomo "$action" --json '手动 Group *'
    assert_mihomo_args json "$action" '手动 Group *'
done
for action in select test; do
    "$BASH" "$fixture/repo/envpilot.sh" mihomo "$action" '手动 Group *' --json 'Node ? [] 🇯🇵'
    assert_mihomo_args json "$action" '手动 Group *' 'Node ? [] 🇯🇵'
    "$BASH" "$fixture/repo/envpilot.sh" mihomo "$action" --json -- '-Group *' '-Node ?'
    assert_mihomo_args json "$action" '-Group *' '-Node ?'
done
core_status=0
ENVPILOT_TEST_CORE_STATUS=23 "$BASH" "$fixture/repo/envpilot.sh" mihomo select --non-interactive || core_status=$?
test "$core_status" = 23
assert_mihomo_args text select
for suffix in bare separator; do
    core_status=0
    if [ "$suffix" = separator ]; then
        ENVPILOT_TEST_CORE_STATUS=24 "$BASH" "$fixture/repo/envpilot.sh" run -- || core_status=$?
    else
        ENVPILOT_TEST_CORE_STATUS=24 "$BASH" "$fixture/repo/envpilot.sh" run || core_status=$?
    fi
    test "$core_status" = 24
    printf '%s\0' run --config "$ENVPILOT_CONFIG_DIR/config.yaml" -- > "$fixture/expected.args"
    cmp "$fixture/expected.args" "$ENVPILOT_TEST_ARGS"
done
"$BASH" "$fixture/repo/envpilot.sh" run -- command 'a b' '' '*.txt' '--option'
printf '%s\0' run --config "$ENVPILOT_CONFIG_DIR/config.yaml" -- \
    command 'a b' '' '*.txt' '--option' > "$fixture/expected.args"
cmp "$fixture/expected.args" "$ENVPILOT_TEST_ARGS"
