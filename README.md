# envpilot

[English](README.en.md) · [GitHub](https://github.com/zhangyehao/envpilot) · [Gitee](https://gitee.com/zhangyehao0422/envpilot)

为工作站、HPC 和远程 SSH 环境安装、配置和维护用户态工具。一个 YAML 管理安装、Shell 接入、代理、Codex 运行环境与定时更新；保留原 profile、认证和会话。

## 快速开始与更新

### 第一次使用

```bash
git clone https://github.com/zhangyehao/envpilot.git "$HOME/envpilot"
cd "$HOME/envpilot"
bash envpilot.sh setup-command
export PATH="$PATH:$HOME/.local/bin"
envpilot init --lang zh-CN
envpilot config edit
envpilot plan
envpilot apply
```

国内可将仓库地址换为 `https://gitee.com/zhangyehao0422/envpilot.git`。源码安装会获取并校验匹配的配置工具，无需 Go/Python/Node。离线使用 [Release 平台包](https://github.com/zhangyehao/envpilot/releases/latest)，并准备组件本身的离线资源。

`bootstrap.sh` 仍支持 partial clone 与 sparse-checkout，只获取匹配架构的已有 Mihomo 缓存，适合需要减少克隆体积的用户。

`init` 不覆盖已有配置。初始 `install.components: []` 不安装组件；改成例如 `[mihomo, codex, git]` 后执行 `plan → apply`。登录由对应软件处理。新用户默认只接入 envpilot，代理、Conda、module 和旧快捷命令需主动开启。

从 **0.3.0** 起，确认执行 `apply-shell` 会安装 `~/.local/bin/envpilot`；`setup-command` 可独立登记入口。PATH 生效后，在任意目录运行 `envpilot ...`，等价于 `bash /仓库路径/envpilot.sh ...`。移动仓库后重新登记。

Windows PowerShell，在源码或平台包目录执行：

```powershell
.\envpilot.ps1 setup-command
$env:PATH += ';' + (Join-Path $HOME '.local/bin')
envpilot init -Lang zh-CN
envpilot config edit
envpilot plan
envpilot apply
```

### 更新已有安装

**0.4.0 及以上：**

```bash
envpilot self-update                 # 更新 envpilot、配置工具和管理脚本
envpilot version
envpilot update codex                # 更新组件，也可换成 git、mihomo 等
envpilot codex remote status
```

Codex 原来在运行时，`update codex` 会刷新完整运行目录并重启、验证；原来已停止则保持停止。通常不用先 `stop`。明确需要先停再更新时使用 `stop → update codex → restart → status`。

**0.3.0** 没有 `self-update`，先运行一次升级桥接脚本。它检查源码修改/分叉、备份旧文件、拉取稳定标签并迁移配置，不强制重置仓库：

```bash
curl -fL --retry 3 https://raw.githubusercontent.com/zhangyehao/envpilot/main/scripts/upgrade.sh -o /tmp/envpilot-upgrade.sh
bash /tmp/envpilot-upgrade.sh "$HOME/envpilot"
export PATH="$PATH:$HOME/.local/bin"
envpilot version
```

也可以手动更新已有源码，**拉取成功后**再登记入口：

```bash
cd "$HOME/envpilot" && git pull --ff-only origin main
bash envpilot.sh setup-command
envpilot apply-shell
envpilot codex remote enable         # 仅已使用 Codex 远程服务时需要
```

Git 自更新要求工作区干净、可快进至稳定标签；平台包自更新校验 SHA-256，并切换到新版本目录。[升级与恢复](docs/UPGRADE.zh-CN.md) 包含完整平台包命令和恢复方法。

### 定时检查与夜间自动安装

0.4.4 默认每 **3 天**检查一次，自动安装窗口默认 **03:00–05:00**。默认仅检查；需要无人值守安装时，在主配置中设置：

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

```bash
envpilot config validate
envpilot updates check               # 立即检查，不安装
envpilot updates enable              # 登记定时任务，无需保持终端打开
envpilot updates status              # 策略、下次时间与上次结果
envpilot updates history             # 最近 30 天的手动/自动更新
envpilot updates history --days 90 --component codex
```

未安装的组件跳过；外部/系统安装由原包管理器维护，受管工具使用各自的兼容性规则。窗口限制自动安装的**开始时间**，已开始的安装允许完成；Codex 重启可能中断任务。手动 `update COMPONENT` / `self-update` 不受窗口限制。修改间隔无需重新登记；禁用任务用 `envpilot updates disable`。详见 [更新机制与历史](docs/UPDATES.zh-CN.md)。

## 配置文件说明

主配置：`~/.config/envpilot/config.yaml`。优先级：命令参数 → 已声明的环境变量覆盖 → YAML → 默认值。

- [完整中文样例](examples/config.example.zh-CN.yaml)：全部可配置字段、参数与注释。
- [Complete English example](examples/config.example.en.yaml)。
- [配置与受保护文件说明](docs/CONFIG.zh-CN.md)：不同引用方式、文件内容与权限。

**订阅链接**写入 `~/.config/mihomo/subscription.url`，只写一行 URL；YAML 中使用 `mihomo.subscription.file` 引用。**密钥**通常写入 `~/.config/secrets/api.env`，例如 `OPENAI_API_KEY='你的密钥'`，通过 `secrets.file` 和 `codex.api_key.env: OPENAI_API_KEY` 引用。也可使用仅含一行密钥的文件并配置 `codex.api_key.file`，这时将 `env` 留空。Unix 文件应属于当前用户、权限 `600`；实际密钥/订阅链接不要写入 YAML、命令行参数或 Git。

让普通 Shell 优先使用已安装的受管 Git/Python：

```yaml
shell:
  prefer_managed: [git, python]
```

```bash
envpilot apply-shell
# 打开新终端，或在 Bash 中重新加载：
source ~/.bashrc
command -v git
command -v python3
```

未激活 Python 环境时，路径应指向安装前缀下的 `git/current/bin/git`、`python/current/bin/python3`。已激活 Conda/venv 时保留环境的 Python。同名用户 alias/函数不会被覆盖，可用 `type -a git python3` 检查。

修改后运行 `envpilot config validate`；安装与 Shell 设置通过 `plan → apply` 应用。定时更新每次读取 YAML。旧 `shell.local` 保留；Bash/zsh/PowerShell profile 只加入短加载块，不整体替换。

## 各类命令解析

| 目的 | 命令 |
| --- | --- |
| 版本与帮助 | `envpilot version` / `-v` / `-V`；`envpilot help` / `-h` / `-help` |
| 配置 | `envpilot init`；`envpilot config edit/validate/show` |
| 预览并应用 | `envpilot plan`；`envpilot apply` |
| 无交互应用 | Bash：`--yes --non-interactive`；PowerShell：`-Yes -NonInteractive` |
| 安装 / 更新组件 | `envpilot install COMPONENT`；`envpilot update COMPONENT` |
| 更新 envpilot 自身 | `envpilot self-update` |
| 检查 / 运行到期策略 | `envpilot updates check`；`envpilot updates run` |
| 定时任务 / 状态 / 历史 | `envpilot updates enable/disable/status/history` |
| Shell 接入 / 移除 | `envpilot apply-shell`；`envpilot shell remove` |
| 独立子进程环境 | `envpilot run -- COMMAND ...` |
| 诊断 / 快照 / 恢复 | `envpilot doctor`；`envpilot snapshot`；`envpilot restore` |
| Codex 服务 | `envpilot codex remote status/enable/verify/restart/stop` |
| 代理 | `envpilot mihomo start/stop/status/ports/update-subscription` |
| 中断安装 / 状态重置 | `envpilot resume`；`envpilot reset`（不卸载） |

表格中的 `/` 表示可选子命令，执行时选择一个。[命令说明](docs/COMMAND.zh-CN.md) 提供具体示例。

## 软件目录

| 软件 | 用途与文档 |
| --- | --- |
| [Mihomo](docs/MIHOMO.zh-CN.md) | 代理、订阅与端口 |
| [Git / Python](docs/GIT-PYTHON.zh-CN.md) | 兼容的用户态工具，保留系统安装 |
| [Conda / Mamba](docs/CONDA-MAMBA.zh-CN.md) | 包与环境管理，保留已有环境 |
| [Codex](docs/CODEX.zh-CN.md) | CLI、完整节点运行目录与 app-server |
| [GitHub CLI / tmux](docs/GITHUB-TMUX.zh-CN.md) | GitHub 操作与持久终端 |

## 其它内容

- [Shell 接入](docs/SHELL-CONFIG.zh-CN.md)、[升级与恢复](docs/UPGRADE.zh-CN.md)、[更新与历史](docs/UPDATES.zh-CN.md)。
- [维护与分支](docs/OPERATIONS.zh-CN.md)：`main` 是已集成代码，标签是不可变发布点；机器人分支承载定期更新 PR，可在合入后重建；已合并的普通开发分支可删除。
- [架构](docs/ARCHITECTURE.md)、[扩展组件](docs/EXTENDING.zh-CN.md)、[运维指南](docs/ENVPILOT-SKILL.md)、[变更记录](CHANGELOG.md)。
- GitHub/Gitee 同步代码与标签；平台包以实际附件和校验值为准。Gitee 附件尚不完整时，优先使用 GitHub Release。

许可证：MIT。
