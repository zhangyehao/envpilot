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

ep_shell_profile_is_managed()
{
    local profile="$1"
    [ -f "$profile" ] || return 1
    grep -Eq '^#[[:space:]]+~/\.(bashrc|zshrc)[[:space:]]+managed by envpilot$' "$profile"
}

ep_shell_local_has_managed_fragment()
{
    local local_file="$1"
    [ -f "$local_file" ] || return 1
    grep -Fq "module load \"\$module_name\" || return 1" "$local_file" ||
        grep -Fq "export VISUAL=\"\${VISUAL:-\${EDITOR:-vi}}\"" "$local_file"
}

ep_shell_profile_has_line()
{
    local candidate="$1"
    local profile="$2"
    local line normalized
    while IFS= read -r line || [ -n "$line" ]; do
        normalized="$line"
        normalized="${normalized#"${normalized%%[![:space:]]*}"}"
        normalized="${normalized%"${normalized##*[![:space:]]}"}"
        [ "$normalized" = "$candidate" ] && return 0
    done < "$profile"
    return 1
}

ep_shell_local_cleanup_managed_fragments()
{
    local local_file="$1"
    local managed_template="$2"
    local tmp line normalized changed=0
    tmp="$(mktemp "${local_file}.tmp.XXXXXX")"
    while IFS= read -r line || [ -n "$line" ]; do
        normalized="$line"
        normalized="${normalized#"${normalized%%[![:space:]]*}"}"
        normalized="${normalized%"${normalized##*[![:space:]]}"}"
        if [ -n "$normalized" ] && ep_shell_profile_has_line "$normalized" "$managed_template"; then
            changed=1
            continue
        fi
        printf '%s\n' "$line" >> "$tmp"
    done < "$local_file"

    if [ "$changed" = "1" ]; then
        ep_backup_file "$local_file"
        mv "$tmp" "$local_file"
        chmod 600 "$local_file" 2>/dev/null || true
        ep_log "Removed stale envpilot profile fragments from: $local_file"
    else
        rm -f "$tmp"
        chmod 600 "$local_file" 2>/dev/null || true
        ep_log "Preserved existing shell.local: $local_file"
    fi
}

ep_migrate_shell_local()
{
    local old_profile="$1"
    local local_file="$EP_CONFIG_DIR/shell.local"
    local managed_template=""
    local profile_is_managed=0
    EP_ROLLBACK_LOG="${EP_ROLLBACK_LOG:-$EP_CONFIG_DIR/rollback.log}"
    mkdir -p "$EP_CONFIG_DIR"

    if ep_shell_profile_is_managed "$old_profile"; then
        profile_is_managed=1
        managed_template="$(ep_shell_template)"
        [ -f "$managed_template" ] || managed_template="$old_profile"
    fi

    if [ -f "$local_file" ]; then
        if [ "$profile_is_managed" = "1" ] && ep_shell_local_has_managed_fragment "$local_file"; then
            ep_shell_local_cleanup_managed_fragments "$local_file" "$managed_template"
        else
            chmod 600 "$local_file" 2>/dev/null || true
            if [ "$profile_is_managed" = "1" ]; then
                ep_log "Preserved existing envpilot shell.local: $local_file"
            else
                ep_log "Preserved existing shell.local and skipped profile migration: $local_file"
            fi
        fi
        return 0
    fi

    {
        printf '%s\n' '# envpilot shell.local'
        printf '%s\n' '# Safe exported variables migrated from the previous profile.'
        printf '%s\n' '# Proxy, Mihomo, secret, and API-key variables are intentionally excluded.'
        printf 'BASHRC_ENVPILOT_ROOT=%q\n' "$ENVPILOT_ROOT"
        if [ "$profile_is_managed" = "0" ] && [ -f "$old_profile" ]; then
            grep -E '^[[:space:]]*export[[:space:]]+[A-Za-z_][A-Za-z0-9_]*=' "$old_profile" 2>/dev/null |
                grep -Evi 'KEY|TOKEN|SECRET|PASSWORD|PASSWD|AUTH|MIHOMO|PROXY|ENVPILOT_ROOT' |
                grep -Ev '\$\(' || true
            grep -E '^[[:space:]]*module[[:space:]]+load[[:space:]]+' "$old_profile" 2>/dev/null |
                grep -Evi 'KEY|TOKEN|SECRET|PASSWORD|PASSWD|AUTH|MIHOMO|PROXY|ENVPILOT_ROOT' || true
        fi
    } > "$local_file.tmp"
    mv "$local_file.tmp" "$local_file"
    chmod 600 "$local_file" 2>/dev/null || true
    if [ "$profile_is_managed" = "1" ]; then
        ep_log "Created new envpilot shell.local: $local_file"
    else
        ep_log "Wrote migrated shell hints: $local_file"
        ep_log "Migrated safe exported variables; excluded old proxy/Mihomo functions and secret-like variables."
    fi
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
