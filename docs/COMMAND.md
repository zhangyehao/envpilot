# Command guide

[简体中文](COMMAND.zh-CN.md) · [Getting started](../README.en.md)

`envpilot install COMPONENT` installs/configures one tool. `envpilot update COMPONENT` reruns its compatible update path; it is not a scheduling command. `envpilot self-update` updates envpilot itself. Supported components: `mihomo`, `git`, `python`, `conda`, `mamba`, `codex`, `github`, `tmux`.

Configure once with `envpilot init`, `envpilot config edit`, `envpilot config validate`, then `envpilot plan` and `envpilot apply`. `apply --yes --non-interactive` never prompts; missing required data fails before installation. PowerShell uses `-Yes -NonInteractive`.

`envpilot updates check` discovers releases; `updates enable` registers scheduling; `updates run` respects the configured interval and installation window. `updates status` reads saved results. `updates history` lists 30 days by default; use `--days 90 --component codex --json` to filter/export. See [update policy](UPDATES.md).

`envpilot apply-shell` adds a short managed profile loader. `shell remove` removes it. Set `shell.prefer_managed: [git, python]` for regular-shell priority, or use `envpilot run -- git --version` for one child. Parent-shell proxy changes require shell integration.

`envpilot doctor` diagnoses without replacing snapshots. `snapshot` creates a recovery point; `restore` restores it. External package-manager operations are not fully reversible by file snapshots.

Codex remote lifecycle: `status`, `enable`, `verify`, `ready`, `restart`, `stop`, `repair`, `disable`. `update codex` already restarts a previously running server. See [Codex](CODEX.md).

Mihomo commands added in 0.4.5: `envpilot mihomo select` prompts for a group/node; `nodes` lists candidates and `test "GROUP"` probes directly listed proxy nodes only. Explicitly use `test "GROUP" "MEMBER"` for nested groups or DIRECT/REJECT. Scripts use `envpilot mihomo select "GROUP" "NODE" --non-interactive`; these node commands support `--json`. Saved choices survive restart and subscription refresh when the names still exist.

Since 0.4.7, set `group_order: ["烟火云"]` inside the main configuration's `mihomo` section to display that group first in `nodes` lists and `select` menus. Default `[]` preserves name ordering; remaining groups sort by name and absent names are ignored. The next command uses the saved order, without changing nodes or routing. See the full YAML example in [configuration](CONFIG.md#show-frequently-used-groups-first).

`envpilot mihomo update-subscription` refreshes complete YAML using the protected URL reference. Use `--network direct|proxy|auto` to choose the download route, or `--file PATH` to import a file downloaded elsewhere. On Unix, first run `chmod 600 PATH` to protect the imported file. Failed downloads preserve the old configuration and running service.

PowerShell options are `-Network`, `-SubscriptionFile`, `-Json` and `-NonInteractive`; their double-dash aliases above are also supported. See [Mihomo](MIHOMO.md).

Version aliases: `version`, `-v`, `-V`, `-version`, `--version`. Help aliases: `help`, `-h`, `-H`, `-help`, `--help`. They work offline without a valid YAML or helper.
