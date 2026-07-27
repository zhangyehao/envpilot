#!/usr/bin/env bash

ep_conda_bin()
{
    if ep_command_exists conda; then
        command -v conda
        return 0
    fi
    for candidate in \
        "$EP_PREFIX/miniconda3/bin/conda" \
        "$EP_PREFIX/anaconda3/bin/conda" \
        "$HOME/miniconda3/bin/conda" \
        "$HOME/anaconda3/bin/conda"; do
        [ -x "$candidate" ] && { printf '%s' "$candidate"; return 0; }
    done
    return 1
}

ep_conda_installer_url()
{
    case "$EP_OS:$EP_ARCH" in
        linux:amd64) printf 'https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh' ;;
        linux:arm64) printf 'https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-aarch64.sh' ;;
        darwin:amd64) printf 'https://repo.anaconda.com/miniconda/Miniconda3-latest-MacOSX-x86_64.sh' ;;
        darwin:arm64) printf 'https://repo.anaconda.com/miniconda/Miniconda3-latest-MacOSX-arm64.sh' ;;
        *) ep_die "No Conda installer rule for $EP_OS/$EP_ARCH. Use --mode offline --asset-path." ;;
    esac
}

ep_doctor_conda()
{
    if conda_path="$(ep_conda_bin 2>/dev/null)"; then
        ep_log "Conda: found at $conda_path"
    else
        ep_warn "Conda: not found"
    fi
}

ep_write_condarc()
{
    local condarc="$HOME/.condarc"
    ep_backup_file "$condarc"
    cp "$ENVPILOT_ROOT/templates/condarc" "$condarc.tmp"
    mv "$condarc.tmp" "$condarc"
    ep_log "Wrote Conda channels: $condarc"
}

ep_install_conda()
{
    ep_require_unix_runtime
    if conda_path="$(ep_conda_bin 2>/dev/null)"; then
        ep_log "Conda already available: $conda_path"
        ep_write_condarc
        ep_state_mark_done conda
        ep_report_event conda skipped "already installed" "$("$conda_path" --version 2>/dev/null || true)" "" "$conda_path"
        return 0
    fi

    local target installer url source
    target="$EP_PREFIX/miniconda3"
    installer="$(mktemp "${TMPDIR:-/tmp}/envpilot-miniconda.XXXXXX.sh")"
    url="$(ep_conda_installer_url)"

    ep_log "Component: conda"
    ep_log "Selected Miniconda installer for $EP_OS/$EP_ARCH"
    ep_log "Install target: $target"
    ep_log "Conda init will not be run; shell templates source conda.sh only when requested."
    ep_confirm "Install Conda to $target?" "yes" || {
        ep_report_event conda skipped "user declined" "" "$url" "$target"
        return 0
    }

    source="$(ep_download_or_offline "$url" 'Miniconda3-*.sh' "$installer")"
    bash "$installer" -b -p "$target"
    rm -f "$installer"
    ep_write_condarc
    ep_state_mark_done conda
    ep_report_event conda installed "installed Miniconda" "$("$target/bin/conda" --version 2>/dev/null || true)" "$source" "$target"
}

