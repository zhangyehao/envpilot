# envpilot

[简体中文](README.md) · [GitHub](https://github.com/zhangyehao/envpilot) · [Gitee](https://gitee.com/zhangyehao0422/envpilot)

User-space environment installation and maintenance for workstations, HPC nodes and remote SSH hosts. Components include Mihomo, Git, Python, Conda/Mamba, Codex, GitHub CLI and tmux.

Version 0.4.0 adds one YAML configuration, preserves existing shell profiles, verifies Codex restarts, and provides versioned recovery snapshots.

**Version 0.4.2 handles Desktop reconnect races during Codex restart, recognizes Desktop version identifiers, and adds version/help aliases.** Update an existing checkout without cloning it again:

```bash
cd "$HOME/envpilot" && git pull --ff-only origin main
# After the pull succeeds, refresh the command and copied Codex manager:
bash envpilot.sh setup-command
export PATH="$PATH:$HOME/.local/bin"
envpilot codex remote enable
envpilot codex remote status
```

The final two commands apply to installations using Codex remote services. See [upgrade and recovery](docs/UPGRADE.md) for complete source and platform-package commands.

Check the application version with `envpilot version`, `-v`, `-V` or `--version`. Read help with `envpilot help`, `-h`, `-help` or `--help`. These commands need neither network access, a configuration helper nor valid YAML. The YAML `version: 1` field describes the configuration format.

## Get started

Download the matching platform package from [Releases](https://github.com/zhangyehao/envpilot/releases). It includes `envpilot-core`; Go, Python and Node are not prerequisites for configuration commands. From the extracted directory:

```bash
bash envpilot.sh setup-command
export PATH="$PATH:$HOME/.local/bin"
envpilot init --lang en
envpilot config edit
envpilot plan
envpilot apply
```

Select components in `install.components`. The initial list is empty. `envpilot install all` retains the existing component-installation interface.

Source installations are also supported. Clone either mirror and run `setup-command`; the matching configuration tool is downloaded from the selected release source and checksum-verified. Completely offline setup requires a platform package plus offline assets for the desired components. Bootstrap retains partial clone and sparse-checkout support for the bundled Mihomo cache.

Since **0.3.0**, confirmed `apply-shell` installs `~/.local/bin/envpilot`. Once PATH is active, `envpilot ...` works from any directory and is equivalent to `bash /path/to/repository/envpilot.sh ...`, preserving arguments, working directory and exit status. Re-run `setup-command` after moving a checkout.

PowerShell:

```powershell
.\envpilot.ps1 setup-command
$env:PATH += ';' + (Join-Path $HOME '.local/bin')
envpilot init -Lang en
envpilot config edit
envpilot plan
envpilot apply
```

PowerShell uses `-Yes -NonInteractive`; Bash uses `--yes --non-interactive`. Codex node-local runtime management uses the Unix entrypoint on Linux, macOS or WSL.

## Configuration and commands

Edit `~/.config/envpilot/config.yaml`. Keep API keys and subscription URLs in referenced protected files or environment variables. Existing Codex authentication is preserved. See [configuration](docs/CONFIG.md).

| Command | Purpose |
| --- | --- |
| `envpilot plan` | Preview selected components, locations and integration changes. |
| `envpilot apply` | Apply configuration with one confirmation. |
| `envpilot install COMPONENT` | Install a component. |
| `envpilot update COMPONENT` | Re-evaluate compatible updates. |
| `envpilot doctor` | Diagnose without replacing recovery points. |
| `envpilot snapshot` | Create an immutable managed-file snapshot. |
| `envpilot restore` | Restore a snapshot, with legacy baseline support. |
| `envpilot rollback` | Restore the most recent individual backup. |
| `envpilot self-update` | Update envpilot and installed management scripts. |
| `envpilot apply-shell` | Add a short loading block while preserving the profile. |
| `envpilot shell remove` | Remove only the managed loading block. |
| `envpilot run -- COMMAND ...` | Run a child with the configured environment. |
| `envpilot resume` | Continue incomplete installation. |
| `envpilot reset` | Clear installation state without uninstalling tools. |

New installations only integrate the envpilot command by default. Enable proxy startup, Conda, modules, history synchronization or compatibility aliases explicitly. Legacy migration preserves previous switches.

## Codex lifecycle

```bash
envpilot codex remote enable
envpilot codex remote status
envpilot codex remote restart
envpilot codex remote stop
envpilot codex remote enable
envpilot update codex
```

Restart manages the verified current-user, current-node instance for the selected control socket, including Desktop/SSH instances. It verifies a new process and a protocol handshake. Other Codex homes and unidentified socket owners are preserved. Restart may interrupt active requests.

Updating Codex refreshes and restarts a previously running target service; a stopped service remains stopped. Configuration, credentials and sessions remain persistent. Node-local runtime files use versioned directories. Native daemon commands are selected only when their fixed installation-path requirements match the intended runtime.

## Upgrade and recover

See [upgrade and recovery](docs/UPGRADE.md) and [shell integration](docs/SHELL-CONFIG.md). Modified legacy profiles are preserved for review; known unmodified templates can migrate automatically. `shell.local` and protected credentials are retained.

GitHub Actions tests Linux, macOS and Windows. A repository-scoped GitHub App opens maintenance PRs so CI can run without the approval state imposed on `GITHUB_TOKEN` PR events. Releases include source packages, platform packages and SHA-256 checksums. Both mirrors use matching main commits and immutable release tags.

[Architecture](docs/ARCHITECTURE.md) · [Contributing components](docs/EXTENDING.md) · [MIT license](LICENSE)

Component guides: [Mihomo](docs/MIHOMO.md), [Conda/Mamba](docs/CONDA-MAMBA.md), [Git/Python](docs/GIT-PYTHON.md), [GitHub CLI/tmux](docs/GITHUB-TMUX.md), [Codex](docs/CODEX.md).
