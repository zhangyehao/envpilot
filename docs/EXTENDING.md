# Extending envpilot

[简体中文](EXTENDING.zh-CN.md)

## Component contract

Bash components expose `ep_doctor_<name>()` and `ep_install_<name>()`; PowerShell provides the equivalent platform adapter. Preserve supported installation methods, user-space locations and existing system tools. Prefer the newest stable release compatible with OS, architecture and libc. Exclude alpha, beta, rc and nightly assets.

Configuration is parsed by `envpilot-core`, using the maintained Go YAML library. Add new fields to the shared schema, validation, adapter export, documentation and tests. Do not parse arbitrary YAML using shell substitutions. Ordinary environment settings, protected references and operational state are distinct.

Every installer reports the component, selected source, destination and result. Configuration application supplies one confirmation; an optional default-no fallback remains declined in non-interactive mode. Missing required inputs must fail without reading stdin. Use the shared message catalog for user-facing text; preserve stable machine fields and upstream diagnostic output.

## Shell integration

`apply-shell` preserves user profile content and updates only the marked loading block. Implementation lives under the envpilot configuration directory, with namespaced helpers. New users opt in to proxy startup, Conda, modules, history and compatibility aliases. Preserve previous switches when migrating existing installations.

Do not execute profiles to discover settings. Only import understood literal assignments. Match known historical templates exactly before replacing an old managed profile; modified legacy files must remain available for review. Keep user-owned `shell.local` and credential files.

Interactive initialization does not belong in non-interactive SSH/scp/rsync startup. Proxy variables require a listening port; preserve existing no_proxy values. Parent-shell changes require explicit shell integration; `envpilot run` only changes its child.

## Codex lifecycle

Discover the same target consistently in status, stop, ready, enable and restart. Verify user, node, CODEX_HOME/control socket, and process start identity. Matching Desktop/SSH instances are within the selected target; unrelated or unidentified owners are not.

Serialize lifecycle operations. Keep control state, auth and sessions persistent. Cache reconstructible binaries and required helpers in versioned node-local directories; never copy an arbitrary PATH directory wholesale. Validate staging before stopping a working service. Reuse only a healthy matching generation, and verify a new process for restart. Native daemon capability alone is insufficient: its fixed installation path must match the intended runtime.

Ordinary installation preserves usable or slow-to-probe artifacts. Updates preserve standalone/npm methods, retain authentication/configuration, and refresh a previously running server. A stopped service remains stopped. Standalone installation uses `CODEX_NON_INTERACTIVE=1`; optional npm fallback is an explicit choice.

## Recovery

Doctor is diagnostic-only. Create a new immutable snapshot before managed changes; never overwrite earlier recovery points. Record newly created managed files even when their parent directory already existed. Restore remains compatible with legacy baseline.tsv. State clearly that managed-file snapshots do not reverse every external package-manager transaction or modify session history.

Subscription URLs, API keys, controller credentials, auth files and runtime logs must not enter Git history. Protected Unix files require current-user ownership and mode 600/400. Tests use synthetic credentials and isolated homes.

## Components and caching

Mihomo installs before network-dependent components. Preserve selected ports and managed configuration, and restart a previously running instance after updates. The curated downloads cache includes Linux/Windows amd64 Mihomo plus country.mmdb and geoip.metadb; other offline assets remain user-provided.

Conda defaults to Miniconda and selects compatible archives on old glibc. Preserve environments during an in-place base upgrade. Mamba preserves user .condarc and uses its isolated bootstrap channel/solver. Git/Python/tmux prefer compatible existing tools and user-space upgrades, without replacing system glibc.

## Tests and release

Run Go tests, Bash and PowerShell regression/integration tests, Python maintenance tests, ShellCheck, actionlint and git diff --check. Include fresh and upgraded profiles, arbitrary user commands, non-interactive flows, malformed configuration, real socket/process behavior, and network/transaction failures.

PR tests use read-only permissions. Scheduled updaters stage and validate complete changes before replacing files and use a private GitHub App installed only on envpilot, with Contents/Pull requests write permissions. Repository variable ENVPILOT_APP_ID and secret ENVPILOT_APP_PRIVATE_KEY configure it. Never put tokens or keys into files committed to the repository.

Update VERSION and CHANGELOG, verify the exact release commit, and publish immutable version tags. Package source plus platform-specific envpilot-core binaries and SHA256SUMS. Confirm GitHub/Gitee main and tags match; never force-push a mirror or move a released tag. Mirror scripts must verify the remote results, not merely print success after attempting a push.
