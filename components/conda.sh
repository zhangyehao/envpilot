#!/usr/bin/env bash

EP_LEGACY_MINICONDA_VERSION="${EP_LEGACY_MINICONDA_VERSION:-py312_24.11.1-0}"
EP_LEGACY_ANACONDA_VERSION="${EP_LEGACY_ANACONDA_VERSION:-2025.06-1}"

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

ep_conda_distribution()
{
    case "${EP_CONDA_DISTRIBUTION:-miniconda}" in
        miniconda|anaconda) printf '%s' "$EP_CONDA_DISTRIBUTION" ;;
        *) ep_die "Unsupported Conda distribution: $EP_CONDA_DISTRIBUTION. Use miniconda or anaconda." ;;
    esac
}

ep_conda_distribution_label()
{
    case "$(ep_conda_distribution)" in
        miniconda) printf 'Miniconda' ;;
        anaconda) printf 'Anaconda' ;;
        *) printf 'Conda' ;;
    esac
}

ep_conda_install_target()
{
    case "$(ep_conda_distribution)" in
        miniconda) printf '%s/miniconda3' "$EP_PREFIX" ;;
        anaconda) printf '%s/anaconda3' "$EP_PREFIX" ;;
        *) ep_die "No Conda install target rule for $EP_OS/$EP_ARCH." ;;
    esac
}

ep_conda_offline_pattern()
{
    case "$(ep_conda_distribution):$EP_OS" in
        miniconda:windows*) printf 'Miniconda3-*.exe' ;;
        miniconda:*) printf 'Miniconda3-*.sh' ;;
        anaconda:windows*) printf 'Anaconda3-*.exe' ;;
        anaconda:*) printf 'Anaconda3-*.sh' ;;
        *) ep_die "No Conda offline asset pattern for $EP_OS/$EP_ARCH." ;;
    esac
}

ep_conda_uses_legacy_miniconda()
{
    [ "$(ep_conda_distribution)" = "miniconda" ] || return 1
    [ "$EP_OS" = "linux" ] || return 1
    [ "$EP_LIBC" = "glibc" ] || return 1
    [ "$EP_GLIBC_VERSION" != "unknown" ] || return 1
    ! ep_version_at_least "$EP_GLIBC_VERSION" "2.28"
}

ep_conda_uses_legacy_anaconda()
{
    [ "$(ep_conda_distribution)" = "anaconda" ] || return 1
    [ "$EP_OS" = "linux" ] || return 1
    [ "$EP_LIBC" = "glibc" ] || return 1
    [ "$EP_GLIBC_VERSION" != "unknown" ] || return 1
    ! ep_version_at_least "$EP_GLIBC_VERSION" "2.28"
}

