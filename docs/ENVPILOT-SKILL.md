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

## Mihomo subscriptions and node selection (since 0.4.5)

Use `envpilot mihomo nodes`, `select` and `test` to inspect and choose nodes. Prefer the numbered interactive menu for users; scripts supply exact group and node names. `test GROUP` probes directly listed proxy nodes, excluding nested groups and DIRECT/REJECT; use `test GROUP NODE` to explicitly probe those members. A policy group is not another network endpoint, and an automatic group containing one real node provides no alternative route.

Since 0.4.7, `mihomo.group_order` is an optional list of complete names to show first in group lists and menus, for example `["烟火云"]`. Default `[]` preserves name ordering; absent names are ignored and remaining groups sort by name. This is a display preference, effective on the next command, not a node selection or routing change. Preserve node order within groups and existing selections; no service restart or subscription rewrite is needed.

Save selections per host under the envpilot configuration directory's `mihomo-selections/`, outside temporary runtime files. Restore valid selections across stop/start, restart and subscription replacement; report deleted or renamed choices without guessing. Do not leak controller credentials or overwrite another host's selections on a shared home.

For subscription failures, inspect direct access separately from the current proxy. `mihomo.subscription_network: auto` tries direct access before proxy fallback; `--network direct|proxy|auto` overrides one command. A stopped proxy can leave stale variables in the caller's shell. Distinguish DNS, connection, TLS, HTTP and configuration failures without printing the URL or credentials.

When the host cannot download, import a protected complete Clash YAML with `envpilot mihomo update-subscription --file PATH`. Require current-user ownership and mode 600/400 on Unix (`chmod 600 PATH`); use user ACLs on Windows. PowerShell uses `-Network`/`-SubscriptionFile`, with `--network`/`--file` aliases. Keep the saved subscription reference. Stage and validate downloads/imports before changing live configuration or stopping the proxy, restore the previous configuration on restart failure, and preserve prior running/stopped state. Verify real API state and proxy reachability separately.

## Delivery

Verify Bash, PowerShell, Go, Python, ShellCheck and workflow checks. Publish only verified immutable tags, source/platform packages and checksums. Confirm matching GitHub/Gitee remote refs and actual Actions/Release results. The maintenance GitHub App is repository-scoped; credentials belong only in protected local storage and repository Secrets.

## Scheduled maintenance (0.4.4)

All components use the shared updates policy. Default interval is 3 days and the automatic installation window is 03:00–05:00 in the configured timezone. Automatic installation is opt-in; manual commands run immediately. Do not trigger an out-of-window installation by checking status. Missing tools are skipped; external/system tools remain with their package manager. Keep update history for all manual/automatic component and self updates; preserve failed/incomplete results and never put raw credentials/errors in structured history.

Use `shell.prefer_managed: [git, python]` only by explicit selection. Verify actual command resolution, keep aliases/functions, and preserve activated Conda/venv Python. Update bilingual complete YAML samples whenever the schema changes. Preserve immutable tags, review active automation PRs, and remove only fully merged inactive development branches.
