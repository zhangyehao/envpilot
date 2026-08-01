# Changelog

## 0.1.12 - 2026-08-01

### Fixed

- Isolated the Mamba regression fixture from GitHub-hosted runner `conda` shell functions, so Linux CI always exercises the intended fake post-transaction failure instead of invoking the runner's real Conda installation.

## 0.1.11 - 2026-08-01

### Added

- Added the MIT License from the synchronized Gitee repository.
- Added documented GitHub/Gitee mirror URLs and maintainer scripts that publish `main` and release tags to both remotes without force-pushing.

### Changed

- Conda configuration now keeps only the TUNA conda-forge and bioconda mirrors, disables inherited `defaults`, and removes the official installer's default-only prefix config when it is safe to do so.
- Mamba installation now uses the managed mirror configuration without appending the upstream `-c conda-forge` channel.
- Conda/Mamba commands isolate `LD_LIBRARY_PATH`, `PYTHONHOME`, and `PYTHONPATH` to avoid HPC module contamination.

### Fixed

- Mamba installation now verifies the resulting executable when Conda reports a post-transaction cleanup error, preventing a completed installation from being recorded as failed.
- Doctor and install can find Mamba inside the managed Conda prefix even before shell initialization adds it to `PATH`.

## 0.1.10 - 2026-07-31

### Fixed

- Replaced the architecture-aware bootstrap regression test's clone of the full cache-bearing repository with a tiny local Git fixture, preventing Linux termination and macOS stalls in GitHub Actions.
- Updated the fake Mihomo process used by Unix CI to exit cleanly on `SIGTERM`, avoiding unnecessary stop timeouts and leaked test processes.
- Reissued the patch release after the `v0.1.9` Linux and macOS shell-test jobs failed or stalled in the test fixture rather than product code.

## 0.1.9 - 2026-07-31

### Added

- Added node-local Mihomo runtime management: persistent binary/config/geodata remain under the user home, while the active binary, config, cache, PID, and log run from `/tmp/${USER}_mihomo_${HOSTNAME}` on Unix-like hosts.
- Added `mihomo ports PROXY_PORT API_PORT` and `mihomo update-subscription [URL]` across Bash, Zsh, PowerShell, and repository entrypoints.
- Added `bootstrap.sh` and `bootstrap.ps1` for OS/architecture-aware partial clone and sparse checkout, avoiding unrelated tracked Mihomo caches when supported by Git 2.25 or newer.
- Added dedicated Mihomo start, stop, status, common, and subscription-update scripts with API and proxy health checks.

### Changed

- Standardized Mihomo configuration on `MIHOMO_PROXY_PORT` and `MIHOMO_API_PORT`, defaulting to `42290` and `60290`, with validation, occupancy reporting, persistence, and local-only binding.
- Mihomo installation now reports the selected source, persistent paths, node-local runtime path, both ports, and port availability before confirmation.
- Shell templates no longer auto-start Mihomo or auto-enable proxy variables by default.
- CI ShellCheck coverage now includes the architecture-aware bootstrap and every Mihomo management script.

### Fixed

- Restored the Bash `envpilot_restore` helper and extended baseline restore to stop Mihomo and remove the current node runtime directory.
- Fixed PowerShell dual-port persistence, the compatibility `mihomo port` command, and one-command subscription updates; added regression coverage for generated `profile.local.ps1`.
- Preserved unrelated shell/profile local settings while updating Mihomo ports and rejected unsafe runtime-directory identities.
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
