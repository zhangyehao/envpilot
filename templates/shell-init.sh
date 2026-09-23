# envpilot 0.4 shell integration. Sourced, never executed during installation.
# shellcheck shell=bash
# All user-facing helpers are namespaced; startup performs no downloads.
__envpilot_config_dir="${ENVPILOT_CONFIG_DIR:-$HOME/.config/envpilot}"
# shellcheck disable=SC1091 # Generated user-specific configuration.
[ ! -r "$__envpilot_config_dir/shell/config.sh" ] || . "$__envpilot_config_dir/shell/config.sh"

__envpilot_path_append()
{
    [ -d "$1" ] || return 0
    case ":$PATH:" in *":$1:"*) ;; *) PATH="${PATH:+$PATH:}$1" ;; esac
    export PATH
}
__envpilot_path_append "$HOME/.local/bin"
for __envpilot_path in "${ENVPILOT_EXTRA_PATHS[@]:-}"; do __envpilot_path_append "$__envpilot_path"; done
unset __envpilot_path

envpilot_proxy_on()
{
    local port="${MIHOMO_PROXY_PORT:-42290}"
    if command -v nc >/dev/null 2>&1; then
        nc -z -w 1 127.0.0.1 "$port" >/dev/null 2>&1 || return 1
    elif command -v timeout >/dev/null 2>&1; then
        # shellcheck disable=SC2016 # $1 belongs to the child shell.
        timeout 2 bash -c 'exec 3<>/dev/tcp/127.0.0.1/$1' _ "$port" >/dev/null 2>&1 || return 1
    else
        return 1
    fi
    export http_proxy="http://127.0.0.1:$port" https_proxy="http://127.0.0.1:$port"
    export HTTP_PROXY="$http_proxy" HTTPS_PROXY="$https_proxy"
    if [ "${BASHRC_PROXY_ENABLE_SOCKS:-0}" = 1 ]; then
        export all_proxy="socks5h://127.0.0.1:$port" ALL_PROXY="socks5h://127.0.0.1:$port"
    fi
    no_proxy="${no_proxy:-${NO_PROXY:-}}"
    local host
    for host in localhost 127.0.0.1 ::1; do
        case ",$no_proxy," in *",$host,"*) ;; *) no_proxy="${no_proxy:+$no_proxy,}$host" ;; esac
    done
    export no_proxy NO_PROXY="$no_proxy"
}
envpilot_proxy_off() { unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY all_proxy ALL_PROXY; }
envpilot_mihomo() { envpilot mihomo "$@"; }
envpilot_codex_ready() { envpilot codex remote ready "$@"; }

# User customizations remain user-owned and run only in interactive shells.
case $- in
    *i*)
        if [ "${ENVPILOT_LEGACY_LOCAL:-0}" = 1 ] && [ -r "$__envpilot_config_dir/shell.local" ]; then
            # shellcheck disable=SC1091 # Optional user-owned customization.
            . "$__envpilot_config_dir/shell.local"
        fi
        if [ "${BASHRC_INIT_CONDA:-0}" = 1 ] && ! command -v conda >/dev/null 2>&1; then
            for __envpilot_conda in "${BASHRC_CONDA_PRIMARY_PREFIX:-}" "${EP_PREFIX:-$HOME/software}/miniconda3" "$HOME/miniconda3" "$HOME/anaconda3"; do
                if [ -n "$__envpilot_conda" ] && [ -r "$__envpilot_conda/etc/profile.d/conda.sh" ]; then
                    # shellcheck disable=SC1091 # Discovered Conda installation.
                    . "$__envpilot_conda/etc/profile.d/conda.sh"
                    break
                fi
            done
            unset __envpilot_conda
        fi
        if command -v module >/dev/null 2>&1; then
            for __envpilot_module in "${ENVPILOT_MODULES[@]:-}"; do [ -z "$__envpilot_module" ] || module load "$__envpilot_module"; done
            unset __envpilot_module
        fi
        if [ "${BASHRC_ENABLE_HISTORY_SYNC:-0}" = 1 ] && [ -n "${BASH_VERSION:-}" ]; then
            shopt -s histappend
            case ";${PROMPT_COMMAND:-};" in *';history -a;'*) ;; *) PROMPT_COMMAND="${PROMPT_COMMAND:+$PROMPT_COMMAND;}history -a" ;; esac
        fi
        if [ "${ENVPILOT_LEGACY_ALIASES:-0}" = 1 ]; then
            command -v proxy_on >/dev/null 2>&1 || alias proxy_on=envpilot_proxy_on
            command -v proxy_off >/dev/null 2>&1 || alias proxy_off=envpilot_proxy_off
            command -v mihomo >/dev/null 2>&1 || alias mihomo=envpilot_mihomo
            command -v codex_ready >/dev/null 2>&1 || alias codex_ready=envpilot_codex_ready
        fi
        ;;
esac
if [ "${BASHRC_AUTO_LOAD_SECRETS:-0}" = 1 ] && [ -f "${BASHRC_SECRETS_FILE:-}" ]; then
    __envpilot_mode="$(stat -c '%a' "$BASHRC_SECRETS_FILE" 2>/dev/null || stat -f '%Lp' "$BASHRC_SECRETS_FILE" 2>/dev/null)"
    __envpilot_owner="$(stat -c '%u' "$BASHRC_SECRETS_FILE" 2>/dev/null || stat -f '%u' "$BASHRC_SECRETS_FILE" 2>/dev/null)"
    if [ "$__envpilot_owner" = "$(id -u)" ]; then
        case "$__envpilot_mode" in
            400|600)
                __envpilot_core="${ENVPILOT_ROOT:-}/bin/envpilot-core"
                if [ ! -x "$__envpilot_core" ] && [ -r "$__envpilot_config_dir/core-path" ]; then
                    IFS= read -r __envpilot_core < "$__envpilot_config_dir/core-path" || true
                fi
                if [ -x "$__envpilot_core" ]; then
                    while IFS= read -r -d '' __envpilot_name && IFS= read -r -d '' __envpilot_value; do
                        export "$__envpilot_name=$__envpilot_value"
                    done < <("$__envpilot_core" secret-export --format nul --config "${ENVPILOT_CONFIG_FILE:-$__envpilot_config_dir/config.yaml}" 2>/dev/null)
                fi
                unset __envpilot_core __envpilot_name __envpilot_value
                ;;
        esac
    fi
    unset __envpilot_mode __envpilot_owner
fi
if [ "${BASHRC_AUTO_START_MIHOMO:-0}" = 1 ] && [ -r "${EP_PREFIX:-$HOME/software}/mihomo/start_mihomo.sh" ]; then
    MIHOMO_QUIET_START=1 bash "${EP_PREFIX:-$HOME/software}/mihomo/start_mihomo.sh" >/dev/null 2>&1 || true
fi
if [ "${BASHRC_AUTO_ENABLE_PROXY:-0}" = 1 ]; then envpilot_proxy_on >/dev/null 2>&1 || true; fi
unset __envpilot_config_dir
