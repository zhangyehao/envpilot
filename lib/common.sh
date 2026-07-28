#!/usr/bin/env bash

EP_MODE="${EP_MODE:-online}"
EP_PREFIX="${EP_PREFIX:-${HOME:-}/software}"
EP_ASSET_PATH="${EP_ASSET_PATH:-}"
EP_ASSUME_YES="${EP_ASSUME_YES:-0}"
EP_COMMAND="${EP_COMMAND:-}"
EP_COMPONENT="${EP_COMPONENT:-all}"
EP_RUN_ID=""
EP_CONFIG_DIR=""
EP_STATE_FILE=""
EP_REPORT_FILE=""
EP_LOG_FILE=""
EP_ROLLBACK_LOG=""

ep_timestamp()
{
    date +%Y%m%d%H%M%S
}

ep_iso_now()
{
    date -u +%Y-%m-%dT%H:%M:%SZ
}

ep_init()
{
    [ -n "${HOME:-}" ] || ep_die "HOME is not set"
    EP_RUN_ID="${EP_RUN_ID:-$(ep_timestamp)}"
    EP_CONFIG_DIR="${EP_CONFIG_DIR:-$HOME/.config/envpilot}"
    EP_STATE_FILE="$EP_CONFIG_DIR/state"
    EP_REPORT_FILE="$EP_CONFIG_DIR/install-report.json"
    EP_LOG_FILE="$EP_CONFIG_DIR/logs/envpilot-$EP_RUN_ID.log"
    EP_ROLLBACK_LOG="$EP_CONFIG_DIR/rollback.log"
    mkdir -p "$EP_CONFIG_DIR/logs" "$EP_CONFIG_DIR/backups" "$HOME/.local/bin"
    trap ep_on_interrupt INT TERM
}

ep_on_interrupt()
{
    printf '\n[WARN] Interrupted. Completed stages remain in %s; run resume or reset.\n' "$EP_STATE_FILE" >&2
    exit 130
}

ep_log()
{
    printf '[INFO] %s\n' "$*"
    if [ -n "${EP_LOG_FILE:-}" ]; then
        printf '[INFO] %s\n' "$*" >> "$EP_LOG_FILE" 2>/dev/null || true
    fi
}

ep_warn()
{
    printf '[WARN] %s\n' "$*" >&2
    if [ -n "${EP_LOG_FILE:-}" ]; then
        printf '[WARN] %s\n' "$*" >> "$EP_LOG_FILE" 2>/dev/null || true
    fi
}

ep_die()
{
    printf '[ERROR] %s\n' "$*" >&2
    if [ -n "${EP_LOG_FILE:-}" ]; then
        printf '[ERROR] %s\n' "$*" >> "$EP_LOG_FILE" 2>/dev/null || true
    fi
    exit 1
}

ep_command_exists()
{
    command -v "$1" >/dev/null 2>&1
}

ep_confirm()
{
    local prompt="$1"
    local default="${2:-no}"
    local answer

    if [ "$EP_ASSUME_YES" = "1" ] && [ "$default" = "yes" ]; then
        return 0
    fi

    while true; do
        if [ "$default" = "yes" ]; then
            printf '%s [Y/n]: ' "$prompt"
        else
            printf '%s [y/N]: ' "$prompt"
        fi
        IFS= read -r answer || return 1
        case "${answer:-}" in
            '')
                if [ "$default" = "yes" ]; then
                    return 0
                fi
                return 1
                ;;
            y|Y|yes|YES|Yes) return 0 ;;
            n|N|no|NO|No) return 1 ;;
            *) printf 'Please answer yes or no.\n' ;;
        esac
    done
}

ep_prompt_nonempty()
{
    local var_name="$1"
    local prompt="$2"
    local value
    while true; do
        printf '%s: ' "$prompt"
        IFS= read -r value || return 1
        if [ -n "$value" ]; then
            printf -v "$var_name" '%s' "$value"
            return 0
        fi
        printf 'Value cannot be empty. Press Ctrl+C to cancel.\n'
    done
}

