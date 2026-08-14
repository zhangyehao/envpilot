#!/usr/bin/env bash

EP_CODEX_BASE_URL="${EP_CODEX_BASE_URL:-https://yanhuoapi.com/v1}"
EP_CODEX_PACKAGE="${EP_CODEX_PACKAGE:-@openai/codex}"
EP_MIN_NODE_MAJOR="${EP_MIN_NODE_MAJOR:-22}"
EP_NVM_VERSION="${EP_NVM_VERSION:-v0.40.1}"

ep_node_major()
{
    node -v 2>/dev/null | sed 's/^v//' | cut -d. -f1
}

ep_doctor_codex()
{
    local secret_file

    if ep_command_exists codex; then
        ep_log "Codex: found at $(command -v codex)"
        codex --version 2>/dev/null | sed 's/^/[INFO] Codex version: /' || true
    else
        ep_warn "Codex: not found"
    fi
    if [ -f "$HOME/.codex/config.toml" ]; then
        ep_log "Codex config: $HOME/.codex/config.toml"
    else
        ep_warn "Codex config: not found"
    fi
    if [ -f "$HOME/.codex/auth.json" ]; then
        ep_log "Codex auth: found at $HOME/.codex/auth.json (value not displayed)"
    else
        ep_warn "Codex auth: not found; install will ask before creating it"
    fi
    secret_file="$(ep_secrets_file)"
    if [ -f "$secret_file" ]; then
        if ep_codex_secret_file_is_safe "$secret_file"; then
            ep_log "Codex secrets: protected file at $secret_file"
        else
            ep_warn "Codex secrets: $secret_file exists but is not owned by the current user or is not mode 600/400"
        fi
    else
        ep_warn "Codex secrets: not found; install or apply-shell will create a protected scaffold"
    fi
}

ep_load_nvm()
{
    export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
    if [ -s "$NVM_DIR/nvm.sh" ]; then
        # shellcheck disable=SC1091
        . "$NVM_DIR/nvm.sh" || ep_die "Failed to load nvm from $NVM_DIR/nvm.sh"
    fi
    return 0
}

ep_ensure_node()
{
    local major nvm_installer_url
    ep_load_nvm
    if ep_command_exists node; then
        major="$(ep_node_major || true)"
        if [ -n "$major" ] && [ "$major" -ge "$EP_MIN_NODE_MAJOR" ]; then
            ep_log "Node.js satisfies requirement: $(node -v)"
            return 0
        fi
        ep_warn "Node.js $(node -v 2>/dev/null || true) is lower than required v$EP_MIN_NODE_MAJOR"
    else
        ep_warn "Node.js: not found"
    fi

    ep_command_exists curl || ep_die "curl is required to install nvm/Node.js automatically"
    nvm_installer_url="https://raw.githubusercontent.com/nvm-sh/nvm/$EP_NVM_VERSION/install.sh"
    ep_log "Node.js source: nvm $EP_NVM_VERSION, then the latest Node.js LTS"
    ep_log "Node.js target: $HOME/.nvm (user space; no root required)"
    ep_confirm "Install Node.js LTS via nvm under $HOME/.nvm?" "yes" || ep_die "Node.js $EP_MIN_NODE_MAJOR+ is required for Codex"
    export NVM_DIR="$HOME/.nvm"
    if [ ! -s "$NVM_DIR/nvm.sh" ]; then
        ep_log "Downloading nvm installer: $nvm_installer_url"
        if ! curl -fsSL "$nvm_installer_url" | bash; then
            ep_die "Failed to download or install nvm from $nvm_installer_url"
        fi
    fi
    ep_load_nvm
    ep_command_exists nvm || ep_die "nvm did not load; reopen shell and retry"
    ep_log "Installing the latest Node.js LTS through nvm. This may download an archive and take several minutes."
    nvm install 'lts/*' || ep_die "nvm failed to install the latest Node.js LTS"
    nvm alias default 'lts/*' || ep_die "nvm failed to set the default Node.js LTS alias"
    nvm use default || ep_die "nvm failed to activate the default Node.js version"
    major="$(ep_node_major || true)"
    if [ -z "$major" ] || [ "$major" -lt "$EP_MIN_NODE_MAJOR" ]; then
        ep_die "Node.js installation completed but v$EP_MIN_NODE_MAJOR+ is not active"
    fi
    ep_log "Node.js ready: $(node -v) at $(command -v node)"
}

