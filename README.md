# envpilot

envpilot 是面向非管理员用户的跨平台环境引导和维护工具，重点解决 HPC 登录节点、共享文件系统、远程 SSH 和普通工作站上的用户态安装、代理、恢复与升级问题。

当前支持 Mihomo、Conda/Anaconda、Mamba、Git、Python、Codex、GitHub CLI 和 tmux。默认优先使用与当前系统、架构和 libc 兼容的 stable 版本；Mihomo 和 geodata 优先使用仓库内匹配架构的缓存。

仓库镜像：

- GitHub：https://github.com/zhangyehao/envpilot
- Gitee：https://gitee.com/zhangyehao0422/envpilot

两端使用相同的 main 和版本标签。用户下载优先 HTTPS；维护者在获得授权后同步 main、标签和 Release。

## 快速开始

### Linux、macOS、WSL、Git Bash

~~~bash
git clone https://github.com/zhangyehao/envpilot.git
# 国内网络可改用：
# git clone https://gitee.com/zhangyehao0422/envpilot.git
cd envpilot
# 仅在更新版本的时候使用
git pull --ff-only

bash envpilot.sh doctor
export MIHOMO_PROXY_PORT=42290
export MIHOMO_API_PORT=60290

bash envpilot.sh install mihomo
bash envpilot.sh apply-shell
source ~/.bashrc

mihomo start
mihomo status
proxy_on

bash envpilot.sh install
~~~

也可以使用按架构稀疏下载的入口：

bootstrap 使用 partial clone 和 sparse-checkout，只拉取当前架构需要的 Mihomo 缓存，随后再获取仓库其余必要文件。

~~~bash
curl -fsSL https://raw.githubusercontent.com/zhangyehao/envpilot/main/bootstrap.sh | bash
cd envpilot
bash envpilot.sh doctor
~~~

国内网络：

~~~bash
export ENVPILOT_REPO_URL=https://gitee.com/zhangyehao0422/envpilot.git
curl -fsSL https://gitee.com/zhangyehao0422/envpilot/raw/main/bootstrap.sh | bash
~~~

### Windows PowerShell

~~~powershell
irm https://raw.githubusercontent.com/zhangyehao/envpilot/main/bootstrap.ps1 | iex
cd envpilot
.\envpilot.ps1 doctor
.\envpilot.ps1 install all
~~~

也可以直接 clone Gitee：

~~~powershell
git clone https://gitee.com/zhangyehao0422/envpilot.git
cd envpilot
.\envpilot.ps1 doctor
~~~

### 推荐顺序

共享服务器上先让 Mihomo 就绪，再安装依赖网络的组件：

1. doctor，记录恢复基线；
2. install mihomo，使用架构匹配缓存或稳定网络源；
3. apply-shell，备份并安装受管 profile；
4. source profile，启动并检查 Mihomo；
5. install 或 update 其他组件。

详细说明：

- Mihomo：[docs/MIHOMO.zh-CN.md](docs/MIHOMO.zh-CN.md)
- Conda/Mamba：[docs/CONDA-MAMBA.zh-CN.md](docs/CONDA-MAMBA.zh-CN.md)
- Git/Python：[docs/GIT-PYTHON.zh-CN.md](docs/GIT-PYTHON.zh-CN.md)
- Codex：[docs/CODEX.zh-CN.md](docs/CODEX.zh-CN.md)
- GitHub CLI/tmux：[docs/GITHUB-TMUX.zh-CN.md](docs/GITHUB-TMUX.zh-CN.md)
- 生命周期和恢复：[docs/OPERATIONS.zh-CN.md](docs/OPERATIONS.zh-CN.md)
- Shell 配置：[docs/SHELL-CONFIG.zh-CN.md](docs/SHELL-CONFIG.zh-CN.md)

## Mihomo

Mihomo 是 envpilot 的本地 HTTP/SOCKS5 代理和外网准备组件。持久文件在用户目录，实际运行文件复制到当前节点的 /tmp，以减少共享文件系统执行问题。

安装、更新和缓存：

~~~bash
bash envpilot.sh install mihomo
bash envpilot.sh update mihomo
bash envpilot.sh install mihomo --mode offline
bash envpilot.sh install mihomo --asset-path downloads/mihomo-linux-amd64-compatible-v1.19.29.gz
bash envpilot.sh update-mihomo-cache
~~~

交互式命令：

~~~bash
mihomo start
mihomo stop
mihomo status
mihomo port PORT
mihomo ports PROXY_PORT API_PORT
mihomo update-subscription [URL]
mihomo proxy-on
mihomo proxy-off
mihomo run [ARGS]
proxy_on
proxy_off
proxy_status
~~~

统一端口变量：

