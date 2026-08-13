# 扩展 envpilot

本文面向维护者，说明如何新增组件、更新 manifest、维护缓存，以及支持 `doctor -> restore` 的状态闭环。

## 核心原则

- 默认走用户态安装。
- 只有平台确实需要时才考虑管理员权限。
- 安装前必须说清楚：装什么、为什么选这个版本、写到哪里、会不会改配置。
- 不要把密钥、订阅链接、生成凭据写进受版本控制的 profile。
- 非交互 shell 必须保持安静。
- 交互式 shell 中敏感服务默认不自动启动，除非用户明确选择；如果远程自动化确实需要，可以提供有文档说明、安静且有边界的非交互就绪钩子。

## 组件契约

一个组件通常提供这些函数：

- `ep_doctor_<name>()`
- `ep_install_<name>()`
- 可选的 `ep_restore_<name>()` 或通过 baseline 恢复逻辑处理

安装函数应该按这个顺序工作：

1. 先判断是否已经安装
2. 再解析平台对应的安装源或包管理路径
3. 下载或改文件前先打印简短计划
4. 改写任何用户文件前先备份
5. 成功后调用 `ep_state_mark_done <name>`
6. 安装、跳过、失败都要写 report 事件

如果组件需要 Windows 支持，要在 `envpilot.ps1` 里补对应实现。

## Manifest 规则

每个 manifest 至少要说明：

- 上游来源
- stable 版本选择规则
- OS / 架构映射
- 离线文件名模式
- 需要排除的 prerelease 内容
- 预期安装路径和配置文件行为

resolver 可以在运行时查询上游 API，但如果无法安全判断具体版本，就必须停下来并明确提示，不能猜。

## Workflow 规则

- `test.yml`：语法检查和快速回归测试。
- `update-manifests.yml`：刷新上游 stable 元数据并自动开 PR。
- `update-mihomo-cache.yml`：刷新 `downloads/` 里的 mihomo 缓存和 GeoIP 侧车数据，再自动开 PR。
- `release-assets.yml`：只打包 envpilot 自己的 release 产物，不上传第三方安装包。

## 仓库镜像

GitHub 是主仓库，Gitee 是国内镜像。维护者本地应配置：

```bash
git remote add gitee https://gitee.com/zhangyehao0422/envpilot.git
git remote set-url --add --push gitee git@gitee.com:zhangyehao0422/envpilot.git
```

发布前确认工作区干净且位于 `main`，同步更新 `VERSION` 和 `CHANGELOG.md`，创建不可移动的版本标签，再运行 `scripts/push-mirrors.sh` 或 `scripts/push-mirrors.ps1`。禁止对任一镜像强推，也不要移动已经发布的标签。

## 缓存与 downloads

`downloads/` 是本地缓存目录，用来放安装包和其他想保留的 payload。大多数文件仍然默认忽略。

当前例外：

- `mihomo-linux-amd64-compatible-*.gz`
- `mihomo-windows-amd64-compatible-*.zip`
- `country.mmdb`
- `geoip.metadb`

如果要新增缓存文件，先更新 `.gitignore`，再更新对应的刷新脚本，并在这里写清楚原因。

## 状态、resume、rollback、restore

- 状态文件：`~/.config/envpilot/state`
- 备份日志：`~/.config/envpilot/rollback.log`
- doctor baseline：`~/.config/envpilot/baseline/baseline.tsv`
- baseline 快照文件：`~/.config/envpilot/baseline/files/`

`rollback` 只恢复最近一条备份记录，不是整机回滚。
`restore` 则按 doctor baseline 恢复 envpilot 管理的文件、目录和部分工具状态。如果组件会在可能已经存在的目录里创建受管理文件，必须在 baseline 里显式记录这个文件，不能只依赖目录是否存在。

子进程不能清理父 shell 中已经导出的代理变量，所以 shell 模板提供 `envpilot_restore`，用于执行 restore 后顺手清掉当前 shell 代理变量。

如果组件会写用户配置文件，必须先备份；如果一次要写多个文件，就分别备份。建议把用户最常恢复的那个文件放在最后备份，这样 `rollback` 默认恢复最后一条记录时更符合直觉。

## Shell profile 规则

Shell 模板必须：

- 在非交互 shell 中保持安静
- 交互式 shell 默认不自动启动 mihomo；非交互预启动必须可关闭、有超时、保持安静，并且只有存在有效配置时才执行
- 默认不自动加载 secrets
- 默认不自动激活 Conda base
- 允许从 `~/.config/envpilot/shell.local` 读取用户自定义内容

如果需要迁移 profile，优先写新模板或辅助文件，不要把主 profile 写成一大串分支脚本。

代理辅助函数必须先检查目标端口正在监听，再导出代理变量；默认只启用 HTTP/HTTPS，SOCKS 必须显式开启；只能向已有 `no_proxy` 追加本地地址，关闭代理时不得清空 `no_proxy`。

### 非交互 SSH 与 Codex 启动

Unix shell 模板必须把一段安静、尽力而为的准备逻辑放在非交互 TTY `return` 之前。这段逻辑可以创建节点本地 `TMPDIR`、读取持久化 Mihomo 端口、在存在有效配置时启动 envpilot 管理的 Mihomo，并且只在代理端口真实监听后导出 HTTP/HTTPS。启动等待必须有上限；它不能输出常规日志、让 shell 失败，或导出一个不可用的代理地址。

进程模型是“用户 + 节点”级别：同一用户在同一主机上的多个 SSH 窗口共享一个 envpilot Mihomo 运行实例，启动锁必须放在运行目录外。代理环境变量则是当前 shell 级别，所以 `proxy_on` 和 `proxy_off` 只影响当前窗口。不要把完整的 `~/.codex` 或 SQLite/会话状态迁移到 `/tmp`，这里只放临时文件、Mihomo 节点本地运行副本和启动锁。

