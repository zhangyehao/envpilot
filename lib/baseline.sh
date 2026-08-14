#!/usr/bin/env bash

ep_baseline_snapshot_path()
{
    local target="$1"
    printf '%s/%s' "$EP_BASELINE_DIR/files" "$(ep_baseline_slug "$target")"
}

ep_baseline_slug()
{
    printf '%s' "$1" | sed -E \
        -e 's#^([A-Za-z]):#drive_\1#' \
        -e 's#^[\\/]+##' \
        -e 's#[/\\:[:space:]]#_#g' \
        -e 's#[^A-Za-z0-9_.-]#_#g'
}

ep_baseline_write_header()
{
    mkdir -p "$EP_BASELINE_DIR/files"
    cat > "$EP_BASELINE_FILE" <<EOF
# envpilot doctor baseline
# captured_at=$(ep_iso_now)
# platform=${EP_OS:-unknown}/${EP_ARCH:-unknown}/${EP_LIBC:-unknown}
# shell=${EP_SHELL_NAME:-unknown}
# prefix=${EP_PREFIX:-unknown}
EOF
}

ep_baseline_append_entry()
{
    local kind="$1"
    local name="$2"
    local target="$3"
    local present="$4"
    local snapshot="${5:-}"
    local detail="${6:-}"
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$kind" "$name" "$target" "$present" "$snapshot" "$detail" >> "$EP_BASELINE_FILE"
}

ep_baseline_record_file()
{
    local name="$1"
    local target="$2"
    local snapshot

    if [ -e "$target" ] || [ -L "$target" ]; then
        snapshot="$(ep_baseline_snapshot_path "$target")"
        mkdir -p "$(dirname "$snapshot")"
        cp -p "$target" "$snapshot"
        ep_baseline_append_entry file "$name" "$target" 1 "files/$(basename "$snapshot")" ""
    else
        ep_baseline_append_entry file "$name" "$target" 0 "" ""
    fi
}

ep_baseline_record_dir()
{
    local name="$1"
    local target="$2"
    if [ -d "$target" ]; then
        ep_baseline_append_entry dir "$name" "$target" 1 "" ""
    else
        ep_baseline_append_entry dir "$name" "$target" 0 "" ""
    fi
}

ep_baseline_record_tool()
{
    local name="$1"
    local path="${2:-}"
    if [ -n "$path" ]; then
        ep_baseline_append_entry tool "$name" "$path" 1 "" ""
    else
        ep_baseline_append_entry tool "$name" "" 0 "" ""
    fi
}

ep_capture_doctor_baseline()
{
    local shell_target mihomo_tool

    [ -n "${EP_BASELINE_DIR:-}" ] || ep_die "Baseline directory is not initialized."
    rm -rf "$EP_BASELINE_DIR"
    ep_baseline_write_header

    shell_target="$(ep_shell_profile_target)"
    ep_baseline_record_file shell-profile "$shell_target"
    ep_baseline_record_file shell-local "$EP_CONFIG_DIR/shell.local"
    ep_baseline_record_file repo-root "$EP_REPO_ROOT_FILE"
    ep_baseline_record_file condarc "$HOME/.condarc"
    ep_baseline_record_file mihomo-config "$HOME/.config/mihomo/config.yaml"
    ep_baseline_record_file mihomo-country "$HOME/.config/mihomo/country.mmdb"
    ep_baseline_record_file mihomo-geoip "$HOME/.config/mihomo/geoip.metadb"
    ep_baseline_record_file mihomo-bin "$HOME/software/mihomo/mihomo"
    ep_baseline_record_file mihomo-common "$HOME/software/mihomo/mihomo_common.sh"
    ep_baseline_record_file mihomo-start "$HOME/software/mihomo/start_mihomo.sh"
    ep_baseline_record_file mihomo-stop "$HOME/software/mihomo/stop_mihomo.sh"
    ep_baseline_record_file mihomo-status "$HOME/software/mihomo/status_mihomo.sh"
    ep_baseline_record_file mihomo-subscription "$HOME/software/mihomo/update_mihomo_subscription.sh"
    ep_baseline_record_file mihomo-log "$HOME/logs/mihomo.log"
    ep_baseline_record_file mihomo-state-log "$HOME/.local/state/mihomo/start.log"
    ep_baseline_record_file codex-config "$HOME/.codex/config.toml"
    ep_baseline_record_file codex-auth "$HOME/.codex/auth.json"
    ep_baseline_record_file codex-secrets "$HOME/.config/secrets/api.env"
    ep_baseline_record_file gh-link "$HOME/.local/bin/gh"
    ep_baseline_record_file tmux-link "$HOME/.local/bin/tmux"

    ep_baseline_record_dir git-prefix "$EP_PREFIX/git"
    ep_baseline_record_dir python-prefix "$EP_PREFIX/python"
    ep_baseline_record_dir conda-miniconda-prefix "$EP_PREFIX/miniconda3"
    ep_baseline_record_dir conda-anaconda-prefix "$EP_PREFIX/anaconda3"
    ep_baseline_record_dir github-prefix "$EP_PREFIX/github-cli"
    ep_baseline_record_dir mihomo-prefix "$HOME/software/mihomo"
    ep_baseline_record_dir nvm-dir "$HOME/.nvm"
    ep_baseline_record_dir tmux-prefix "$HOME/.local/envpilot"

    ep_baseline_record_tool git "$(command -v git 2>/dev/null || true)"
    ep_baseline_record_tool python "$(command -v python3 2>/dev/null || command -v python 2>/dev/null || true)"
    ep_baseline_record_tool conda "$(command -v conda 2>/dev/null || true)"
    ep_baseline_record_tool mamba "$(command -v mamba 2>/dev/null || true)"
    ep_baseline_record_tool codex "$(command -v codex 2>/dev/null || true)"
    ep_baseline_record_tool gh "$(command -v gh 2>/dev/null || true)"
    ep_baseline_record_tool tmux "$(command -v tmux 2>/dev/null || true)"
    mihomo_tool="$(ep_mihomo_bin)"
    if [ -x "$mihomo_tool" ]; then
        ep_baseline_record_tool mihomo "$mihomo_tool"
    else
        ep_baseline_record_tool mihomo ""
    fi

    ep_log "Captured doctor baseline: $EP_BASELINE_FILE"
}

