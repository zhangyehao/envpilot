# envpilot

envpilot 是一个面向非管理员用户的跨平台环境引导仓库，用来在新服务器、工作站或远程主机上，按可控顺序安装常用工具、配置 shell、启用代理，并保留可恢复的用户态状态。

## 快速开始

### Linux / macOS / WSL / Git Bash

优先用 HTTPS 拉取，因为新服务器通常还没有 GitHub SSH key：

```bash
git clone https://github.com/zhangyehao/envpilot.git
cd envpilot
bash envpilot.sh doctor
bash envpilot.sh install mihomo
bash envpilot.sh apply-shell
source ~/.bashrc
mihomo start
# 可选：把代理端口完整切换到 7891
mihomo port 7891
proxy_on
bash envpilot.sh install
```

如果后面出了问题，先回到仓库目录执行：

```bash
bash envpilot.sh restore
```

如果已经执行过 `apply-shell` 并重新加载了 shell，也可以直接执行：

```bash
envpilot_restore
```

`envpilot_restore` 会额外关闭当前 shell 里的代理环境变量；普通的 `bash envpilot.sh restore` 是子进程，不能修改父 shell 已经导出的环境变量。

### Windows PowerShell

```powershell
git clone https://github.com/zhangyehao/envpilot.git
cd envpilot
.\envpilot.ps1 doctor
.\envpilot.ps1 install mihomo
.\envpilot.ps1 apply-shell
```

PowerShell 下可用：

```powershell
.\envpilot.ps1 mihomo status
.\envpilot.ps1 mihomo stop
.\envpilot.ps1 mihomo port 7891
.\envpilot.ps1 restore
```

## 命令总览

| 命令 | 作用 |
| --- | --- |
| `doctor` | 只检查，不安装；同时记录本次 restore baseline。 |
| `install [all|mihomo|conda|mamba|codex|github|tmux]` | 安装组件；默认在线解析，组件可优先使用 `downloads/` 缓存。 |
| `apply-shell` | 备份并替换当前 shell profile。 |
| `mihomo start` / `mihomo stop` / `mihomo status` / `mihomo port PORT` | 在加载 shell 模板后管理 envpilot 安装的 mihomo，并可一条命令切换代理端口。 |
| `bash envpilot.sh mihomo start|stop|status|port PORT` | 不依赖 shell 模板，直接从仓库目录管理 mihomo。 |
| `restore` | 恢复到最近一次 `doctor` 记录的 baseline。 |
| `rollback` | 只恢复最近一次 envpilot 备份的单个文件。 |
| `resume` | 继续上一次中断的安装流程。 |
| `reset` | 清掉安装状态文件，允许重新跑安装步骤。 |
| `update-manifests` | 刷新 manifest 的上游 stable 元数据。 |
| `update-mihomo-cache` | 刷新 `downloads/` 里的 mihomo 缓存和 GeoIP 侧车数据。 |
| `self-test` | 运行仓库快速测试。 |

常用参数：

```bash
bash envpilot.sh install conda --conda-distribution anaconda
bash envpilot.sh install mihomo --mode offline
bash envpilot.sh install mihomo --asset-path downloads/mihomo-linux-amd64-compatible-v1.19.29.gz
bash envpilot.sh mihomo port 7891
bash envpilot.sh install --prefix "$HOME/software"
```

## 推荐安装顺序

默认 `install all` 的顺序是：

```text
mihomo -> conda -> mamba -> codex -> github -> tmux
```

推荐先单独安装 mihomo，再应用 shell，再启动代理，最后继续安装其他组件：

```bash
bash envpilot.sh doctor
bash envpilot.sh install mihomo
bash envpilot.sh apply-shell
source ~/.bashrc
mihomo start
# 可选：把代理端口完整切换到 7891
mihomo port 7891
proxy_on
bash envpilot.sh install
```

这样后续 Conda、Codex、GitHub CLI 等网络步骤更少被网络问题卡住。默认不会偷偷自动启动代理，也不会默认把代理变量写进 shell。

## Mihomo

