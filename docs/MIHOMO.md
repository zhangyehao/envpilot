# Mihomo

[简体中文](MIHOMO.zh-CN.md)

```bash
envpilot install mihomo
envpilot update mihomo
envpilot mihomo start
envpilot mihomo status
envpilot mihomo stop
envpilot mihomo ports 42290 60290
envpilot mihomo update-subscription
```

Mihomo supplies a local HTTP/SOCKS proxy and API. Persistent configuration lives under `~/.config/mihomo`; execution files are staged on the current node. The default proxy/API ports are 42290 and 60290. They must differ. Existing chosen ports are preserved; an unconfigured fresh installation can scan for available ports.

Configure `mihomo.subscription.file` or `.env` in the main YAML. Store the actual subscription URL in the referenced protected file/environment variable. Updates reuse the saved URL; configuration previews and logs do not display it. Complete Clash/Mihomo YAML is required, not an HTML login page or a raw node list.

Updates preserve managed configuration and restore a previously running instance. A new installation does not enable shell proxy changes until those switches are selected. `shell.auto_start_proxy` prepares a configured runtime; `shell.auto_enable_proxy` exports proxy variables only after a real listener is available. `envpilot_proxy_on` and `envpilot_proxy_off` act on the current shell. `envpilot run` affects a child only.

Status checks the process, listening ports, API, proxy egress and recent logs. Unknown or unrelated instances are not silently terminated. The curated cache contains Linux/Windows amd64 Mihomo plus GeoIP data; other platform/offline assets may need to be supplied separately with `--asset-path`.

See [configuration](CONFIG.md), [shell integration](SHELL-CONFIG.md) and [recovery](UPGRADE.md).
