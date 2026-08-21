# envpilot

envpilot 是面向非管理员用户的跨平台环境引导仓库，用于在新服务器、HPC 登录节点、工作站或远程主机上安装和管理常用工具，并保留可恢复的用户态状态。

当前重点支持 Mihomo、Conda/Anaconda、Mamba、Codex、Git、Python、GitHub CLI 和 tmux。默认在线安装；Mihomo 和地理数据可优先使用仓库内的受控缓存。

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
# apply-shell 会在交互式真实 TTY 中自动初始化 Conda，但不会自动进入 base。
# 如需关闭 Conda 初始化，在 ~/.config/envpilot/shell.local 写入：BASHRC_INIT_CONDA=0
# 修改之后，进行source后，mihomo start, mihomo status, proxy_on这些都会自动加载，可以不运行了
source ~/.bashrc

mihomo start
mihomo status
# 除此之外，还可以这样查看代理变量：
# printenv | grep -E '^(http_proxy|https_proxy|all_proxy|no_proxy|HTTP_PROXY|HTTPS_PROXY|ALL_PROXY|NO_PROXY)='
proxy_on

bash envpilot.sh install
```

`apply-shell` 会同时创建 `~/.config/secrets/api.env` 安全模板，目录权限为 700、文件权限为 600。模板只包含注释，不会写入假密钥；真正的 API key 只在 Codex 安装时检测到或交互输入后，经确认才会保存。受管 Bash/zsh 会在 TTY 判断之前安静地读取该文件，并通过 `set -a` 将其中的全部赋值导出给当前 shell 及其子进程；文件必须属于当前用户且权限为 600 或 400，否则会跳过。

`~/.config/envpilot/shell.local` 是 `.bashrc`/`.zshrc` 的用户配置覆盖层：交互式 shell 会完整加载它；静默的非交互 shell 只读取其中经过白名单校验的 Mihomo 端口、代理模式、密钥加载开关和节点临时目录设置，不执行任意 `module load` 或自定义命令。需要让 SSH、Codex、Git、Python 或其他子进程共同继承的简单环境变量应放在 `api.env`；该文件会整文件 source，因此只应包含安静的 shell 变量赋值，不要放命令或交互逻辑。若明确不希望自动注入，在 `shell.local` 中设置 `BASHRC_AUTO_LOAD_SECRETS=0`，之后仍可按需执行 `with_secrets command`。

`apply-shell` 可以重复执行。若检测到现有 `.bashrc` 已带有 `managed by envpilot` 标记，envpilot 会保留已有的 `shell.local` 和 `api.env`，不会把模板内部的 `EDITOR`、`TMPDIR`、`module load` 等实现细节再次迁移；检测到旧版本已经误迁移的模板片段时，会先备份 `shell.local`，再只清除能与旧受管 profile 精确匹配的片段。首次接管未受管 `.bashrc` 且不存在 `shell.local` 时，才会执行安全变量迁移。

交互式 shell 默认不会自动启动 Mihomo，也不会自动设置代理环境变量；需要代理时执行 `proxy_on`，不用时执行 `proxy_off`。非交互 SSH/Codex shell 则会按下一节的规则，在配置存在且端口准备好后安静地预启动并继承 HTTP/HTTPS 代理。

`proxy_on` 会先确认 `${MIHOMO_PROXY_HOST}:${MIHOMO_PROXY_PORT}` 确实正在监听；检查失败时直接返回，不会留下导致 `Connection refused` 的错误代理变量。默认只设置 HTTP/HTTPS 代理，这对 Conda、Git、curl 和 Codex 通常更稳。确实需要 SOCKS 时，在 `~/.config/envpilot/shell.local` 中设置：

```bash
BASHRC_PROXY_ENABLE_SOCKS=1
```

envpilot 只向已有 `no_proxy/NO_PROXY` 追加 `localhost`、`127.0.0.1` 和 `::1`，不会覆盖集群内部域名或网段；`proxy_off` 只清理代理地址并保留 `no_proxy`。

### 非交互 SSH / Codex shell

`apply-shell` 生成的 Bash/zsh 模板会在非交互 TTY 判断之前执行一段安静的、尽力而为的准备逻辑：

1. 校验并加载 `~/.config/secrets/api.env` 中的全部环境变量，不向 SSH 协议输出任何提示。
2. 从当前环境或 `~/.config/envpilot/shell.local` 的白名单设置中读取 `MIHOMO_PROXY_PORT` 和 `MIHOMO_API_PORT`。
3. 如果配置文件存在且目标端口尚未监听，尝试以 `MIHOMO_QUIET_START=1` 启动 envpilot 管理的 Mihomo。
4. 只有确认 HTTP 代理端口真实监听后，才向当前 shell 导出 HTTP/HTTPS 代理；启动失败时不输出错误，也不设置错误代理变量。
5. 默认只导出 HTTP/HTTPS；`all_proxy/ALL_PROXY` 只有 `BASHRC_PROXY_ENABLE_SOCKS=1` 时才启用。

因此，多个 SSH 窗口在同一用户、同一节点上共享一个 Mihomo 进程；`proxy_on` 和 `proxy_off` 仍然只改变当前 shell 的代理变量。启动锁会让并发的非交互 shell 等待已有启动流程，不会反复删除和重建同一个 `/tmp/${USER}_mihomo_${HOSTNAME}/` 运行目录。

这段逻辑不会在没有 `~/.config/mihomo/config.yaml` 时凭空启动服务；启动检查是有界的，代理不可用时不会无限阻塞，shell 最终仍会安静返回。若远程启动器完全不读取 `.bashrc`/`.zshrc`，普通程序仍需显式使用 `bash -lc 'command'`，或在受信任的启动环境中设置 `BASH_ENV`；`ssh host command`、某些 supervisor 和 app-server 启动器并不保证读取 profile。envpilot 的 Codex wrapper 是例外：它会在启动 CLI 或 app-server 前独立校验并加载完整 `api.env`，因此 Codex Desktop 的 `/bin/sh -c ... codex ...` 路径也能获得这些变量。

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

`BASHRC_USE_NODE_LOCAL_TMP=1` 时，模板还会创建 `/tmp/${USER}-codex-tmp` 并在可用时设置 `TMPDIR`。这只处理通用临时文件；启用下面的 Codex Remote Runtime 后，envpilot 还会把 Codex 的完整 `bin/` runtime 暂存到节点本地 `/tmp`。无论哪种模式，都不会把整个 `~/.codex`、SQLite 数据库、会话历史或长期配置搬到易失的 `/tmp`。节点重启或清理 `/tmp` 后，重新执行 `codex_ready` 即可重建 Codex runtime。

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
| `install [all|git|python|mihomo|conda|mamba|codex|github|tmux]` | 首次安装组件；在线模式优先使用匹配的受控缓存。 |
| `update [all|git|python|mihomo|conda|mamba|codex|github|tmux]` | 忽略已完成状态，重新解析当前系统可兼容的 stable 版本并更新。 |
| `apply-shell` | 备份并替换当前 shell/profile。 |
| `mihomo start|stop|status` | 管理和检查 Mihomo。 |
| `mihomo ports PROXY API` | 完整修改双端口并重启。 |
| `mihomo update-subscription [URL]` | 备份、更新、修正并按需重启订阅配置。 |
| `codex remote status|enable|stage|ready|warm|stop|repair|disable` | 管理共享文件系统上的 Codex 本地 runtime 与 app-server 预热。 |
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

`restore` 会停止 envpilot 管理的 Mihomo、清理对应节点的 `/tmp` 运行目录，并把受管文件恢复到最近一次 `doctor` 状态。适合安装中途失败后回到初始状态。baseline 也会记录 Git/Python 用户态目录和 Codex `auth.json`，因此失败后不需要手动停止代理、卸载工具或逐个删除配置。

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
- Git：系统 Git 达到 2.30 时直接复用；低于 2.30 时构建 `$HOME/software/git/current`，不覆盖 `/usr/bin/git`。
- Python：系统或 Conda Python 达到 3.9 时直接复用；低于 3.9 时选择匹配 OS、架构和 libc 的稳定用户态解释器。
- Codex：普通 `install codex` 复用已经可执行的 Codex；缺少 Codex 时在线优先使用官方独立安装器，只有失败后才回退 npm。
- GitHub CLI：只更新 envpilot 管理的用户态副本；系统管理员提供的副本不强制覆盖。
- tmux：比较 manifest 的 stable 目标；系统/module 版本过低时，在用户目录构建新版本并让 `~/.local/bin/tmux` 优先生效。

Windows 对应命令为 `.\envpilot.ps1 update`，也可使用 `.\envpilot.ps1 install -Upgrade`。

## Conda / Mamba

- 默认安装官方 Miniconda，也可显式选择 Anaconda。
- 不使用 Miniforge。
- Linux 根据 glibc 和架构选择最新可安装的官方版本。
- `apply-shell` 默认只在交互式真实 TTY 中加载已安装 Conda 的 `conda.sh`；不会向 `.bashrc`/`.zshrc` 追加 Conda 自己的初始化代码块，非交互 shell 会在 TTY 守卫处返回。
- `~/.condarc` 默认写入 `auto_activate_base: false`，因此新终端可以使用 `conda` 和 `conda activate`，但不会自动进入 `base`。
- 如需关闭交互式 Conda 初始化，在 `~/.config/envpilot/shell.local` 设置 `BASHRC_INIT_CONDA=0`。
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

## Git / Python

`install all` 会先检查 Git 和 Python。检测规则不是只看“命令是否存在”：

- Git 最低版本为 2.30。系统 Git 达标时直接使用；系统 Git 过低时保留原文件，并把新 Git 安装到 `$HOME/software/git/current/bin/git`。
- Python 最低版本为 3.9。优先使用系统 Python 3.9+ 或已有 Conda Python；都不满足时，Linux/macOS 根据 OS、架构和 libc 选择 `python-build-standalone` 的 stable `install_only` 资产。
- shell 模板会在非交互 shell 的 TTY 判断之前加入这些用户态目录，因此 `scp`、批处理和远程命令也能找到用户安装的 Git/Python。
- 系统目录和系统解释器不会被 envpilot 删除或覆盖。缺少编译器、开发库或可用的用户态安装源时，安装会停止并给出恢复路径，不会假装已经完成。
- 在线缓存、`downloads/` 离线包和 `--asset-path` 都会再次解析文件名版本；低于 Git 2.30 或 Python 3.9 的资产会在写入前停止。

手动执行：

```bash
bash envpilot.sh doctor
bash envpilot.sh install git
bash envpilot.sh install python
bash envpilot.sh update git
bash envpilot.sh update python
```
## Codex

单独安装 Codex：

```bash
bash envpilot.sh install codex
```

安装时会先真正执行 `codex --version` 检查现有 CLI。已有且可执行时，普通 `install codex` 只更新配置和密钥，不会重新安装 Codex，也不会安装 Node.js/npm；需要更新版本时使用：

```bash
bash envpilot.sh update codex
# 等价于：bash envpilot.sh install codex --upgrade
```

缺少 Codex 时，在线模式先使用官方独立安装器：
`https://chatgpt.com/codex/install.sh`。只有独立安装器下载或执行失败，才会进入 npm 回退路径。离线模式不会偷偷访问 npm；没有本地可执行 Codex 时会明确失败并给出恢复路径。

