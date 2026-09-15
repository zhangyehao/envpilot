# Upgrade and recovery

[简体中文](UPGRADE.zh-CN.md)

Run `envpilot self-update` with an existing command installation. Git checkouts must be clean and fast-forwardable to the stable release. Diverged branches and local edits are preserved. Platform-package upgrades verify SHA-256 and install into a new version directory.

For the first upgrade from 0.3.0 or earlier, update the source checkout or extract a platform package, then run:

```bash
bash envpilot.sh setup-command
export PATH="$PATH:$HOME/.local/bin"
envpilot init --lang en
envpilot config show
envpilot plan
envpilot apply
```

Skip init if YAML already exists. Recognized literal legacy switches, ports and modules are imported without executing shell code. Existing `shell.local`, protected credentials and `auth.json` are preserved.

Exact historical profile templates migrate automatically. Modified legacy profiles remain unchanged and produce `migration-pending.txt`. Review the backup, preserve custom content in your own profile, then run `apply-shell`. Complex functions are not guessed or discarded.

Changes create a new managed-file snapshot. Existing snapshots remain immutable, and `doctor` no longer replaces recovery baselines.

```bash
envpilot doctor
envpilot snapshot
envpilot restore
envpilot restore /actual/config/directory/snapshots/TIMESTAMP
```

Snapshots cover managed configuration and scripts, not every external package-manager transaction, third-party database, or Codex session. Restore falls back to the legacy baseline when no new snapshot exists. `rollback` retains its single-file-backup purpose.

Updating Codex restarts a previously running service using the new runtime; stopped services remain stopped. After restoring files, run `envpilot codex remote restart` when a service restart is needed.
