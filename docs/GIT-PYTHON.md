# Git and Python

[简体中文](GIT-PYTHON.zh-CN.md)

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

New shell integration preserves existing command priority. Use `envpilot run` to select managed tools for a child, or configure additional paths deliberately. Configuration parsing itself uses the bundled `envpilot-core`, so installing Python is not a prerequisite for editing or applying YAML.
