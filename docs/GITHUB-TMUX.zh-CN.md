# GitHub CLI 和 tmux

## GitHub CLI

~~~bash
bash envpilot.sh install github
bash envpilot.sh update github
gh --version
~~~

envpilot 只更新自己安装的用户态副本，不强制覆盖管理员提供的系统 gh。登录和 token 管理仍由 GitHub CLI 自己负责。

## tmux

~~~bash
bash envpilot.sh install tmux
bash envpilot.sh update tmux
tmux -V
~~~

安装顺序：先检查系统命令和 HPC module；如果版本已达到 manifest stable 目标，直接复用；如果系统/module 版本过低且没有管理员权限，则在用户目录构建新版本，并让 ~/.local/bin/tmux 优先。

tmux 不通过 Conda/Mamba 安装。Windows 原生环境不承诺 tmux，优先使用 WSL、MSYS2 或 Git Bash。

## 常见检查

~~~bash
command -v gh
gh --version
command -v tmux
tmux -V
~~~