如果确实进入 npm 回退，envpilot 会根据系统兼容性选择 Node.js：Linux amd64 且 glibc 2.17-2.27 时使用 Node.js 22 的 `x64-glibc-217` 用户态构建，安装到默认 `$HOME/software/node22`，并把它放在 nvm 路径前面。glibc >= 2.28 的 Linux 才使用兼容的官方 nvm Node.js；其他架构没有安全匹配资产时会停止，不会下载错误架构。不要为了 Codex 升级系统 glibc，也不要把无法执行的官方 Node.js 24 二进制强行加入 PATH。

安装过程会显示 Node.js 来源、兼容性判断、目标目录和实际错误；例如旧系统会保留 `GLIBC_2.28 not found` 等诊断，而不是误报成“Node.js v22+ 未激活”。

Codex 配置使用：

```toml
env_key = "OPENAI_API_KEY"
```

这里的 `env_key` 是 Codex 配置项，不是 shell 变量名。正确的环境变量是 `OPENAI_API_KEY`，不是 `export env_key=...`。

安装器会按以下顺序查找密钥：

1. 当前 shell 的 `OPENAI_API_KEY`。
2. 权限为 600 或 400、且属于当前用户的 `~/.config/secrets/api.env`。
3. 检测到误写的 `env_key` 时提示是否修正使用。
4. 没有找到时，提示从兼容服务商（例如 YanHuoAPI）获取密钥并安全输入。

