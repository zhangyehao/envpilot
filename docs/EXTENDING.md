# Extending envpilot

This document is for maintainers who add components, update manifests, or change automation policy.

## Core rules

- Prefer user-space installs.
- Do not require administrator privileges unless a platform truly needs it.
- Explain what will be installed, why that version was chosen, where it will be written, and whether config files will change.
- Never write secrets, subscription URLs, or generated credentials into tracked profile files.
- Keep non-interactive shells quiet.
- Any default service startup must be documented, opt-out, bounded where it waits, and conditional on the managed executable and valid configuration; non-interactive readiness hooks must remain quiet and best-effort.

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
- enable Conda integration, module loading, managed Mihomo startup, ready-proxy export, protected environment loading, and history synchronization by default, with an effective `shell.local` opt-out for each feature
- make default module loading a no-op without `modules.list`, and default Mihomo startup a no-op without both the managed script and a valid config
- keep any non-interactive Mihomo pre-start opt-out, bounded, quiet, and conditional on a valid config
- avoid auto-activating Conda base by default
- load user-specific additions from `~/.config/envpilot/shell.local`

`apply-shell` migration must preserve existing `shell.local` and `api.env` content, never overwrite an existing variable, never source the old profile, and never print protected values. Only strict single-line exports and simple module-load statements may be merged; command substitution, control operators, redirection, functions, loops, and conditions must be rejected. If the active profile is already managed, migrate only from the newest unmanaged backup.

Proxy helpers must check that the configured port is listening before exporting variables, default to HTTP/HTTPS only, make SOCKS opt-in, append to existing `no_proxy`, and leave `no_proxy` intact when disabling proxy variables.

### Non-interactive SSH and Codex startup

The Unix shell templates intentionally place a quiet, best-effort preparation block before the non-interactive TTY return. That block may create the node-local `TMPDIR`, read the persisted Mihomo ports, start the envpilot-managed Mihomo instance when a valid config exists, and export HTTP/HTTPS variables only after the proxy port is actually listening. Its startup wait must be bounded; it must never print routine output, fail the shell, or export a dead proxy endpoint.

The process model is node-scoped: one envpilot-managed Mihomo runtime is shared by the same user on the same host, guarded by a lock outside the runtime directory. Proxy variables are shell-scoped, so `proxy_on` and `proxy_off` affect only the current shell. Do not move the complete `~/.codex` directory or its SQLite/session state to `/tmp`; only transient files, the Mihomo runtime copy, and startup locks belong there.

Not every remote launcher reads `.bashrc`. Tests and documentation must cover `bash -lc`, `BASH_ENV`, and direct supervisor/app-server invocation separately. A non-interactive profile must remain safe when Mihomo is absent, has no config, or fails health checks.

## Component update contract

`install` may honor completed state. `update` / `upgrade` must bypass completed state and re-evaluate the selected component without requiring `reset`.

Each component update path must:

- resolve the newest stable version compatible with the detected OS, architecture, libc/runtime, and existing environment
- report the current version, selected target, source, path, and why an update was applied or skipped
- avoid overwriting administrator-managed system tools when envpilot cannot prove ownership
- preserve user configuration and restore the previous running state when updating an envpilot-managed service
- keep install and update behavior covered on Unix and PowerShell entrypoints

Mihomo updates preserve an existing envpilot `config.yaml` and restart the managed runtime only if it was running before the update. `install all` prepares Mihomo before network-dependent components so a configured proxy is available before Git/Python/Conda/Mamba/Codex downloads. Conda and Mamba defer compatibility selection to the current Conda solver. tmux compares the current command with `manifests/tmux.json` and builds the target in user space when the system/module version is older. Codex uses the standalone installer first and only falls back to npm; GitHub CLI updates only an envpilot-managed copy on Unix and uses winget on Windows when available.

Every initialized run records the repository path in `~/.config/envpilot/repo-root`. Shell templates may default to `$HOME/envpilot`, but must fall back to this recorded path so a repository cloned elsewhere remains manageable after upgrades.

Codex must keep credentials separate from profile and TOML configuration. `~/.codex/config.toml` stores only `env_key = "OPENAI_API_KEY"`; the actual key belongs in mode-600 `~/.config/secrets/api.env`. `apply-shell` and `install codex` may create a key-free protected scaffold, and persistence of a detected or entered key requires separate confirmation. An existing `~/.codex/auth.json` is user-owned authentication state and ordinary install/configure runs must preserve it without prompting or replacement. Only when it is absent may envpilot import `OPENAI_API_KEY` from the current environment or protected secret file, prompt as a last resort, and offer to create the mode-600 plaintext compatibility copy. New sensitive files must be added to doctor baseline, backup, rollback/restore, and ignore-rule coverage.

### Codex and Node.js resolver

The Codex component must probe the executable with `codex --version`, not merely trust `command -v`. A usable existing Codex is reused by ordinary `install`; it must not trigger Node.js, npm, or nvm installation. `update codex` or `--upgrade` is the explicit path for replacing the CLI.

For a missing or explicitly upgraded Codex, online mode tries the official standalone installer at `https://chatgpt.com/codex/install.sh` first. npm is only a fallback after that installer fails. Offline mode must stop with an actionable error when no usable local Codex is present; it must never silently reach the npm registry.

The npm fallback resolver must inspect OS, architecture, libc, and the real Node.js execution result. On Linux amd64 with glibc 2.17-2.27, select Node.js 22 `x64-glibc-217` from the unofficial-builds installer and place its `bin` directory ahead of nvm. On Linux glibc >= 2.28, official nvm binaries may be used. For unsupported architectures or unknown libc, stop and explain how to provide a compatible runtime rather than downloading an x64 asset. Preserve stderr from failed `node -v` probes so GLIBC loader errors remain visible.

`manifests/codex.json` must keep the standalone installer URL, the minimum Node major, and the legacy Node fallback rule in sync with `components/codex.sh`. Resolver changes require fixtures for existing-Codex reuse, old-glibc selection, unsupported-platform stopping, and failed Node diagnostics.

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
