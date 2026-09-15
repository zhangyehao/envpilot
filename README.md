# envpilot

[English](README.en.md) · [GitHub](https://github.com/zhangyehao/envpilot) · [Gitee](https://gitee.com/zhangyehao0422/envpilot)

envpilot 为无管理员权限的工作站、HPC 和远程 SSH 环境安装、配置及维护用户态工具。支持 Mihomo、Git、Python、Conda/Mamba、Codex、GitHub CLI 和 tmux。

**0.4.0：统一 YAML 配置、保留原 profile 的 Shell 接入、可靠的 Codex 重启，以及可恢复的升级。**

## 快速开始

下载 [Release](https://github.com/zhangyehao/envpilot/releases) 中对应系统和架构的平台包。平台包包含 `envpilot-core`，使用配置功能不需要预装 Go、Python 或 Node。解压后在目录内执行：

```bash
bash envpilot.sh setup-command
export PATH="$PATH:$HOME/.local/bin"
envpilot init --lang zh-CN
envpilot config edit
envpilot plan
envpilot apply
```

`init` 默认不选择安装组件。编辑配置的 `install.components` 后，`apply` 会按依赖顺序安装所选组件。安装全部组件仍可使用 `envpilot install all`。

也可以从源码安装；配置工具会从对应版本的 Release 获取并校验：

```bash
git clone https://github.com/zhangyehao/envpilot.git
# 国内网络可改用 https://gitee.com/zhangyehao0422/envpilot.git
cd envpilot
bash envpilot.sh setup-command
export PATH="$PATH:$HOME/.local/bin"
envpilot init --lang zh-CN
```

`bootstrap.sh` 继续支持 partial clone 和 sparse-checkout，按架构获取已有 Mihomo 缓存。完全离线时使用包含配置工具的平台包；组件本身的离线资源仍需准备。

从 **0.3.0** 起，确认执行 `apply-shell` 会安装 `~/.local/bin/envpilot`。PATH 生效后，可在任意目录使用 `envpilot ...`，与 `bash /仓库路径/envpilot.sh ...` 等价，保留当前目录、参数及退出码。`setup-command` 可以独立登记入口。仓库移动后，在新位置重新登记。

Windows PowerShell：

```powershell
.\envpilot.ps1 setup-command
$env:PATH += ';' + (Join-Path $HOME '.local/bin')
envpilot init -Lang zh-CN
envpilot config edit
envpilot plan
envpilot apply
```

PowerShell 使用 `-Yes -NonInteractive`；Bash 使用 `--yes --non-interactive`。Codex 节点本地运行管理使用 Linux/macOS/WSL 入口。

## 一个主配置入口

默认配置：`~/.config/envpilot/config.yaml`。例如：

```yaml
version: 1
language: zh-CN
install:
  components: [mihomo, git, python, codex]
  mode: online
  prefix: ~/software
  release_source: github
shell:
  enabled: true
  auto_start_proxy: true
  auto_enable_proxy: true
  conda: false
mihomo:
  proxy_port: 42290
  api_port: 60290
  subscription:
    file: ~/.config/mihomo/subscription.url
codex:
  remote: true
  home: ~/.codex
  ready_timeout: 60
  api_key:
    env: OPENAI_API_KEY
secrets:
  file: ~/.config/secrets/api.env
```

常规设置集中在 YAML；密钥和订阅链接存放在引用的受保护文件或环境变量中。保留已有 `auth.json`。配置字段、优先级及示例见 [配置说明](docs/CONFIG.zh-CN.md)。

```bash
envpilot config validate
envpilot apply --yes --non-interactive
```

新用户默认只接入 envpilot，不自动改变代理、Conda、module、历史设置或旧快捷别名；按需在配置中开启。旧用户迁移保留已有开关。

## 常用命令

| 命令 | 用途 |
| --- | --- |
| `envpilot plan` | 查看配置和拟议变更。 |
| `envpilot apply` | 应用所选组件及 Shell 设置。 |
| `envpilot install COMPONENT` | 安装指定组件。 |
| `envpilot update COMPONENT` | 检查兼容更新。 |
| `envpilot doctor` | 只诊断，不覆盖恢复点。 |
| `envpilot snapshot` | 创建新的文件恢复快照。 |
| `envpilot restore` | 恢复最新快照，兼容旧 baseline。 |
| `envpilot rollback` | 恢复最近一次单文件备份。 |
| `envpilot self-update` | 更新 envpilot 和已安装的管理脚本。 |
| `envpilot apply-shell` | 安装独立脚本，并在原 profile 中加入短加载块。 |
| `envpilot shell remove` | 仅移除 envpilot 加载块。 |
| `envpilot run -- COMMAND ...` | 在配置的工具和环境中运行子进程。 |
| `envpilot resume` | 继续未完成的安装。 |
| `envpilot reset` | 清除安装状态，不卸载软件。 |

## Codex 重启和更新

```bash
envpilot codex remote status
envpilot codex remote enable
envpilot codex remote restart
# 也可以：
envpilot codex remote stop
envpilot codex remote enable
envpilot update codex
```

`restart` 会停止当前用户、当前节点、同一控制 socket 的已核实实例，包括由 Desktop/SSH 启动的实例，再启动并验证新进程。未知归属或其他 CODEX_HOME 的实例不会被停止。重启可能中断当前请求。

`update codex` 在更新前服务运行时刷新运行文件并重启；此前停止则保持停止。配置、认证和会话数据保留。节点缓存采用版本目录；只有协议握手和运行版本校验通过才报告就绪。详见 [Codex](docs/CODEX.zh-CN.md)。

## Shell 与升级

0.4.0 保留原 `.bashrc`、`.zshrc` 或 PowerShell profile，只添加受管加载块。独立脚本保存在配置目录中；重复应用不堆积内容，同名函数和别名默认保留。

从旧版升级时，精确识别的旧模板可自动迁移；带自定义修改的旧 profile 保持可用并给出待处理提示。`shell.local` 和密钥文件保留。升级步骤见 [升级与恢复](docs/UPGRADE.zh-CN.md) 和 [Shell 接入](docs/SHELL-CONFIG.zh-CN.md)。

## 组件、维护与发布

[Mihomo](docs/MIHOMO.zh-CN.md) · [Conda/Mamba](docs/CONDA-MAMBA.zh-CN.md) · [Git/Python](docs/GIT-PYTHON.zh-CN.md) · [GitHub CLI/tmux](docs/GITHUB-TMUX.zh-CN.md)

GitHub Actions 测试 Linux、macOS、Windows；定时更新使用只安装到本仓库的 GitHub App 创建 PR，避免 `GITHUB_TOKEN` 触发的待批准状态。发布包包含源码、配置工具和 SHA-256 校验文件。GitHub/Gitee 使用相同 main 和不可变版本标签。

维护说明：[架构](docs/ARCHITECTURE.md)、[扩展](docs/EXTENDING.zh-CN.md)、[运维技能](docs/ENVPILOT-SKILL.md)。许可证：MIT。
