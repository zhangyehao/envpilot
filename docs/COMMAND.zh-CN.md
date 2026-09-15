# 命令入口

0.3.0 起，确认执行 `apply-shell` 会安装 `~/.local/bin/envpilot`。也可以只登记入口：

```bash
bash /实际仓库路径/envpilot.sh setup-command
export PATH="$PATH:$HOME/.local/bin"
envpilot doctor
```

入口与 `bash /实际仓库路径/envpilot.sh ...` 等价，保留调用目录、参数和退出码。登记文件为 `~/.config/envpilot/command-root`；临时运行另一份仓库不会隐式切换登记。仓库移动后重新登记，已有非 envpilot 同名文件不会被覆盖。

0.4.0 的 PowerShell 用户态入口为 `~/.local/bin/envpilot.ps1`，同样可从任何目录运行。PowerShell 选项使用 `-Config`、`-Lang`、`-Yes` 和 `-NonInteractive`。

`apply-shell` 现在仅添加短加载块，见 [Shell 接入](SHELL-CONFIG.zh-CN.md)。服务生命周期见 [Codex](CODEX.zh-CN.md)，统一配置见 [配置说明](CONFIG.zh-CN.md)。
