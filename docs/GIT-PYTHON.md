# Git and Python

[简体中文](GIT-PYTHON.zh-CN.md)

Run `envpilot preflight git` and `envpilot preflight python` on the maintenance node using the scheduler's account. Git probes compile, link and execute small programs. Python checks the package platform and the installation filesystem's execution and symbolic link support. Both accept `--json`.

Linux Git 2.56 builds can use OpenSSL when the host lacks a working getrandom interface. The optional Rust code can be disabled so Cargo is unnecessary. To use site-specific development libraries or a compiler directory, merge these fields into the main configuration:

```yaml
git:
  dependency_prefix: ~/anaconda3
  toolchain_bin: ""   # Optional directory containing compiler/build tools
  build_jobs: 2       # Match the CPU allocation
```

Defaults suit hosts with standard tools and libraries. Manual and scheduled Git builds read the same settings. Store site settings in YAML so they survive scheduler re-registration.

Standalone Python downloads use the upstream SHA-256 associated with the exact release asset. Offline archives need a matching bundled manifest entry or a trusted adjacent `SHA256SUMS` or `<archive>.sha256`. The digest and staged interpreter are verified before activation.

```bash
envpilot install git
envpilot update git
envpilot install python
envpilot update python
envpilot run -- git --version
envpilot run -- python3 --version
```

Git requires version 2.30 or newer. A compatible system/module installation is reused; otherwise envpilot builds a user-space copy without replacing system Git. A compiler and build prerequisites are needed for source builds.

Python requires version 3.9 or newer. Existing system or Conda interpreters are preferred. Standalone assets are selected for OS, architecture and libc; incompatible latest releases are not installed on older glibc hosts.

On Linux/macOS each new standalone archive is extracted into a fresh version directory. A package's `bin/python3` may be a relative link to its versioned interpreter. EnvPilot verifies that both paths resolve inside the archive, runs the interpreter in isolated mode to check the exact version and import its standard library, then switches `python/current`. A failed validation leaves the previously active interpreter usable.

New shell integration preserves existing command priority. Use `envpilot run` to select managed tools for a child, or configure additional paths deliberately. Configuration parsing itself uses the bundled `envpilot-core`, so installing Python is not a prerequisite for editing or applying YAML.
