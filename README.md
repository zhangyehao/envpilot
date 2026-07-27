# envpilot

`envpilot` 是一个面向普通用户的跨平台环境引导工具。目标是在没有管理员权限的新机器或服务器上，尽量自动完成常用环境预安装、代理配置、Shell 配置备份替换、Codex/GitHub/tmux 等工具准备。

它默认优先在线安装，并根据当前系统、CPU 架构、Shell、root/非 root、已有命令和网络代理状态选择合适的安装方式。离线模式用于无外网或受限服务器。

## 快速开始

Linux/macOS/WSL/Git Bash:

```bash
git clone git@github.com:zhangyehao/envpilot.git
cd envpilot
bash envpilot.sh doctor
bash envpilot.sh install
bash envpilot.sh apply-shell
```

Windows PowerShell:

```powershell
git clone git@github.com:zhangyehao/envpilot.git
cd envpilot
.\envpilot.ps1 doctor
.\envpilot.ps1 install
.\envpilot.ps1 apply-shell
```

如果服务器不能直接访问外网：

```bash
bash envpilot.sh install --mode offline
```

将安装包预先放到 `downloads/`，或者使用：

```bash
bash envpilot.sh install mihomo --mode offline --asset-path /path/to/mihomo.gz
```

## 常用命令

```bash
bash envpilot.sh doctor
bash envpilot.sh install conda
bash envpilot.sh install mihomo
bash envpilot.sh install codex
bash envpilot.sh install github
bash envpilot.sh install tmux
bash envpilot.sh apply-shell
bash envpilot.sh rollback
bash envpilot.sh resume
bash envpilot.sh reset
```

PowerShell 使用同名命令：

```powershell
.\envpilot.ps1 doctor
.\envpilot.ps1 install github
.\envpilot.ps1 rollback
```

## 交互、中断和恢复

- 所有关键输入都会先校验，例如 mihomo 订阅链接、安装路径、是否替换 Shell 配置。
- 输入错误时可以重新输入。
- `Ctrl+C` 会退出当前流程，已经完成的组件会记录到 `~/.config/envpilot/state`。
- 再次运行：

```bash
bash envpilot.sh resume
```

会跳过已完成组件并继续。

如果希望完全重新开始：

```bash
bash envpilot.sh reset
```

## 安装报告

每次安装会写入：

```text
~/.config/envpilot/install-report.json
~/.config/envpilot/logs/
```

报告包含：

- 检测到的 OS、架构、Shell、root 状态
- 安装了什么
- 为什么选择这个版本或资产
- 下载来源
- 安装路径
- 跳过原因
- 用户下一步需要执行的命令

## Shell 配置策略

`apply-shell` 会先备份再替换：

```text
~/.bashrc.bak.YYYYmmddHHMMSS
~/.zshrc.bak.YYYYmmddHHMMSS
PowerShell_profile.ps1.bak.YYYYmmddHHMMSS
```

模板设计原则：

- 非交互 Shell 不输出、不加载 module、不初始化 Conda、不启动后台服务。
- 所有命令先检测再使用。
- API key 不写进主 Shell 配置。
- 可迁移的 PATH、`module load`、Conda 路径会写入：

```text
~/.config/envpilot/shell.local
```

明文密钥不会迁移。请手动写到：

```text
~/.config/secrets/api.env
```

示例：

```bash
mkdir -p ~/.config/secrets
cp templates/api.env.example ~/.config/secrets/api.env
chmod 600 ~/.config/secrets/api.env
vim ~/.config/secrets/api.env
```

使用密钥运行 Codex：

```bash
with_secrets codex
```

## Conda 和 Mamba

默认安装 Miniconda 到：

```text
~/software/miniconda3
```

不会执行 `conda init`，也不会自动 `conda activate base`。

写入的 `.condarc`：

```yaml
channels:
  - https://mirrors.tuna.tsinghua.edu.cn/anaconda/cloud/conda-forge
  - https://mirrors.tuna.tsinghua.edu.cn/anaconda/cloud/bioconda
show_channel_urls: true
channel_priority: strict
```

`mamba` 只用于 Conda 环境求解，不用于安装 `tmux`。

## mihomo 代理

安装前请先在以下网站注册并获取订阅：

```text
https://proxy.yanhuoapi.com/
```

复制的是 **Clash/Mihomo 的订阅链接**，不是网页地址、节点名称或 API key。

envpilot 会：

- 自动选择当前系统和架构匹配的 mihomo stable 资产。
- 排除 alpha/beta/rc/prerelease。
- 安装到 `~/software/mihomo/mihomo`。
- 写入启动脚本 `~/software/mihomo/start_mihomo.sh`。
- 强制 `allow-lan: false`。
- 默认使用 `127.0.0.1:7890`。

常用命令：

```bash
mihomo_start
proxy_status
proxy_on
proxy_off
mihomo_stop
```

检查代理：

```bash
curl --proxy http://127.0.0.1:7890 https://ipinfo.io/ip
curl -x http://127.0.0.1:7890 -I https://api.openai.com
```

## Codex

Codex 配置使用环境变量密钥：

```toml
env_key = "OPENAI_API_KEY"
```

不会默认写 `~/.codex/auth.json`。

把密钥放入：

```text
~/.config/secrets/api.env
```

然后运行：

```bash
with_secrets codex
```

默认接口地址为：

```text
https://yanhuoapi.com/v1
```

可以在安装前覆盖：

```bash
EP_CODEX_BASE_URL="https://example.com/v1" bash envpilot.sh install codex
```

## GitHub

GitHub CLI 用于私有仓库 clone、创建仓库、PR/issue 等工作。推荐 SSH 协议：

```bash
gh auth login -h github.com --git-protocol ssh
ssh -T git@github.com
```

如果私有仓库无法 clone，先确认账号是否有 collaborator/team 读权限。

## tmux

`tmux` 必须是直接可用的命令，不通过 Conda 环境提供。

安装优先级：

1. 使用系统已有 `tmux`
2. 尝试加载 `module load tmux`
3. root 或 macOS Homebrew 环境使用包管理器
4. 非 root Linux 构建 `ncurses + libevent + tmux` 到 `~/.local/envpilot`，并链接到 `~/.local/bin/tmux`

Windows 原生不承诺 tmux；如需 tmux，请使用 WSL、MSYS2 或 Git Bash 对应的 Unix 环境。

## 离线资产

不要把二进制包提交到 Git。`downloads/` 已被 `.gitignore` 忽略。

推荐来源：

- 用户手动上传到 `downloads/`
- 私有 GitHub Release assets
- 使用 `--asset-path` 指定本地文件

## 安全边界

- 不写系统目录，除非当前用户明确以 root 运行并确认。
- 不提交密钥、订阅链接、mihomo `config.yaml`、Codex `auth.json`。
- 所有 profile 替换前都有备份。
- 可用 `rollback` 恢复最近一次备份。

## 维护者文档

新增组件、维护 manifest、CI 更新策略见：

```text
docs/EXTENDING.zh-CN.md
docs/EXTENDING.md
```

