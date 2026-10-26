# Mihomo

[简体中文](MIHOMO.zh-CN.md)

Mihomo provides a local HTTP/SOCKS proxy. envpilot manages its installation, subscription, ports and node selection; you do not need to construct API requests or install Python or jq.

## Everyday workflow

After configuring a subscription:

```bash
envpilot mihomo update-subscription
envpilot mihomo start
envpilot mihomo select
envpilot mihomo status
```

Without arguments, `select` lists manual-selection groups and their choices, then prompts for a number. A successful subscription update restarts a previously running proxy and restores valid selections. A stopped proxy stays stopped; use `start` afterward. Switching a node alone does not require updating the subscription or restarting.

| Command | Purpose |
| --- | --- |
| `envpilot mihomo nodes` | List groups, current selections and available nodes. |
| `envpilot mihomo nodes "GROUP"` | Inspect one group. |
| `envpilot mihomo select` | Choose a group and node interactively. |
| `envpilot mihomo select "GROUP" "NODE"` | Select exact names, including in scripts. |
| `envpilot mihomo test "GROUP"` | Probe directly listed proxy nodes, excluding nested groups and DIRECT/REJECT. |
| `envpilot mihomo test "GROUP" "NODE"` | Probe one candidate without changing the selection. |
| `envpilot mihomo restart` | Restart this node's managed service and restore valid selections. |

Use complete names from `nodes` and quote names containing spaces. Non-interactive selection requires both group and node; it never waits for input. A successful probe establishes reachability for that probe, not access to every site. Testing does not automatically select the fastest node.

`test "GROUP" "NODE"` can explicitly probe any member, including a nested group, `DIRECT` or `REJECT`. For example, `envpilot mihomo test "Manual selection" "Automatic selection"` probes the latter group; replace both names with those shown by `nodes`. Group-wide tests do not recurse into nested groups.

`nodes`, `select` and `test` support `--json`. JSON mode never opens the selection menu. Scripts can use:

```bash
envpilot mihomo nodes --json
envpilot mihomo select "GROUP" "NODE" --non-interactive --json
```

PowerShell uses the same subcommands and positional arguments, with `-Json` and `-NonInteractive` options. Subscription options are `-Network` and `-SubscriptionFile`; `--network` and `--file` aliases are also supported:

```powershell
envpilot mihomo nodes -Json
envpilot mihomo select "GROUP" "NODE" -NonInteractive -Json
envpilot mihomo update-subscription -Network direct
envpilot mihomo update-subscription -SubscriptionFile "$HOME/subscription.yaml"
```

“Automatic selection” and “fallback” are usually policy groups, not separate network endpoints. A manual-selection group can select an actual node or delegate to an automatic group. If every group contains only one real node, changing groups does not create another route; the subscription must supply more nodes.

Selections are saved per host under `~/.config/envpilot/mihomo-selections/`, outside the temporary runtime. `stop → start`, `restart` and subscription updates restore selections when both names still exist. Removed or renamed entries produce a warning and retain the subscription's default behavior; envpilot does not guess a replacement. Run `nodes` and `select` again. Hosts sharing a home directory keep separate selections.

Controller commands verify that the API listener belongs to the current user's managed Mihomo process. If another instance owns the port or ownership cannot be established, no controller request is sent. `nodes` can show the saved configuration; `select` reports the issue. Localhost ports on a shared server are not private to each user.

## Install, update and service commands

```bash
envpilot install mihomo
envpilot update mihomo
envpilot mihomo start
envpilot mihomo restart
envpilot mihomo status
envpilot mihomo stop
envpilot mihomo ports 42290 60290
```

Persistent configuration, the protected subscription URL and GeoIP data live under `~/.config/mihomo`; the existing installers keep the executable under `~/software/mihomo`. Unix runtime files are staged under `/tmp/${USER}_mihomo_${HOSTNAME}/` on the current node. This reduces execution and metadata issues on shared filesystems. `start` rebuilds a missing runtime after temporary-file cleanup.

The default proxy/API ports are 42290 and 60290. They must differ. Existing chosen ports are preserved; an unconfigured fresh installation can scan for available ports. `ports PROXY_PORT API_PORT` saves both; the older `port PROXY_PORT` form preserves the existing API port. Only local top-level listener settings are rewritten, never the subscription nodes' remote addresses, ports or credentials.

Status checks the process, listening ports, API, proxy egress and recent upstream logs. `stop` targets the current user's managed instance on this host. Stopping a process cannot clear proxy variables in its parent shell.

## Configure and refresh a subscription

Obtain a subscription that returns **complete Clash/Mihomo YAML**. An HTML login page, one node URL or a base64 node list is not a complete configuration.

