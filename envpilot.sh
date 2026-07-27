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
  bash envpilot.sh doctor
  bash envpilot.sh install [all|conda|mamba|mihomo|codex|github|tmux] [--mode online|offline] [--prefix PATH] [--asset-path PATH] [--yes]
  bash envpilot.sh apply-shell [--yes]
  bash envpilot.sh rollback
  bash envpilot.sh resume
  bash envpilot.sh reset
  bash envpilot.sh update-manifests
  bash envpilot.sh self-test

Options:
  --mode online|offline   Prefer live downloads or local downloads/ assets. Default: online.
  --prefix PATH           User-space install root. Default: $HOME/software.
  --asset-path PATH       Explicit offline asset path for the selected component.
  --yes                   Accept low-risk confirmations. Profile/config writes still summarize first.
  -h, --help              Show this help.
EOF
}

parse_args()
{
    EP_COMMAND="${1:-help}"
    shift || true

    EP_COMPONENT="all"
    if [ "$EP_COMMAND" = "install" ] && [ "${1:-}" != "" ] && [ "${1#-}" = "$1" ]; then
        EP_COMPONENT="$1"
        shift
    fi

    while [ "$#" -gt 0 ]; do
        case "$1" in
            --mode)
                EP_MODE="${2:-}"
                [ "$EP_MODE" = "online" ] || [ "$EP_MODE" = "offline" ] || ep_die "--mode must be online or offline"
                shift 2
                ;;
            --prefix)
                EP_PREFIX="${2:-}"
                [ -n "$EP_PREFIX" ] || ep_die "--prefix requires a path"
                shift 2
                ;;
            --asset-path)
                EP_ASSET_PATH="${2:-}"
                [ -n "$EP_ASSET_PATH" ] || ep_die "--asset-path requires a path"
                shift 2
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
                ep_die "Unknown option: $1"
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
        conda) ep_install_conda ;;
        mamba) ep_install_mamba ;;
        mihomo) ep_install_mihomo ;;
        codex) ep_install_codex ;;
        github) ep_install_github ;;
        tmux) ep_install_tmux ;;
        *) ep_die "Unknown component: $component" ;;
    esac
}

run_install()
{
    ep_init
    ep_platform_detect
    ep_report_start "install" "$EP_COMPONENT"

    case "$EP_COMPONENT" in
        all)
            for component in conda mamba mihomo codex github tmux; do
                if ep_state_is_done "$component"; then
                    ep_log "Skip $component: already marked done. Use reset to clear state."
                    ep_report_event "$component" "skipped" "already marked done" "" "" ""
                    continue
                fi
                install_one "$component"
            done
            ;;
        conda|mamba|mihomo|codex|github|tmux)
            install_one "$EP_COMPONENT"
            ;;
        *)
            ep_die "Unknown component: $EP_COMPONENT"
            ;;
    esac

    ep_report_finish
    ep_log "Install report: $EP_REPORT_FILE"
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
    ep_init
    ep_platform_detect
    ep_update_manifests
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
        apply-shell) run_apply_shell ;;
        rollback) ep_init; ep_rollback_latest ;;
        resume) run_resume ;;
        reset) run_reset ;;
        update-manifests) run_update_manifests ;;
        self-test) run_self_test ;;
        help|-h|--help) usage ;;
        *) usage; exit 2 ;;
    esac
}

main "$@"

