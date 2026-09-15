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
# shellcheck source=lib/config.sh
. "$ENVPILOT_ROOT/lib/config.sh"

for __envpilot_component in "$ENVPILOT_ROOT"/components/*.sh; do
    # shellcheck source=/dev/null
    . "$__envpilot_component"
done
unset __envpilot_component

usage()
{
    if [ "${ENVPILOT_LANG:-${LANG:-}}" = zh-CN ] || [[ "${ENVPILOT_LANG:-${LANG:-}}" == zh_* ]]; then
        cat <<'EOF'
envpilot — 用户态环境安装与维护

  envpilot init                         创建统一配置
  envpilot config edit|validate|show     编辑、校验或查看配置
  envpilot plan                         查看拟议变更
  envpilot apply [--yes --non-interactive] 应用配置
  envpilot install|update [组件]         安装或更新组件
  envpilot doctor                       只诊断，不覆盖恢复点
  envpilot snapshot                     创建恢复快照
  envpilot restore [快照路径]            恢复快照（兼容旧 baseline）
  envpilot apply-shell                  接入 Shell，保留原 profile
  envpilot shell remove                 移除受管加载块
  envpilot run -- 命令 参数              在选定环境中运行子进程
  envpilot codex remote status|enable|ready|restart|stop|repair|disable
  envpilot mihomo start|stop|status|ports|update-subscription
  envpilot self-update                  更新 envpilot 和受管脚本

通用选项：--config 路径，--lang auto|en|zh-CN，--mode online|offline，
          --prefix 路径，--yes，--non-interactive，--help
EOF
        return
    fi
    cat <<'EOF'
envpilot - cross-platform user-space environment bootstrapper

Configuration workflow:
  envpilot init                         Create configuration without overwriting it.
  envpilot config edit|validate|show     Edit, validate or inspect configuration.
  envpilot plan                         Preview changes.
  envpilot apply [--yes --non-interactive] Apply configured components and integration.
  envpilot snapshot                     Create an immutable recovery point.
  envpilot shell remove                 Remove only the managed profile block.
  envpilot run -- COMMAND [ARGS...]      Run a child with the configured environment.
  envpilot self-update                  Update envpilot and installed management scripts.

Usage:
  envpilot doctor             Show status and capture a restore baseline.
  envpilot install [all|git|python|mihomo|conda|mamba|codex|github|tmux] [--mode online|offline] [--prefix PATH] [--asset-path PATH] [--upgrade] [--yes]
                                      Install the selected component(s). Online is the default.
  envpilot update [all|git|python|mihomo|conda|mamba|codex|github|tmux]
                                       Re-check compatible latest versions and update existing envpilot components.
  envpilot apply-shell [--yes]
                                      Back up and replace the active shell profile.
  envpilot setup-command      Install ~/.local/bin/envpilot without replacing the shell profile.
  envpilot rollback           Restore the most recent envpilot-managed backup.
  envpilot restore            Restore envpilot-managed changes to the latest doctor baseline.
  envpilot mihomo [start|stop|status|port PORT|ports PROXY_PORT API_PORT|update-subscription [URL]]
                                      Manage Mihomo, its two local ports, and subscription config.
  envpilot codex remote [status|enable|stage|ready|warm|restart|stop|repair|disable]
                                      Stage Codex on node-local storage and manage app-server warmup.
  envpilot resume             Continue an interrupted install using saved state.
  envpilot reset              Clear saved state so install steps can run again.
  envpilot update-manifests   Refresh manifest latest metadata from upstream.
  envpilot update-mihomo-cache
                                      Refresh the bundled stable mihomo assets in downloads/.
  envpilot self-test          Run the repo test suite.

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
    EP_ACTION=""
    EP_RUN_ARGS=()
    case "$EP_COMMAND" in
        config|shell|restore)
            if [ -n "${1:-}" ] && [[ "$1" != -* ]]; then EP_ACTION="$1"; shift; fi ;;
    esac
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
    if [ "$EP_COMMAND" = "codex" ] && [ "${1:-}" != "" ]; then
        arg="${1%$'\r'}"
        if [ "${arg#-}" = "$arg" ]; then
            EP_CODEX_ACTION="$arg"
            shift
        fi
    fi
    if [ "$EP_COMMAND" = "codex" ] && [ "${1:-}" != "" ]; then
        arg="${1%$'\r'}"
        if [ "${arg#-}" = "$arg" ]; then
            EP_CODEX_VALUE="$arg"
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
                export ENVPILOT_MODE="$EP_MODE"
                unset ENVPILOT_MANAGED_ENVPILOT_MODE
                shift 2
                ;;
            --prefix)
                EP_PREFIX="${2:-}"
                EP_PREFIX="${EP_PREFIX%$'\r'}"
                [ -n "$EP_PREFIX" ] || ep_die "--prefix requires a path"
                export ENVPILOT_PREFIX="$EP_PREFIX"
                unset ENVPILOT_MANAGED_ENVPILOT_PREFIX
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
                export ENVPILOT_CONDA_DISTRIBUTION="$EP_CONDA_DISTRIBUTION"
                unset ENVPILOT_MANAGED_ENVPILOT_CONDA_DISTRIBUTION
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
            --lang)
                [ -n "${2:-}" ] || ep_die '--lang requires a value'
                export ENVPILOT_LANG="$2"; unset ENVPILOT_MANAGED_ENVPILOT_LANG; shift 2 ;;
            --config)
                [ -n "${2:-}" ] || ep_die '--config requires a path'
                EP_CONFIG_FILE="$2"; shift 2 ;;
            --non-interactive)
                EP_NON_INTERACTIVE=1; export EP_NON_INTERACTIVE; shift ;;
            --)
                shift; EP_RUN_ARGS=("$@"); break ;;
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
    ep_doctor_command
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
    if [ "${EP_CONFIG_APPLY:-0}" != 1 ]; then ep_snapshot; fi
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
    if [ -n "${EP_ACTION:-}" ] || [ -r "$EP_CONFIG_DIR/latest-snapshot" ]; then
        ep_core restore ${EP_ACTION:+"$EP_ACTION"}
    else
        ep_restore_doctor_baseline
    fi
}

run_mihomo()
{
    ep_init
    ep_platform_detect
    if [ "${ENVPILOT_LANG:-auto}" = zh-CN ]; then
        ep_mihomo_cli "$EP_MIHOMO_ACTION" "$EP_MIHOMO_PORT" "$EP_MIHOMO_VALUE2" | "$(ep_core_path)" message --stream --lang zh-CN
    else
        ep_mihomo_cli "$EP_MIHOMO_ACTION" "$EP_MIHOMO_PORT" "$EP_MIHOMO_VALUE2"
    fi
}

run_codex()
{
    ep_init
    ep_platform_detect
    ep_codex_remote_cli "$EP_CODEX_ACTION" "$EP_CODEX_VALUE"
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
        help|-h|--help|self-test|update-manifests|update-mihomo-cache) ;;
        init) ep_ensure_core; ep_core init --lang "${ENVPILOT_LANG:-auto}"; return ;;
        config)
            if [ "${EP_ACTION:-show}" = edit ]; then "${EDITOR:-vi}" "${EP_CONFIG_FILE:-${ENVPILOT_CONFIG_DIR:-$HOME/.config/envpilot}/config.yaml}"; return; fi
            case "${EP_ACTION:-show}" in validate|show) ep_core "${EP_ACTION:-show}" ;; *) ep_die "Use envpilot config edit, validate or show." ;; esac
            return ;;
        plan) ep_core plan; return ;;

        *) ep_config_load || return ;;
    esac
    case "$EP_COMMAND" in
        config)
            case "${EP_ACTION:-show}" in
                edit) "${EDITOR:-vi}" "${EP_CONFIG_FILE:-${ENVPILOT_CONFIG_DIR:-$HOME/.config/envpilot}/config.yaml}" ;;
                validate|show) ep_core "${EP_ACTION:-show}" ;;
                *) ep_die 'Use envpilot config edit, validate or show.' ;;
            esac ;;
        plan) ep_core plan ;;
        apply) ep_apply_config ;;
        snapshot) ep_snapshot ;;
        run) "$(ep_core_path)" run --config "${EP_CONFIG_FILE:-${ENVPILOT_CONFIG_DIR:-$HOME/.config/envpilot}/config.yaml}" -- "${EP_RUN_ARGS[@]}" ;;
        shell) ep_init; ep_platform_detect; ep_core shell "${EP_ACTION:-install}" --shell "$(basename "${SHELL:-bash}")" ;;
        self-update) ep_self_update ;;
        doctor) run_doctor ;;
        install) run_install ;;
        update|upgrade) run_update ;;
        apply-shell) run_apply_shell ;;
        setup-command) ep_init; ep_setup_command ;;
        rollback) ep_init; ep_rollback_latest ;;
        restore) run_restore ;;
        mihomo) run_mihomo ;;
        codex) run_codex ;;
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