Save the actual URL as one line in a protected file:

```bash
install -d -m 700 "$HOME/.config/mihomo"
(umask 077; touch "$HOME/.config/mihomo/subscription.url")
chmod 600 "$HOME/.config/mihomo/subscription.url"
${EDITOR:-vi} "$HOME/.config/mihomo/subscription.url"
envpilot mihomo update-subscription
```

Keep a reference in the existing `mihomo` section of `~/.config/envpilot/config.yaml`:

```yaml
mihomo:
  subscription_network: auto
  subscription:
    file: ~/.config/mihomo/subscription.url
```

Alternatively use `subscription.env` and clear `file`; see [configuration](CONFIG.md). The older `envpilot mihomo update-subscription 'URL'` form remains supported, but actual URLs can enter shell history. Prefer the protected-file reference.

Protected Unix files must belong to the current user and use mode 600 or 400. URL replacements keep protected backups. Status and diagnostics report paths, never the subscription value. An old `config.yaml` usually cannot reliably recover the original complete-configuration URL; create the reference file when migrating.

Downloads are staged and validated before replacing the configuration or stopping a running service. Failures leave the old configuration and running instance available. A failed restart restores the previous configuration. Successful replacement preserves local ports and restores still-valid selections. Subscription updates can interrupt existing proxy connections.

### Choose the download route

The default `mihomo.subscription_network: auto` attempts direct access first, then an environment proxy or available local managed proxy. Refreshing a broken proxy subscription no longer depends solely on that proxy. Override the route for one invocation:

```bash
envpilot mihomo update-subscription --network direct
envpilot mihomo update-subscription --network proxy
```

| Value | Behavior |
| --- | --- |
| `auto` | Try direct access, then available proxy routes on failure. |
| `direct` | Ignore shell proxy variables and connect directly. |
| `proxy` | Use a proxy route; report an unavailable proxy listener clearly. |

Errors distinguish DNS resolution, connection timeout/refusal, TLS, HTTP status and invalid configuration while hiding subscription credentials. Retryable connection failures and HTTP 429/5xx receive bounded retries. Old proxy variables may remain after stopping Mihomo; `--network direct` ignores them for this download. envpilot cannot repair site egress restrictions or an unavailable provider server.

The downloader honors `Retry-After`. If the requested wait exceeds the remaining download budget, it asks you to retry later rather than shortening the interval or switching proxies immediately. Authentication failures, expired URLs and persistent rate limits require the corresponding upstream issue to be resolved.

### Import a file when the host cannot download

Download the complete YAML in a browser or on another machine, upload it to the host, then:

```bash
chmod 600 "$HOME/subscription.yaml"
envpilot mihomo update-subscription --file "$HOME/subscription.yaml"
envpilot mihomo start
envpilot mihomo select
```

`--file` requires a regular file. On Unix it must belong to the current user and have mode `600` or `400`; do not omit `chmod 600` above. On Windows, protect the file with user ACLs. The YAML contains proxy credentials and must not be committed to a public repository.

`--file` does not contact the subscription URL and preserves the saved URL reference. It uses the same validation, backup and recovery path; do not combine a URL argument with `--file`. Importing a configuration does not establish endpoint reachability; check with `test` and `status`.

### Full subscriptions versus providers

`envpilot update mihomo` updates the program; `envpilot mihomo update-subscription` refreshes its full configuration. Component scheduling does not implicitly refresh subscriptions. A `proxy-providers` entry with its own `interval` is refreshed by Mihomo itself; this is separate from replacing the full `config.yaml`.

## Shell proxy settings and cached assets

A new installation does not automatically start the proxy or export proxy variables. Select `shell.auto_start_proxy` and `shell.auto_enable_proxy` explicitly. After `envpilot apply-shell` and reloading the shell, use `envpilot_proxy_on` and `envpilot_proxy_off` to change the current shell. Existing `no_proxy` entries are preserved. `envpilot run` affects a child only.

`mihomo.socks: true` additionally exports SOCKS5 `all_proxy` through shell integration. Multiple SSH sessions share the same current-user instance on one host, but each session owns its environment variables. Legacy shortcuts require `shell.legacy_aliases`; use `envpilot ...` in scripts and documentation.

The curated cache contains Linux/Windows amd64 Mihomo plus GeoIP data. Other offline assets may need to be supplied separately with `--asset-path`. Maintainers can use `envpilot update-mihomo-cache` to refresh the bundled assets.

See [configuration](CONFIG.md), [shell integration](SHELL-CONFIG.md) and [recovery](UPGRADE.md).
