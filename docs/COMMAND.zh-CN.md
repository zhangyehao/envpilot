# envpilot 命令入口

## 安装与使用

首次可以确认执行 `bash envpilot.sh apply-shell`，随后加载 profile；也可以独立执行：

```bash
bash /path/to/envpilot/envpilot.sh setup-command
export PATH="$HOME/.local/bin:$PATH"
envpilot doctor
envpilot install
envpilot update codex
envpilot codex remote restart
```

独立登记不会重写 profile、安装组件或启动服务。后续终端需将 `~/.local/bin` 放入 PATH；受管 Bash/zsh 模板已有这项配置。纯非交互环境未设置 PATH 时，使用 `~/.local/bin/envpilot ...`。启动器不加载完整 `.bashrc`，保留当前目录、参数边界和退出码，不额外输出。

## 仓库与恢复

- `~/.local/bin/envpilot` 是薄 Bash 启动器，不是仓库入口的直接软链接。
- `~/.config/envpilot/command-root` 保存显式登记的绝对路径，只由 setup-command / 已确认的 apply-shell 更新。
- 现有 `repo-root` 仍记录最近运行的仓库；它不会改变正式命令登记。
- `git pull` 更新后直接使用新代码。仓库移动后，从新位置重新执行 setup-command；不存在时会明确报错，不搜索或执行其他副本。
- 不覆盖非受管同名文件或符号链接；请先人工核对并改名。重复登记会备份受管文件；doctor baseline 包含入口和登记文件，可使用既有 restore/rollback 机制恢复。
- 原生 Windows PowerShell 仍使用 envpilot.ps1；这个 Bash 启动器不替代 PowerShell 安装方式。

## app-server 重启

```bash
envpilot codex remote status
envpilot codex remote restart
envpilot codex remote status
```

restart 使用仓库当前的 remote manager 实现，不必先重新安装 Codex。它会刷新可重建 runtime（仅在需要时），串行执行停止与新建，输出新旧 PID，重新执行环境加载逻辑；当前进程显式设置的环境变量仍优先于 api.env。不会删除 auth.json、配置、会话或持久控制目录。

重启会断开连接或中断当前请求，不保证任务完成后才退出；请在独立 SSH 终端操作，并先保存工作。只允许重启 PID 文件记录的受管 app-server。遇到 Desktop 等非受管 app-server 时，先正常退出对应连接/进程，再重试。无法确认 socket 归属或有竞争实例时返回失败，不假报成功。

ready 是检查并复用/启动；restart 要求新实例；repair 强制重建 runtime 缓存；stop 仅停止受管实例。