ep_write_codex_config()
{
    local config_dir="$HOME/.codex"
    local config_file="$config_dir/config.toml"
    mkdir -p "$config_dir"
    ep_backup_file "$config_file"
    cat > "$config_file.tmp" <<EOF
model_provider = "codex"
model = "gpt-5.5"
review_model = "gpt-5.5"
model_reasoning_effort = "high"
disable_response_storage = true
network_access = "enabled"
model_context_window = 270000
model_auto_compact_token_limit = 270000
effective_context_window_percent = 95

[model_providers.codex]
name = "codex"
base_url = "$EP_CODEX_BASE_URL"
wire_api = "responses"
env_key = "OPENAI_API_KEY"
EOF
    mv "$config_file.tmp" "$config_file"
    chmod 600 "$config_file" 2>/dev/null || true
    ep_log "Wrote Codex config using env_key=OPENAI_API_KEY: $config_file"
}

ep_codex_secret_file_mode()
{
    local secret_file="$1"
    stat -c '%a' "$secret_file" 2>/dev/null || stat -f '%Lp' "$secret_file" 2>/dev/null || true
}

ep_codex_secret_file_is_safe()
{
    local secret_file="$1"
    local mode owner current
    [ -f "$secret_file" ] || return 1
    current="$(id -u)"
    owner="$(stat -c '%u' "$secret_file" 2>/dev/null || stat -f '%u' "$secret_file" 2>/dev/null || printf '%s' "$current")"
    [ "$owner" = "$current" ] || return 1
    mode="$(ep_codex_secret_file_mode "$secret_file")"
    case "$mode" in
        400|600) return 0 ;;
        *) return 1 ;;
    esac
}

ep_codex_key_from_secret_file()
{
    local secret_file="$1"
    EP_CODEX_API_KEY=""
    if ! ep_codex_secret_file_is_safe "$secret_file"; then
        return 1
    fi
    EP_CODEX_API_KEY="$(
        set +e
        # The path is user-specific and validated above.
        # shellcheck disable=SC1090
        . "$secret_file" >/dev/null 2>&1
        printenv OPENAI_API_KEY 2>/dev/null || true
    )"
    [ -n "$EP_CODEX_API_KEY" ]
}

ep_codex_prompt_api_key()
{
    local value
    if [ ! -t 0 ] && [ ! -r /dev/tty ]; then
        return 1
    fi
    if [ -r /dev/tty ]; then
        exec 9</dev/tty
    else
        exec 9<&0
    fi
    printf 'Enter an OpenAI-compatible API key (press Enter to skip): '
    IFS= read -r -s value <&9 || value=""
    printf '\n'
    exec 9<&-
    if [ -n "$value" ]; then
        EP_CODEX_API_KEY="$value"
        return 0
    fi
    unset value
    return 1
}

ep_codex_write_auth()
{
    local auth_file="$HOME/.codex/auth.json"
    local tmp escaped_key
    ep_confirm "Write plaintext API key to $auth_file with mode 600?" "no" || {
        ep_warn "auth.json was not changed. Use: chmod 600 $HOME/.config/secrets/api.env; with_secrets codex"
        return 0
    }
    mkdir -p "$HOME/.codex"
    ep_backup_file "$auth_file"
    escaped_key="$(printf '%s' "$EP_CODEX_API_KEY" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')"
    tmp="$auth_file.tmp.$$"
    printf '{\n  "OPENAI_API_KEY": "%s"\n}\n' "$escaped_key" > "$tmp"
    chmod 600 "$tmp" 2>/dev/null || true
    mv "$tmp" "$auth_file"
    chmod 600 "$auth_file" 2>/dev/null || true
    ep_log "Wrote Codex auth file without printing its value: $auth_file"
}

ep_codex_shell_quote()
{
    local value="${1//\'/\'\\\'\'}"
    printf "'%s'" "$value"
}

ep_codex_persist_api_key()
{
    local secret_file="$HOME/.config/secrets/api.env"
    local tmp line quoted written=0

    ep_ensure_secrets_file
    quoted="$(ep_codex_shell_quote "$1")"
    ep_backup_file "$secret_file"
    tmp="$secret_file.tmp.$$"
    : > "$tmp"
    while IFS= read -r line || [ -n "$line" ]; do
        if [[ "$line" =~ ^[[:space:]]*(export[[:space:]]+)?OPENAI_API_KEY= ]]; then
            if [ "$written" = "0" ]; then
                printf 'export OPENAI_API_KEY=%s\n' "$quoted" >> "$tmp"
                written=1
            fi
        else
            printf '%s\n' "$line" >> "$tmp"
        fi
    done < "$secret_file"
    if [ "$written" = "0" ]; then
        printf '\nexport OPENAI_API_KEY=%s\n' "$quoted" >> "$tmp"
    fi
    chmod 600 "$tmp" || ep_die "Could not restrict secrets file: $secret_file"
    mv "$tmp" "$secret_file" || ep_die "Could not save API key to: $secret_file"
    ep_log "Saved OPENAI_API_KEY to protected secrets file: $secret_file"
}

