# 扩展 envpilot

本文面向维护者，说明如何新增组件、更新 manifest、维护缓存，以及支持 `doctor -> restore` 的状态闭环。

## 核心原则

- 默认走用户态安装。
- 只有平台确实需要时才考虑管理员权限。
- 安装前必须说清楚：装什么、为什么选这个版本、写到哪里、会不会改配置。
- 不要把密钥、订阅链接、生成凭据写进受版本控制的 profile。
- 非交互 shell 必须保持安静。
- 敏感服务默认不自动启动，除非用户明确选择。

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
- 默认不自动启动 mihomo
- 默认不自动加载 secrets
- 默认不自动激活 Conda base
- 允许从 `~/.config/envpilot/shell.local` 读取用户自定义内容

如果需要迁移 profile，优先写新模板或辅助文件，不要把主 profile 写成一大串分支脚本。

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