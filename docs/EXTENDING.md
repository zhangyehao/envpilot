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
- `update-mihomo-cache.yml`: refresh the curated stable mihomo cache files under `downloads/` and open a PR.
- `release-assets.yml`: package envpilot release artifacts only. Do not upload third-party installers there.

## Cache and downloads policy

`downloads/` is a local cache for installers and other payloads that the maintainer wants to keep nearby. Most files remain ignored by default.

Current exception policy:

- keep the curated stable `mihomo-linux-amd64-compatible-*.gz`
- keep the curated stable `mihomo-windows-amd64-compatible-*.zip`
- continue ignoring other large third-party binaries unless a future policy explicitly adds a new exception

If a new cache file is needed, add a clear rule to `.gitignore`, update the relevant updater, and document the reason in this file.

## State, resume, and rollback

State file:

```text
~/.config/envpilot/state
```

Rollback log:

```text
~/.config/envpilot/rollback.log
```

If a component writes a user config, back it up before writing. If a component writes several files, back them up separately and keep the user-visible config last so `rollback` restores the file the user most likely wants first.

`rollback` only restores the latest backup record. It is not a full system rollback.

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
