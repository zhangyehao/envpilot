#!/usr/bin/env bash

EP_CODEX_BASE_URL="${EP_CODEX_BASE_URL:-https://yanhuoapi.com/v1}"
EP_CODEX_PACKAGE="${EP_CODEX_PACKAGE:-@openai/codex}"
EP_MIN_NODE_MAJOR="${EP_MIN_NODE_MAJOR:-22}"

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
    # shellcheck disable=SC1091
    [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
}

ep_ensure_node()
{
    local major
    ep_load_nvm
    if ep_command_exists node; then
        major="$(ep_node_major || true)"
        if [ -n "$major" ] && [ "$major" -ge "$EP_MIN_NODE_MAJOR" ]; then
            ep_log "Node.js satisfies requirement: $(node -v)"
            return 0
        fi
        ep_warn "Node.js $(node -v 2>/dev/null || true) is lower than required v$EP_MIN_NODE_MAJOR"
    fi

    ep_command_exists curl || ep_die "curl is required to install nvm/Node.js automatically"
    ep_confirm "Install Node.js LTS via nvm under $HOME/.nvm?" "yes" || ep_die "Node.js $EP_MIN_NODE_MAJOR+ is required for Codex"
    export NVM_DIR="$HOME/.nvm"
    if [ ! -s "$NVM_DIR/nvm.sh" ]; then
        curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash
    fi
    ep_load_nvm
    ep_command_exists nvm || ep_die "nvm did not load; reopen shell and retry"
    nvm install 'lts/*'
    nvm alias default 'lts/*'
    nvm use default
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
        npm install -g "$EP_CODEX_PACKAGE"
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

