#!/usr/bin/env bash

ep_rollback_latest()
{
    [ -s "$EP_ROLLBACK_LOG" ] || ep_die "No rollback records found."

    local target backup
    IFS="$(printf '\t')" read -r target backup <<EOF
$(tail -n 1 "$EP_ROLLBACK_LOG")
EOF
    [ -n "$target" ] && [ -n "$backup" ] || ep_die "Invalid rollback record."
    [ -f "$backup" ] || ep_die "Backup file not found: $backup"
    cp -p "$backup" "$target"
    ep_log "Restored $target from $backup"
}