ep_write_file_atomic()
{
    local target="$1"
    local tmp
    tmp="$(mktemp "${target}.tmp.XXXXXX")"
    cat > "$tmp"
    mv "$tmp" "$target"
}

ep_backup_file()
{
    local target="$1"
    local backup
    [ -e "$target" ] || return 0
    backup="$target.bak.$(ep_timestamp)"
    cp -p "$target" "$backup"
    printf '%s\t%s\n' "$target" "$backup" >> "$EP_ROLLBACK_LOG"
    ep_log "Backed up $target -> $backup"
}

ep_state_mark_done()
{
    local component="$1"
    mkdir -p "$(dirname "$EP_STATE_FILE")"
    grep -v "^$component=" "$EP_STATE_FILE" 2>/dev/null > "$EP_STATE_FILE.tmp" || true
    printf '%s=done:%s\n' "$component" "$(ep_iso_now)" >> "$EP_STATE_FILE.tmp"
    mv "$EP_STATE_FILE.tmp" "$EP_STATE_FILE"
}

ep_state_is_done()
{
    local component="$1"
    grep -q "^$component=done:" "$EP_STATE_FILE" 2>/dev/null
}

ep_json_escape()
{
    sed \
        -e 's/\\/\\\\/g' \
        -e 's/"/\\"/g' \
        -e ':a;N;$!ba;s/\n/\\n/g'
}

ep_report_start()
{
    local action="$1"
    local component="$2"
    mkdir -p "$(dirname "$EP_REPORT_FILE")"
    cat > "$EP_REPORT_FILE" <<EOF
{
  "run_id": "$EP_RUN_ID",
  "started_at": "$(ep_iso_now)",
  "action": "$action",
  "requested_component": "$component",
  "mode": "$EP_MODE",
  "prefix": "$(printf '%s' "$EP_PREFIX" | ep_json_escape)",
  "platform": {
    "os": "${EP_OS:-unknown}",
    "arch": "${EP_ARCH:-unknown}",
    "libc": "${EP_LIBC:-unknown}",
    "glibc_version": "${EP_GLIBC_VERSION:-unknown}",
    "shell": "$(printf '%s' "${SHELL:-unknown}" | ep_json_escape)",
    "is_root": "${EP_IS_ROOT:-unknown}"
  },
  "events": [
EOF
    : > "$EP_CONFIG_DIR/.report-comma"
}

ep_report_event()
{
    local component="$1"
    local status="$2"
    local message="$3"
    local version="${4:-}"
    local source="${5:-}"
    local path="${6:-}"
    local comma=""
    [ -s "$EP_CONFIG_DIR/.report-comma" ] && comma=","
    cat >> "$EP_REPORT_FILE" <<EOF
$comma    {
      "component": "$(printf '%s' "$component" | ep_json_escape)",
      "status": "$(printf '%s' "$status" | ep_json_escape)",
      "message": "$(printf '%s' "$message" | ep_json_escape)",
      "version": "$(printf '%s' "$version" | ep_json_escape)",
      "source": "$(printf '%s' "$source" | ep_json_escape)",
      "path": "$(printf '%s' "$path" | ep_json_escape)",
      "time": "$(ep_iso_now)"
    }
EOF
    printf '1' > "$EP_CONFIG_DIR/.report-comma"
}

ep_report_finish()
{
    cat >> "$EP_REPORT_FILE" <<EOF
  ],
  "finished_at": "$(ep_iso_now)"
}
EOF
    rm -f "$EP_CONFIG_DIR/.report-comma"
}

ep_symlink_or_copy()
{
    local source="$1"
    local target="$2"
    mkdir -p "$(dirname "$target")"
    rm -f "$target"
    if ln -s "$source" "$target" 2>/dev/null; then
        return 0
    fi
    cp "$source" "$target"
}

