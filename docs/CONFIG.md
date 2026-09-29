# Configuration

[简体中文](CONFIG.zh-CN.md)

Run `envpilot init --lang en`, then `envpilot config edit`. Init never overwrites an existing file. `config validate` checks syntax and values; `config show` reports effective settings and their sources. Fields without a source entry use defaults.

The default file is `~/.config/envpilot/config.yaml`. `ENVPILOT_CONFIG_DIR` changes the configuration directory; `--config PATH` selects a file for the current invocation.

Precedence is explicit arguments, declared environment overrides, YAML, then defaults. Supported overrides include `ENVPILOT_LANG`, `ENVPILOT_MODE`, `ENVPILOT_PREFIX`, `ENVPILOT_RELEASE_SOURCE`, `ENVPILOT_CONDA_DISTRIBUTION`, `CODEX_HOME`, `ENVPILOT_CODEX_RUNTIME_DIR`, `ENVPILOT_CODEX_REMOTE_READY_TIMEOUT`, `MIHOMO_PROXY_PORT`, and `MIHOMO_API_PORT`.

| Setting | Meaning/default |
| --- | --- |
| `version` | Configuration format, currently `1`. |
| `language` | `auto`, `en`, or `zh-CN`. |
| `install.components` | Components to install; initially empty. |
| `install.mode` | `online` or `offline`. |
| `install.prefix` | User-space location, initially `~/software`. |
| `install.release_source` | `github` or `gitee`. |
| `shell.enabled` | Install shell integration; true. |
| `shell.conda` | Initialize Conda without activating base; false. |
| `shell.modules` | Modules to load in interactive shells. |
| `shell.auto_start_proxy` | Prepare a configured Mihomo runtime; false. |
| `shell.auto_enable_proxy` | Export proxy variables after readiness; false. |
| `shell.load_secrets` | Load protected variables in the shell; false. |
| `shell.history_sync` | Bash history synchronization; false. |
| `shell.legacy_aliases` | Add unclaimed compatibility names; false. |
| `shell.legacy_local` | Load the previous interactive `shell.local`; preserved during migration. |
| `shell.paths` | Additional paths, appended to preserve existing command priority. |
| `mihomo.proxy_port/api_port` | 42290/60290; distinct integers between 1 and 65535. |
| `mihomo.socks` | Export a SOCKS proxy; false. |
| `mihomo.subscription.file/env` | Subscription file or environment reference, not both. |
| `conda.distribution` | `miniconda` or `anaconda`. |
| `conda.prefix` | Optional existing Conda location. |
| `codex.remote` | Apply node-local Codex integration; false. |
| `codex.home` | `~/.codex`. |
| `codex.runtime` | Optional node-local cache location. |
| `codex.ready_timeout` | Readiness timeout, 60 seconds; range 1–600. |
| `codex.base_url` | API URL for a new Codex config; existing config is preserved. |
| `codex.api_key.file/env` | API-key file or environment reference. |
| `secrets.file` | Assignment-only protected environment file, initially `~/.config/secrets/api.env`. |
| `env` | Ordinary environment variables; sensitive names must use protected references. |

Unknown or duplicate YAML fields, multiple documents and invalid ports are rejected. YAML is never executed as shell code. Apply changes and reload the profile after editing shell settings; shells read generated configuration rather than invoking a YAML parser during startup.

On Unix, protected files must belong to the current user and use mode 600 or 400. Windows uses filesystem ACLs. Keep credentials out of ordinary URLs and `env` entries. Configuration previews show references rather than their contents.

```bash
envpilot plan
envpilot apply --yes --non-interactive
envpilot run -- python3 --version
```

Non-interactive mode never waits for input. Optional fallback installation methods are not automatically accepted. Third-party installer output remains in its original language.

## Complete examples, updates and command priority

[English example](../examples/config.example.en.yaml) and [中文样例](../examples/config.example.zh-CN.yaml) cover every setting and choice. Merge selected fields rather than overwriting existing user settings.

Set `shell.prefer_managed: [git, python]` to prefer installed managed tools in ordinary shells. Default `[]` preserves existing priority. Run `envpilot apply-shell`, open a new shell, then inspect `command -v git` / `command -v python3`. User functions/aliases and activated Conda/venv Python remain intact.

Update fields: `enabled: true`, `interval_days: 3` (1–365), `auto_apply: false`, `components: [mihomo, git, python, conda, mamba, codex, github, tmux]`, `envpilot: true`, `window_start: "03:00"`, `window_end: "05:00"`, `timezone: Local`. Use an explicit zone such as `Asia/Shanghai` when needed. See [updates/history](UPDATES.md).

### Where credentials and subscriptions go

```bash
install -d -m 700 "$HOME/.config/secrets" "$HOME/.config/mihomo"
(umask 077; touch "$HOME/.config/secrets/api.env" "$HOME/.config/mihomo/subscription.url")
chmod 600 "$HOME/.config/secrets/api.env" "$HOME/.config/mihomo/subscription.url"
${EDITOR:-vi} "$HOME/.config/secrets/api.env"
${EDITOR:-vi} "$HOME/.config/mihomo/subscription.url"
```

Put `OPENAI_API_KEY='your-real-key'` inside `api.env`; put just the actual subscription URL on one line inside `subscription.url`. Keep only references in YAML: `secrets.file`, `mihomo.subscription.file`, and `codex.api_key.env: OPENAI_API_KEY`. Codex does not require globally enabling `shell.load_secrets`.

Alternatively set `codex.api_key.file: ~/.config/secrets/codex.key`, containing just the key, and clear `codex.api_key.env`. For a subscription environment reference, set `mihomo.subscription.env: MIHOMO_SUBSCRIPTION_URL` and clear `file`. Scheduled tasks do not inherit variables temporarily exported by an interactive terminal; protected file references are recommended. `secrets` supports only an assignment file, never executable shell content. On Windows, protect the same referenced files using user ACLs.
