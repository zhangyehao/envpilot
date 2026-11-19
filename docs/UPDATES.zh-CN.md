# 更新策略与历史

[English](UPDATES.md) · [完整配置样例](../examples/config.example.zh-CN.yaml)

## 三种操作

- `envpilot update COMPONENT`：立即更新一个组件，沿用该组件的安装方式和兼容性判断。`all` 会遍历全部组件，可能安装尚未安装的组件；定时更新不会这样做。
- `envpilot self-update`：立即更新 envpilot、配置工具、入口和已复制的管理器，不自动更新所有组件。
- `envpilot updates run`：执行到期的统一策略；默认每 3 天检查，只有开启 `auto_apply` 且处于安装窗口内才安装。`updates check` 强制检查，但永不安装。

首次执行 `envpilot init` 可选择仅检查或夜间安装。无人值守初始化用 `envpilot init --policy check` 或 `envpilot init --policy nightly`。保存主配置并执行 `envpilot setup-command`、`envpilot updates enable` 后，系统调度器开始唤醒 envpilot。

Codex 有活跃任务时延后切换，返回 `deferred`。下一次允许安装时重试切换，核验正在监听的 app-server。`envpilot codex remote status` 显示最近检查到的上游版本和本节点运行情况。

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
  maintenance_host: "login02"
  policies:
    codex: {interval_days: 1, auto_apply: true, window_start: "03:00", window_end: "05:00"}
    conda: {auto_apply: false}
    mamba: {auto_apply: false}
  subscription: {enabled: true, interval_days: 3}
  models: {enabled: true, interval_days: 1}
```

配置默认 `auto_apply: false`、`timezone: Local`；北京时间需要明确写 `Asia/Shanghai`，避免服务器 UTC 时区造成偏移。时间包含开始、不包含结束，支持跨午夜窗口。每个组件开始安装前再次判断窗口；已经开始的安装允许完成，不在 05:00 强制杀进程。手动更新不受窗口限制。

`policies` 的四个字段均可独立覆盖；省略或填 `null` 继承全局，显式 `false` 仅检查。所有受支持组件及 envpilot 都可配置。上例让 Codex 每天检查并在窗口内安装，让 Conda、Mamba 只检查。共享 home 可将 `maintenance_host` 设为实际维护节点的短主机名或完整域名；其他节点仍可检查并核验自己的 Codex 实例。空字符串允许当前节点执行维护。

`subscription.enabled` 默认关闭。开启后，仅在维护节点的 Mihomo 窗口内调用 `envpilot mihomo update-subscription`，沿用现有下载、校验和已保存的节点选择。订阅引用写在 `mihomo.subscription.file` 或 `mihomo.subscription.env`，不要把 URL 写入策略。此开关可独立于软件自动安装启用。手动 `updates check` 只检查软件和模型，不替换订阅。`models.enabled` 默认开启，每三天对已安装的 Codex 刷新目录。用 `envpilot codex models status` 查看各来源。

`interval_days` 为 1–365 天，按经过的小时计算，不使用每月日号取模。网络或安装失败后 1 小时重试；等待安装的版本在下一个允许窗口处理。机器离线/关机期间不会安装，恢复运行后继续检查窗口，不在白天补做夜间安装。时区数据随工具打包。

## 登记定时任务

```bash
envpilot config validate
envpilot updates check
envpilot updates enable
envpilot updates status
envpilot updates disable
```

新版调度每分钟检查是否到期，只有到期组件才执行探测、下载或安装，以支持短于一小时的维护窗口。已有小时任务可执行 `envpilot updates enable` 刷新登记。平台使用以下调度器。

| 平台 | 调度器 |
| --- | --- |
| Linux | 可用时使用 systemd 用户 timer，否则使用当前用户 crontab |
| macOS | 当前登录用户的 launchd agent |
| Windows | 当前用户的任务计划程序，不保存密码，需要用户处于登录状态 |

Linux 的 cron 服务必须在运行；systemd 用户实例是否在退出登录后继续，取决于系统的 linger 设置。使用自己的集群调度器时，定时调用 `envpilot updates tick`，可记录实际触发时间。普通手动检查或 `updates run` 不计为系统触发。

`envpilot doctor` 将默认策略、各组件覆盖、实际调度登记、上次触发与结果、最近成功检查、安装时间和下个窗口放在同一份报告。出现“未登记”时运行 `updates enable`。“已登记”但从未触发或超过两小时未触发时，检查系统定时服务和登录节点。单个组件失败可见稳定错误码；其他组件的成功状态独立保存。机器可读结果见 `envpilot doctor --json`。

同一用户使用一个 envpilot 更新任务；再次 `enable --config PATH` 切换到指定配置。修改配置内容后无需重建定时任务。`updates.enabled: false` 暂停执行，`updates disable` 注销任务；历史保留。迁移主目录或命令入口后重新登记。

## 组件范围与兼容性

定时任务只处理 `updates.components` 中已经安装的组件。受管 Git/Python、Mihomo、GitHub CLI、tmux，以及已有 Conda/Mamba 和 Codex 使用各自的升级路径。外部或系统安装显示 `external`，交给原包管理器维护；不会偷偷取得管理员权限或替换系统目录。

Git/tmux 的在线更新查询上游稳定版；受管 Python 选择匹配平台的稳定资源。Conda/Mamba 由现有环境的解析器选择兼容版本。上游有新版但安装器保留当前兼容版本时显示 `compatible`，不谎报已升级。开发版/预发布版不自动降级；新组件由 `install` 或 `apply` 显式安装。

所有 envpilot 安装/更新共用进程锁；并发运行会返回 `E_UPDATE_BUSY`，崩溃后锁自动释放。Git 自更新遇到本地修改或分叉停止；旧源码/配置保留。发布包更新校验 SHA-256。共享 home 时在 updates.maintenance_host 指定负责写入持久安装的节点，并在其上登记任务。需要自动核验本地 Codex 的其他节点可分别登记；登记脚本和运行记录按节点保存。

## 最近 30 天更新历史

```bash
envpilot updates history
envpilot updates history --days 90
envpilot updates history --days 30 --component git
envpilot updates history --component codex --json
envpilot updates history --component subscription
envpilot updates status --json
```

PowerShell 使用 `-Days 90 -HistoryComponent codex -Json`。记录手动/自动的安装与更新时间、组件、更新前后版本和结果。失败保留，版本未变化显示 `unchanged`；进程被强制结束而无法收尾时保留 `in_progress`，不伪造成功。未能探测的版本显示 `?`。

历史存放于 `~/.config/envpilot/updates/history/`，每次操作独立记录，不覆盖此前历史；30 天是默认查询范围，不是删除期限。此功能从 0.4.4 起记录，无法还原以前没有保存的操作。单纯检查不算安装历史。其他包管理器或用户手动在 envpilot 外更新的软件不会自动出现在记录中。

`updates status` 显示上次结果和下一次到期时间。自动安装日志在 `updates/install.log`，超过 2 MiB 后在下次安装前保留上一份；文件权限受保护。结构化状态/历史只记录版本和稳定错误码，不包含密钥、订阅或原始错误内容。
