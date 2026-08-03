# envpilot

envpilot 是面向非管理员用户的跨平台环境引导仓库，用于在新服务器、HPC 登录节点、工作站或远程主机上安装和管理常用工具，并保留可恢复的用户态状态。

当前重点支持 Mihomo、Conda/Anaconda、Mamba、Codex、GitHub CLI 和 tmux。默认在线安装；Mihomo 和地理数据可优先使用仓库内的受控缓存。

代码同时发布到：

- GitHub 主仓库：`https://github.com/zhangyehao/envpilot.git`
- Gitee 国内镜像：`https://gitee.com/zhangyehao0422/envpilot.git`

两个仓库使用相同的 `main` 和版本标签。普通用户一律优先使用 HTTPS clone，不需要提前登录 GitHub/Gitee。

## 快速开始

### Linux / macOS / WSL / Git Bash

推荐使用轻量克隆入口。它会先检测 OS 和 CPU 架构，再通过 Git partial clone + sparse checkout 只取匹配的 Mihomo 缓存：

```bash
curl -fsSL https://raw.githubusercontent.com/zhangyehao/envpilot/main/bootstrap.sh | bash
cd envpilot
bash envpilot.sh doctor
```

也可以普通克隆，按网络情况任选一个镜像：

```bash
git clone https://github.com/zhangyehao/envpilot.git
# 国内网络也可以：
# git clone https://gitee.com/zhangyehao0422/envpilot.git
cd envpilot
bash envpilot.sh doctor
```

从 Gitee 使用轻量入口：

```bash
export ENVPILOT_REPO_URL=https://gitee.com/zhangyehao0422/envpilot.git
curl -fsSL https://gitee.com/zhangyehao0422/envpilot/raw/main/bootstrap.sh | bash
```

普通 `git clone` 无法在下载前根据客户端架构自动过滤 Git 中已经跟踪的文件，因此会取得 Linux/Windows 的全部缓存。轻量入口要求较新的 Git；旧版 Git 会说明原因并自动回退普通 HTTPS clone。

### Windows PowerShell

```powershell
irm https://raw.githubusercontent.com/zhangyehao/envpilot/main/bootstrap.ps1 | iex
cd envpilot
.\envpilot.ps1 doctor
```

也可以使用普通 HTTPS clone，按网络情况任选一个镜像：

```powershell
git clone https://github.com/zhangyehao/envpilot.git
# 国内网络也可以：
# git clone https://gitee.com/zhangyehao0422/envpilot.git
cd envpilot
.\envpilot.ps1 doctor
```

从 Gitee 使用轻量入口：

```powershell
$env:ENVPILOT_REPO_URL = "https://gitee.com/zhangyehao0422/envpilot.git"
irm https://gitee.com/zhangyehao0422/envpilot/raw/main/bootstrap.ps1 | iex
```

## 推荐部署顺序

共享服务器上先安装并启动 Mihomo，再继续网络依赖较重的组件：

```bash
bash envpilot.sh doctor

export MIHOMO_PROXY_PORT=42290
export MIHOMO_API_PORT=60290

bash envpilot.sh install mihomo
bash envpilot.sh apply-shell
# 可选：vim ~/.bashrc，将需要自动启用的 BASHRC_INIT_CONDA / BASHRC_AUTO_* 默认值改为 1
source ~/.bashrc

mihomo start
mihomo status
proxy_on

bash envpilot.sh install
```

默认不会自动启动 Mihomo，也不会自动设置代理环境变量。需要代理时执行 `proxy_on`，不用时执行 `proxy_off`。

`proxy_on` 会先确认 `${MIHOMO_PROXY_HOST}:${MIHOMO_PROXY_PORT}` 确实正在监听；检查失败时直接返回，不会留下导致 `Connection refused` 的错误代理变量。默认只设置 HTTP/HTTPS 代理，这对 Conda、Git、curl 和 Codex 通常更稳。确实需要 SOCKS 时，在 `~/.config/envpilot/shell.local` 中设置：

```bash
BASHRC_PROXY_ENABLE_SOCKS=1
```

envpilot 只向已有 `no_proxy/NO_PROXY` 追加 `localhost`、`127.0.0.1` 和 `::1`，不会覆盖集群内部域名或网段；`proxy_off` 只清理代理地址并保留 `no_proxy`。

## Mihomo 运行模型

