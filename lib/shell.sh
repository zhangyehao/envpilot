#!/usr/bin/env bash

ep_shell_profile_target()
{
    case "$EP_SHELL_NAME" in
        zsh) printf '%s/.zshrc' "$HOME" ;;
        bash) printf '%s/.bashrc' "$HOME" ;;
        *)
            if [ "$EP_OS" = "darwin" ]; then
                printf '%s/.zshrc' "$HOME"
            else
                printf '%s/.bashrc' "$HOME"
            fi
            ;;
    esac
}

ep_shell_template()
{
    case "$EP_SHELL_NAME" in
        zsh) printf '%s/templates/zshrc' "$ENVPILOT_ROOT" ;;
        *) printf '%s/templates/bashrc' "$ENVPILOT_ROOT" ;;
    esac
}

ep_migrate_shell_local()
{
    local old_profile="$1"
    local local_file="$EP_CONFIG_DIR/shell.local"
    mkdir -p "$EP_CONFIG_DIR"
    {
        printf '%s\n' '# envpilot shell.local'
        printf '%s\n' '# Safe exported variables migrated from the previous profile.'
        printf '%s\n' '# Proxy, Mihomo, secret, and API-key variables are intentionally excluded.'
        printf 'BASHRC_ENVPILOT_ROOT=%q\n' "$ENVPILOT_ROOT"
        if [ -f "$old_profile" ]; then
            grep -E '^[[:space:]]*export[[:space:]]+[A-Za-z_][A-Za-z0-9_]*=' "$old_profile" 2>/dev/null |
                grep -Evi 'KEY|TOKEN|SECRET|PASSWORD|PASSWD|AUTH|MIHOMO|PROXY|ENVPILOT_ROOT' |
                grep -Ev '\$\(' || true
            grep -E '^[[:space:]]*module[[:space:]]+load[[:space:]]+' "$old_profile" 2>/dev/null |
                grep -Evi 'KEY|TOKEN|SECRET|PASSWORD|PASSWD|AUTH|MIHOMO|PROXY|ENVPILOT_ROOT' || true
        fi
    } > "$local_file.tmp"
    mv "$local_file.tmp" "$local_file"
    chmod 600 "$local_file" 2>/dev/null || true
    ep_log "Wrote migrated shell hints: $local_file"
    ep_log "Migrated safe exported variables; excluded old proxy/Mihomo functions and secret-like variables."
}

ep_secrets_file()
{
    printf '%s/.config/secrets/api.env' "$HOME"
}

ep_ensure_secrets_file()
{
    local secret_dir="$HOME/.config/secrets"
    local secret_file
    local template="$ENVPILOT_ROOT/templates/api.env.example"
    local tmp

    secret_file="$(ep_secrets_file)"
    [ -f "$template" ] || ep_die "Secrets template missing: $template"
    mkdir -p "$secret_dir"
    chmod 700 "$secret_dir" 2>/dev/null || ep_die "Could not restrict secrets directory: $secret_dir"

    if [ -e "$secret_file" ] || [ -L "$secret_file" ]; then
        [ -f "$secret_file" ] || ep_die "Secrets path is not a regular file: $secret_file"
    else
        tmp="$secret_file.tmp.$$"
        ( umask 077; cp "$template" "$tmp" ) || ep_die "Could not create secrets file: $secret_file"
        chmod 600 "$tmp" || ep_die "Could not restrict secrets file: $secret_file"
        mv "$tmp" "$secret_file" || ep_die "Could not install secrets file: $secret_file"
        ep_log "Created protected secrets file: $secret_file"
    fi

    chmod 600 "$secret_file" 2>/dev/null ||
        ep_die "Could not set mode 600 on secrets file: $secret_file"
}

ep_apply_shell_profile()
{
    ep_require_unix_runtime
    local target template
    target="$(ep_shell_profile_target)"
    template="$(ep_shell_template)"
    [ -f "$template" ] || ep_die "Shell template missing: $template"

    ep_log "Shell profile target: $target"
    ep_log "Template: $template"
    ep_log "Existing profile will be backed up before replacement."
    if ! ep_confirm "Apply envpilot shell profile now?" "no"; then
        ep_warn "Shell profile unchanged."
        return 0
    fi

    ep_ensure_secrets_file
    ep_backup_file "$target"
    ep_migrate_shell_local "$target"
    cp "$template" "$target.tmp"
    mv "$target.tmp" "$target"
    ep_log "Applied shell profile: $target"
    ep_log "Reload with: source $target"
}
