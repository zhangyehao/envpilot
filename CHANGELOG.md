# Changelog

## 0.1.8 - 2026-07-31

### Added

- Added `mihomo port PORT` for one-command Mihomo port switching from both repository entrypoints and loaded shell/profile helpers.
- The port switch updates `config.yaml`, persists the port in envpilot local shell/profile config, refreshes the installed start script, stops the envpilot-managed process, restarts Mihomo, and reports the current-shell refresh command.

### Changed

- Mihomo start, stop, status, doctor, and install summaries now use the configured proxy port instead of hard-coding `7890`.
## 0.1.7 - 2026-07-30

### Fixed

- Suppressed ShellCheck SC2034 for the cross-file `EP_BASELINE_FILE` variable used by the baseline restore module.
- Reissued the patch release after the `v0.1.6` Linux ShellCheck job failed on the tag run.
## 0.1.6 - 2026-07-30

### Changed

- `doctor` now captures a restore baseline under `~/.config/envpilot/baseline/`.
- Added `restore` to return envpilot-managed files, directories, and tool state to the latest doctor baseline.
- Added `mihomo stop` / `mihomo status` shell helpers and `envpilot.sh mihomo start|stop|status`.

### Fixed

- Baseline restore now avoids manual teardown of Mihomo, shell edits, and user-space install paths when an install fails.
- PowerShell and Bash entrypoints now expose the same restore semantics.

## 0.1.5 - 2026-07-30

### Changed

- `update-mihomo-cache` now refreshes the curated Mihomo Linux/Windows amd64 binaries plus `country.mmdb` and `geoip.metadb` from MetaCubeX `meta-rules-dat`.
- `install mihomo` now hydrates `~/.config/mihomo/country.mmdb` and `~/.config/mihomo/geoip.metadb` from `downloads/` first, falling back to upstream only when needed.

### Fixed

- Prevented Mihomo startup from depending on runtime GitHub downloads for GeoIP data on restricted servers.

## 0.1.4 - 2026-07-28

### Fixed

- Fixed mihomo/proxy status detection when `ss` reports the listener as `:::7890` instead of `127.0.0.1:7890`.
- Made shell startup avoid repeated mihomo starts when the proxy port is already listening.
- Updated `doctor` to detect any listener on port 7890 instead of only exact IPv4 loopback output.

## 0.1.3 - 2026-07-28
### Changed

- `install all` now installs mihomo first so proxy setup can happen before other network-heavy components.
- Online/offline downloads now print source URL or selected offline asset, destination path, and transfer progress before long-running work.
- Conda selection no longer switches to a third-party distribution; default remains Miniconda, with the newest archived installer selected automatically for older Linux glibc and Anaconda available by explicit option.

### Fixed

- Improved mihomo install summary, subscription URL validation, local-only proxy defaults, and start-script errors when `config.yaml` is missing.

## 0.1.2 - 2026-07-28

### Changed

- Default clone instructions now use HTTPS so users without GitHub SSH keys can get the repository immediately.
- Linux Conda selection is now glibc-aware: glibc >= 2.28 uses the latest official Miniconda/Anaconda installers, older Linux glibc uses the newest archived official installer that still works, and the detected glibc version is recorded in install reports.
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
