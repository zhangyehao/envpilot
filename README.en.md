# envpilot

[简体中文](README.md) · [GitHub](https://github.com/zhangyehao/envpilot) · [Gitee](https://gitee.com/zhangyehao0422/envpilot)

Install, configure and maintain user-space tools on workstations, HPC and SSH hosts. One YAML manages components, shell integration, proxies, Codex runtimes and scheduled updates while preserving profiles, credentials and sessions.

## Quick start and updates

### First installation

```bash
git clone https://github.com/zhangyehao/envpilot.git "$HOME/envpilot"
cd "$HOME/envpilot"
bash envpilot.sh setup-command
export PATH="$PATH:$HOME/.local/bin"
envpilot init --lang en
envpilot config edit
envpilot plan
envpilot apply
```

Alternative clone URL: `https://gitee.com/zhangyehao0422/envpilot.git`. Source installs fetch and verify a matching helper; Go, Python and Node are not prerequisites. Offline users need a [platform package](https://github.com/zhangyehao/envpilot/releases/latest) and prepared component assets.

`bootstrap.sh` also supports partial clone and sparse-checkout to retrieve only matching bundled Mihomo assets.

Init preserves existing YAML and initially selects no components. Set `install.components`, for example `[mihomo, codex, git]`, then follow `plan → apply`. Tool login remains with each tool. Proxy, Conda, modules and old shortcuts are opt-in.

Since **0.3.0**, confirmed `apply-shell` installs `~/.local/bin/envpilot`; `setup-command` registers it independently. Once PATH includes that directory, `envpilot ...` works anywhere, equivalent to `bash /repository/path/envpilot.sh ...`. Register again after moving the checkout.

Windows PowerShell, inside a checkout or platform package:

```powershell
.\envpilot.ps1 setup-command
$env:PATH += ';' + (Join-Path $HOME '.local/bin')
envpilot init -Lang en
envpilot config edit
envpilot plan
envpilot apply
```

### Update an existing installation

**0.4.0 and later:**

```bash
envpilot self-update
envpilot version
envpilot update codex                # Or git, mihomo, etc.
envpilot codex remote status
```

`update codex` refreshes the complete runtime and restarts/verifies a previously running service. A stopped service stays stopped. Normally do not stop it first. For a stop-first workflow, use `stop → update codex → restart → status`.

**0.3.0** has no self-update command. Use this one-time bridge, which checks local edits/divergence, backs up files and migrates to a stable tag without a forced reset:

```bash
curl -fL --retry 3 https://raw.githubusercontent.com/zhangyehao/envpilot/main/scripts/upgrade.sh -o /tmp/envpilot-upgrade.sh
bash /tmp/envpilot-upgrade.sh "$HOME/envpilot"
export PATH="$PATH:$HOME/.local/bin"
envpilot version
```

To update source manually, continue only after a successful pull:

```bash
cd "$HOME/envpilot" && git pull --ff-only origin main
bash envpilot.sh setup-command
envpilot apply-shell
envpilot codex remote enable         # Only when using the remote service.
```

Git self-update requires a clean, fast-forwardable checkout. Package self-update verifies SHA-256 and activates a new version directory. See [upgrade and recovery](docs/UPGRADE.md).

### Scheduled checks and overnight installation

0.4.4 checks every **3 days** by default. Automatic installations start during **03:00–05:00**. The default only checks; enable unattended installation explicitly:

```yaml
updates:
  enabled: true
  interval_days: 3
  auto_apply: true
  components: [mihomo, git, python, conda, mamba, codex, github, tmux]
  envpilot: true
  window_start: "03:00"
  window_end: "05:00"
  timezone: Local                    # Or Asia/Shanghai, UTC, America/New_York.
```

```bash
envpilot config validate
envpilot updates check               # Check now, never install.
envpilot updates enable              # Register persistent scheduling.
envpilot updates status
envpilot updates history             # Last 30 days, manual and automatic.
envpilot updates history --days 90 --component codex
```

Missing components are skipped. External/system installations remain with their original package manager. Managed tools retain their compatibility rules. The window limits installation start times; work already started may finish afterward. Codex restarts can interrupt tasks. Manual `update COMPONENT` and `self-update` run immediately. YAML changes take effect without re-registering the interval. Disable with `envpilot updates disable`. See [updates and history](docs/UPDATES.md).

## Configuration

Default: `~/.config/envpilot/config.yaml`. Precedence: arguments → declared environment overrides → YAML → defaults.

- [Complete English example](examples/config.example.en.yaml): every field, choices and explanations.
- [完整中文样例](examples/config.example.zh-CN.yaml).
- [Configuration and protected files](docs/CONFIG.md).

Put the **subscription URL** alone on one line in `~/.config/mihomo/subscription.url`, referenced by `mihomo.subscription.file`. Put **API keys** in `~/.config/secrets/api.env`, for example `OPENAI_API_KEY='your-key'`, referenced by `secrets.file` and `codex.api_key.env: OPENAI_API_KEY`. Alternatively use `codex.api_key.file` for a file containing only the key and leave `env` empty. Unix files must be owned by you and mode `600`. Keep credentials and subscription URLs out of YAML, command arguments and Git.

Prefer managed Git/Python in ordinary shells (Linux/macOS):

```yaml
shell:
  prefer_managed: [git, python]
```

If the managed versions are missing, set this option and run `envpilot install git` and `envpilot install python`. This installs separate user-space copies even when system tools are available, preserving system files. Scheduled updates never install missing components. On Windows, Git/Python remain maintained by their original package manager.

Run `envpilot apply-shell`, open a new shell and inspect `command -v git` / `command -v python3`. They should resolve under the managed `git/current/bin` and `python/current/bin` directories. Activated Conda/venv environments retain their Python; user aliases/functions are preserved. Use `type -a git python3` to inspect conflicts.

Validate edits with `envpilot config validate`. Apply installation/shell changes with `plan → apply`. Scheduled runs read YAML each time. `shell.local` is preserved; profiles receive only a short loader.

## Commands

| Purpose | Command |
| --- | --- |
| Version / help | `envpilot version` / `-v` / `-V`; `envpilot help` / `-h` / `-help` |
| Configuration | `envpilot init`; `envpilot config edit/validate/show` |
| Preview / apply | `envpilot plan`; `envpilot apply` |
| Unattended apply | Bash: `--yes --non-interactive`; PowerShell: `-Yes -NonInteractive` |
| Install / update a component | `envpilot install COMPONENT`; `envpilot update COMPONENT` |
| Update envpilot | `envpilot self-update` |
| Check / run due policy | `envpilot updates check`; `envpilot updates run` |
| Schedule / status / history | `envpilot updates enable/disable/status/history` |
| Shell integration / removal | `envpilot apply-shell`; `envpilot shell remove` |
| Child environment | `envpilot run -- COMMAND ...` |
| Diagnose / snapshot / restore | `envpilot doctor`; `envpilot snapshot`; `envpilot restore` |
| Codex service | `envpilot codex remote status/enable/verify/restart/stop` |
| Proxy | `envpilot mihomo start/stop/status/ports/update-subscription` |
| Resume / reset install state | `envpilot resume`; `envpilot reset` (does not uninstall) |

Slashes mean alternative subcommands; choose one when running. See [command guide](docs/COMMAND.md).

## Software directory

| Software | Documentation |
| --- | --- |
| [Mihomo](docs/MIHOMO.md) | Proxy, subscription and ports |
| [Git / Python](docs/GIT-PYTHON.md) | User-space tools; preserve system installations |
| [Conda / Mamba](docs/CONDA-MAMBA.md) | Environment and package management |
| [Codex](docs/CODEX.md) | CLI, complete node-local runtime and app-server |
| [GitHub CLI / tmux](docs/GITHUB-TMUX.md) | GitHub operations and persistent terminals |

## More

[Shell integration](docs/SHELL-CONFIG.md) · [Upgrade/recovery](docs/UPGRADE.md) · [Updates/history](docs/UPDATES.md) · [Architecture](docs/ARCHITECTURE.md) · [Extending](docs/EXTENDING.md) · [Operations](docs/ENVPILOT-SKILL.md) · [Changelog](CHANGELOG.md).

`main` contains integrated work. Immutable tags identify releases. Automation branches carry recurring update PRs and may be recreated after merging; fully merged development branches can be removed. GitHub/Gitee mirror code and tags. Platform packages require actual attachments/checksums; use GitHub Release while Gitee attachments remain incomplete.

License: MIT.