不是所有远程启动器都会读取 `.bashrc`。测试和文档要分别覆盖 `bash -lc`、`BASH_ENV` 以及 supervisor/app-server 的直接启动；当 Mihomo 缺失、没有配置或健康检查失败时，非交互 profile 仍必须安静返回。

## 组件升级契约

`install` 可以遵循已完成状态；`update` / `upgrade` 必须绕过已完成状态并重新检查目标组件，用户不需要先执行 `reset`。

每个组件的升级路径必须：

- 根据 OS、架构、libc/runtime 和现有环境选择可兼容的最新 stable 版本
- 报告当前版本、目标版本、来源、路径以及更新或跳过原因
- 无法确认所有权时，不覆盖管理员维护的系统工具
- 更新 envpilot 已管理服务时保留用户配置，并恢复升级前的运行状态
- 同时覆盖 Unix 和 PowerShell 入口的 install/update 测试

Mihomo 升级必须保留已有 envpilot `config.yaml`，并且只在升级前本来就在运行时自动重启。`install all` 必须先准备 Mihomo，再处理 Git/Python/Conda/Mamba/Codex 等网络依赖，确保后续下载有机会使用代理。Conda 和 Mamba 由当前 Conda 求解器选择兼容版本。tmux 将当前命令与 `manifests/tmux.json` 比较，系统或 module 版本过低时构建用户态目标版本。Codex 通过 npm 更新；GitHub CLI 在 Unix 上只更新 envpilot 管理的副本，Windows 上优先交给 winget。

每次初始化都会把仓库实际位置记录到 `~/.config/envpilot/repo-root`。Shell 模板可以默认使用 `$HOME/envpilot`，但必须在该目录无效时读取记录路径，确保仓库 clone 到其他位置后仍可升级和管理。

## 测试

新增组件时，至少补这些 fixture：

- 已安装时的跳过行为
- 离线缺包的错误提示
- resolver 的 prerelease 过滤
- report 生成
- rollback 记录生成
- baseline 捕获与 restore
- mihomo 本地缓存优先选择

优先写快速测试，不要默认下载大文件。真正依赖网络的检查放到定时 CI 或 release workflow 里。

## 维护建议

- 只要行为变了，就同步更新 README、manifest 和测试。
- 默认行为要保守。
- Windows PowerShell 和 Unix-like shell 要当成两条不同执行面来看。
- 新增组件或缓存策略时，代码和刷新 workflow 要一起改。
- `update-mihomo-cache` 是维护本地和 CI 里 mihomo 缓存文件的统一入口。
- `doctor` 负责记录 baseline，`restore` 负责用这个 baseline 回到初始状态。

## Mihomo GeoIP 数据

Mihomo 在受限服务器上启动时，如果必须先从网络拉 GeoIP 数据，可能会因为代理还没起来而失败。envpilot 因此把它们当成 sidecar 资产：

- `downloads/country.mmdb` -> `~/.config/mihomo/country.mmdb`
- `downloads/geoip.metadb` -> `~/.config/mihomo/geoip.metadb`

`install mihomo` 会先从 `downloads/` 取这些文件，只有缺失时才回退到上游。离线模式下如果本地侧车文件缺失，就直接明确失败。

## Mihomo 运行与端口扩展约束

Mihomo 的 Unix 实现采用“家目录持久化、节点本地运行”模型。修改 Mihomo 时必须同时检查：

- `components/mihomo.sh` 负责解析平台、缓存、双端口和仓库入口。
- `templates/mihomo_common.sh` 是 start/stop/status/update-subscription 的共享契约。
- `templates/start_mihomo.sh` 只从 `~/software/mihomo` 和 `~/.config/mihomo` 复制到 `/tmp/${USER}_mihomo_${HOSTNAME}` 后运行。
- `MIHOMO_PROXY_PORT` 和 `MIHOMO_API_PORT` 必须贯穿安装、配置、启动、状态、代理变量和订阅更新。
- 新增运行文件时必须加入 doctor baseline、restore 和 Bash 语法/ShellCheck 测试。
- 订阅 URL、API secret 和生成的 `config.yaml` 不得进入测试 fixture 或 Git 历史。

`bootstrap.sh` / `bootstrap.ps1` 使用 partial clone + sparse checkout 按架构选择 `downloads/` 缓存。新增缓存平台时，需要同步更新 bootstrap 选择规则、manifest、更新 Action 和测试。

## Git / Python 组件约定

Git 组件的最低版本是 2.30，Python 组件的最低版本是 3.9。doctor 和 install 必须先验证现有命令的真实版本，不能只用 command -v 判断。达标的系统命令直接复用；低版本系统命令不能被删除或覆盖，新的用户态版本应安装到 prefix/git/current 或 prefix/python/current，并由 shell 模板在非交互 TTY 守卫之前加入 PATH。

Git 的 Linux/macOS 兜底路径是用户态源码构建，因此 manifest 必须记录稳定源码版本、离线文件名和构建依赖检查。Python 优先使用系统或 Conda 解释器，兜底资产必须同时匹配 OS、架构和 libc。新增版本下限时，要同步修改组件、manifest、doctor 输出、README、PowerShell 实现和 fixture 测试。

Codex 组件不得把密钥写入日志。密钥来源、auth.json 写入和明文配置覆盖都必须单独确认；新增敏感配置文件时要加入 doctor baseline、备份、rollback/restore 和 gitignore 规则。