`install codex` 会确保 `~/.config/secrets/api.env` 存在。如果 `~/.codex/auth.json` 已经存在，普通安装或配置流程会原样保留它，不删除、不覆盖，也不会要求重新输入密钥。只有新用户尚无 `auth.json` 时，安装器才按上述顺序查找密钥：当前环境已有 `OPENAI_API_KEY` 就直接复用；否则读取受保护的 `api.env`；两处都没有时才提示安全输入。来自当前环境、修正后的 `env_key` 或交互输入的密钥会询问是否保存到 `api.env`，并保留其中已有的其他变量；随后默认确认创建权限为 600 的 `auth.json`。拒绝保存到 `api.env` 时，密钥只在本次进程中有效；拒绝创建 `auth.json` 时仍可使用：

```bash
chmod 600 ~/.config/secrets/api.env
with_secrets codex
```

### HPC / Remote SSH 的 Codex 本地 runtime

如果 `codex --version` 在共享文件系统（例如 NFS、Lustre、GPFS、BeeGFS 或 ParaStor）上出现几十秒无响应，而同一二进制复制到节点本地 `/tmp` 后很快，启用 Codex Remote Runtime：

```bash
bash envpilot.sh codex remote status
bash envpilot.sh codex remote enable
```

`enable` 不会重新安装 Codex。它会：

