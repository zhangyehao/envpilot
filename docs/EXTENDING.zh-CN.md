# 扩展 envpilot

[English](EXTENDING.md)

## 组件接口

Bash 组件提供 `ep_doctor_<name>()` 和 `ep_install_<name>()`，PowerShell 提供对应适配。保留用户安装方式和系统工具，按 OS、架构、libc 选择兼容 stable 版本，排除 alpha、beta、rc、nightly。

配置统一由 envpilot-core 的 YAML 库解析。新增选项须同步 schema、校验、适配器导出、文档和测试。常规设置、密钥引用、运行状态分开保存，不通过 Shell 执行配置。

安装器说明组件、来源、目标和结果。apply 统一确认，默认否的可选备用安装方式在非交互流程中仍不接受。缺少必要输入时直接报错，不等待 stdin。面向用户的消息使用共享中英文目录，机器字段稳定，上游原始诊断保留。

## Shell 接入

apply-shell 保留原 profile，只更新受管加载块，逻辑存放在独立文件。新用户显式选择代理、Conda、module、历史和兼容别名；迁移保留旧开关。

不得执行旧 profile 来发现配置。只导入理解明确的字面赋值；仅精确匹配历史模板时自动替换旧受管 profile。自定义修改必须保留并提示核对。保留 shell.local 和密钥文件。

非交互 SSH/scp/rsync 不运行交互初始化。代理导出前须确认端口监听，保留 no_proxy。修改父 Shell 环境只能通过明确的 Shell 接入；envpilot run 只影响子进程。

## Codex 生命周期

status、stop、ready、enable、restart 使用同一识别规则：当前用户、节点、CODEX_HOME/控制 socket 和进程启动身份。已确认匹配的 Desktop/SSH 实例可以管理；无关或归属不明的实例不能接管。

生命周期操作串行化。认证、配置、sessions 和控制目录保留在持久存储；仅可重建的二进制及必要 helper 放入版本化本地缓存。不可复制 PATH 命中目录的全部内容。停止正常服务前先校验新文件，restart 必须确认新进程和协议就绪。原生 daemon 除命令能力外，还须满足固定安装路径要求。

普通 install 保留已有或版本探测较慢的安装。update 保持 standalone/npm 方式，刷新并重启原先运行的服务；原先停止则不自动启动。官方安装器使用 CODEX_NON_INTERACTIVE=1，npm 备用方式为显式选择。

## 恢复与数据

Doctor 只诊断。修改受管文件前创建新快照，不覆盖旧恢复点；已有目录中的新增文件也须记录。兼容旧 baseline.tsv。文件快照不承诺回退所有包管理事务，也不改变会话历史。

订阅、API key、认证文件和运行日志不进入 Git。Unix 密钥文件属于当前用户，权限 600/400。测试使用隔离 HOME 和虚构凭据。

Mihomo 优先安装，保留已选端口和受管配置；更新后恢复原运行状态。仓库只保留既有 Linux/Windows amd64 Mihomo 及 country.mmdb、geoip.metadb 缓存。其他离线资源由用户提供。

Mihomo 节点列表、选择及测试使用配置工具处理控制接口 JSON，不引入 Python/jq 运行依赖。读取订阅 YAML 中的控制凭据时不输出值。非交互选择必须显式提供组与节点；测试不修改选择。

选择记录按主机保存在配置目录的 `mihomo-selections/` 下，不依赖可删除的运行缓存。重启或订阅替换后仅恢复仍存在的组和节点，缺失时提示用户重新选择，不猜测替代值。共享 HOME 的节点不能覆盖彼此的选择。

订阅下载支持 `auto/direct/proxy`，默认先直连再尝试代理，避免不可用的旧节点阻断更新。网络错误分类并脱敏，可重试失败使用有界退避。完整 YAML 下载和本地文件导入共用校验、备份与替换流程；验证完成前不能停止运行中的代理或覆盖旧配置。本地导入保留原订阅引用。

Conda 默认 Miniconda，在旧 glibc 使用兼容安装器并保留环境。Mamba 保留 .condarc，使用隔离频道和求解器。Git/Python/tmux 优先复用兼容工具，升级写入用户目录，不替换系统 glibc。

## 测试和发布

运行 Go、Bash、PowerShell、Python 测试，以及 ShellCheck、actionlint、git diff --check。覆盖新装、旧配置、复杂 profile、静默模式、无效配置、真实 socket/进程和网络事务失败。

Mihomo 回归覆盖 Unicode 组名/节点名、交互与非交互选择、控制接口鉴权、重启后的选择恢复、订阅删除节点、共享 HOME 的节点隔离、直连/代理回退、残留代理变量、限流重试、HTML/无效 YAML 和离线导入。所有诊断断言同时检查凭据不会进入输出。

PR 测试使用只读权限。更新任务暂存并校验完整结果后提交，使用仅安装到 envpilot 的 GitHub App。配置 ENVPILOT_APP_ID 变量和 ENVPILOT_APP_PRIVATE_KEY Secret，不提交密钥或令牌。

更新 VERSION 和 CHANGELOG，验收确切提交后发布不可变标签、平台包和 SHA256SUMS。验证 GitHub/Gitee main 和标签一致，不强推、不移动已发布标签。推送脚本必须验证远程引用，不能只根据“已尝试推送”报告成功。
