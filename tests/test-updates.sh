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
    # A 0.4.7 scheduler already invokes the stable entrypoint. Upgrading via
    # the new apply-shell must make subsequent automatic triggers observable.
    mkdir -p "$ENVPILOT_CONFIG_DIR/updates"
    printf "#!/bin/bash\nexec '%s' updates run --config '%s'\n" "$HOME/.local/bin/envpilot" "$ENVPILOT_CONFIG_DIR/config.yaml" > "$ENVPILOT_CONFIG_DIR/updates/run.sh"
    bash "$ROOT/envpilot.sh" apply-shell --yes --non-interactive
    grep -q ' updates tick --config ' "$ENVPILOT_CONFIG_DIR/updates/run.sh"
    bash "$ROOT/envpilot.sh" updates enable
    cp "$HOME/test.crontab" "$fixture/enabled.crontab"
    bash "$ROOT/envpilot.sh" updates enable
    cmp "$HOME/test.crontab" "$fixture/enabled.crontab"
    launchers=("$ENVPILOT_CONFIG_DIR"/updates/schedulers/*/run.sh)
    test "${#launchers[@]}" = 1 && bash -n "${launchers[0]}"
    # edit validates the exact custom file and reports effective rules without
    # reinstalling the job. Editing broken YAML remains possible.
    custom="$fixture/site config.yaml"
    printf 'updates: {auto_apply: true}\n' > "$custom"
    bash "$ROOT/envpilot.sh" updates enable --config "$custom"
    cp "${launchers[0]}" "$fixture/before-edit"
    cat > "$fixture/bin/test-editor" <<'EOF'
#!/bin/sh
cp "$ENVPILOT_TEST_EDIT" "$1"
EOF
    chmod 700 "$fixture/bin/test-editor"
    export EDITOR="$fixture/bin/test-editor" ENVPILOT_TEST_EDIT="$fixture/edit.yaml"
    printf 'updates: {auto_apply: true, policies: {git: {auto_apply: false}}}\n' > "$ENVPILOT_TEST_EDIT"
    bash "$ROOT/envpilot.sh" config edit --config "$custom" > "$fixture/edit.log"
    grep -Fq 'git: check only' "$fixture/edit.log"
    grep -Fq 'registered scheduler reads this file' "$fixture/edit.log"
    cmp "${launchers[0]}" "$fixture/before-edit"
    printf 'updates: {interval_days: private-credential-example}\n' > "$ENVPILOT_TEST_EDIT"
    if bash "$ROOT/envpilot.sh" config edit --config "$custom" > "$fixture/edit.log" 2>&1; then exit 1; fi
    grep -Fq E_CONFIG_EDIT_INVALID "$fixture/edit.log"
    if grep -Fq private-credential-example "$fixture/edit.log"; then exit 1; fi
    # Report a different registered path explicitly when editing another file.
    alternative="$fixture/second config.yaml"
    printf 'updates: {auto_apply: false}\n' > "$alternative"
    printf 'updates: {auto_apply: true}\n' > "$ENVPILOT_TEST_EDIT"
    bash "$ROOT/envpilot.sh" config edit --config "$alternative" > "$fixture/edit.log"
    grep -Fq 'registered for a different file' "$fixture/edit.log"
    printf 'updates: {enabled: false}\n' > "$ENVPILOT_TEST_EDIT"
    bash "$ROOT/envpilot.sh" config edit --config "$custom" > "$fixture/edit.log"
    grep -Fq 'Configuration is valid.' "$fixture/edit.log"
    unset EDITOR ENVPILOT_TEST_EDIT
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
# The installer must not skip a requested managed Python because a system
# interpreter exists. An invalid explicit asset must fail and record failure.
if bash "$ROOT/envpilot.sh" update python --mode offline --asset-path "$fixture/missing.tar.gz" --yes --non-interactive > "$fixture/failed-install.log" 2>&1; then
    cat "$fixture/failed-install.log"; exit 1
fi
bash "$ROOT/envpilot.sh" updates history --component python --json | grep '"status": "failed"'
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
if command -v zsh >/dev/null 2>&1; then
    env -u CONDA_PREFIX -u VIRTUAL_ENV zsh -f -c '
        source "$HOME/.config/envpilot/shell/init.sh"
        test "$(command -v git)" = "$HOME/software/git/current/bin/git"
        previous=$PATH; source "$HOME/.config/envpilot/shell/init.sh"; test "$previous" = "$PATH"
    '
fi
echo '[TEST] update CLI, offline policy, history and idempotent scheduler passed'
python3 "$ROOT/tests/test-scheduled-subscription.py"
bash "$ROOT/tests/test-python-update.sh"
