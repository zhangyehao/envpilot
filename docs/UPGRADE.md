# Upgrade and recovery

[简体中文](UPGRADE.zh-CN.md)

## Update an existing 0.4.x installation

```bash
envpilot self-update
envpilot version
envpilot config validate
envpilot plan
```

Git checkouts must be clean and fast-forwardable to the stable release. Diverged branches and local edits are preserved. Platform-package upgrades verify SHA-256 and install into a new version directory. Update individual components separately with `envpilot update COMPONENT`.

## Update an existing source checkout

For a checkout at `~/envpilot`, run the following command. Adjust the path when installed elsewhere:

```bash
cd "$HOME/envpilot" && git pull --ff-only origin main
```

Continue to registration below only after the pull succeeds. Do not clone into the existing directory or rename it for a routine upgrade. If local changes or a diverged branch prevent updating, inspect `git status` and save your changes; do not force-reset the checkout.

Only when no checkout exists, clone it first:

```bash
git clone https://github.com/zhangyehao/envpilot.git "$HOME/envpilot" && cd "$HOME/envpilot"
# Alternative repository URL:
# https://gitee.com/zhangyehao0422/envpilot.git
```

Run `bash envpilot.sh ...` inside the checkout, or use `bash "$HOME/envpilot/envpilot.sh" ...`. Cloning does not change the working directory.

## Upgrade using a platform package (Linux/macOS)

This downloads the fixed 0.4.3 release for your OS and architecture, verifies SHA-256, and extracts to a new directory. The package includes the configuration helper and leaves the old checkout available:

```bash
(
  set -eu
  version=0.4.3
  case "$(uname -s)" in Linux) os=linux ;; Darwin) os=darwin ;; *) echo 'Select a package for your OS'; exit 1 ;; esac
  case "$(uname -m)" in x86_64|amd64) arch=amd64 ;; aarch64|arm64) arch=arm64 ;; armv7l) arch=armv7 ;; *) echo 'Unsupported architecture'; exit 1 ;; esac
  asset="envpilot-$version-$os-$arch.tar.gz"
  base="https://github.com/zhangyehao/envpilot/releases/download/v$version"
  # Only with a complete Gitee release: base="https://gitee.com/zhangyehao0422/envpilot/releases/download/v$version"
  mkdir -p "$HOME/Downloads/envpilot-$version"
  cd "$HOME/Downloads/envpilot-$version"
  curl -fL --retry 3 "$base/$asset" -o "$asset"
  curl -fL --retry 3 "$base/SHA256SUMS" -o SHA256SUMS
  awk -v name="$asset" '$2 == name {print}' SHA256SUMS > selected.sha256
  test -s selected.sha256
  if command -v sha256sum >/dev/null; then sha256sum -c selected.sha256; else shasum -a 256 -c selected.sha256; fi
  mkdir -p "$HOME/.local/share/envpilot/releases"
  test ! -e "$HOME/.local/share/envpilot/releases/envpilot-$version"
  tar -xzf "$asset" -C "$HOME/.local/share/envpilot/releases"
)
```

After all commands succeed, enter the extracted directory. If it already exists, inspect its contents instead of overwriting it:

```bash
cd "$HOME/.local/share/envpilot/releases/envpilot-0.4.3"
```

## Register the command and apply configuration

Run these commands inside the updated checkout or extracted platform package:

```bash
bash envpilot.sh setup-command
export PATH="$PATH:$HOME/.local/bin"
if [ ! -f "${ENVPILOT_CONFIG_DIR:-$HOME/.config/envpilot}/config.yaml" ]; then
  envpilot init --lang en
fi
envpilot config validate
envpilot config show
envpilot plan
envpilot apply
```

If using a custom `--config` path, continue passing that path and skip init. Recognized literal legacy switches, ports and modules are imported without executing shell code. Existing `shell.local`, protected credentials and `auth.json` are preserved.

For the 0.4.0 issue where Codex 0.156.0 runs but reports its socket as not ready, refresh copied scripts and check the service from a separate terminal. No manual kill is required:

```bash
envpilot codex remote enable
envpilot codex remote status
# To explicitly recreate the service:
envpilot codex remote restart
```

Version 0.4.1 resolves Codex's socket symlink when checking listeners and process ownership. Keep the `app-server-control` directory on persistent storage; the socket file inside it may be a Codex-managed symlink.

## Migration and recovery

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
