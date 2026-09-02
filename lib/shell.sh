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
        EP_SHELL_LOCAL_BACKED_UP=1
        mv "$tmp" "$local_file"
        chmod 600 "$local_file" 2>/dev/null || true
        ep_log "Removed stale envpilot profile fragments from: $local_file"
    else
        rm -f "$tmp"
        chmod 600 "$local_file" 2>/dev/null || true
        ep_log "Preserved existing shell.local: $local_file"
    fi
}

ep_shell_trim_line()
{
    local line="$1"
    line="${line%$'\r'}"
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    printf '%s' "$line"
}

ep_shell_value_is_safe()
{
    local value="$1"
    local command_substitution="\$("
    local char index=0 length single_quote=0 double_quote=0 escaped=0

    case "$value" in
        *"$command_substitution"*|*'`'*|*';'*|*'|'*|*'&'*|*'<'*|*'>'*) return 1 ;;
    esac

    length="${#value}"
    while [ "$index" -lt "$length" ]; do
        char="${value:$index:1}"
        index=$((index + 1))
        if [ "$escaped" = "1" ]; then
            escaped=0
            continue
        fi
        if [ "$single_quote" = "1" ]; then
            [ "$char" = "'" ] && single_quote=0
            continue
        fi
        if [ "$double_quote" = "1" ]; then
            case "$char" in
                \\) escaped=1 ;;
                '"') double_quote=0 ;;
            esac
            continue
        fi
        case "$char" in
            \\) escaped=1 ;;
            "'") single_quote=1 ;;
            '"') double_quote=1 ;;
            [[:space:]]) return 1 ;;
        esac
    done

    [ "$single_quote" = "0" ] &&
        [ "$double_quote" = "0" ] &&
        [ "$escaped" = "0" ]
}

ep_shell_export_name()
{
    local line="$1" assignment name value
    case "$line" in
        export[[:space:]]*) ;;
        *) return 1 ;;
    esac
    assignment="${line#export}"
    assignment="${assignment#"${assignment%%[![:space:]]*}"}"
    case "$assignment" in
        *=*) ;;
        *) return 1 ;;
    esac
    name="${assignment%%=*}"
    value="${assignment#*=}"
    case "$name" in
        ''|[0-9]*|*[!A-Za-z0-9_]*) return 1 ;;
    esac
    ep_shell_value_is_safe "$value" || return 1
    printf '%s' "$name"
}

ep_shell_assignment_name()
{
    local line="$1" assignment name value
    assignment="$line"
    case "$assignment" in
        export[[:space:]]*)
            assignment="${assignment#export}"
            assignment="${assignment#"${assignment%%[![:space:]]*}"}"
            ;;
    esac
    case "$assignment" in
        *=*) ;;
        *) return 1 ;;
    esac
    name="${assignment%%=*}"
    value="${assignment#*=}"
    case "$name" in
        ''|[0-9]*|*[!A-Za-z0-9_]*) return 1 ;;
    esac
    ep_shell_value_is_safe "$value" || return 1
    printf '%s' "$name"
}

ep_shell_variable_is_ordered_path()
{
    case "$1" in
        PATH|PYTHONPATH|LD_LIBRARY_PATH|DYLD_LIBRARY_PATH|MANPATH|CPATH|C_INCLUDE_PATH|CPLUS_INCLUDE_PATH|LIBRARY_PATH|PKG_CONFIG_PATH|PERL5LIB|RUBYLIB|CLASSPATH)
            return 0
            ;;
        *) return 1 ;;
    esac
}

ep_shell_alias_name()
{
    local line="$1" assignment name value
    case "$line" in
        alias[[:space:]]*) ;;
        *) return 1 ;;
    esac
    assignment="${line#alias}"
    assignment="${assignment#"${assignment%%[![:space:]]*}"}"
    case "$assignment" in
        *=*) ;;
        *) return 1 ;;
    esac
    name="${assignment%%=*}"
    value="${assignment#*=}"
    case "$name" in
        ''|[0-9]*|*[!A-Za-z0-9_.-]*) return 1 ;;
    esac
    ep_shell_value_is_safe "$value" || return 1
    printf '%s' "$name"
}

