# Extending envpilot

Chinese version: [EXTENDING.zh-CN.md](EXTENDING.zh-CN.md)

This document is for maintainers who add components, platforms, or updater logic.

## Design rules

- Keep user-space installation as the default.
- Detect before using a command.
- Print what will be installed, why that asset was selected, where it will be installed, and what config will change.
- Do not commit secrets, subscription URLs, generated configs, logs, or binary installers.
- Avoid changing shell startup behavior for non-interactive sessions.
- Do not install direct command-line tools through Conda when users expect them outside Conda environments.

## Adding a component

Add four pieces:

1. `components/<name>.sh`
2. Optional Windows support in `envpilot.ps1`
3. `manifests/<name>.json`
4. Tests and README examples

The shell component must expose:

```bash
ep_doctor_<name>()
ep_install_<name>()
```

The install function should:

- call `ep_require_unix_runtime` when appropriate
- detect existing installation first
- resolve platform-specific assets
- summarize the action before mutating files
- call `ep_state_mark_done <name>` on success
- call `ep_report_event <name> ...` for installed, skipped, or failed states

## Manifest rules

Each manifest should document:

- upstream source
- stable release policy
- OS and architecture mapping
- offline filename pattern
- excluded versions such as alpha, beta, rc, pre, prerelease
- expected install path and config files

The resolver may query upstream APIs at runtime, but must stop with a clear message when no safe match exists.

## CI/CD strategy

Use three workflow types:

- `test.yml`: syntax and fixture tests on every PR and push.
- `update-manifests.yml`: scheduled or manual manifest refresh through `scripts/update-manifests.py`; writes upstream stable metadata into manifest `latest` fields and opens PRs instead of committing directly to `main`.
- `release-assets.yml`: manual packaging workflow that attaches envpilot-owned `.tar.gz`, `.zip`, and `.sha256` assets to a release tag.

Do not store large binaries in Git history. Third-party offline installers, including Miniconda, Anaconda, mihomo, and related payloads, should stay in local ignored `downloads/` by default. If centralized caching is needed, use a separate offline-cache repository or a dedicated non-version tag instead of normal envpilot `v0.x.y` releases.

## State, resume, and rollback

State file:

```text
~/.config/envpilot/state
```

Rollback log:

```text
~/.config/envpilot/rollback.log
```

If a component writes a user config, use `ep_backup_file` first. If a component writes multiple files, back up each file separately and keep the most important user-facing file last so `rollback` restores that file by default.

## Shell templates

Rules for `.bashrc`, `.zshrc`, and PowerShell profiles:

- non-interactive shell must return quietly
- do not auto-start mihomo unless explicitly enabled
- do not auto-load secrets by default
- do not auto-activate Conda base
- source local overrides from `~/.config/envpilot`

If future templates need more platform-specific behavior, add a new template instead of making one large conditional file.

## Testing new components

Add fixture tests for:

- missing dependency
- existing installation
- online asset resolver excluding prereleases
- offline missing asset
- report event creation
- rollback record creation when configs are changed

Prefer fast tests that do not download large assets. Network-heavy checks belong in scheduled CI or manual release workflows.


## Offline asset collection

GitHub Actions runs on GitHub-hosted runners and cannot read a maintainer workstation path such as `D:\software`, `E:\software`, or `~/Downloads`. Collect local installers on the maintainer machine first.

Windows:

```powershell
.\scripts\collect-assets.ps1 -DryRun
.\scripts\collect-assets.ps1 -MaxSizeMB 2000
```

Unix-like:

```bash
ENVPILOT_ASSET_MAX_SIZE_MB=2000 bash scripts/collect-assets.sh --dry-run
ENVPILOT_ASSET_MAX_SIZE_MB=2000 bash scripts/collect-assets.sh
```

The scripts copy matching stable Miniconda/Anaconda/mihomo installers into ignored `downloads/` and write `downloads/assets-index.json`. Treat `downloads/` as a local offline cache and do not commit binary payloads to Git history.

`-UploadRelease` / `--upload-release` is only for a separate offline-cache repository or a dedicated non-version tag. The scripts reject uploading third-party installers to `zhangyehao/envpilot` normal `v0.x.y` releases.
