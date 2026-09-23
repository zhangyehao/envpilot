# Codex

[简体中文](CODEX.zh-CN.md)

## Complete runtime packages (0.4.3)

Versions 0.4.0–0.4.2 flattened selected top-level package files into `bin/`, omitting the nested code-mode host, PATH helpers and resources. Version 0.3.0 copied the selected `bin/` directory and retained sibling executables, but did not guarantee resources alongside that directory. A successful main-binary probe or app-server handshake does not establish package completeness.

Version 0.4.3 reads `codex-package.json`, retains the entire package tree, permissions and internal links, and fingerprints all assets. It activates only a fully copied, verified generation. Resource-only updates and missing/corrupt cache files invalidate the cache; incomplete sources cannot replace the working generation. npm vendor packages retain their platform tree; arbitrary PATH directories are not copied wholesale.

```bash
envpilot codex remote enable
envpilot codex remote verify  # Read-only comparison of all package assets.
envpilot codex remote repair  # Rebuild and restart.
```

Each generation records `.runtime-manifest.json` and a full content fingerprint. User configuration, model-catalog JSON, authentication and sessions remain in persistent CODEX_HOME. File completeness and host compatibility are separate: the musl main binary may bundle helpers with newer glibc requirements (for example, zsh in 0.156.0). Do not replace system glibc to work around this.

## Model discovery and refresh

Leave `model_catalog_json` unset by default. Codex and the selected provider should own model discovery; downloaded caches and bundled metadata are fallbacks, not a reason to fabricate model capabilities to fill the picker.

In Codex 0.156.0, API-key discovery is gated by `features.api_key_model_discovery` (disabled by default). Custom providers also need a Codex-native catalog endpoint configured as `model_providers.<id>.model_catalog_url`. A standard OpenAI-compatible `/v1/models` response containing IDs is not interchangeable with the rich Codex catalog. Verify provider routing, authentication, response format and cache state before claiming upstream refresh works.

## Optional: fixed custom model catalogs

Use this only when the user explicitly wants a local, static catalog. It replaces dynamic discovery and is not a solution for automatic upstream refresh. envpilot does not create or enable this override by default.

A JSON file in CODEX_HOME is not loaded automatically. Set the actual absolute path at the top level of `config.toml`, before any `[section]`:

```toml
model_catalog_json = "/actual/home/.codex/models.json"
```

Restart the app-server after changes. Entries marked `visibility: "hide"` remain hidden by default; `model/list` with `includeHidden: true` includes them. A listed model still requires provider-side support. See the official [configuration reference](https://developers.openai.com/codex/config-reference/) and [app-server protocol](https://developers.openai.com/codex/app-server/).

```bash
envpilot install codex
envpilot update codex
envpilot codex remote enable
envpilot codex remote status
envpilot codex remote restart
envpilot codex remote stop
envpilot codex remote enable
```

Linux/macOS default to the official non-interactive standalone installer. Existing installation methods are preserved, standalone takes precedence when npm also exists, and a slow shared-filesystem version probe is not treated as a missing executable. Existing configuration and authentication remain user-owned.

Remote lifecycle operations identify the current user's instance on this node for the selected control socket, including Desktop/SSH instances. Missing PID files do not prevent discovery. Process identity is checked before signaling; unidentified owners and other Codex homes are preserved.

Version 0.4.1 resolves the control socket symlink used by Codex 0.156.0, including node-local targets under `/tmp/codex-daemon-UID/`. If 0.4.0 reports a running process as not ready, follow the [upgrade commands](UPGRADE.md), then run `envpilot codex remote enable`. A manual kill is unnecessary. Keep the control directory persistent; the socket file inside it may be a Codex-managed symlink. Upstream warnings about unrecognized configuration settings do not themselves indicate startup failure; envpilot preserves user configuration.

Restart verifies a new process, its runtime generation and a JSON-RPC handshake. Ready can reuse a healthy matching generation. Repair rebuilds the runtime. Updating Codex restarts a previously running service; stopped services remain stopped. Active requests may be interrupted, while persistent credentials, configuration and sessions are retained.

The 0.154.0 native daemon interface requires a fixed standalone installation path. envpilot checks both capabilities and layout; it directly starts a verified node-local runtime when native start cannot launch that target. Only reconstructible binaries and required helpers belong in the node-local cache. Persistent control state stays under CODEX_HOME.

Version 0.4.2 also handles Desktop/SSH reconnects that start a replacement during restart. It rediscovers the socket owner and verifies the user, Codex home, runtime files and protocol version before accepting a new PID. Product names with spaces, such as `Codex Desktop/0.156.0`, are supported. Unidentified owners and other homes remain protected. If a supervisor keeps reviving the service during stop, the command reports failure instead of claiming the service is stopped.

Use YAML secret references for OPENAI_API_KEY; do not paste credentials into scripts, logs or repository files. Native login remains available through `codex login`. See [configuration](CONFIG.md) and [recovery](UPGRADE.md).