~~~bash
export MIHOMO_PROXY_HOST=127.0.0.1
export MIHOMO_PROXY_PORT=42290
export MIHOMO_API_PORT=60290
mihomo ports 42290 60290
~~~

mihomo status 会检查进程、实际监听端口、API 健康、代理出口和最近日志。mihomo stop 只停止当前用户、当前节点、envpilot 运行目录中的实例。安装或更新遇到已有 Mihomo 时会先显示接管计划，确认后才停止，并记录 mihomo-takeover-report.json。

订阅 URL 不要提交到仓库或聊天记录。完整参数、接管规则、端口安全和缓存策略见 [docs/MIHOMO.zh-CN.md](docs/MIHOMO.zh-CN.md)。

## Conda 和 Mamba

安装和更新：

~~~bash
bash envpilot.sh install conda
bash envpilot.sh install conda --conda-distribution anaconda
bash envpilot.sh update conda
bash envpilot.sh install mamba
bash envpilot.sh update mamba
~~~

默认选择官方 Miniconda；Linux 根据架构和 glibc 选择可运行的官方版本。Anaconda 与 Miniconda 并存时，交互式 profile 优先 Miniconda，并把标准 Anaconda envs 加入 CONDA_ENVS_PATH。只有 Anaconda 时，默认 install conda 仍会按需并存安装 Miniconda。

envpilot 管理仓库模板 templates/condarc，并在安装或更新 Conda 时备份和写入 ~/.condarc。默认频道是清华镜像的 conda-forge 和 bioconda，default_channels 为空，base 不自动激活。Mamba 安装不会重写现有 ~/.condarc；bootstrap 事务只索引 conda-forge，因为 bioconda 不参与 Mamba 安装。若检测到旧 Miniconda（Conda 低于 24.11.1），envpilot 会先询问是否用官方兼容安装器原地升级 base，保留已有 envs 目录，再使用 libmamba 安装 Mamba。

常用检查：

~~~bash
conda config --show-sources
conda config --show channels default_channels channel_priority auto_activate_base
conda env list
conda info --base
conda activate ENV_NAME
~~~

详细注意事项见 [docs/CONDA-MAMBA.zh-CN.md](docs/CONDA-MAMBA.zh-CN.md)。

## Git

envpilot 要求 Git 2.30 或更高。达标的系统/module Git 直接复用；过低时保留系统 Git，在用户目录安装新版本：

~~~bash
bash envpilot.sh install git
bash envpilot.sh update git
git --version
command -v git
~~~

用户态目标通常是 $HOME/software/git/current/bin/git。不会覆盖 /usr/bin/git 或管理员提供的 Git。详情见 [docs/GIT-PYTHON.zh-CN.md](docs/GIT-PYTHON.zh-CN.md)。

## Python

envpilot 要求 Python 3.9 或更高。优先使用系统 Python 3.9+ 或已有 Conda Python；两者都不满足时，按 OS、架构、libc 选择兼容的 stable standalone 资产：

~~~bash
bash envpilot.sh install python
bash envpilot.sh update python
python3 --version
command -v python3
~~~

旧 glibc 主机不会盲目下载无法执行的最新版。不会删除或替换系统 Python。详情见 [docs/GIT-PYTHON.zh-CN.md](docs/GIT-PYTHON.zh-CN.md)。

## Codex

安装和更新：

~~~bash
bash envpilot.sh install codex
bash envpilot.sh update codex
~~~

普通 install codex 会复用已有且可执行的 Codex，只更新配置和认证；只有 update 才会主动重新解析和更新版本。真正的 API 变量是 OPENAI_API_KEY，已有 ~/.codex/auth.json 会被保留。

共享文件系统上的 Codex 较慢时：

~~~bash
bash envpilot.sh codex remote status
bash envpilot.sh codex remote enable
bash envpilot.sh codex remote ready
bash envpilot.sh codex remote repair
bash envpilot.sh codex remote stop
bash envpilot.sh codex remote disable
codex_ready
~~~

持久配置、auth、sessions 和 app-server control 留在 ~/.codex，只把可重建 runtime 放到节点本地 /tmp。旧 glibc 的 Node.js 兼容策略、api.env、auth.json 保留规则见 [docs/CODEX.zh-CN.md](docs/CODEX.zh-CN.md)。

## GitHub CLI

~~~bash
bash envpilot.sh install github
bash envpilot.sh update github
gh --version
~~~

envpilot 只更新自己的用户态副本，不强制覆盖管理员提供的 gh。GitHub 登录和 token 管理由 gh 自己负责。详情见 [docs/GITHUB-TMUX.zh-CN.md](docs/GITHUB-TMUX.zh-CN.md)。

## tmux

~~~bash
bash envpilot.sh install tmux
bash envpilot.sh update tmux
tmux -V
~~~

