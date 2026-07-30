# envpilot

envpilot 是一个面向非管理员用户的跨平台环境引导仓库，用来在新服务器、工作站或远程主机上，按可控顺序安装常用工具、准备 shell 配置、启用代理、配置 Codex，并保留可回退的操作记录。

## 快速开始

Linux/macOS/WSL/Git Bash：

```bash
git clone https://github.com/zhangyehao/envpilot.git
cd envpilot
bash envpilot.sh doctor
bash envpilot.sh install mihomo
bash envpilot.sh apply-shell
source ~/.bashrc
mihomo_start
proxy_on
bash envpilot.sh install
```

Windows PowerShell：

```powershell
git clone https://github.com/zhangyehao/envpilot.git
cd envpilot
.\envpilot.ps1 doctor
.\envpilot.ps1 install mihomo
.\envpilot.ps1 apply-shell
```

推荐顺序是先装 `mihomo`，再 `apply-shell`，然后手动 `mihomo_start` 和 `proxy_on`，最后再跑其余安装。这样后续安装尽量不被网络波动卡住。默认不会自动启动代理，也不会在 shell 里偷偷改代理变量。

## 命令

### `doctor`
只检查，不修改。会输出系统、架构、shell、root/非 root、已安装工具、代理端口和缓存包状态。

### `install`
安装一个或多个组件。

```bash
bash envpilot.sh install
bash envpilot.sh install mihomo
bash envpilot.sh install conda
bash envpilot.sh install github
bash envpilot.sh install tmux
```

- `install all` 的默认顺序是 `mihomo -> conda -> mamba -> codex -> github -> tmux`
- 默认在线安装
- 可以加 `--mode offline`
- 可以加 `--asset-path PATH`
- 可以加 `--prefix PATH`
- 可以加 `--yes`

### `apply-shell`
备份当前 shell profile，然后替换为 envpilot 模板。

- Linux 通常处理 `~/.bashrc` 或 `~/.zshrc`
- Windows 处理 PowerShell profile
- 会把可迁移的 PATH / module / conda 片段写入 `~/.config/envpilot/shell.local`

### `rollback`
回退最近一次由 envpilot 备份的配置文件。

- 只恢复最后一条备份记录
- 不是整机回滚
- 主要用于 shell profile、Codex 配置、mihomo 配置这类文件

### `resume`
继续上一次中断的安装流程。

- 会读取状态文件
- 已完成的步骤会跳过
- 适合 `Ctrl+C` 后继续跑

### `reset`
清掉 envpilot 的状态文件，让安装步骤可以重新来。

- 不删除已安装的软件
- 只清理流程状态

### `update-manifests`
刷新 manifest 里的上游稳定版本元数据。

### `update-mihomo-cache`
刷新仓库里保留的两份稳定兼容 mihomo 缓存：

- `downloads/mihomo-linux-amd64-compatible-*.gz`
- `downloads/mihomo-windows-amd64-compatible-*.zip`

## mihomo

安装前会提示先去 [proxy.yanhuoapi.com](https://proxy.yanhuoapi.com/) 注册账号，并复制 **Clash/Mihomo 订阅链接**。

安装逻辑是：

1. 优先使用 `downloads/` 里的对应缓存包
2. 没有缓存时再去 GitHub Releases 选 stable release
3. 排除 alpha / beta / rc / prerelease
4. 安装到 `~/software/mihomo/mihomo`
5. 写入 `~/software/mihomo/start_mihomo.sh`

mihomo 不会自动启动。安装后建议手动执行：

```bash
mihomo_start
proxy_on
proxy_status
```

## Conda / Mamba

- 默认优先安装可用的最新 Miniconda 或 Anaconda
- 会根据 OS / 架构 / libc 选择可安装版本
- 不会自动 `conda init`
- `mamba` 只作为 Conda 环境里的求解器，不用于安装 tmux

## Codex

Codex 配置使用：

```toml
env_key = "OPENAI_API_KEY"
```

不要默认写入 `auth.json`。推荐把密钥放在：

```text
~/.config/secrets/api.env
```

然后通过：

```bash
with_secrets codex
```

## GitHub

普通 clone 优先用 HTTPS，因为很多服务器环境里还没登录 GitHub 账号，SSH key 也未必准备好了。

```bash
git clone https://github.com/zhangyehao/envpilot.git
```

如果你要用 SSH 推送，再执行：

```bash
gh auth login -h github.com --git-protocol ssh
ssh -T git@github.com
```

## tmux

tmux 必须是系统里能直接调用的命令，不通过 Conda 提供。

优先级：

1. 系统自带 tmux
2. module load tmux
3. root / 包管理器
4. 非 root Linux 用户态构建
5. Windows 原生不承诺，优先 WSL / MSYS2 / Git Bash

## Actions

- `test.yml`：语法检查和基础回归测试
- `update-manifests.yml`：刷新 manifest 的上游稳定元数据
- `update-mihomo-cache.yml`：刷新 `downloads/` 里的 mihomo 缓存包
- `release-assets.yml`：只打包 envpilot 自己的 release 产物，不上传第三方安装包

## 下载缓存

`downloads/` 默认仍然忽略大部分第三方安装包，但允许保留两份受控的 mihomo 缓存文件。其余二进制包仍然不要提交到 Git 历史。

## 报告与状态

每次安装都会写：

- `~/.config/envpilot/install-report.json`
- `~/.config/envpilot/logs/`
- `~/.config/envpilot/state*`

这些文件用于诊断、恢复和回退。

## Mihomo GeoIP ??

`install mihomo` ?? `downloads/country.mmdb` ? `downloads/geoip.metadb` ??? `~/.config/mihomo/`??? `mihomo_start` ????????? GitHub ?? GeoIP ??????????????????????????

`update-mihomo-cache` ??? GitHub Actions ????? Mihomo ??????`country.mmdb` ? `geoip.metadb`?