ep_codex_offer_secret_persistence()
{
    local source="$1"
    local secret_file="$HOME/.config/secrets/api.env"

    [ "$source" = "secret-file" ] && return 0
    if ep_confirm "Save OPENAI_API_KEY to protected $secret_file?" "yes"; then
        ep_codex_persist_api_key "$EP_CODEX_API_KEY"
    else
        ep_warn "API key will remain available only in the current process; no persistent api.env key was written."
    fi
}

ep_codex_configure_auth()
{
    local secret_file
    local key_source=none

    secret_file="$HOME/.config/secrets/api.env"
    ep_ensure_secrets_file
    EP_CODEX_API_KEY=""
    if [ -n "$(printenv OPENAI_API_KEY 2>/dev/null || true)" ]; then
        EP_CODEX_API_KEY="$(printenv OPENAI_API_KEY)"
        key_source=current-environment
        ep_log "Codex API key source: current OPENAI_API_KEY environment variable."
    elif ep_codex_key_from_secret_file "$secret_file"; then
        key_source=secret-file
        ep_log "Codex API key source: protected $secret_file."
    elif [ -n "$(printenv env_key 2>/dev/null || true)" ]; then
        ep_warn "Found lowercase env_key in the environment. The correct variable name is OPENAI_API_KEY."
        if ep_confirm "Use the detected lowercase env_key value as OPENAI_API_KEY?" "yes"; then
            EP_CODEX_API_KEY="$(printenv env_key)"
            key_source=corrected-environment
            ep_log "Codex API key source: corrected lowercase env_key environment variable."
        fi
    fi
    if [ -z "$EP_CODEX_API_KEY" ]; then
        ep_warn "No OPENAI_API_KEY was detected. Obtain an OpenAI-compatible key from your provider, for example YanHuoAPI, and put it in $secret_file or enter it now."
        ep_codex_prompt_api_key || {
            ep_warn "Codex CLI was installed/configured, but no API key was saved and auth.json was not generated. Put a key in $secret_file, then run: with_secrets codex"
            return 0
        }
        key_source=interactive
        ep_log "Codex API key source: interactive input."
    fi
    ep_codex_offer_secret_persistence "$key_source"
    ep_codex_write_auth
    unset EP_CODEX_API_KEY
}

ep_install_codex()
{
    ep_require_unix_runtime
    local action
    action=configured
    ep_log "Component: codex"
    ep_log "Package: $EP_CODEX_PACKAGE"
    ep_log "Codex config uses env_key=OPENAI_API_KEY; installer will detect a key and ask before writing auth.json."
    ep_confirm "Install/update and configure Codex CLI?" "yes" || {
        ep_report_event codex skipped "user declined" "" "" ""
        return 0
    }

    ep_ensure_node
    ep_command_exists npm || ep_die "npm is required after Node.js installation"
    if ! ep_command_exists codex; then
        action=installed
        ep_log "Installing the latest compatible Codex CLI from the npm registry: $EP_CODEX_PACKAGE"
        ep_log "npm executable: $(command -v npm)"
        ep_log "npm global prefix: $(npm config get prefix 2>/dev/null || printf unknown)"
        if ! npm install -g "$EP_CODEX_PACKAGE"; then
            ep_die "npm failed to install $EP_CODEX_PACKAGE"
        fi
        hash -r
        ep_command_exists codex || ep_die "npm completed but the codex command is not available in PATH"
        ep_log "Codex CLI installed: $(codex --version 2>/dev/null || printf 'version unavailable')"
    elif [ "$EP_UPGRADE" = "1" ]; then
        action=updated
        ep_log "Updating Codex CLI from $(codex --version 2>/dev/null || printf unknown) using npm package $EP_CODEX_PACKAGE."
        if ! npm install -g "$EP_CODEX_PACKAGE"; then
            ep_die "npm failed to update $EP_CODEX_PACKAGE"
        fi
        hash -r
        ep_command_exists codex || ep_die "npm completed but the codex command is not available in PATH"
        ep_log "Codex CLI update complete: $(codex --version 2>/dev/null || printf 'version unavailable')"
    else
        ep_log "Codex CLI already exists at $(command -v codex); keeping the installed executable and updating config."
    fi
    ep_write_codex_config
    ep_codex_configure_auth
    ep_state_mark_done codex
    ep_report_event codex "$action" "installed or updated Codex and configured env_key" "$(codex --version 2>/dev/null || true)" "npm:$EP_CODEX_PACKAGE" "$(command -v codex 2>/dev/null || true)"
}