ep_remove_path_safe()
{
    local target="$1"

    case "$target" in
        "$HOME"/*|"$EP_PREFIX"/*|"$EP_CONFIG_DIR"/*)
            rm -rf -- "$target"
            ;;
        *)
            ep_warn "Skip unsafe restore target: $target"
            ;;
    esac
}

ep_restore_tool_cleanup()
{
    local name="$1"

    case "$name" in
        mamba)
            local conda_path
            conda_path="$(command -v conda 2>/dev/null || true)"
            if [ -z "$conda_path" ] && [ -x "$EP_PREFIX/miniconda3/bin/conda" ]; then
                conda_path="$EP_PREFIX/miniconda3/bin/conda"
            fi
            if [ -z "$conda_path" ] && [ -x "$EP_PREFIX/anaconda3/bin/conda" ]; then
                conda_path="$EP_PREFIX/anaconda3/bin/conda"
            fi
            if [ -n "$conda_path" ]; then
                "$conda_path" remove -n base -y mamba >/dev/null 2>&1 || ep_warn "Could not remove mamba from Conda base."
            fi
            ;;
        codex)
            if ep_command_exists npm; then
                npm uninstall -g "$EP_CODEX_PACKAGE" >/dev/null 2>&1 || ep_warn "Could not uninstall Codex from npm global packages."
            fi
            ;;
        mihomo)
            ep_remove_path_safe "$(ep_mihomo_bin)"
            ;;
        tmux)
            if [ "$EP_OS" = "darwin" ] && ep_command_exists brew; then
                brew uninstall tmux >/dev/null 2>&1 || ep_warn "Could not uninstall tmux with brew."
            fi
            if [ "$EP_IS_ROOT" = "true" ]; then
                if ep_command_exists apt-get; then
                    apt-get remove -y tmux >/dev/null 2>&1 || ep_warn "Could not remove tmux with apt-get."
                elif ep_command_exists dnf; then
                    dnf remove -y tmux >/dev/null 2>&1 || ep_warn "Could not remove tmux with dnf."
                elif ep_command_exists yum; then
                    yum remove -y tmux >/dev/null 2>&1 || ep_warn "Could not remove tmux with yum."
                fi
            fi
            ;;
    esac
}

ep_restore_doctor_baseline()
{
    local kind name target present snapshot detail snapshot_path

    [ -s "$EP_BASELINE_FILE" ] || ep_die "No doctor baseline found. Run: bash envpilot.sh doctor"
    ep_log "Restoring doctor baseline from $EP_BASELINE_FILE"
    ep_stop_mihomo
    ep_cleanup_mihomo_runtime

    while IFS="$(printf '\t')" read -r kind name target present snapshot detail; do
        case "$kind" in
            ''|'#'*) continue ;;
            file)
                if [ "$present" = "1" ]; then
                    snapshot_path="$EP_BASELINE_DIR/$snapshot"
                    [ -f "$snapshot_path" ] || { ep_warn "Missing snapshot for $name: $snapshot_path"; continue; }
                    mkdir -p "$(dirname "$target")"
                    cp -p "$snapshot_path" "$target"
                    ep_log "Restored file: $target"
                else
                    ep_remove_path_safe "$target"
                fi
                ;;
            dir)
                if [ "$present" = "0" ]; then
                    ep_remove_path_safe "$target"
                fi
                ;;
            tool)
                if [ "$present" = "0" ]; then
                    ep_restore_tool_cleanup "$name"
                fi
                ;;
        esac
    done < "$EP_BASELINE_FILE"

    rm -f "$EP_STATE_FILE"
    ep_log "Baseline restore complete."
}
