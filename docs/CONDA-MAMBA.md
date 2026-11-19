# Conda and Mamba

[简体中文](CONDA-MAMBA.zh-CN.md)

```bash
envpilot install conda
envpilot install conda --conda-distribution anaconda
envpilot update conda
envpilot install mamba
envpilot update mamba
```

Miniconda is the default. Set `conda.distribution` in YAML to select Anaconda. Linux installers are selected for the detected architecture and glibc; old hosts use compatible official archives. Existing environments are preserved during supported in-place base upgrades.

Set `conda.condarc_policy: preserve` (default) to keep an existing `~/.condarc`. A new installation with no file uses the repository template with TUNA conda-forge and bioconda. To apply the template over a custom file, choose `template`. An online Conda update shows proposed changed configuration keys and the solver's base package additions, replacements and removals before confirmation. Existing configuration is backed up when replaced. After a failed dry run, use `conda update -n base conda --dry-run` for upstream diagnostics. Mamba uses its own conda-forge bootstrap transaction.

Update checks give Conda/Mamba up to 60 seconds on shared storage. The version probe and update both clear inherited Python, loader, channel and solver overrides and select the home `.condarc`. `E_UPDATE_PROBE_TIMEOUT` means the process exceeded its deadline. `E_UPDATE_PROBE_COMMAND` means the process failed. `E_UPDATE_PROBE_FORMAT` means a successful process returned an unrecognized version.

Shell initialization is controlled by `shell.conda` and optional `conda.prefix`. It is not enabled by default for fresh users. When migrating an existing installation, previous switches and `shell.local` are retained. Do not copy obsolete initialization blocks into the new managed loader.

Useful checks:

```bash
conda info --base
conda env list
conda config --show-sources
conda config --show channels default_channels channel_priority auto_activate_base
```
