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
    local source archive install_dir asset_regex
    ep_log "Component: github"
    ep_log "GitHub CLI enables repo creation, private clone, issue/PR workflows, and SSH setup."

    if ep_command_exists gh; then
        ep_log "GitHub CLI already available: $(command -v gh)"
    else
        install_dir="$EP_PREFIX/github-cli"
        mkdir -p "$install_dir" "$HOME/.local/bin"
        archive="$(mktemp "${TMPDIR:-/tmp}/envpilot-gh.XXXXXX")"
        asset_regex="$(ep_gh_asset_regex)"
        ep_log "Selected GitHub CLI asset rule: $asset_regex"
        ep_confirm "Install GitHub CLI to $install_dir?" "yes" || {
            ep_report_event github skipped "user declined" "" "" ""
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
                unzip -q "$archive" -d "$install_dir"
                ;;
            *.tar.gz)
                tar -xzf "$archive" -C "$install_dir" --strip-components=1
                ;;
            *) ep_die "Unsupported GitHub CLI archive: $source" ;;
        esac
        rm -f "$archive"
        ep_symlink_or_copy "$install_dir/bin/gh" "$HOME/.local/bin/gh"
    fi

    if ep_command_exists gh; then
        if gh auth status >/dev/null 2>&1; then
            ep_log "GitHub CLI is authenticated."
        else
            ep_warn "Run this to authenticate with SSH git protocol:"
            ep_warn "  gh auth login -h github.com --git-protocol ssh"
        fi
    fi
    ep_state_mark_done github
    ep_report_event github installed "GitHub CLI checked/installed; auth may require user action" "$(gh --version 2>/dev/null | head -n 1 || true)" "github.com/cli/cli" "$(command -v gh 2>/dev/null || true)"
}

