#!/usr/bin/env bash
set -euo pipefail

ENVPILOT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib/common.sh
. "$ENVPILOT_ROOT/lib/common.sh"
# shellcheck source=lib/platform.sh
. "$ENVPILOT_ROOT/lib/platform.sh"
# shellcheck source=lib/download.sh
. "$ENVPILOT_ROOT/lib/download.sh"
# shellcheck source=lib/manifest.sh
. "$ENVPILOT_ROOT/lib/manifest.sh"
# shellcheck source=lib/shell.sh
. "$ENVPILOT_ROOT/lib/shell.sh"
# shellcheck source=lib/rollback.sh
. "$ENVPILOT_ROOT/lib/rollback.sh"
# shellcheck source=lib/baseline.sh
. "$ENVPILOT_ROOT/lib/baseline.sh"

for __envpilot_component in "$ENVPILOT_ROOT"/components/*.sh; do
    # shellcheck source=/dev/null
    . "$__envpilot_component"
done
unset __envpilot_component

usage()
{
    cat <<'EOF'
envpilot - cross-platform user-space environment bootstrapper

Usage:
  bash envpilot.sh doctor             Show status and capture a restore baseline.
  bash envpilot.sh install [all|git|python|mihomo|conda|mamba|codex|github|tmux] [--mode online|offline] [--prefix PATH] [--asset-path PATH] [--upgrade] [--yes]
                                      Install the selected component(s). Online is the default.
  bash envpilot.sh update [all|git|python|mihomo|conda|mamba|codex|github|tmux]
                                       Re-check compatible latest versions and update existing envpilot components.
  bash envpilot.sh apply-shell [--yes]
                                      Back up and replace the active shell profile.
  bash envpilot.sh rollback           Restore the most recent envpilot-managed backup.
  bash envpilot.sh restore            Restore envpilot-managed changes to the latest doctor baseline.
  bash envpilot.sh mihomo [start|stop|status|port PORT|ports PROXY_PORT API_PORT|update-subscription [URL]]
                                      Manage Mihomo, its two local ports, and subscription config.
  bash envpilot.sh resume             Continue an interrupted install using saved state.
  bash envpilot.sh reset              Clear saved state so install steps can run again.
  bash envpilot.sh update-manifests   Refresh manifest latest metadata from upstream.
  bash envpilot.sh update-mihomo-cache
                                      Refresh the bundled stable mihomo assets in downloads/.
  bash envpilot.sh self-test          Run the repo test suite.

Options:
  --mode online|offline   Prefer live downloads or local downloads/ assets. Default: online.
  --prefix PATH           User-space install root. Default: $HOME/software.
  --asset-path PATH       Explicit offline asset path for the selected component.
  --conda-distribution miniconda|anaconda
                         Conda distribution to install. Default: miniconda.
  --upgrade               Re-evaluate installed components instead of honoring completed state.
  --yes                   Accept low-risk confirmations. Profile/config writes still summarize first.
  -h, --help              Show this help.
EOF
}

parse_args()
{
    local arg
    EP_COMMAND="${1:-help}"
    EP_COMMAND="${EP_COMMAND%$'\r'}"
    shift || true

    EP_COMPONENT="all"
    if { [ "$EP_COMMAND" = "install" ] || [ "$EP_COMMAND" = "update" ] || [ "$EP_COMMAND" = "upgrade" ]; } && [ "${1:-}" != "" ]; then
        arg="${1%$'\r'}"
        if [ "${arg#-}" = "$arg" ]; then
            EP_COMPONENT="$arg"
            shift
        fi
    fi
    if [ "$EP_COMMAND" = "mihomo" ] && [ "${1:-}" != "" ]; then
        arg="${1%$'\r'}"
        if [ "${arg#-}" = "$arg" ]; then
            EP_MIHOMO_ACTION="$arg"
            shift
        fi
    fi
    if [ "$EP_COMMAND" = "mihomo" ] && [ "${1:-}" != "" ]; then
        arg="${1%$'\r'}"
        if [ "${arg#-}" = "$arg" ]; then
            EP_MIHOMO_PORT="$arg"
            shift
        fi
    fi
    if [ "$EP_COMMAND" = "mihomo" ] && [ "${1:-}" != "" ]; then
        arg="${1%$'\r'}"
        if [ "${arg#-}" = "$arg" ]; then
            EP_MIHOMO_VALUE2="$arg"
            shift
        fi
    fi

    while [ "$#" -gt 0 ]; do
        arg="${1%$'\r'}"
        case "$arg" in
            --mode)
                EP_MODE="${2:-}"
                EP_MODE="${EP_MODE%$'\r'}"
                [ "$EP_MODE" = "online" ] || [ "$EP_MODE" = "offline" ] || ep_die "--mode must be online or offline"
                shift 2
                ;;
            --prefix)
                EP_PREFIX="${2:-}"
                EP_PREFIX="${EP_PREFIX%$'\r'}"
                [ -n "$EP_PREFIX" ] || ep_die "--prefix requires a path"
                shift 2
                ;;
            --asset-path)
                EP_ASSET_PATH="${2:-}"
                EP_ASSET_PATH="${EP_ASSET_PATH%$'\r'}"
                [ -n "$EP_ASSET_PATH" ] || ep_die "--asset-path requires a path"
                shift 2
                ;;
            --conda-distribution)
                EP_CONDA_DISTRIBUTION="${2:-}"
                EP_CONDA_DISTRIBUTION="${EP_CONDA_DISTRIBUTION%$'\r'}"
                case "$EP_CONDA_DISTRIBUTION" in
                    miniconda|anaconda) ;;
                    *) ep_die "--conda-distribution must be miniconda or anaconda" ;;
                esac
                shift 2
                ;;
            --upgrade|-u)
                EP_UPGRADE="1"
                shift
                ;;
            --yes|-y)
                EP_ASSUME_YES="1"
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                ep_die "Unknown option: $arg"
                ;;
        esac
    done
}

run_doctor()
{
    ep_init
    ep_platform_detect
    ep_log "envpilot doctor"
    ep_platform_print
    ep_capture_doctor_baseline
    ep_doctor_git
    ep_doctor_python
    ep_doctor_conda
    ep_doctor_mamba
    ep_doctor_mihomo
    ep_doctor_codex
    ep_doctor_github
    ep_doctor_tmux
}

install_one()
{
    local component="$1"
    case "$component" in
        git) ep_install_git ;;
        python) ep_install_python ;;
        conda) ep_install_conda ;;
        mamba) ep_install_mamba ;;
        mihomo) ep_install_mihomo ;;
        codex) ep_install_codex ;;
        github) ep_install_github ;;
        tmux) ep_install_tmux ;;
        *) ep_die "Unknown component: $component" ;;
    esac
}

ep_install_no_proxy_add()
{
    local value="${1:-}"
    [ -n "$value" ] || return 0
    no_proxy="${no_proxy:-${NO_PROXY:-}}"
    case ",${no_proxy:-}," in
        *",$value,"*) ;;
        *) no_proxy="${no_proxy:+$no_proxy,}$value" ;;
    esac
    export no_proxy
    export NO_PROXY="$no_proxy"
}

ep_prepare_install_proxy()
{
    local config proxy_port
    config="$(ep_mihomo_config_file 2>/dev/null || true)"
    [ -s "$config" ] || {
        ep_warn "Install proxy unavailable: Mihomo config not found at ${config:-$HOME/.config/mihomo/config.yaml}; continuing without proxy."
        return 1
    }

    proxy_port="$(ep_mihomo_proxy_port)"
    if ! ep_proxy_port_is_listening 127.0.0.1 "$proxy_port"; then
        ep_log "Preparing envpilot-managed Mihomo before the next installation step."
        if ! MIHOMO_PROXY_PORT="$proxy_port" MIHOMO_API_PORT="$(ep_mihomo_api_port)" ep_start_mihomo; then
            ep_warn "Mihomo could not be started on 127.0.0.1:$proxy_port; subsequent downloads will use direct network if available."
            return 1
        fi
    fi
    if ! ep_proxy_port_is_listening 127.0.0.1 "$proxy_port"; then
        ep_warn "Mihomo proxy port 127.0.0.1:$proxy_port is not listening; continuing without proxy."
        return 1
    fi

    export http_proxy="http://127.0.0.1:$proxy_port"
    export https_proxy="$http_proxy"
    export HTTP_PROXY="$http_proxy"
    export HTTPS_PROXY="$https_proxy"
    if [ "${BASHRC_PROXY_ENABLE_SOCKS:-0}" = "1" ]; then
        export all_proxy="socks5h://127.0.0.1:$proxy_port"
        export ALL_PROXY="$all_proxy"
    else
        unset all_proxy ALL_PROXY
    fi
    ep_install_no_proxy_add localhost
    ep_install_no_proxy_add 127.0.0.1
    ep_install_no_proxy_add ::1
    ep_log "Proxy ready for subsequent installation steps: http://127.0.0.1:$proxy_port"
    return 0
}

run_install()
{
    local action="install" component proxy_attempted
    [ "$EP_UPGRADE" = "1" ] && action="update"
    ep_init
    ep_platform_detect
    ep_report_start "$action" "$EP_COMPONENT"

    case "$EP_COMPONENT" in
        all)
            proxy_attempted=0
            for component in mihomo git python conda mamba codex github tmux; do
                if [ "$component" != "mihomo" ] && [ "$proxy_attempted" = "0" ]; then
                    ep_prepare_install_proxy || true
                    proxy_attempted=1
                fi
                if ep_state_is_done "$component" && [ "$EP_UPGRADE" != "1" ]; then
                    ep_log "Skip $component: already marked done. Use update or --upgrade to re-check versions."
                    ep_report_event "$component" "skipped" "already marked done" "" "" ""
                    continue
                fi
                if ep_state_is_done "$component"; then
                    ep_log "Re-checking installed $component for compatible updates."
                fi
                install_one "$component"
                if [ "$component" = "mihomo" ]; then
                    ep_prepare_install_proxy || true
                    proxy_attempted=1
                fi
            done
            ;;
        git|python|mihomo|conda|mamba|codex|github|tmux)
            if [ "$EP_COMPONENT" != "mihomo" ]; then
                ep_prepare_install_proxy || true
            fi
            install_one "$EP_COMPONENT"
            ;;
        *)
            ep_die "Unknown component: $EP_COMPONENT"
            ;;
    esac

    ep_report_finish
    ep_log "Install report: $EP_REPORT_FILE"
}

run_update()
{
    EP_UPGRADE="1"
    run_install
}

run_apply_shell()
{
    ep_init
    ep_platform_detect
    ep_apply_shell_profile
}

run_resume()
{
    ep_init
    if [ ! -s "$EP_STATE_FILE" ]; then
        ep_log "No interrupted or partial state found."
        return 0
    fi
    ep_log "Current state:"
    sed 's/^/  /' "$EP_STATE_FILE"
    ep_log "Resuming install all with completed stages skipped."
    EP_COMPONENT="all"
    run_install
}

run_restore()
{
    ep_init
    ep_platform_detect
    ep_restore_doctor_baseline
}

run_mihomo()
{
    ep_init
    ep_platform_detect
    ep_mihomo_cli "$EP_MIHOMO_ACTION" "$EP_MIHOMO_PORT" "$EP_MIHOMO_VALUE2"
}

run_reset()
{
    ep_init
    if [ -e "$EP_STATE_FILE" ]; then
        rm -f "$EP_STATE_FILE"
        ep_log "Removed state file: $EP_STATE_FILE"
    else
        ep_log "No state file to remove."
    fi
}

run_update_manifests()
{
    ep_update_manifests
}

run_update_mihomo_cache()
{
    local python
    python="$(command -v python3 || command -v python || true)"
    [ -n "$python" ] || ep_die "python3 or python is required to refresh the mihomo cache"
    "$python" "$ENVPILOT_ROOT/scripts/update-mihomo-cache.py"
}

run_self_test()
{
    bash "$ENVPILOT_ROOT/tests/run-tests.sh"
}

main()
{
    parse_args "$@"
    case "$EP_COMMAND" in
        doctor) run_doctor ;;
        install) run_install ;;
        update|upgrade) run_update ;;
        apply-shell) run_apply_shell ;;
        rollback) ep_init; ep_rollback_latest ;;
        restore) run_restore ;;
        mihomo) run_mihomo ;;
        resume) run_resume ;;
        reset) run_reset ;;
        update-manifests) run_update_manifests ;;
        update-mihomo-cache) run_update_mihomo_cache ;;
        self-test) run_self_test ;;
        help|-h|--help) usage ;;
        *) usage; exit 2 ;;
    esac
}

main "$@"
