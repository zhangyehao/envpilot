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
    ep_log "Manifest updates are resolver-driven and CI-managed."
    ep_log "Run this command in CI or a maintainer workstation with network access."
    ep_log "Current manifests:"
    find "$ENVPILOT_ROOT/manifests" -maxdepth 1 -type f -name '*.json' -print | sort
}

