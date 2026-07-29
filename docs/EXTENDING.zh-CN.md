# 扩展 envpilot

这份文档面向维护者，用来说明如何新增组件、维护 manifest、以及调整自动化策略。

## 基本原则

- 默认走用户态安装。
- 只有平台真的需要时才考虑管理员权限。
- 安装前必须说清楚：装什么、为什么选这个版本、写到哪里、是否会改配置。
- 不要把密钥、订阅链接、生成出来的凭据写进受版本控制的 profile 文件。
- 非交互 shell 必须保持安静。
- 敏感服务默认不要自动启动，除非用户明确选择。

## 组件契约

一个组件通常要提供这些 shell 函数：

- `ep_doctor_<name>()`
- `ep_install_<name>()`

安装函数应该按下面顺序工作：

1. 先判断是不是已经安装过
2. 再解析平台相关的安装源或包管理路径
3. 在下载或改文件前先打印简要计划
4. 任何用户文件都要先备份再改
5. 成功后调用 `ep_state_mark_done <name>`
6. 安装、跳过、失败都要写 report 事件

如果组件需要 Windows 支持，就要在 `envpilot.ps1` 里补对应实现。

## Manifest 规则

每个 manifest 至少要说明：

- 上游来源
- stable 版本选择规则
- OS / 架构映射
- 离线文件名匹配规则
- 需要排除的 prerelease 内容
- 预期安装路径和配置文件行为

resolver 可以在运行时查询上游 API，但如果无法安全判断该装哪个版本，就必须停下来并明确提示，不允许猜。

## Workflow 规则

- `test.yml`：语法检查和快速回归测试。
- `update-manifests.yml`：刷新上游 stable 元数据并自动开 PR。
- `update-mihomo-cache.yml`：刷新 `downloads/` 中保留的 mihomo 缓存文件并自动开 PR。
- `release-assets.yml`：只打包 envpilot 自己的发布产物，不要把第三方安装包传到这里。

## 缓存与 downloads 规则

`downloads/` 是本地缓存目录，用来放安装包和其他 payload。默认仍然忽略大多数文件。

当前例外是：

- 保留稳定版 `mihomo-linux-amd64-compatible-*.gz`
- 保留稳定版 `mihomo-windows-amd64-compatible-*.zip`
- 其他第三方大文件继续默认忽略，除非以后有新的明确规则

如果以后要加新的缓存文件，要先在 `.gitignore` 里写清楚规则，再更新对应的刷新脚本，并在本文说明原因。

## 状态、resume 和 rollback

状态文件：

```text
~/.config/envpilot/state
```

回退日志：

```text
~/.config/envpilot/rollback.log
```

如果组件会写用户配置文件，必须先备份；如果一次要写多个文件，就分别备份。建议把用户最常见需要恢复的那个文件放在最后备份，这样 `rollback` 默认恢复最后一条记录时最符合直觉。

`rollback` 只恢复最近一次备份记录，不是整机回滚。

## Shell profile 规则

Shell 模板必须：

- 在非交互 shell 里保持安静
- 默认不自动启动 mihomo
- 默认不自动加载 secrets
- 默认不自动激活 Conda base
- 用户自定义追加内容放在 `~/.config/envpilot/shell.local`

如果需要迁移 profile，优先新增模板或辅助文件，不要把主 profile 写成很多分支的脚本。

## 测试

新增组件时至少补这些 fixture：

- 已安装时的跳过行为
- 离线缺包时的错误提示
- resolver 的 prerelease 过滤
- report 生成
- rollback 记录生成
- mihomo 本地缓存优先选择

优先写快速测试，不要默认下载大文件。真正依赖网络的检查放到定时 CI 或 release workflow 里。

## 维护建议

- 行为变化时，同步更新 README、manifest 和测试。
- 默认行为保持保守。
- Windows PowerShell 和 Unix-like shell 要当成两条不同执行面来看。
- 新增组件或缓存策略时，代码和刷新 workflow 要一起改。
- `update-mihomo-cache` 是维护本地和 CI 里那两份 mihomo 缓存的统一入口。
