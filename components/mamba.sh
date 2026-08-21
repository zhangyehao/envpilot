#!/usr/bin/env bash

ep_mamba_bin()
{
    if ep_command_exists mamba; then
        command -v mamba
        return 0
    fi

    local conda_path prefix candidate
    conda_path="$(ep_conda_bin 2>/dev/null || true)"
    [ -n "$conda_path" ] || return 1
    prefix="$(ep_conda_prefix_from_bin "$conda_path" 2>/dev/null || true)"
    [ -n "$prefix" ] || return 1
    for candidate in \
        "$prefix/bin/mamba" \
        "$prefix/condabin/mamba" \
        "$prefix/Scripts/mamba.exe"; do
        [ -x "$candidate" ] && { printf '%s' "$candidate"; return 0; }
    done
    return 1
}

ep_mamba_version()
{
    ep_run_conda_clean "$1" --version 2>/dev/null || true
}

ep_doctor_mamba()
{
    local mamba_path
    if mamba_path="$(ep_mamba_bin 2>/dev/null)"; then
        ep_log "Mamba: found at $mamba_path"
    else
        ep_warn "Mamba: not found"
    fi
}

ep_install_mamba()
{
    ep_require_unix_runtime
    local conda_path mamba_path install_status version action prompt solver_note
    local -a conda_install_args
    action=installed
    if mamba_path="$(ep_mamba_bin 2>/dev/null)"; then
        if [ "$EP_UPGRADE" != "1" ]; then
            ep_log "Mamba already available: $mamba_path"
            ep_state_mark_done mamba
            ep_report_event mamba skipped "already installed; use update mamba to refresh" "$(ep_mamba_version "$mamba_path")" "" "$mamba_path"
            return 0
        fi
        action=updated
        ep_log "Current Mamba: $(ep_mamba_version "$mamba_path") at $mamba_path"
    fi

    conda_path="$(ep_conda_bin 2>/dev/null || true)"
    [ -n "$conda_path" ] || ep_die "Conda is required before installing mamba. Run: bash envpilot.sh install conda"

    ep_log "Component: mamba"
    ep_log "Mamba will be installed into Conda base, not used for tmux."
    ep_log "Channels: TUNA conda-forge and bioconda mirrors only; inherited defaults are disabled."
    ep_log "Conda will resolve the newest Mamba package compatible with the current base environment."
    ep_log "Conda command environment: LD_LIBRARY_PATH, PYTHONHOME, and PYTHONPATH will be isolated."
    ep_log "Bootstrap channels: $EP_CONDA_FORGE_CHANNEL and $EP_BIOCONDA_CHANNEL (override inherited Conda channels)."
    prompt=Install
    [ "$action" = updated ] && prompt=Update
    ep_confirm "$prompt mamba using the configured mirror channels?" "yes" || {
        ep_report_event mamba skipped "user declined" "" "" ""
        return 0
    }

    if [ -f "$HOME/.condarc" ]; then
        ep_log "Preserving existing Conda config: $HOME/.condarc"
    else
        ep_log "No $HOME/.condarc; explicit mirror channels will be used for this transaction."
    fi
    conda_install_args=(
        install -n base -y
        --override-channels
        -c "$EP_CONDA_FORGE_CHANNEL"
        -c "$EP_BIOCONDA_CHANNEL"
    )
    solver_note="$(ep_conda_preferred_solver "$conda_path")"
    conda_install_args+=(--solver "$solver_note")
    if [ "$solver_note" = "libmamba" ]; then
        ep_log "Conda libmamba solver is available; using it for the Mamba transaction."
    else
        ep_log "Mamba is not available yet; using Conda classic solver for bootstrap. The first solve may take several minutes."
    fi
    conda_install_args+=(mamba)
    ep_log "Conda bootstrap solver: $solver_note"
    if ep_run_conda_clean "$conda_path" "${conda_install_args[@]}"; then
        install_status=0
    else
        install_status=$?
    fi

    mamba_path="$(ep_mamba_bin 2>/dev/null || true)"
    if [ -z "$mamba_path" ] || ! ep_run_conda_clean "$mamba_path" --version >/dev/null 2>&1; then
        ep_report_event mamba failed "conda install/update failed with exit $install_status" "" "$HOME/.condarc" ""
        ep_die "Mamba installation or update failed (conda exit $install_status). Review the Conda error above, then run: bash envpilot.sh update mamba"
    fi
    if [ "$install_status" -ne 0 ]; then
        ep_warn "Conda returned exit $install_status after the transaction, but the installed mamba executable passed verification; continuing."
    fi

    version="$(ep_mamba_version "$mamba_path")"
    ep_state_mark_done mamba
    ep_report_event mamba "$action" "resolved newest compatible Mamba into Conda base" "$version" "$HOME/.condarc" "$mamba_path"
}
