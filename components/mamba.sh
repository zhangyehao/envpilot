#!/usr/bin/env bash

ep_doctor_mamba()
{
    if ep_command_exists mamba; then
        ep_log "Mamba: found at $(command -v mamba)"
    else
        ep_warn "Mamba: not found"
    fi
}

ep_install_mamba()
{
    ep_require_unix_runtime
    if ep_command_exists mamba; then
        ep_log "Mamba already available: $(command -v mamba)"
        ep_state_mark_done mamba
        ep_report_event mamba skipped "already installed" "$(mamba --version 2>/dev/null || true)" "" "$(command -v mamba)"
        return 0
    fi

    local conda_path
    conda_path="$(ep_conda_bin 2>/dev/null || true)"
    [ -n "$conda_path" ] || ep_die "Conda is required before installing mamba. Run: bash envpilot.sh install conda"

    ep_log "Component: mamba"
    ep_log "Mamba will be installed into Conda base, not used for tmux."
    ep_confirm "Install mamba with conda-forge?" "yes" || {
        ep_report_event mamba skipped "user declined" "" "" ""
        return 0
    }

    "$conda_path" install -n base -y -c conda-forge mamba
    ep_state_mark_done mamba
    ep_report_event mamba installed "installed into Conda base" "$(mamba --version 2>/dev/null || true)" "conda-forge" "$(command -v mamba 2>/dev/null || true)"
}

