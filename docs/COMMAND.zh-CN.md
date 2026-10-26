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

## 统一更新命令（0.4.4）

`update COMPONENT` 立即更新组件；`self-update` 立即更新 envpilot 自身。`updates check` 立即检查、不安装；`updates run` 执行到期策略并遵守夜间窗口；`updates enable/disable` 登记/注销任务；`updates status` 读取保存状态。

`envpilot updates history` 默认查询最近 30 天；`--days 90 --component codex --json` 可调整范围、筛选和导出。PowerShell 使用 `-Days 90 -HistoryComponent codex -Json`。详见 [更新与历史](UPDATES.zh-CN.md)。

要让普通 Shell 优先使用受管 Git/Python，设置 `shell.prefer_managed: [git, python]` 后 `apply-shell` 并重开终端；已激活的 Python 环境仍优先。

## Mihomo 节点与订阅（0.4.5）

`envpilot mihomo select` 按编号交互选择策略组和节点；`nodes` 查看候选项，`test "策略组"` 只测试组内直接代理节点。嵌套组和 DIRECT/REJECT 需用 `test "策略组" "成员名"` 明确指定。脚本使用完整参数：`envpilot mihomo select "策略组" "节点名" --non-interactive`；这些节点命令均支持 `--json`。选择独立保存，`restart`、停止后启动及订阅更新会恢复仍有效的选择。

`envpilot mihomo update-subscription` 更新完整配置，默认先直连、失败后尝试代理；`--network direct|proxy|auto` 覆盖网络路径。无法下载时上传完整 Clash YAML，Unix 上先执行 `chmod 600 PATH`，再执行 `envpilot mihomo update-subscription --file PATH`。下载失败保留原配置和运行服务。订阅 URL 通过受保护文件或环境引用读取。

PowerShell 对应选项为 `-Network`、`-SubscriptionFile`、`-Json`、`-NonInteractive`，也支持上述双横线写法。详见 [Mihomo](MIHOMO.zh-CN.md)。
