---
name: envpilot-hpc-ops
description: Maintain and troubleshoot the zhangyehao/envpilot repository and its user-space installations on HPC or remote Unix hosts, including Mihomo, Conda/Mamba, Codex remote runtime, shell profiles, recovery, and GitHub/Gitee releases.
metadata:
  short-description: Operate envpilot on HPC and remote hosts
---

# envpilot HPC operations

Maintain the envpilot repository and user-space installations without discarding user-owned configuration. Read docs/CONFIG.md, docs/UPGRADE.md and docs/EXTENDING.md when the task touches those areas.

## Default workflow

1. Diagnose with `envpilot doctor`; it does not replace recovery points.
2. For a new configuration, run `envpilot init`, review YAML and protected references, then `envpilot plan`.
3. Apply selected settings with `envpilot apply`. Prepare Mihomo before network-dependent components.
4. Verify configured services, actual listening ports and command resolution.
5. For upgrades use `envpilot self-update`; update components separately with `envpilot update COMPONENT`.

Create immutable snapshots before modifying managed user files. Preserve shell.local, authentication and sessions. Never print or commit credentials, subscription URLs or protected file contents. Use synthetic secrets and isolated homes for tests.

## Shell and configuration

Install a short marked profile loader and independent implementation files. Preserve user profile content, functions and aliases. New users explicitly opt in to automatic integrations; legacy settings are imported only from understood literal values. Modified legacy profiles remain available for review. Do not execute old profiles to migrate them.

Keep non-interactive startup quiet. Load only explicitly configured environment settings; do not initialize Conda or modules there. Parent-shell environment changes require shell integration; `envpilot run` modifies only a child.

## Services and compatibility

For Codex, match user, node, CODEX_HOME/control socket and process start identity consistently across status/stop/ready/enable/restart. Matching Desktop/SSH services can be managed; unidentified or unrelated processes cannot. Serialize changes and verify a new process and protocol handshake after restart. Native daemon commands require both capability and a compatible installation layout.

Keep persistent auth, sessions, configuration and control state separate from versioned node-local runtime files. Validate a staged version before stopping a working server. Updates restart a previously running target; stopped targets remain stopped. Preserve standalone/npm methods and do not mistake a slow version probe for a missing installation.

Mihomo ports must be distinct and real listeners must be checked before exporting proxies. Preserve no_proxy, subscription files and configured ports. Conda upgrades preserve environments; Mamba preserves .condarc. Never replace system glibc or unrelated system tools.

## Delivery

Verify Bash, PowerShell, Go, Python, ShellCheck and workflow checks. Publish only verified immutable tags, source/platform packages and checksums. Confirm matching GitHub/Gitee remote refs and actual Actions/Release results. The maintenance GitHub App is repository-scoped; credentials belong only in protected local storage and repository Secrets.

## Scheduled maintenance (0.4.4)

All components use the shared updates policy. Default interval is 3 days and the automatic installation window is 03:00–05:00 in the configured timezone. Automatic installation is opt-in; manual commands run immediately. Do not trigger an out-of-window installation by checking status. Missing tools are skipped; external/system tools remain with their package manager. Keep update history for all manual/automatic component and self updates; preserve failed/incomplete results and never put raw credentials/errors in structured history.

Use `shell.prefer_managed: [git, python]` only by explicit selection. Verify actual command resolution, keep aliases/functions, and preserve activated Conda/venv Python. Update bilingual complete YAML samples whenever the schema changes. Preserve immutable tags, review active automation PRs, and remove only fully merged inactive development branches.