安装前脚本会提示去 [proxy.yanhuoapi.com](https://proxy.yanhuoapi.com/) 注册账号，并复制 **Clash/Mihomo 订阅链接**。

安装源优先级：

1. `downloads/` 里的稳定兼容缓存包
2. GitHub Releases 的 stable release
3. 排除 alpha / beta / rc / prerelease

当前受控缓存包括：

```text
downloads/mihomo-linux-amd64-compatible-*.gz
downloads/mihomo-windows-amd64-compatible-*.zip
downloads/country.mmdb
downloads/geoip.metadb
```

安装后会写入：

```text
~/software/mihomo/mihomo
~/software/mihomo/start_mihomo.sh
~/.config/mihomo/config.yaml
~/.config/mihomo/country.mmdb
~/.config/mihomo/geoip.metadb
```

常用命令：

```bash
mihomo start
mihomo stop
mihomo status
mihomo port 7891
proxy_on
proxy_off
proxy_status
```

如果还没执行 `apply-shell`，也可以从仓库目录直接执行：

```bash
bash envpilot.sh mihomo status
bash envpilot.sh mihomo stop
bash envpilot.sh mihomo port 7891
```

`mihomo stop` 只停止 envpilot 管理路径下的 mihomo 进程，不会杀掉其他用户或其他路径的 mihomo。`mihomo port 7891` 会完整修改 `~/.config/mihomo/config.yaml` 的 `mixed-port`，把端口写入 envpilot 本地 shell/profile 配置，重启 envpilot 管理的 mihomo，并刷新当前 shell 的代理变量；未加载 shell 模板时可在仓库目录执行 `bash envpilot.sh mihomo port 7891`。

## Baseline / Restore

`doctor` 会记录：

```text
~/.config/envpilot/baseline/baseline.tsv
~/.config/envpilot/baseline/files/
```

`restore` 会按 baseline 恢复 envpilot 管理的文件和目录，停止 envpilot 管理的 mihomo，并清理安装状态文件。适合安装中途失败后回到执行 `doctor` 后的状态。

注意：再次执行 `doctor` 会覆盖 baseline。因此，想保留初始状态时，不要在失败后的半安装状态再执行 `doctor`。

`rollback` 和 `restore` 不一样：

- `rollback`：恢复最近一次备份的单个文件，例如 `.bashrc.bak.TIMESTAMP`。
- `restore`：按最近一次 `doctor` 的 baseline 恢复一组 envpilot 管理对象。

## Conda / Mamba

- 默认安装 Miniconda；也支持显式选择 Anaconda。
- 不使用 Miniforge。
- Linux 会根据 glibc 版本选择可安装的官方 Miniconda / Anaconda 版本。
- 不会默认执行 `conda init`。
- `mamba` 安装到 Conda base，但 tmux 不通过 Conda/Mamba 安装。

## Codex

Codex 配置使用：

```toml
env_key = "OPENAI_API_KEY"
```

推荐把密钥放到：

```text
~/.config/secrets/api.env
```

再通过：

```bash
with_secrets codex
```

## GitHub

普通用户 clone 推荐 HTTPS：

```bash
git clone https://github.com/zhangyehao/envpilot.git
```

如果需要 SSH 推送，再执行：

```bash
gh auth login -h github.com --git-protocol ssh
ssh -T git@github.com
```

## tmux

tmux 必须是系统里能直接调用的命令，不通过 Conda 环境提供。优先顺序：

1. 系统已有 tmux
2. module load tmux
3. root / 包管理器
4. 非 root 用户态构建
5. Windows 原生不承诺，优先 WSL / MSYS2 / Git Bash

## Actions 与发布

- `test.yml`：语法检查和快速回归测试。
- `update-manifests.yml`：定时刷新上游 stable 元数据并开 PR。
- `update-mihomo-cache.yml`：定时刷新 `downloads/` 里的 mihomo 缓存和 GeoIP 侧车数据并开 PR。
- `release-assets.yml`：只打包 envpilot 自身源码归档和校验值，不上传第三方安装包。

## 仓库约定

- secrets、订阅链接、日志、生成配置不进入 Git 历史。
- `downloads/` 只保留明确允许的受控缓存文件。
- 新增组件时同步更新测试、文档、manifest 和 baseline/restore 规则。
