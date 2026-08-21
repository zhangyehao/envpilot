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

ep_conda_prefix_from_bin()
{
    local conda_path="$1"
    local bin_dir
    bin_dir="$(cd "$(dirname "$conda_path")" && pwd)"
    case "$(basename "$bin_dir")" in
        bin|condabin|Scripts) dirname "$bin_dir" ;;
        *) return 1 ;;
    esac
}

ep_run_conda_clean()
{
    (
        unset LD_LIBRARY_PATH PYTHONHOME PYTHONPATH
        CONDARC="$HOME/.condarc"
        export CONDARC
        "$@"
    )
}

ep_prune_conda_default_seed_config()
{
    local conda_path="$1"
    local prefix prefix_condarc
    prefix="$(ep_conda_prefix_from_bin "$conda_path" 2>/dev/null || true)"
    [ -n "$prefix" ] || return 0
    prefix_condarc="$prefix/.condarc"
    [ -f "$prefix_condarc" ] || return 0

    if awk '
        /^[[:space:]]*(#.*)?$/ { next }
        /^[[:space:]]*channels:[[:space:]]*$/ { channels = 1; next }
        /^[[:space:]]*-[[:space:]]*defaults[[:space:]]*$/ { defaults = 1; next }
        { other = 1 }
        END { exit !(channels && defaults && !other) }
    ' "$prefix_condarc"; then
        if [ -w "$prefix_condarc" ] && [ -w "$prefix" ]; then
            ep_backup_file "$prefix_condarc"
            rm -f "$prefix_condarc"
            ep_log "Removed installer-seeded defaults config: $prefix_condarc"
        else
            ep_warn "Cannot remove installer-seeded defaults config: $prefix_condarc"
        fi
    fi
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
    local conda_path="${1:-}"
    if [ -f "$condarc" ] && cmp -s "$ENVPILOT_ROOT/templates/condarc" "$condarc"; then
        ep_log "Conda channels already match envpilot: $condarc"
    else
        ep_backup_file "$condarc"
        cp "$ENVPILOT_ROOT/templates/condarc" "$condarc.tmp"
        mv "$condarc.tmp" "$condarc"
        ep_log "Wrote Conda channels: $condarc"
    fi
    [ -n "$conda_path" ] && ep_prune_conda_default_seed_config "$conda_path"
}

ep_update_conda()
{
    local conda_path="$1"
    local before_version after_version
    before_version="$(ep_run_conda_clean "$conda_path" --version 2>/dev/null || true)"
    ep_log "Component: conda"
    ep_log "Current Conda: ${before_version:-unknown} at $conda_path"
    ep_log "Update strategy: let Conda resolve the newest compatible base conda package for this platform."
    ep_write_condarc "$conda_path"

    if [ "$EP_MODE" = "offline" ]; then
        ep_warn "Offline mode cannot resolve a newer Conda package; keeping ${before_version:-the current version}."
        ep_state_mark_done conda
        ep_report_event conda skipped "offline update requires a prepared package cache" "$before_version" "$HOME/.condarc" "$conda_path"
        return 0
    fi

    ep_confirm "Update the Conda base command to the newest compatible package?" "yes" || {
        ep_report_event conda skipped "user declined update" "$before_version" "" "$conda_path"
        return 0
    }
    if ! ep_run_conda_clean "$conda_path" update -n base -y conda; then
        ep_report_event conda failed "conda self-update failed" "$before_version" "$HOME/.condarc" "$conda_path"
        ep_die "Conda update failed. The existing installation remains at $conda_path."
    fi
    after_version="$(ep_run_conda_clean "$conda_path" --version 2>/dev/null || true)"
    ep_state_mark_done conda
    ep_report_event conda updated "resolved newest compatible base conda package" "$after_version" "$HOME/.condarc" "$conda_path"
    ep_log "Conda update complete: ${before_version:-unknown} -> ${after_version:-unknown}"
}

ep_install_conda()
{
    ep_require_unix_runtime

    local target target_conda existing_conda installer url source label pattern glibc_version conda_version
    target="$(ep_conda_install_target)"
    target_conda="$target/bin/conda"

    if [ -x "$target_conda" ]; then
        if [ "$EP_UPGRADE" = "1" ]; then
            ep_update_conda "$target_conda"
            return 0
        fi
        ep_log "Conda already available at requested target: $target_conda"
        ep_write_condarc "$target_conda"
        ep_state_mark_done conda
        ep_report_event conda skipped "already installed" "$(ep_run_conda_clean "$target_conda" --version 2>/dev/null || true)" "" "$target_conda"
        return 0
    fi

    if [ -e "$target" ]; then
        ep_die "Conda target exists but does not contain bin/conda: $target. Move it aside or rerun with --prefix."
    fi

    if [ "$(ep_conda_distribution)" = "miniconda" ] && existing_conda="$(ep_conda_bin 2>/dev/null)"; then
        if [ "$EP_UPGRADE" = "1" ]; then
            ep_update_conda "$existing_conda"
            return 0
        fi
        ep_log "Conda already available: $existing_conda"
        ep_write_condarc "$existing_conda"
        ep_state_mark_done conda
        ep_report_event conda skipped "already installed" "$(ep_run_conda_clean "$existing_conda" --version 2>/dev/null || true)" "" "$existing_conda"
        return 0
    fi

    if [ "$(ep_conda_distribution)" = "anaconda" ] && existing_conda="$(ep_conda_bin 2>/dev/null)"; then
        ep_log "Conda already available at $existing_conda, but requested Anaconda target is missing; installing Anaconda side by side."
    fi
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
    ep_log "Conda shell integration is enabled by the managed profile for interactive TTYs; base auto-activation is disabled."
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
    ep_write_condarc "$target_conda"
    ep_state_mark_done conda
    conda_version="$(ep_run_conda_clean "$target_conda" --version 2>/dev/null || true)"
    ep_report_event conda installed "installed $label" "$conda_version" "$source" "$target"
}
