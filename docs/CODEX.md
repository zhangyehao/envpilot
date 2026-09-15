# Codex

[简体中文](CODEX.zh-CN.md)

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

Restart verifies a new process, its runtime generation and a JSON-RPC handshake. Ready can reuse a healthy matching generation. Repair rebuilds the runtime. Updating Codex restarts a previously running service; stopped services remain stopped. Active requests may be interrupted, while persistent credentials, configuration and sessions are retained.

The 0.154.0 native daemon interface requires a fixed standalone installation path. envpilot checks both capabilities and layout; it directly starts a verified node-local runtime when native start cannot launch that target. Only reconstructible binaries and required helpers belong in the node-local cache. Persistent control state stays under CODEX_HOME.

Use YAML secret references for OPENAI_API_KEY; do not paste credentials into scripts, logs or repository files. Native login remains available through `codex login`. See [configuration](CONFIG.md) and [recovery](UPGRADE.md).
