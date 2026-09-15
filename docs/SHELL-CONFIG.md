# Shell integration

[简体中文](SHELL-CONFIG.zh-CN.md)

Version 0.4.0 adds a short loading block instead of replacing the profile:

```bash
envpilot apply-shell
envpilot shell remove
```

The block is delimited by `# >>> envpilot >>>` and `# <<< envpilot <<<`. Content outside it remains unchanged. Repeated application does not add duplicate blocks. Independent scripts and generated settings live in `~/.config/envpilot/shell/`; startup does not download files or parse YAML.

New users only get the envpilot command integration. Explicitly enable Conda, proxy, modules, history or compatibility aliases in YAML. Helpers use the envpilot namespace. Legacy `proxy_on`, `proxy_off`, `mihomo` and `codex_ready` names are added only when compatibility is enabled and the name is unclaimed.

`envpilot_proxy_on` enables the current shell proxy after the port is ready; `envpilot_proxy_off` clears it. A child process cannot modify its parent shell. Use `envpilot run -- COMMAND ...` for a separate configured environment.

Existing `shell.local` is retained and loaded interactively when `shell.legacy_local` is enabled. Ordinary environment variables belong in YAML `env`, extra paths in `shell.paths`, and credentials in protected references. Non-interactive shells skip Conda, modules and interactive history; configured proxy preparation remains quiet and bounded.

Exact historical profile templates can migrate automatically. Modified legacy profiles remain available and produce `migration-pending.txt` for a one-time review. Complex user functions are not guessed. `BASHRC_PROFILE_ACTIVE` and `ENVPILOT_LAST_*` belong to legacy compatibility, not new configuration.

Use self-update to refresh installed files, or re-register after moving the checkout. See [upgrade and recovery](UPGRADE.md).
