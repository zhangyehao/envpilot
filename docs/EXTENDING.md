# Extending envpilot

This document is for maintainers who add components, update manifests, or change automation policy.

## Core rules

- Prefer user-space installs.
- Do not require administrator privileges unless a platform truly needs it.
- Explain what will be installed, why that version was chosen, where it will be written, and whether config files will change.
- Never write secrets, subscription URLs, or generated credentials into tracked profile files.
- Keep non-interactive shells quiet.
- Do not auto-start sensitive services unless the user explicitly opts in.

## Component contract

A component usually provides these shell functions:

- `ep_doctor_<name>()`
- `ep_install_<name>()`

The installer should:

1. detect whether the component is already installed
2. resolve the platform-specific asset or package manager path
3. print a short plan before downloading or modifying files
4. back up any user-owned file before changing it
5. record state with `ep_state_mark_done <name>`
6. write a report event for install, skip, or failure

If a component needs Windows support, add the PowerShell equivalent in `envpilot.ps1`.

## Manifest policy

Each manifest should describe:

- the upstream source
- stable release selection rules
- OS and architecture mapping
- offline filename pattern
- exclusions for prerelease content
- expected install path and config file behavior

Resolvers may query upstream APIs at runtime, but if a safe choice cannot be made, they must stop and tell the user instead of guessing.

## Workflow policy

- `test.yml`: parser / syntax checks and fast regression tests.
- `update-manifests.yml`: refresh manifest metadata from upstream stable releases and open a PR.
- `update-mihomo-cache.yml`: refresh the curated stable mihomo cache files and Mihomo GeoIP sidecar data under `downloads/`, then open a PR.
- `release-assets.yml`: package envpilot release artifacts only. Do not upload third-party installers there.

## Repository mirrors

GitHub is the primary repository and Gitee is the China mirror. Maintainer clones should keep:

```bash
git remote add gitee https://gitee.com/zhangyehao0422/envpilot.git
git remote set-url --add --push gitee git@gitee.com:zhangyehao0422/envpilot.git
```

Before a release, verify a clean `main`, update `VERSION` and `CHANGELOG.md`, create the immutable tag, then run `scripts/push-mirrors.sh` or `scripts/push-mirrors.ps1`. Never force-push either mirror or move an existing release tag.

## Cache and downloads policy

`downloads/` is a local cache for installers and other payloads that the maintainer wants to keep nearby. Most files remain ignored by default.

Current exception policy:

- keep the curated stable `mihomo-linux-amd64-compatible-*.gz`
- keep the curated stable `mihomo-windows-amd64-compatible-*.zip`
- keep `country.mmdb` and `geoip.metadb` from MetaCubeX `meta-rules-dat` because Mihomo may need them before proxy access is available
- continue ignoring other large third-party binaries unless a future policy explicitly adds a new exception

If a new cache file is needed, add a clear rule to `.gitignore`, update the relevant updater, and document the reason in this file.

## State, resume, rollback, and restore

State file:

```text
~/.config/envpilot/state
```

Rollback log:

```text
~/.config/envpilot/rollback.log
```

Doctor baseline:

```text
~/.config/envpilot/baseline/baseline.tsv
~/.config/envpilot/baseline/files/
```

`rollback` only restores the latest backup record. It is not a full system rollback.
`restore` replays the latest doctor baseline and is the right entry point when an install fails and the user wants to return to the initial state without manually stopping mihomo or cleaning up user-space paths. If a component creates a managed file inside a directory that may already exist, record that file explicitly in the baseline; do not rely only on directory absence.

A subprocess cannot unset proxy variables in the parent shell. Shell templates therefore provide `envpilot_restore`, which runs restore and then clears the current shell proxy variables.

If a component writes a user config, back it up before writing. If a component writes several files, back them up separately and keep the user-visible config last so `rollback` restores the file the user most likely wants first.

## Shell profile policy

Shell templates must:

- stay quiet in non-interactive shells
- avoid auto-starting mihomo by default
- avoid auto-loading secrets by default
- avoid auto-activating Conda base by default
- load user-specific additions from `~/.config/envpilot/shell.local`

If a profile migration is needed, prefer writing a new template or helper file instead of growing the main profile into a branchy script.

## Tests

Add fixtures for:

- already-installed behavior
- offline missing-asset errors
- resolver prerelease filtering
- report generation
- rollback record creation
- cache-first mihomo selection

Prefer fast tests that do not download large files. Networked checks belong in scheduled CI or release workflows.

## Maintenance notes

- Update README, manifests, and tests together when behavior changes.
- Keep the default behavior conservative.
- Treat Windows PowerShell and Unix-like shells as separate execution surfaces.
- When adding a new component or cache policy, update both the implementation and the updater workflow.
- `update-mihomo-cache` is the local / CI entry point for the curated mihomo cache files.

## Mihomo GeoIP data

Mihomo can fail during startup on restricted servers if it must download GeoIP data before the proxy is available. The installer therefore treats these as sidecar assets:

- `downloads/country.mmdb` -> `~/.config/mihomo/country.mmdb`
- `downloads/geoip.metadb` -> `~/.config/mihomo/geoip.metadb`

`install mihomo` copies these from `downloads/` first. In online mode it falls back to `https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/`. Offline mode fails clearly if the local sidecar file is missing.


## Mihomo runtime and port contract

The Unix implementation keeps persistent assets under the user's home directory and runs a node-local copy from `/tmp/${USER}_mihomo_${HOSTNAME}`.

Changes to Mihomo must keep `MIHOMO_PROXY_PORT` and `MIHOMO_API_PORT` consistent across installation, YAML patching, start/stop/status scripts, proxy environment helpers, and subscription updates. New runtime files must be included in doctor baseline/restore coverage and Bash/ShellCheck tests. Subscription URLs, controller secrets, and generated `config.yaml` files must never enter fixtures or Git history.

`bootstrap.sh` and `bootstrap.ps1` use partial clone plus sparse checkout to select the matching tracked cache. New cached platforms require coordinated bootstrap, manifest, updater workflow, and test changes.
