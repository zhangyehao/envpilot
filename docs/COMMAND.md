# Command guide

[简体中文](COMMAND.zh-CN.md) · [Getting started](../README.en.md)

`envpilot install COMPONENT` installs/configures one tool. `envpilot update COMPONENT` reruns its compatible update path; it is not a scheduling command. `envpilot self-update` updates envpilot itself. Supported components: `mihomo`, `git`, `python`, `conda`, `mamba`, `codex`, `github`, `tmux`.

Configure once with `envpilot init`, `envpilot config edit`, `envpilot config validate`, then `envpilot plan` and `envpilot apply`. `apply --yes --non-interactive` never prompts; missing required data fails before installation. PowerShell uses `-Yes -NonInteractive`.

`envpilot updates check` discovers releases; `updates enable` registers scheduling; `updates run` respects the configured interval and installation window. `updates status` reads saved results. `updates history` lists 30 days by default; use `--days 90 --component codex --json` to filter/export. See [update policy](UPDATES.md).

`envpilot apply-shell` adds a short managed profile loader. `shell remove` removes it. Set `shell.prefer_managed: [git, python]` for regular-shell priority, or use `envpilot run -- git --version` for one child. Parent-shell proxy changes require shell integration.

`envpilot doctor` diagnoses without replacing snapshots. `snapshot` creates a recovery point; `restore` restores it. External package-manager operations are not fully reversible by file snapshots.

Codex remote lifecycle: `status`, `enable`, `verify`, `ready`, `restart`, `stop`, `repair`, `disable`. `update codex` already restarts a previously running server. See [Codex](CODEX.md).

Version aliases: `version`, `-v`, `-V`, `-version`, `--version`. Help aliases: `help`, `-h`, `-H`, `-help`, `--help`. They work offline without a valid YAML or helper.
