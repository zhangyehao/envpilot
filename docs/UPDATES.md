# Updates and history

[简体中文](UPDATES.zh-CN.md) · [Complete configuration](../examples/config.example.en.yaml)

## Choose an operation

- `envpilot update COMPONENT` updates immediately using that component's installation/compatibility rules. `all` traverses every component and may install missing tools; scheduled updates do not.
- `envpilot self-update` updates envpilot, its helper, entrypoint and copied managers immediately.
- `envpilot updates run` executes the due policy. The default check interval is 3 days. Installation requires `auto_apply: true` and an open maintenance window. `updates check` forces a check without installing.

Codex updates refresh the entire runtime and restart/verify a previously running server; stopped servers stay stopped. No manual stop/restart sequence is required. `codex remote status` and `updates status` do not check online releases or change services.

## Policy and installation window

```yaml
updates:
  enabled: true
  interval_days: 3
  auto_apply: true
  components: [mihomo, git, python, conda, mamba, codex, github, tmux]
  envpilot: true
  window_start: "03:00"
  window_end: "05:00"
  timezone: Local
```

Defaults are `auto_apply: false` and `timezone: Local`. Specify an IANA zone such as `Asia/Shanghai` when the intended zone differs from the server's. Start is inclusive; end is exclusive. Cross-midnight windows are supported. Each component must start inside the window; work already started may finish afterward. Manual updates ignore the window.

Intervals are 1–365 elapsed days, not day-of-month cron expressions. Failures defer retries by an hour; pending installations wait for an allowed window. A machine that was offline does not install at the wrong time on resuming. Time-zone data is included in the helper.

## Register scheduling

```bash
envpilot config validate
envpilot updates check
envpilot updates enable
envpilot updates status
envpilot updates disable
```

The scheduler wakes hourly; YAML and persisted state determine whether work is due:

| Platform | Backend |
| --- | --- |
| Linux | systemd user timer when available, otherwise the user's crontab |
| macOS | launchd agent for the logged-in user |
| Windows | Task Scheduler under the current logged-in user, without storing a password |

Cron must be running. A systemd user instance surviving logout depends on the host's linger policy; envpilot does not change administrator settings. If no scheduler is available, registration fails explicitly. Cluster users can run `envpilot updates run` hourly from their own scheduler. No terminal must stay open.

One update task is registered per user. Repeating `enable --config PATH` selects another config; editing its contents requires no re-registration. `updates.enabled: false` pauses execution; `updates disable` removes scheduling and preserves history. Re-register after moving the home or command entrypoint.

## Components and compatibility

Only already-installed components listed in `updates.components` are maintained. Managed Git/Python, Mihomo, GitHub CLI and tmux, plus existing Conda/Mamba and Codex, retain their installation methods. External/system installations are marked `external` and remain with their original package manager.

Git/tmux resolve upstream stable releases; managed Python selects a platform-matching stable asset. Conda/Mamba use their existing environment solver. If compatibility requires keeping the current version, the result is `compatible`, not a false upgrade. Development/prerelease builds are not automatically downgraded. Install new tools explicitly.

Install/update commands share a kernel lock. Concurrent writers receive `E_UPDATE_BUSY`; crashes release the lock. Git self-update rejects edits/divergence. Package upgrades verify SHA-256. On shared homes, register scheduling on one maintenance node to avoid maintaining the same persistent installation from several nodes.

## Last 30 days of updates

```bash
envpilot updates history
envpilot updates history --days 90
envpilot updates history --days 30 --component git
envpilot updates history --component codex --json
envpilot updates status --json
```

PowerShell: `-Days 90 -HistoryComponent codex -Json`. History includes manual and automatic installation/update time, component, previous/resulting version and outcome. Failures remain visible; unchanged versions are `unchanged`. Interrupted attempts remain `in_progress`. Unknown versions display `?`.

Each operation has a separate record under `~/.config/envpilot/updates/history/`; 30 days is the query default, not retention. Recording begins with 0.4.4 and cannot reconstruct unrecorded older operations. Checks alone are not installation history. Updates made outside envpilot are not recorded.

`updates status` reports results and the next due time. Automatic installer logs are protected at `updates/install.log`, rotated before a subsequent install once larger than 2 MiB. Structured status/history contain versions and stable error codes, never credentials, subscription URLs or raw errors.
