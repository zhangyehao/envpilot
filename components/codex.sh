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

ep_install_codex()
{
    ep_require_unix_runtime
    ep_log "Component: codex"
    ep_log "Package: $EP_CODEX_PACKAGE"
    ep_log "Config uses env_key=OPENAI_API_KEY; auth.json is not generated."
    ep_confirm "Install/configure Codex CLI?" "yes" || {
        ep_report_event codex skipped "user declined" "" "" ""
        return 0
    }

    ep_ensure_node
    ep_command_exists npm || ep_die "npm is required after Node.js installation"
    if ! ep_command_exists codex; then
        ep_log "Installing Codex CLI from the npm registry: $EP_CODEX_PACKAGE"
        ep_log "npm executable: $(command -v npm)"
        ep_log "npm global prefix: $(npm config get prefix 2>/dev/null || printf unknown)"
        if ! npm install -g "$EP_CODEX_PACKAGE"; then
            ep_die "npm failed to install $EP_CODEX_PACKAGE"
        fi
        hash -r
        ep_command_exists codex || ep_die "npm completed but the codex command is not available in PATH"
        ep_log "Codex CLI installed: $(codex --version 2>/dev/null || printf 'version unavailable')"
    else
        ep_log "Codex CLI already exists at $(command -v codex); keeping the installed executable and updating config."
    fi
    ep_write_codex_config
    mkdir -p "$HOME/.config/secrets"
    if [ ! -f "$HOME/.config/secrets/api.env" ]; then
        cp "$ENVPILOT_ROOT/templates/api.env.example" "$HOME/.config/secrets/api.env.example"
        chmod 600 "$HOME/.config/secrets/api.env.example" 2>/dev/null || true
        ep_warn "Add OPENAI_API_KEY to $HOME/.config/secrets/api.env before running: with_secrets codex"
    fi
    ep_state_mark_done codex
    ep_report_event codex installed "configured Codex with env_key" "$(codex --version 2>/dev/null || true)" "npm:$EP_CODEX_PACKAGE" "$(command -v codex 2>/dev/null || true)"
}

