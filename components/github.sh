#!/usr/bin/env bash

ep_gh_asset_regex()
{
    case "$EP_OS:$EP_ARCH" in
        linux:amd64) printf 'gh_.*_linux_amd64\.tar\.gz$' ;;
        linux:arm64) printf 'gh_.*_linux_arm64\.tar\.gz$' ;;
        darwin:amd64) printf 'gh_.*_macOS_amd64\.zip$' ;;
        darwin:arm64) printf 'gh_.*_macOS_arm64\.zip$' ;;
        *) ep_die "No GitHub CLI asset rule for $EP_OS/$EP_ARCH" ;;
    esac
}

ep_doctor_github()
{
    if ep_command_exists gh; then
        ep_log "GitHub CLI: found at $(command -v gh)"
        gh auth status 2>&1 | sed 's/^/[INFO] gh auth: /' || ep_warn "gh auth status failed"
    else
        ep_warn "GitHub CLI: not found"
    fi
    if ep_command_exists ssh; then
        ep_log "SSH: found at $(command -v ssh)"
    else
        ep_warn "SSH: not found"
    fi
}

ep_install_github()
{
    ep_require_unix_runtime
    local source archive install_dir asset_regex gh_path action install_needed reason
    action=skipped
    install_needed=0
    reason="already available"
    ep_log "Component: github"
    ep_log "GitHub CLI enables repo creation, private clone, issue/PR workflows, and SSH setup."

    gh_path="$(command -v gh 2>/dev/null || true)"
    if [ -z "$gh_path" ]; then
        action=installed
        install_needed=1
        reason="installed envpilot-managed GitHub CLI"
    elif [ "$EP_UPGRADE" = "1" ]; then
        case "$gh_path" in
            "$HOME/.local/bin/gh"|"$EP_PREFIX/github-cli"/*)
                action=updated
                install_needed=1
                reason="updated envpilot-managed GitHub CLI from stable release"
                ep_log "Updating envpilot-managed GitHub CLI: $gh_path"
                ;;
            *)
                reason="system-managed GitHub CLI was not overwritten"
                ep_log "GitHub CLI is managed outside envpilot at $gh_path; update will not overwrite it."
                ;;
        esac
    else
        ep_log "GitHub CLI already available: $gh_path"
    fi

    if [ "$install_needed" = "1" ]; then
        install_dir="$EP_PREFIX/github-cli"
        mkdir -p "$install_dir" "$HOME/.local/bin"
        archive="$(mktemp "${TMPDIR:-/tmp}/envpilot-gh.XXXXXX")"
        asset_regex="$(ep_gh_asset_regex)"
        ep_log "Selected latest stable GitHub CLI asset rule: $asset_regex"
        ep_confirm "Install/update GitHub CLI in $install_dir?" "yes" || {
            ep_report_event github skipped "user declined" "" "" ""
            rm -f "$archive"
            return 0
        }
        if [ "$EP_MODE" = "offline" ]; then
            source="$(ep_find_offline_asset 'gh_*')"
            cp "$source" "$archive"
        else
            source="$(ep_github_asset_url cli cli "$asset_regex")"
            ep_fetch_url "$source" "$archive"
        fi
        case "$source" in
            *.zip)
                ep_command_exists unzip || ep_die "unzip is required for GitHub CLI zip assets"
                unzip -qo "$archive" -d "$install_dir"
                ;;
            *.tar.gz)
                tar -xzf "$archive" -C "$install_dir" --strip-components=1
                ;;
            *) ep_die "Unsupported GitHub CLI archive: $source" ;;
        esac
        rm -f "$archive"
        ep_symlink_or_copy "$install_dir/bin/gh" "$HOME/.local/bin/gh"
        gh_path="$HOME/.local/bin/gh"
    fi

    if [ -n "$gh_path" ] && [ -x "$gh_path" ]; then
        if "$gh_path" auth status >/dev/null 2>&1; then
            ep_log "GitHub CLI is authenticated."
        else
            ep_warn "Run this to authenticate with SSH git protocol:"
            ep_warn "  gh auth login -h github.com --git-protocol ssh"
        fi
    fi
    ep_state_mark_done github
    ep_report_event github "$action" "$reason; auth may require user action" "$("$gh_path" --version 2>/dev/null | head -n 1 || true)" "github.com/cli/cli" "$gh_path"
}