Linux/macOS/Unix-like 环境按以下方式运行：

```text
持久文件：
~/software/mihomo/mihomo
~/.config/mihomo/config.yaml
~/.config/mihomo/country.mmdb
~/.config/mihomo/geoip.metadb

当前节点运行目录：
/tmp/${USER}_mihomo_${HOSTNAME}/
```

二进制和订阅配置保存在用户目录；实际运行时复制到节点本地 `/tmp`。这样可以减少 NFS、Lustre、GPFS、BeeGFS 等共享文件系统上的锁、元数据和缓存 I/O 问题。

切换登录节点后，`/tmp` 和 `127.0.0.1` 都会变化，需要在新节点重新执行：

```bash
mihomo start
```

## Mihomo 双端口
所有 Mihomo 操作统一读取：

```bash
MIHOMO_PROXY_PORT=42290
MIHOMO_API_PORT=60290
```

- `MIHOMO_PROXY_PORT`：HTTP 和 SOCKS5 共用的本地 mixed port。
- `MIHOMO_API_PORT`：Mihomo external controller API。
- 两个端口必须不同。
- 非 root 用户应选择大于 `1024` 的端口。
- 写配置或启动前会检查端口是否合法、是否已经被占用。

临时指定：

```bash
export MIHOMO_PROXY_PORT=42290
export MIHOMO_API_PORT=60290
mihomo start
```

持久修改并自动完成配置、停止、占用检查和重启：

```bash
mihomo ports 42290 60290
```

兼容旧命令，只修改代理端口并保留当前 API 端口：

```bash
mihomo port 42291
```

没有执行 `apply-shell` 时，可在仓库目录执行：

```bash
bash envpilot.sh mihomo ports 42290 60290
```

配置会统一修正为：

```yaml
mixed-port: 42290
allow-lan: false
bind-address: 127.0.0.1
external-controller: 127.0.0.1:60290
```

只修改本地监听项，不会改动订阅节点中的远端 `server`、`port`、`uuid`、`public-key` 或 `short-id`。

## Mihomo 接管已有进程

执行 `install mihomo` 或 `update mihomo` 时，envpilot 会先记录当前用户的 Mihomo 进程、版本和目标端口，然后在确认后向已有 Mihomo 发送 SIGTERM，等待几秒；仍未退出时发送 SIGKILL。停止后会重新检查 `MIHOMO_PROXY_PORT` 和 `MIHOMO_API_PORT`，端口仍被占用就中止安装，不会生成一个无法启动的配置。

安装流程会优先使用当前架构匹配的 `downloads/` 缓存；如果已有 envpilot 二进制版本与选中的 stable 版本一致，则保留二进制，只更新脚本和数据，否则安装或更新二进制。旧 Mihomo 的代理环境变量不会继续用于下载，安装过程会清除当前脚本进程继承的代理变量。

接管记录保存到 `~/.config/envpilot/mihomo-takeover-report.json`。如果检测到的是 envpilot 已管理的 Mihomo，升级会保留现有 `config.yaml`，不会再次要求粘贴订阅；升级前正在运行的实例会在完成后自动恢复。如果检测到外部 Mihomo 且没有提供新订阅，旧配置才会备份并改名为 `config.yaml.disabled.TIMESTAMP`，防止继续使用旧代理渠道。

如果当前主机只能通过旧代理访问外网，请提前准备 `downloads/` 离线资产，或确认主机具备直连网络；因为接管外部代理后，旧代理不会被用于下载。

## Mihomo 订阅更新

