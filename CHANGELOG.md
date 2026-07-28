# Changelog

## 0.1.3 - 2026-07-28

### Changed

- `install all` now installs mihomo first so proxy setup can happen before other network-heavy components.
- Online/offline downloads now print source URL or selected offline asset, destination path, and transfer progress before long-running work.
- Conda selection no longer switches to a third-party distribution; default remains Miniconda, with archived Miniconda selected for Linux glibc 2.17-2.27 and Anaconda available by explicit option.

### Fixed

- Improved mihomo install summary, subscription URL validation, local-only proxy defaults, and start-script errors when `config.yaml` is missing.

## 0.1.2 - 2026-07-28

### Changed

- Default clone instructions now use HTTPS so users without GitHub SSH keys can get the repository immediately.
- Linux Conda selection is now glibc-aware: glibc >= 2.28 uses Miniconda, glibc 2.17-2.27 falls back to Miniforge, and the detected glibc version is recorded in install reports.
- Updated asset collection and shell templates so offline cache and config lookup cover Miniforge paths as well.

### Fixed

- Prevented Linux glibc 2.17 installs from failing on Miniconda's current minimum by falling back to a compatible installer.
- Fixed manifest metadata and validation coverage for the new compatibility-aware Conda flow.

## 0.1.1 - 2026-07-27

### Changed

- Implemented network-backed manifest updates that record upstream stable metadata in `manifests/*.json`.
- Changed `release-assets.yml` to publish envpilot-owned source archives and checksums only.
- Clarified that third-party offline installers belong in local `downloads/` or a separate offline-cache distribution path, not normal envpilot version releases.

### Fixed

- Added tests for manifest updater validation and release workflow semantics.
- Guarded local asset collection scripts against uploading third-party installers to `zhangyehao/envpilot` `v0.x.y` releases.

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
