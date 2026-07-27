# Changelog

## 0.1.0 - 2026-07-27

Initial private preview release.

### Added

- Cross-platform entrypoints: `envpilot.sh` for Unix-like shells and `envpilot.ps1` for PowerShell.
- User-space component modules for Conda, Mamba, mihomo, Codex, GitHub CLI, and tmux.
- Safe shell templates for Bash, Zsh, and PowerShell with backup, rollback, and local override support.
- Manifest-driven asset selection rules for stable upstream releases and offline installation.
- GitHub Actions for Linux, macOS, and Windows validation.
- Maintainer documentation for adding components, updating manifests, and handling offline assets.

### Notes

- Binary installers, secrets, mihomo subscriptions, generated configs, and logs are intentionally excluded from Git.
- GitHub Packages is not used in this release; offline assets should be attached to GitHub Releases when needed.

