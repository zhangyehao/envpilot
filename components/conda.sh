#!/usr/bin/env bash

ep_conda_bin()
{
    if ep_command_exists conda; then
        command -v conda
        return 0
    fi
    for candidate in \
        "$EP_PREFIX/miniforge3/bin/conda" \
        "$EP_PREFIX/miniconda3/bin/conda" \
        "$EP_PREFIX/anaconda3/bin/conda" \
        "$HOME/miniforge3/bin/conda" \
        "$HOME/miniconda3/bin/conda" \
        "$HOME/anaconda3/bin/conda"; do
        [ -x "$candidate" ] && { printf '%s' "$candidate"; return 0; }
    done
    return 1
}

ep_conda_distribution()
{
    case "$EP_OS:$EP_ARCH" in
        linux:amd64|linux:arm64)
            if [ "$EP_LIBC" = "glibc" ]; then
                local glibc_version
                glibc_version="$(ep_linux_glibc_version)"
                [ "$glibc_version" != "unknown" ] || ep_die "Could not determine glibc version for Linux Conda selection."
                if ep_version_at_least "$glibc_version" "2.28"; then
                    printf 'miniconda'
                elif ep_version_at_least "$glibc_version" "2.17"; then
                    printf 'miniforge'
                else
                    ep_die "No bundled Conda installer supports glibc $glibc_version on Linux. Use an offline asset or upgrade glibc."
                fi
            else
                printf 'miniforge'
            fi
            ;;
        darwin:amd64|darwin:arm64|windows:amd64)
            printf 'miniconda'
            ;;
        *) ep_die "No Conda installer rule for $EP_OS/$EP_ARCH. Use --mode offline --asset-path." ;;
    esac
}

ep_conda_distribution_label()
{
    case "$(ep_conda_distribution)" in
        miniforge) printf 'Miniforge' ;;
        miniconda) printf 'Miniconda' ;;
        *) printf 'Conda' ;;
    esac
}

ep_conda_install_target()
{
    case "$(ep_conda_distribution)" in
        miniforge) printf '%s/miniforge3' "$EP_PREFIX" ;;
        miniconda) printf '%s/miniconda3' "$EP_PREFIX" ;;
        *) ep_die "No Conda install target rule for $EP_OS/$EP_ARCH." ;;
    esac
}

ep_conda_offline_pattern()
{
    case "$(ep_conda_distribution)" in
        miniforge) printf 'Miniforge3-*.sh' ;;
        miniconda) printf 'Miniconda3-*.sh' ;;
        *) ep_die "No Conda offline asset pattern for $EP_OS/$EP_ARCH." ;;
    esac
}

ep_conda_installer_url()
{
    case "$EP_OS:$EP_ARCH:$(ep_conda_distribution)" in
        linux:amd64:miniconda) printf 'https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh' ;;
        linux:amd64:miniforge) printf 'https://github.com/conda-forge/miniforge/releases/latest/download/Miniforge3-Linux-x86_64.sh' ;;
        linux:arm64:miniconda) printf 'https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-aarch64.sh' ;;
        linux:arm64:miniforge) printf 'https://github.com/conda-forge/miniforge/releases/latest/download/Miniforge3-Linux-aarch64.sh' ;;
        darwin:amd64:miniconda) printf 'https://repo.anaconda.com/miniconda/Miniconda3-latest-MacOSX-x86_64.sh' ;;
        darwin:arm64:miniconda) printf 'https://repo.anaconda.com/miniconda/Miniconda3-latest-MacOSX-arm64.sh' ;;
        windows:amd64:miniconda) printf 'https://repo.anaconda.com/miniconda/Miniconda3-latest-Windows-x86_64.exe' ;;
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
        ep_report_event conda skipped "already installed" "$($conda_path --version 2>/dev/null || true)" "" "$conda_path"
        return 0
    fi

    local target installer url source label pattern glibc_version
    target="$(ep_conda_install_target)"
    installer="$(mktemp "${TMPDIR:-/tmp}/envpilot-conda.XXXXXX.sh")"
    url="$(ep_conda_installer_url)"
    label="$(ep_conda_distribution_label)"
    pattern="$(ep_conda_offline_pattern)"
    glibc_version="$(ep_linux_glibc_version)"

    ep_log "Component: conda"
    ep_log "Selected $label installer for $EP_OS/$EP_ARCH"
    if [ "$label" = "Miniforge" ] && [ "$EP_LIBC" = "glibc" ]; then
        ep_log "Compatibility note: glibc $glibc_version is below Miniconda's current Linux threshold; using Miniforge latest."
    fi
    ep_log "Install target: $target"
    ep_log "Conda init will not be run; shell templates source conda.sh only when requested."
    ep_confirm "Install Conda to $target?" "yes" || {
        ep_report_event conda skipped "user declined" "" "$url" "$target"
        return 0
    }

    source="$(ep_download_or_offline "$url" "$pattern" "$installer")"
    bash "$installer" -b -p "$target"
    rm -f "$installer"
    ep_write_condarc
    ep_state_mark_done conda
    ep_report_event conda installed "installed $label" "$($target/bin/conda --version 2>/dev/null || true)" "$source" "$target"
}