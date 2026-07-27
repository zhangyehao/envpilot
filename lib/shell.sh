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
        printf '# envpilot shell.local\n'
        printf '# Review these migrated lines before enabling them permanently.\n'
        if [ -f "$old_profile" ]; then
            grep -E '^[[:space:]]*(export[[:space:]]+PATH=|PATH=|module[[:space:]]+load|[^#]*conda\.sh)' "$old_profile" 2>/dev/null |
                grep -Evi 'KEY|TOKEN|SECRET|PASSWORD|PASSWD|OPENAI_API_KEY|ALPHA_GENOME_API_KEY|GITHUB_TOKEN' || true
        fi
    } > "$local_file.tmp"
    mv "$local_file.tmp" "$local_file"
    chmod 600 "$local_file" 2>/dev/null || true
    ep_log "Wrote migrated shell hints: $local_file"
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

    ep_backup_file "$target"
    ep_migrate_shell_local "$target"
    cp "$template" "$target.tmp"
    mv "$target.tmp" "$target"
    ep_log "Applied shell profile: $target"
    ep_log "Reload with: source $target"
}

