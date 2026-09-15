# GitHub CLI and tmux

[简体中文](GITHUB-TMUX.zh-CN.md)

```bash
envpilot install github
envpilot update github
gh auth login
envpilot install tmux
envpilot update tmux
tmux -V
```

GitHub CLI authentication remains managed by `gh`; envpilot does not store GitHub access tokens in its main configuration. Existing installations outside envpilot are preserved rather than overwritten.

tmux reuses a suitable existing system/module version. Where an upgrade is needed and administrator access is unavailable, it builds a user-space command with compatible dependencies. It is not installed into Conda/Mamba. Build tools may be required on Unix; native Windows users should use WSL for tmux.

Use `envpilot doctor` to inspect command resolution and `envpilot run -- tmux -V` to select a managed tool in a child environment.
