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

Conda installation/update backs up and applies the repository's channel configuration. The default channels use TUNA conda-forge and bioconda, with base auto-activation disabled. Mamba preserves `.condarc` and uses an isolated conda-forge bootstrap transaction. A sufficiently recent Conda base is required before Mamba installation.

Shell initialization is controlled by `shell.conda` and optional `conda.prefix`. It is not enabled by default for fresh users. When migrating an existing installation, previous switches and `shell.local` are retained. Do not copy obsolete initialization blocks into the new managed loader.

Useful checks:

```bash
conda info --base
conda env list
conda config --show-sources
conda config --show channels default_channels channel_priority auto_activate_base
```
