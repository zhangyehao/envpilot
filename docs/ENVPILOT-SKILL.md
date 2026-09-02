---
name: envpilot-hpc-ops
description: Maintain and troubleshoot the zhangyehao/envpilot repository and its user-space installations on HPC or remote Unix hosts, including Mihomo, Conda/Mamba, Codex remote runtime, shell profiles, recovery, and GitHub/Gitee releases.
metadata:
  short-description: Operate envpilot on HPC and remote hosts
---

# envpilot HPC operations

Use this skill for the `zhangyehao/envpilot` repository or a host already managed by envpilot. Keep repository changes separate from files under the user's home directory, and preserve existing state unless the requested operation explicitly takes it over.

## Working boundaries

- Repository source is normally `~/envpilot`; when it differs, use `~/.config/envpilot/repo-root` or the path reported by `doctor`.
- User-managed files outside the repository include `~/.bashrc`, `~/.zshrc`, `~/.config/envpilot/shell.local`, `~/.config/secrets/api.env`, `~/.condarc`, `~/.config/mihomo/`, `~/.codex/`, `$HOME/software/`, and node-local `/tmp` runtime directories.
- Never print or commit subscription URLs, API keys, `auth.json`, protected environment files, or their contents. Report only path, mode, owner, and presence.
- Before modifying a user file, use envpilot's backup path or create an equivalent timestamped backup. Do not reset or delete unrelated user changes.
- On shared servers, never replace system glibc or system tools. Prefer user-space, module, or platform-compatible assets.

## Default sequence

For a new or uncertain host:

1. Run `bash envpilot.sh doctor` first to capture the restore baseline.
2. Install or take over Mihomo and verify both proxy and API ports.
3. Run `bash envpilot.sh apply-shell`, then source the relevant profile.
4. Verify `mihomo status`, `proxy_status`, and the real HTTP/HTTPS proxy variables.
5. Install the remaining components with the working proxy.
6. Run focused status checks and report the install-report path.

For an existing installation, prefer `git pull --ff-only`, `doctor`, `apply-shell`, profile reload, and `update`; do not assume `reset` is required.

## Mihomo invariants

- Use `MIHOMO_PROXY_HOST`, `MIHOMO_PROXY_PORT`, and `MIHOMO_API_PORT` consistently. Proxy and API ports must be distinct and available.
- Prefer the architecture-matched `downloads/` asset before a network download.
- List and explicitly take over a user-owned existing Mihomo before stopping it. Preserve an envpilot-managed config and restore a runtime that was running before an update.
- `mihomo status` must check real listening sockets and API health, not just process existence.
- `proxy_on` must refuse to export a dead proxy. `proxy_off` affects only the current shell.
- Multiple SSH windows for the same user and node share one managed Mihomo process, while shell proxy variables remain per-process.

## Conda and Mamba invariants

- Default to Miniconda. On old glibc, select the newest compatible official archive rather than an unusable latest installer.
- When Anaconda and Miniconda coexist, the managed interactive profile selects Miniconda, clears inherited Conda state, and adds Anaconda environment directories to `CONDA_ENVS_PATH`.
- `templates/condarc` is the repository source of truth for Conda install/update. Back up and rewrite user `~/.condarc` through those Conda operations, then verify with `conda config --show-sources`.
- Before Mamba bootstrap, upgrade a standard Miniconda base below Conda 24.11.1 in place with the compatible official installer; preserve existing env directories.
- Mamba install/update must preserve the existing `~/.condarc`; bootstrap from TUNA conda-forge only with explicit `--override-channels` and `--solver libmamba` when the plugin is present, otherwise `--solver classic`.
- Do not auto-activate base. Non-interactive shells must not load `conda.sh`.

## Codex and secrets

- Reuse an existing executable Codex for ordinary install; use update when an upgrade is requested.
- `OPENAI_API_KEY` is the real variable. Preserve existing `~/.codex/auth.json`; create a missing auth file only from a detected environment key, protected `api.env`, or explicit user input.
- On glibc 2.17 through 2.27, use the compatible Node.js 22 glibc-217 fallback. Never replace system glibc.
- On slow shared storage, keep Codex config, auth, sessions, and app-server control in `~/.codex`; stage only reconstructible runtime files under node-local `/tmp`.
- Verify Codex Desktop SSH paths with `codex remote status` or `ready`; do not kill unknown app-server processes.

## Shell profile rules

- `BASHRC_PROFILE_ACTIVE` and `ENVPILOT_LAST_*` are internal markers that distinguish envpilot-managed values from external overrides. Do not ask users to edit them.
- `apply-shell` backs up the profile, preserves `shell.local` and `api.env`, migrates ordered PATH-like assignments and safe aliases without executing the old profile, and installs the current template. Before returning, it must tell the user to compare the previous profile with `shell.local` and explain what silent shells do not inherit.
- `api.env` is assignment-only and may contain variables for multiple applications. `shell.local` is for user overrides and safe PATH/module additions. Enforce owner and mode checks for secrets.
- Keep non-interactive shells quiet. Load protected variables and bounded proxy preparation before the TTY guard, but skip interactive Conda, modules, history, and functions with side effects.

## Recovery and delivery

- `restore` returns to the latest doctor baseline; `rollback` restores the latest individual backup; `resume` continues stateful install; `reset` only clears state.
- Test Bash, PowerShell, ShellCheck, and `git diff --check` after changes that touch templates or install flow.
- The maintainer prefers direct commits to `main` when authorized, with matching GitHub/Gitee main and version tags. Confirm both remote refs and GitHub Actions/Release before reporting completion.
- Keep README command-oriented and put detailed component procedures under `docs/`.
