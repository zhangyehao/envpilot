# Updates and history

[简体中文](UPDATES.zh-CN.md) · [Complete configuration](../examples/config.example.en.yaml)

## Choose an operation

- `envpilot update COMPONENT` updates immediately using that component's installation/compatibility rules. `all` traverses every component and may install missing tools; scheduled updates do not.
- `envpilot self-update` updates envpilot, its helper, entrypoint and copied managers immediately.
- `envpilot updates run` executes the due policy. The default check interval is 3 days. Installation requires `auto_apply: true` and an open maintenance window. `updates check` forces a check without installing.

Choose checks or nightly installations at first `envpilot init`. Unattended setup accepts `envpilot init --policy check` or `envpilot init --policy nightly`. Save the configuration, then use `envpilot setup-command` and `envpilot updates enable` to register the system timer.

Active Codex work defers the switch. The scheduler retries in the installation window and verifies the listening server. Use `envpilot codex remote status` for the last observed upstream version and the local instance.

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
  maintenance_host: "login02"
  policies:
    codex: {interval_days: 1, auto_apply: true, window_start: "03:00", window_end: "05:00"}
    conda: {auto_apply: false}
    mamba: {auto_apply: false}
  subscription: {enabled: true, interval_days: 3}
  models: {enabled: true, interval_days: 1}
```

Defaults are `auto_apply: false` and `timezone: Local`. Specify an IANA zone such as `Asia/Shanghai` when the intended zone differs from the server's. Start is inclusive; end is exclusive. Cross-midnight windows are supported. Each component must start inside the window; work already started may finish afterward. Manual updates ignore the window.

Under `policies`, an omitted or null field inherits the global value. Set an explicit `false` to check a component without automatic installation. All components and envpilot support overrides. The example checks Codex daily and allows nightly installation. Conda and Mamba only check. On shared homes, set `maintenance_host` to the short name or FQDN of the host responsible for shared installations and subscriptions. Other nodes can check releases and verify their own Codex instance. The empty default allows the current host to maintain its installation.

Opt in to `subscription.enabled` to run `envpilot mihomo update-subscription` at the specified interval during the Mihomo window. It uses the saved file or environment reference, validates the download and restores valid selections. Keep the URL in the protected reference, outside the policy. Subscription refresh can be enabled independently of automatic package installation. A manual `updates check` does not replace subscriptions. Model checks default to every three days for an installed Codex. Inspect individual catalog sources with `envpilot codex models status`.

Intervals are 1–365 elapsed days, not day-of-month cron expressions. Failures defer retries by an hour; pending installations wait for an allowed window. A machine that was offline does not install at the wrong time on resuming. Time-zone data is included in the helper.

## Register scheduling

```bash
envpilot config validate
envpilot updates check
envpilot updates enable
envpilot updates status
envpilot updates disable
```

New registrations wake each minute to accommodate short maintenance windows. YAML and persisted state determine which components are due. Run `envpilot updates enable` to update an existing hourly registration.

| Platform | Backend |
| --- | --- |
| Linux | systemd user timer when available, otherwise the user's crontab |
| macOS | launchd agent for the logged-in user |
| Windows | Task Scheduler under the current logged-in user, without storing a password |

Cron must be running. A systemd user instance surviving logout depends on the host's linger policy. A custom cluster scheduler can invoke `envpilot updates tick` to record its actual trigger time separately from manual `updates run` or `updates check`.

`envpilot doctor` shows global and component policies, the live scheduler registration, last scheduled trigger and outcome, the next installation window, and the most recent successful check and installation per component. Register an absent job with `envpilot updates enable`. If a registered job has never fired or last fired over two hours ago, check the system scheduler and login node. Component failures retain their error codes alongside successful results from the same run. Use `envpilot doctor --json` for monitoring.

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
envpilot updates history --component subscription
envpilot updates status --json
```

PowerShell: `-Days 90 -HistoryComponent codex -Json`. History includes manual and automatic installation/update time, component, previous/resulting version and outcome. Failures remain visible; unchanged versions are `unchanged`. Interrupted attempts remain `in_progress`. Unknown versions display `?`.

Each operation has a separate record under `~/.config/envpilot/updates/history/`; 30 days is the query default, not retention. Recording begins with 0.4.4 and cannot reconstruct unrecorded older operations. Checks alone are not installation history. Updates made outside envpilot are not recorded.

`updates status` reports results and the next due time. Automatic installer logs are protected at `updates/install.log`, rotated before a subsequent install once larger than 2 MiB. Structured status/history contain versions and stable error codes, never credentials, subscription URLs or raw errors.