先复用系统或 module 中达到 stable 目标的版本；版本过低且无管理员权限时，在用户目录构建新版本并让 ~/.local/bin/tmux 优先。tmux 不通过 Conda/Mamba 安装。详情见 [docs/GITHUB-TMUX.zh-CN.md](docs/GITHUB-TMUX.zh-CN.md)。

## 生命周期和恢复

主命令：

| 命令 | 作用 |
| --- | --- |
| doctor | 只检查并记录最近一次 restore baseline。 |
| install COMPONENT | 首次安装组件；默认在线，Mihomo 优先使用本地匹配缓存。 |
| update COMPONENT | 忽略已完成状态，重新检查兼容 stable 版本。 |
| apply-shell | 备份并替换 Bash/zsh 或 PowerShell profile。 |
| restore | 恢复最近一次 doctor baseline，包括受管文件和用户态目录。 |
| rollback | 恢复最近一次 envpilot 单文件备份。 |
| resume | 继续中断的 install all。 |
| reset | 只清除安装状态，不卸载软件。 |
| update-manifests | 刷新上游 stable 元数据。 |
| update-mihomo-cache | 刷新 Mihomo 和 geodata 缓存。 |
| self-test | 运行 Bash/PowerShell 测试。 |

Unix 参数：

~~~bash
bash envpilot.sh install [all|git|python|mihomo|conda|mamba|codex|github|tmux] [--mode online|offline] [--prefix PATH] [--asset-path PATH] [--conda-distribution miniconda|anaconda] [--upgrade] [--yes]
bash envpilot.sh update [all|git|python|mihomo|conda|mamba|codex|github|tmux]
~~~

Windows 对应使用：

~~~powershell
.\envpilot.ps1 install [all|git|python|mihomo|conda|mamba|codex|github|tmux] [-Mode online|offline] [-Prefix PATH] [-AssetPath PATH] [-Upgrade] [-Yes]
.\envpilot.ps1 update [all|git|python|mihomo|conda|mamba|codex|github|tmux]
~~~

安装失败后的建议：

~~~bash
bash envpilot.sh doctor
bash envpilot.sh restore
~~~

不要在想保留的初始状态上再次执行 doctor，因为它会覆盖最近一次 baseline。restore 和 rollback 的区别、备份位置和升级流程见 [docs/OPERATIONS.zh-CN.md](docs/OPERATIONS.zh-CN.md)。

## Shell 和配置文件

| 文件 | 用途 |
| --- | --- |
| ~/.bashrc 或 ~/.zshrc | envpilot 受管入口、函数、路径和静默准备逻辑。 |
| ~/.config/envpilot/shell.local | 用户覆盖项、PATH 和安全的 module 设置。 |
| ~/.config/secrets/api.env | 需要被多个软件继承的环境变量和 API key，权限 600/400。 |
| ~/.condarc | 由 templates/condarc 统一生成的 Conda 配置。 |
| ~/.config/mihomo/ | Mihomo 持久配置和 geodata。 |
| ~/.codex/ | Codex 配置、auth、sessions 和持久控制目录。 |

BASHRC_PROFILE_ACTIVE、ENVPILOT_LAST_* 是模板内部用于区分“envpilot 管理值”和“用户外部覆盖值”的标记，一般不需要手工修改。静默 shell 会加载 api.env 全部变量和必要的用户态 PATH，但不会加载交互式 Conda、module、历史同步或输出提示。函数暂时保留在 profile 中是为了兼容 SSH/BASH_ENV/Codex 的加载顺序；讨论和边界见 [docs/SHELL-CONFIG.zh-CN.md](docs/SHELL-CONFIG.zh-CN.md)。

## 镜像、缓存和发布

受控缓存位于 downloads/：

~~~text
mihomo-linux-<arch>-*.gz
mihomo-windows-<arch>-*.zip
country.mmdb
geoip.metadb
~~~

bootstrap.sh/bootstrap.ps1 会先检测架构，尽量只获取匹配的 Mihomo 缓存。普通 clone 不会在 Git 传输前过滤所有已跟踪文件。

GitHub Actions：

- test.yml：Linux、macOS、Windows 回归测试；
- update-manifests.yml：定时更新 stable 元数据并创建 PR；
- update-mihomo-cache.yml：定时更新 Mihomo/geodata 缓存并创建 PR；
- release-assets.yml：为版本标签生成源码归档和 sha256。

维护者同步镜像：

~~~bash
bash scripts/push-mirrors.sh
~~~

本项目采用 MIT License，详见 LICENSE。扩展规范见 [docs/EXTENDING.zh-CN.md](docs/EXTENDING.zh-CN.md)。技能源文件见 [docs/ENVPILOT-SKILL.md](docs/ENVPILOT-SKILL.md)。