ep_shell_alias_declared_name()
{
    local line="$1" assignment name
    case "$line" in
        alias[[:space:]]*) ;;
        *) return 1 ;;
    esac
    assignment="${line#alias}"
    assignment="${assignment#"${assignment%%[![:space:]]*}"}"
    case "$assignment" in
        *=*) ;;
        *) return 1 ;;
    esac
    name="${assignment%%=*}"
    case "$name" in
        ''|[0-9]*|*[!A-Za-z0-9_.-]*) return 1 ;;
    esac
    printf '%s' "$name"
}

ep_shell_profile_has_alias()
{
    local name="$1" profile="$2" line normalized existing_name
    [ -f "$profile" ] || return 1
    while IFS= read -r line || [ -n "$line" ]; do
        normalized="$(ep_shell_trim_line "$line")"
        existing_name="$(ep_shell_alias_declared_name "$normalized" 2>/dev/null || true)"
        [ "$existing_name" = "$name" ] && return 0
    done < "$profile"
    return 1
}

ep_shell_variable_is_excluded()
{
    local upper
    upper="$(printf '%s' "$1" | tr '[:lower:]' '[:upper:]')"
    case "$upper" in
        *MIHOMO*|*PROXY*|ENVPILOT_*|BASHRC_PROFILE_ACTIVE|BASHRC_EXTERNAL_*|BASHRC_LAST_*|BASHRC_ENVPILOT_ROOT)
            return 0
            ;;
        SSH_AUTH_SOCK|XAUTHORITY|DISPLAY|DBUS_SESSION_BUS_ADDRESS|GPG_AGENT_INFO|PWD|OLDPWD|SHLVL|BASH_ENV|ENV|_)
            return 0
            ;;
        *) return 1 ;;
    esac
}

ep_shell_variable_is_sensitive()
{
    local upper
    upper="$(printf '%s' "$1" | tr '[:lower:]' '[:upper:]')"
    case "$upper" in
        BASHRC_*) return 1 ;;
        *KEY*|*TOKEN*|*SECRET*|*PASSWORD*|*PASSWD*|*AUTH*) return 0 ;;
        *) return 1 ;;
    esac
}

ep_shell_env_file_has_variable()
{
    local file="$1" name="$2"
    [ -f "$file" ] || return 1
    grep -Eq "^[[:space:]]*(export[[:space:]]+)?${name}=" "$file" 2>/dev/null
}

ep_shell_migration_source()
{
    local profile="$1" candidate source=""
    if [ -f "$profile" ] && ! ep_shell_profile_is_managed "$profile"; then
        printf '%s' "$profile"
        return 0
    fi
    for candidate in "${profile}.bak."*; do
        [ -f "$candidate" ] || continue
        ep_shell_profile_is_managed "$candidate" && continue
        source="$candidate"
    done
    [ -n "$source" ] || return 1
    printf '%s' "$source"
}

ep_shell_merge_additions()
{
    local target="$1" additions="$2" mode="$3" already_backed_up="${4:-0}"
    local tmp
    [ -s "$additions" ] || return 1
    tmp="$(mktemp "${target}.tmp.XXXXXX")"
    if [ -f "$target" ]; then
        cat "$target" > "$tmp"
        printf '\n' >> "$tmp"
        [ "$already_backed_up" = "1" ] || ep_backup_file "$target"
    fi
    cat "$additions" >> "$tmp"
    chmod "$mode" "$tmp" 2>/dev/null || true
    mv "$tmp" "$target"
}

