# 更新策略与历史

[English](UPDATES.md) · [完整配置样例](../examples/config.example.zh-CN.yaml)

## 三种操作

- `envpilot update COMPONENT`：立即更新一个组件，沿用该组件的安装方式和兼容性判断。`all` 会遍历全部组件，可能安装尚未安装的组件；定时更新不会这样做。
- `envpilot self-update`：立即更新 envpilot、配置工具、入口和已复制的管理器，不自动更新所有组件。
- `envpilot updates run`：执行到期的统一策略；默认每 3 天检查，只有开启 `auto_apply` 且处于安装窗口内才安装。`updates check` 强制检查，但永不安装。

Codex 原本运行时，组件更新负责重建完整 runtime、重启与协议验证；原本停止则保持停止。无需手动拼接 stop/restart。`codex remote status` 和 `updates status` 不联网检查新版本、不安装、不重启。

## 配置与夜间窗口

```yaml
updates:
  enabled: true
  interval_days: 3
  auto_apply: true
  components: [mihomo, git, python, conda, mamba, codex, github, tmux]
  envpilot: true
  window_start: "03:00"
  window_end: "05:00"
  timezone: Asia/Shanghai
```

配置默认 `auto_apply: false`、`timezone: Local`；北京时间需要明确写 `Asia/Shanghai`，避免服务器 UTC 时区造成偏移。时间包含开始、不包含结束，支持跨午夜窗口。每个组件开始安装前再次判断窗口；已经开始的安装允许完成，不在 05:00 强制杀进程。手动更新不受窗口限制。

`interval_days` 为 1–365 天，按经过的小时计算，不使用每月日号取模。网络或安装失败后 1 小时重试；等待安装的版本在下一个允许窗口处理。机器离线/关机期间不会安装，恢复运行后继续检查窗口，不在白天补做夜间安装。时区数据随工具打包。

## 登记定时任务

```bash
envpilot config validate
envpilot updates check
envpilot updates enable
envpilot updates status
envpilot updates disable
```

调度器每小时唤醒一次轻量命令，是否到期由 YAML 和检查状态决定：

| 平台 | 调度器 |
| --- | --- |
| Linux | 可用时使用 systemd 用户 timer，否则使用当前用户 crontab |
| macOS | 当前登录用户的 launchd agent |
| Windows | 当前用户的任务计划程序，不保存密码，需要用户处于登录状态 |

Linux 的 cron 服务必须在运行；systemd 用户实例是否在退出登录后继续，取决于系统的 linger 设置。envpilot 不修改管理员级设置。无可用调度器时会明确失败；也可以在集群调度器中每小时运行 `envpilot updates run`。不需要保持终端打开。

同一用户使用一个 envpilot 更新任务；再次 `enable --config PATH` 切换到指定配置。修改配置内容后无需重建定时任务。`updates.enabled: false` 暂停执行，`updates disable` 注销任务；历史保留。迁移主目录或命令入口后重新登记。

## 组件范围与兼容性

定时任务只处理 `updates.components` 中已经安装的组件。受管 Git/Python、Mihomo、GitHub CLI、tmux，以及已有 Conda/Mamba 和 Codex 使用各自的升级路径。外部或系统安装显示 `external`，交给原包管理器维护；不会偷偷取得管理员权限或替换系统目录。

Git/tmux 的在线更新查询上游稳定版；受管 Python 选择匹配平台的稳定资源。Conda/Mamba 由现有环境的解析器选择兼容版本。上游有新版但安装器保留当前兼容版本时显示 `compatible`，不谎报已升级。开发版/预发布版不自动降级；新组件由 `install` 或 `apply` 显式安装。

所有 envpilot 安装/更新共用进程锁；并发运行会返回 `E_UPDATE_BUSY`，崩溃后锁自动释放。Git 自更新遇到本地修改或分叉停止；旧源码/配置保留。发布包更新校验 SHA-256。共享 home 的多节点应只在选定维护节点登记任务，避免让多个节点反复维护同一持久安装。

## 最近 30 天更新历史

```bash
envpilot updates history
envpilot updates history --days 90
envpilot updates history --days 30 --component git
envpilot updates history --component codex --json
envpilot updates status --json
```

PowerShell 使用 `-Days 90 -HistoryComponent codex -Json`。记录手动/自动的安装与更新时间、组件、更新前后版本和结果。失败保留，版本未变化显示 `unchanged`；进程被强制结束而无法收尾时保留 `in_progress`，不伪造成功。未能探测的版本显示 `?`。

历史存放于 `~/.config/envpilot/updates/history/`，每次操作独立记录，不覆盖此前历史；30 天是默认查询范围，不是删除期限。此功能从 0.4.4 起记录，无法还原以前没有保存的操作。单纯检查不算安装历史。其他包管理器或用户手动在 envpilot 外更新的软件不会自动出现在记录中。

`updates status` 显示上次结果和下一次到期时间。自动安装日志在 `updates/install.log`，超过 2 MiB 后在下次安装前保留上一份；文件权限受保护。结构化状态/历史只记录版本和稳定错误码，不包含密钥、订阅或原始错误内容。