1. 在 `~/.codex/packages/standalone/current/bin` 或 `releases/*/bin` 中寻找持久化 Codex release。
2. 将完整 `bin/` 目录复制到 `/tmp/${USER}-envpilot-codex-${HOSTNAME}/current`，并依据路径、文件大小、mtime 和 inode 判断是否需要重新暂存。
3. 把 `~/.local/bin/codex` 替换为受管 wrapper；原有命令会先备份。
4. 保持 `~/.codex/config.toml`、`auth.json`、sessions 和 `app-server-control` 在持久化目录。
5. 预启动 app-server，并等待 `app-server-control.sock` 就绪。

wrapper 和 remote manager 在每次启动 Codex CLI 或 app-server 前都会读取权限为 600/400 的 `~/.config/secrets/api.env`，并导出其中全部变量；当前进程已显式提供的 `OPENAI_API_KEY` 优先于文件中的同名值。可用 `ENVPILOT_CODEX_LOAD_SECRETS=0` 单独关闭 Codex 进程级注入。更新到包含此功能的版本后，需要刷新已安装的 manager 并重启旧 app-server：

```bash
cd ~/envpilot
git pull --ff-only
bash envpilot.sh codex remote enable
bash envpilot.sh codex remote repair
bash envpilot.sh codex remote status
```

状态中应出现 `Protected environment injection: ready from protected ... (all variables)`；该状态只报告可用性，不显示任何密钥值。

日常登录或切换节点后只需要：

```bash
codex_ready
# 或：
bash envpilot.sh codex remote ready
```

检查状态：

```bash
codex_remote status
bash envpilot.sh codex remote status
```

需要修复 stale runtime 或重新复制完整 release 时：

```bash
bash envpilot.sh codex remote repair
```

停止的是 envpilot 自己记录的 app-server，不会主动杀掉 Desktop 或其他工具启动的未知 Codex 服务：

```bash
bash envpilot.sh codex remote stop
```

`~/.codex/app-server-control` 不要软链接到 `/tmp`。该目录承载 Unix socket 和 app-server 的持久控制状态，迁移后可能出现 `socket hang up`。节点本地 `/tmp` 只保存可重建的 Codex `bin/` runtime。禁用功能不会删除持久化 Codex：

```bash
bash envpilot.sh codex remote disable
```

`doctor` 会对 `codex --version` 使用有界探测；如果检测到共享文件系统上的执行超时，会提示使用 `codex remote ready`，不会让整个诊断无限卡住。Windows 原生入口暂不提供此 Unix app-server 预热功能；Windows 用户应使用 WSL、Git Bash 或直接使用本地 Codex 安装。


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
