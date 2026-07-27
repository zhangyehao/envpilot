#!/usr/bin/env bash

ep_manifest_path()
{
    printf '%s/manifests/%s.json' "$ENVPILOT_ROOT" "$1"
}

ep_manifest_show()
{
    local name="$1"
    local file
    file="$(ep_manifest_path "$name")"
    [ -f "$file" ] || ep_die "Manifest not found: $name"
    cat "$file"
}

ep_update_manifests()
{
    local python_bin="" candidate
    for candidate in python3 python; do
        if ep_command_exists "$candidate" && "$candidate" -c 'import sys; sys.exit(0)' >/dev/null 2>&1; then
            python_bin="$candidate"
            break
        fi
    done
    [ -n "$python_bin" ] || ep_die "python3 or python is required to update manifests"
    "$python_bin" "$ENVPILOT_ROOT/scripts/update-manifests.py"
}