安装前先在 [proxy.yanhuoapi.com](https://proxy.yanhuoapi.com/) 注册，并复制 **Clash/Mihomo 订阅链接**。不要把真实订阅 URL 提交到 Git、README、Issue 或聊天记录。

交互更新：

```bash
mihomo update-subscription
```

直接传入新链接：

```bash
mihomo update-subscription 'https://example.invalid/clash-meta'
```

也可从仓库入口执行：

```bash
bash envpilot.sh mihomo update-subscription 'https://example.invalid/clash-meta'
```

更新命令会：

1. 下载到临时文件并拒绝空文件或 HTML 错误页。
2. 备份原 `config.yaml`。
3. 按当前 `MIHOMO_PROXY_PORT` 和 `MIHOMO_API_PORT` 修正本地监听。
4. 如果 Mihomo 正在运行，则停止并重启。
5. 新配置启动失败时恢复旧配置。

## Mihomo 常用命令

```bash
mihomo start
mihomo stop
mihomo status
mihomo ports 42290 60290
mihomo update-subscription
proxy_on
proxy_off
proxy_status
```

`mihomo status` 检查当前节点的：

- envpilot 管理的 Mihomo 进程；
- 代理端口和 API 端口；
- API `/version` 健康状态；
- 代理出口；
- `/tmp/${USER}_mihomo_${HOSTNAME}/mihomo.log` 最近日志。

`mihomo stop` 只停止当前用户、当前节点、envpilot 运行目录中的 Mihomo，不会停止其他用户或其他路径的进程。

## Mihomo 缓存与更新

仓库当前受控缓存：

```text
downloads/mihomo-linux-amd64-compatible-*.gz
downloads/mihomo-windows-amd64-compatible-*.zip
downloads/country.mmdb
downloads/geoip.metadb
```

安装选择顺序：

1. 当前 OS/架构匹配的 `downloads/` 缓存。
2. MetaCubeX GitHub Releases 的最新 stable 资产。
3. 排除 alpha、beta、rc、prerelease。

`update-mihomo-cache.yml` 每周或手动运行，刷新 Linux/Windows amd64 compatible 缓存及 geodata，并通过 PR 提交变化。

## 命令总览

| 命令 | 作用 |
| --- | --- |
| `doctor` | 只检查，不安装；同时记录本次 restore baseline。 |
| `install [all|mihomo|conda|mamba|codex|github|tmux]` | 首次安装组件；在线模式优先使用匹配的受控缓存。 |
| `update [all|mihomo|conda|mamba|codex|github|tmux]` | 忽略已完成状态，重新解析当前系统可兼容的 stable 版本并更新。 |
| `apply-shell` | 备份并替换当前 shell/profile。 |
| `mihomo start|stop|status` | 管理和检查 Mihomo。 |
| `mihomo ports PROXY API` | 完整修改双端口并重启。 |
| `mihomo update-subscription [URL]` | 备份、更新、修正并按需重启订阅配置。 |
| `restore` | 恢复到最近一次 `doctor` 记录的 baseline。 |
| `rollback` | 恢复最近一次 envpilot 单文件备份。 |
| `resume` | 继续中断的安装流程。 |
| `reset` | 清理安装状态，使步骤可重新执行。 |
| `update-manifests` | 刷新上游 stable 版本元数据。 |
| `update-mihomo-cache` | 刷新 `downloads/` 的 Mihomo 和 geodata 缓存。 |
| `self-test` | 运行仓库测试。 |

常用参数：

```bash
bash envpilot.sh install conda --conda-distribution anaconda
bash envpilot.sh install mihomo --mode offline
bash envpilot.sh install mihomo --asset-path downloads/mihomo-linux-amd64-compatible-v1.19.29.gz
bash envpilot.sh install --prefix "$HOME/software"
bash envpilot.sh update
bash envpilot.sh update tmux
```

## Baseline、restore 与 rollback

`doctor` 会记录：

```text
~/.config/envpilot/baseline/baseline.tsv
~/.config/envpilot/baseline/files/
```

`restore` 会停止 envpilot 管理的 Mihomo、清理对应节点的 `/tmp` 运行目录，并把受管文件恢复到最近一次 `doctor` 状态。适合安装中途失败后回到初始状态。

再次执行 `doctor` 会覆盖 baseline。需要保留最初状态时，不要在半安装状态重新运行 `doctor`。

`rollback` 只恢复最近一次备份的单个文件；`restore` 恢复整组 baseline 对象。

## 已有 envpilot 环境如何升级

仓库更新后不要重新 clone 到同一个目录，直接在原仓库执行：

```bash
cd ~/envpilot
git pull --ff-only
bash envpilot.sh doctor
bash envpilot.sh apply-shell
source ~/.bashrc
bash envpilot.sh update
```

如果仓库不在 `~/envpilot`，任意 envpilot 命令都会把实际位置写入 `~/.config/envpilot/repo-root`；新 shell 模板会先尝试 `$HOME/envpilot`，不存在时再读取该记录。升级命令会绕过旧版本留下的 `~/.config/envpilot/state` 完成状态，不需要先执行 `reset`。

`update` 会逐项处理：

- Mihomo：保留 envpilot 管理的订阅配置，并恢复升级前的运行状态。
- Conda/Mamba：让当前 Conda 解析当前平台和 base 环境可兼容的新版本，不强行安装不兼容包。
- Codex：通过 npm 更新 `@openai/codex`。
- GitHub CLI：只更新 envpilot 管理的用户态副本；系统管理员提供的副本不强制覆盖。
- tmux：比较 manifest 的 stable 目标；系统/module 版本过低时，在用户目录构建新版本并让 `~/.local/bin/tmux` 优先生效。

Windows 对应命令为 `.\envpilot.ps1 update`，也可使用 `.\envpilot.ps1 install -Upgrade`。

## Conda / Mamba

- 默认安装官方 Miniconda，也可显式选择 Anaconda。
- 不使用 Miniforge。
- Linux 根据 glibc 和架构选择最新可安装的官方版本。
- 不默认执行 `conda init`。
- `~/.condarc` 只保留清华 `conda-forge` 和 `bioconda` 两个镜像，并通过 `default_channels: []` 禁用继承的 `defaults`。
- Mamba 安装命令不再追加官方 `-c conda-forge`，而是直接使用上述受控频道。
- 在共享服务器执行 Conda/Mamba 时会临时清除 `LD_LIBRARY_PATH`、`PYTHONHOME` 和 `PYTHONPATH`，避免 module 或集群环境污染 Conda。
- 如果 Conda 在事务完成后的清理阶段返回非零，envpilot 会验证实际 `mamba` 可执行文件；只有验证失败才判定安装失败。
- Mamba 安装到 Conda base；tmux 不通过 Conda/Mamba 提供。
- `update conda` 和 `update mamba` 由当前 Conda 求解器选择当前系统可安装的新版本，不用固定旧版本号。

可用以下命令确认实际配置来源和频道：

```bash
conda config --show-sources
conda config --show channels default_channels
```

## Codex

单独安装 Codex：

```bash
bash envpilot.sh install codex
```

安装器会先检查 Node.js。若未安装或低于 Node.js 22，会明确显示 nvm 下载地址、用户态安装目录和当前阶段，再询问是否安装最新 LTS；随后显示 npm 来源、全局 prefix 和 Codex 版本。下载过程中可能需要几分钟，但不会无提示退出。

Codex 配置使用：

```toml
env_key = "OPENAI_API_KEY"
```

密钥推荐放到 `~/.config/secrets/api.env`，再通过：

```bash
with_secrets codex
```

## GitHub/Gitee 镜像与 tmux

新主机 clone 推荐 HTTPS；只有需要 push 时再配置对应平台的 SSH 公钥。本仓库维护端使用：

```bash
git remote add gitee https://gitee.com/zhangyehao0422/envpilot.git
git remote set-url --add --push gitee git@gitee.com:zhangyehao0422/envpilot.git
bash scripts/push-mirrors.sh
```

Windows PowerShell 可运行 `.\scripts\push-mirrors.ps1`。脚本要求位于干净的 `main`，并依次把 `main` 和标签推送到 GitHub `origin` 与 Gitee `gitee`；不会强推。

tmux 优先使用系统命令或 module。执行 `update tmux` 时会把当前版本与 `manifests/tmux.json` 的 stable 目标比较；系统版本较低且不能由管理员更新时，envpilot 会在用户目录构建兼容的新版本并链接到 `~/.local/bin/tmux`。Windows 原生不承诺 tmux，优先使用 WSL、MSYS2 或 Git Bash。

## Actions 与发布

- `test.yml`：Linux、macOS、Windows 语法和回归测试。
- `update-manifests.yml`：定时刷新上游 stable 元数据并开 PR。
- `update-mihomo-cache.yml`：定时刷新受控 Mihomo/geodata 缓存并开 PR。
- `release-assets.yml`：为 envpilot 自身生成源码归档和校验文件。

## 仓库约定

- secrets、订阅链接、API key、运行日志和生成配置不进入 Git。
- `downloads/` 只保留明确允许的受控缓存。
- 新增组件时同步更新测试、文档、manifest 和 baseline/restore 规则。
- 本项目采用 MIT License，详见 `LICENSE`。
- 维护扩展规范见 [docs/EXTENDING.zh-CN.md](docs/EXTENDING.zh-CN.md)。
