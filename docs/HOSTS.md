# Moving to another server

Export your component selection, Mihomo group order and update policies on the original server. The TOML export includes the top-level Codex `model` and `model_reasoning_effort` when set. Recreate any named Codex profiles separately.

```bash
envpilot config export --portable > envpilot-preferences.yaml
envpilot config export --codex-preferences > codex-preferences.toml
scp envpilot-preferences.yaml codex-preferences.toml new-host:
```

After installing envpilot on the destination, run the following commands in the SSH session used for this node. If a main configuration already exists, use `envpilot config edit` to merge the exported fields into its existing sections.

```bash
mkdir -p "$HOME/.config/envpilot"
if [ ! -e "$HOME/.config/envpilot/config.yaml" ]; then
  install -m 600 "$HOME/envpilot-preferences.yaml" "$HOME/.config/envpilot/config.yaml"
fi
envpilot config migrate --preview
envpilot config migrate --yes
envpilot preflight
envpilot config edit
envpilot config validate
envpilot doctor
```

Merge the TOML fields at the top level of the destination's `~/.codex/config.toml`, editing any existing field in place. Choose host-specific paths, proxy ports, provider and secret references on the new machine. Set protected Unix files to mode 600.

Preflight reports architecture, Linux glibc, home filesystem, writable and executable temporary storage, available scheduler commands and the Codex path resolved in the invoking session. It sends an HTTPS HEAD request through the configured local Mihomo proxy to the selected release site. Use `--json` for machine-readable results. To verify the environment used by Desktop, use the same SSH user, node and launch mode and run `envpilot preflight` and `envpilot codex remote verify`.

For a shared home, set `updates.maintenance_host` to the node responsible for updating the persistent installation. Run `envpilot updates enable` and `envpilot doctor` there and verify the node-local runtime on each login node you intend to use.