ep_migrate_shell_local()
{
    local old_profile="$1"
    local local_file="$EP_CONFIG_DIR/shell.local"
    local secret_file source shell_additions secret_additions secret_skip_backup=1
    local managed_template=""
    local profile_is_managed=0
    local line normalized name module_name
    local shell_count=0 path_count=0 alias_count=0 secret_count=0 module_count=0
    EP_SHELL_LOCAL_BACKED_UP=0
    EP_SHELL_MIGRATION_SOURCE=""
    EP_ROLLBACK_LOG="${EP_ROLLBACK_LOG:-$EP_CONFIG_DIR/rollback.log}"
    mkdir -p "$EP_CONFIG_DIR"
    [ -f "$(ep_secrets_file)" ] && secret_skip_backup=0
    ep_ensure_secrets_file
    secret_file="$(ep_secrets_file)"

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
        fi
    fi

    shell_additions="$(mktemp "$EP_CONFIG_DIR/shell.local.additions.XXXXXX")"
    secret_additions="$(mktemp "$(dirname "$secret_file")/api.env.additions.XXXXXX")"
    chmod 600 "$shell_additions" "$secret_additions" 2>/dev/null || true

    if [ ! -f "$local_file" ]; then
        printf '%s\n' '# envpilot shell.local'
        printf '%s\n' '# User overrides and safe shell settings preserved across apply-shell updates.'
    fi > "$shell_additions"
    if ! ep_shell_env_file_has_variable "$local_file" BASHRC_ENVPILOT_ROOT &&
       ! ep_shell_env_file_has_variable "$shell_additions" BASHRC_ENVPILOT_ROOT; then
        printf 'BASHRC_ENVPILOT_ROOT=%q\n' "$ENVPILOT_ROOT" >> "$shell_additions"
    fi

    source="$(ep_shell_migration_source "$old_profile" 2>/dev/null || true)"
    EP_SHELL_MIGRATION_SOURCE="$source"
    if [ -n "$source" ]; then
        while IFS= read -r line || [ -n "$line" ]; do
            normalized="$(ep_shell_trim_line "$line")"
            [ -n "$normalized" ] || continue
            if name="$(ep_shell_export_name "$normalized" 2>/dev/null)"; then
                ep_shell_variable_is_excluded "$name" && continue
                if ep_shell_variable_is_sensitive "$name"; then
                    if ! ep_shell_env_file_has_variable "$secret_file" "$name" &&
                       ! ep_shell_env_file_has_variable "$secret_additions" "$name"; then
                        printf '%s\n' "$normalized" >> "$secret_additions"
                        secret_count=$((secret_count + 1))
                    fi
                elif ep_shell_variable_is_ordered_path "$name"; then
                    if ! ep_shell_profile_has_line "$normalized" "$local_file" 2>/dev/null &&
                       ! ep_shell_profile_has_line "$normalized" "$shell_additions" 2>/dev/null; then
                        printf '%s\n' "$normalized" >> "$shell_additions"
                        path_count=$((path_count + 1))
                    fi
                elif ! ep_shell_env_file_has_variable "$local_file" "$name" &&
                     ! ep_shell_env_file_has_variable "$shell_additions" "$name"; then
                    printf '%s\n' "$normalized" >> "$shell_additions"
                    shell_count=$((shell_count + 1))
                fi
                continue
            fi
            if name="$(ep_shell_assignment_name "$normalized" 2>/dev/null)" &&
               ep_shell_variable_is_ordered_path "$name"; then
                if ! ep_shell_profile_has_line "$normalized" "$local_file" 2>/dev/null &&
                   ! ep_shell_profile_has_line "$normalized" "$shell_additions" 2>/dev/null; then
                    printf '%s\n' "$normalized" >> "$shell_additions"
                    path_count=$((path_count + 1))
                fi
                continue
            fi
            if name="$(ep_shell_alias_name "$normalized" 2>/dev/null)"; then
                if ! ep_shell_profile_has_alias "$name" "$local_file" &&
                   ! ep_shell_profile_has_alias "$name" "$shell_additions"; then
                    printf '%s\n' "$normalized" >> "$shell_additions"
                    alias_count=$((alias_count + 1))
                fi
                continue
            fi
            case "$normalized" in
                module[[:space:]]load[[:space:]]*)
                    module_name="${normalized#module}"
                    module_name="${module_name#"${module_name%%[![:space:]]*}"}"
                    module_name="${module_name#load}"
                    module_name="${module_name#"${module_name%%[![:space:]]*}"}"
                    case "$module_name" in
                        ''|*[!A-Za-z0-9_./:+-]*) continue ;;
                    esac
                    if ! grep -Fqx "module load $module_name" "$local_file" 2>/dev/null &&
                       ! grep -Fqx "module load $module_name" "$shell_additions" 2>/dev/null; then
                        printf 'module load %s\n' "$module_name" >> "$shell_additions"
                        module_count=$((module_count + 1))
                    fi
                    ;;
            esac
        done < "$source"
    fi

    if ep_shell_merge_additions "$local_file" "$shell_additions" 600 "$EP_SHELL_LOCAL_BACKED_UP"; then
        if [ "$shell_count" -gt 0 ] || [ "$path_count" -gt 0 ] ||
           [ "$alias_count" -gt 0 ] || [ "$module_count" -gt 0 ]; then
            ep_log "Merged $shell_count scalar export(s), $path_count ordered path assignment(s), $alias_count alias(es), and $module_count module setting(s) into: $local_file"
        else
            ep_log "Created or completed envpilot shell.local: $local_file"
        fi
    elif [ "$EP_SHELL_LOCAL_BACKED_UP" != "1" ]; then
        ep_log "Preserved existing shell.local: $local_file"
    fi
    if ep_shell_merge_additions "$secret_file" "$secret_additions" 600 "$secret_skip_backup"; then
        ep_log "Migrated $secret_count protected variable(s) into: $secret_file"
    fi

    rm -f "$shell_additions" "$secret_additions"
    chmod 600 "$local_file" "$secret_file" 2>/dev/null || true
    unset EP_SHELL_LOCAL_BACKED_UP
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
    local target template migration_source profile_backup review_source
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

    ep_migrate_shell_local "$target"
    migration_source="${EP_SHELL_MIGRATION_SOURCE:-}"
    ep_backup_file "$target"
    profile_backup="${EP_LAST_BACKUP_FILE:-}"
    cp "$template" "$target.tmp"
    mv "$target.tmp" "$target"
    ep_log "Applied shell profile: $target"

    review_source="$migration_source"
    if [ "$review_source" = "$target" ]; then
        review_source="$profile_backup"
    fi
    ep_warn "REQUIRED REVIEW: immediately check shell.local for important settings missing from the previous profile."
    if [ -n "$review_source" ]; then
        ep_warn "Compare the previous profile with the migrated settings: $review_source -> $EP_CONFIG_DIR/shell.local"
        ep_warn "Suggested review command: less '$review_source' '$EP_CONFIG_DIR/shell.local'"
    else
        ep_warn "No unmanaged previous profile was available for automatic migration; inspect your older profile backups manually."
    fi
    ep_warn "You may manually restore reviewed interactive settings in shell.local: missing PATH/PYTHONPATH/library paths, aliases, shell functions, EDITOR/LANG/tool variables, prompt/history settings, custom module commands, and tool initialization."
    ep_warn "Do not copy API keys or tokens there (use $HOME/.config/secrets/api.env), and do not blindly restore old Conda initialization, proxy exports, or Mihomo startup blocks managed by envpilot."
    ep_warn "Silent/non-interactive/no-real-TTY shells do NOT source shell.local in full. Custom paths, aliases, functions, module commands, prompt settings, and tool initialization added there are interactive-only; protected api.env assignments and envpilot's small non-interactive whitelist are loaded separately."
    ep_log "Reload with: source $target"
    unset EP_SHELL_MIGRATION_SOURCE EP_LAST_BACKUP_FILE
}
