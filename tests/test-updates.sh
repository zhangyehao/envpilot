#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT
export HOME="$fixture/home" ENVPILOT_LANG=en
export ENVPILOT_CONFIG_DIR="$HOME/.config/envpilot"
mkdir -p "$HOME" "$fixture/bin"
export PATH="$fixture/bin:$PATH"
export ENVPILOT_CORE="$ROOT/bin/envpilot-core"
export ENVPILOT_MODE=offline
bash "$ROOT/envpilot.sh" init
bash "$ROOT/envpilot.sh" updates status --json > "$fixture/status.json"
bash "$ROOT/envpilot.sh" updates history --json > "$fixture/history.json"
test "$(cat "$fixture/history.json")" = '[]'
if bash "$ROOT/envpilot.sh" updates history --days 0; then exit 1; fi
if bash "$ROOT/envpilot.sh" updates check; then exit 1; fi
# Exercise real scheduler generation without touching the user's crontab.
cat > "$fixture/bin/systemctl" <<'EOF'
#!/bin/sh
exit 1
EOF
cat > "$fixture/bin/crontab" <<'EOF'
#!/bin/sh
case "$1" in
  -l) cat "$HOME/test.crontab" ;;
  -) cat > "$HOME/test.crontab" ;;
esac
EOF
chmod 700 "$fixture/bin/"*
printf '0 2 * * * /usr/bin/true\n' > "$HOME/test.crontab"
cp "$HOME/test.crontab" "$fixture/original.crontab"
bash "$ROOT/envpilot.sh" setup-command
if [ "$(uname -s)" != Darwin ]; then
    bash "$ROOT/envpilot.sh" updates enable
    cp "$HOME/test.crontab" "$fixture/enabled.crontab"
    bash "$ROOT/envpilot.sh" updates enable
    cmp "$HOME/test.crontab" "$fixture/enabled.crontab"
    bash -n "$ENVPILOT_CONFIG_DIR/updates/run.sh"
    bash "$ROOT/envpilot.sh" updates disable
    cmp "$HOME/test.crontab" "$fixture/original.crontab"
fi
# Finish through the public wrappers, verify failure is retained and filtered.
id="$("$ENVPILOT_CORE" history-begin envpilot --root "$ROOT" --config "$ENVPILOT_CONFIG_DIR/config.yaml")"
"$ENVPILOT_CORE" history-finish "$id" 1 --root "$ROOT" --config "$ENVPILOT_CONFIG_DIR/config.yaml"
bash "$ROOT/envpilot.sh" updates history --component envpilot --json | grep '"status": "failed"'
test "$(bash "$ROOT/envpilot.sh" updates history --component codex --json)" = '[]'
# Explicit managed priority wins in ordinary shells, without duplicate paths,
# while active Python environments and user-defined functions remain intact.
mkdir -p "$HOME/software/git/current/bin" "$HOME/software/python/current/bin" "$fixture/venv/bin"
for file in "$HOME/software/git/current/bin/git" "$HOME/software/python/current/bin/python3" "$fixture/venv/bin/python3"; do
    printf '#!/bin/sh\nexit 0\n' > "$file"; chmod 700 "$file"
done
cat > "$ENVPILOT_CONFIG_DIR/config.yaml" <<'EOF'
shell:
  prefer_managed: [git, python]
EOF
bash "$ROOT/envpilot.sh" apply-shell --yes --non-interactive
env -u CONDA_PREFIX -u VIRTUAL_ENV bash --noprofile --norc -c '
    . "$HOME/.bashrc"
    test "$(command -v git)" = "$HOME/software/git/current/bin/git"
    test "$(command -v python3)" = "$HOME/software/python/current/bin/python3"
    previous=$PATH; . "$HOME/.bashrc"; test "$previous" = "$PATH"
    git() { printf user-function; }; . "$HOME/.bashrc"; test "$(git)" = user-function
'
VIRTUAL_ENV="$fixture/venv" PATH="$fixture/venv/bin:$PATH" bash --noprofile --norc -c '
    . "$HOME/.bashrc"
    test "$(command -v python3)" = "$VIRTUAL_ENV/bin/python3"
    test "$(command -v git)" = "$HOME/software/git/current/bin/git"
'
echo '[TEST] update CLI, offline policy, history and idempotent scheduler passed'