ep_conda_installer_url()
{
    local dist
    dist="$(ep_conda_distribution)"
    case "$EP_OS:$EP_ARCH:$dist" in
        linux:amd64:miniconda)
            if ep_conda_uses_legacy_miniconda; then
                printf 'https://repo.anaconda.com/miniconda/Miniconda3-%s-Linux-x86_64.sh' "$EP_LEGACY_MINICONDA_VERSION"
            else
                printf 'https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh'
            fi
            ;;
        linux:arm64:miniconda)
            if ep_conda_uses_legacy_miniconda; then
                printf 'https://repo.anaconda.com/miniconda/Miniconda3-%s-Linux-aarch64.sh' "$EP_LEGACY_MINICONDA_VERSION"
            else
                printf 'https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-aarch64.sh'
            fi
            ;;
        linux:amd64:anaconda)
            if ep_conda_uses_legacy_anaconda; then
                printf 'https://repo.anaconda.com/archive/Anaconda3-%s-Linux-x86_64.sh' "$EP_LEGACY_ANACONDA_VERSION"
            else
                printf 'https://repo.anaconda.com/archive/Anaconda3-2025.12-2-Linux-x86_64.sh'
            fi
            ;;
        linux:arm64:anaconda)
            if ep_conda_uses_legacy_anaconda; then
                printf 'https://repo.anaconda.com/archive/Anaconda3-%s-Linux-aarch64.sh' "$EP_LEGACY_ANACONDA_VERSION"
            else
                printf 'https://repo.anaconda.com/archive/Anaconda3-2025.12-2-Linux-aarch64.sh'
            fi
            ;;
        darwin:amd64:miniconda) printf 'https://repo.anaconda.com/miniconda/Miniconda3-latest-MacOSX-x86_64.sh' ;;
        darwin:arm64:miniconda) printf 'https://repo.anaconda.com/miniconda/Miniconda3-latest-MacOSX-arm64.sh' ;;
        darwin:amd64:anaconda) printf 'https://repo.anaconda.com/archive/Anaconda3-%s-MacOSX-x86_64.sh' "$EP_LEGACY_ANACONDA_VERSION" ;;
        darwin:arm64:anaconda) printf 'https://repo.anaconda.com/archive/Anaconda3-2025.12-2-MacOSX-arm64.sh' ;;
        windows:amd64:miniconda) printf 'https://repo.anaconda.com/miniconda/Miniconda3-latest-Windows-x86_64.exe' ;;
        windows:amd64:anaconda) printf 'https://repo.anaconda.com/archive/Anaconda3-2025.12-2-Windows-x86_64.exe' ;;
        *) ep_die "No Conda installer rule for $EP_OS/$EP_ARCH/$dist. Use --mode offline --asset-path." ;;
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

    local target installer url source label pattern glibc_version conda_version
    target="$(ep_conda_install_target)"
    installer="$(mktemp "${TMPDIR:-/tmp}/envpilot-conda.XXXXXX.sh")"
    url="$(ep_conda_installer_url)"
    label="$(ep_conda_distribution_label)"
    pattern="$(ep_conda_offline_pattern)"
    glibc_version="$(ep_linux_glibc_version)"
    if [ "$EP_MODE" = "offline" ]; then
        source="$(ep_find_offline_asset "$pattern")"
    else
        source="$url"
    fi

    ep_log "Component: conda"
    ep_log "Selected $label installer for $EP_OS/$EP_ARCH"
    if ep_conda_uses_legacy_miniconda; then
        ep_log "Compatibility note: glibc $glibc_version is below current Miniconda's Linux installer floor; using archived Miniconda $EP_LEGACY_MINICONDA_VERSION."
    fi
    if ep_conda_uses_legacy_anaconda; then
        ep_log "Compatibility note: glibc $glibc_version is below current Anaconda's Linux installer floor; using archived Anaconda $EP_LEGACY_ANACONDA_VERSION."
    elif [ "$label" = "Anaconda" ] && [ "$EP_OS" = "darwin" ] && [ "$EP_ARCH" = "amd64" ]; then
        ep_log "Compatibility note: Anaconda no longer ships a current macOS Intel installer; using archived Anaconda $EP_LEGACY_ANACONDA_VERSION."
    fi
    ep_log "Plan: install $label"
    ep_log "Source: $source"
    ep_log "Target: $target"
    ep_log "Will write: $HOME/.condarc"
    ep_log "Conda init will not be run; shell templates source conda.sh only when requested."
    ep_confirm "Install $label from $source to $target?" "yes" || {
        ep_report_event conda skipped "user declined" "" "$source" "$target"
        return 0
    }

    if [ "$EP_MODE" = "offline" ]; then
        cp "$source" "$installer"
    else
        ep_fetch_url "$source" "$installer"
    fi
    bash "$installer" -b -p "$target"
    rm -f "$installer"
    ep_write_condarc
    ep_state_mark_done conda
    conda_version="$("$target"/bin/conda --version 2>/dev/null || true)"
    ep_report_event conda installed "installed $label" "$conda_version" "$source" "$target"
}
