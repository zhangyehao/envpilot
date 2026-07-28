# 扩展 envpilot

本文面向后续维护者，用于说明如何新增组件、扩展平台支持、维护版本清单以及设计自动更新流程。

## 设计原则

- 默认采用用户态安装，不要求管理员权限。
- 使用任何命令前先检测是否存在。
- 安装前必须说明：将安装什么、为什么选择这个版本、安装到哪里、会修改哪些配置。
- 不提交密钥、订阅链接、生成的配置、日志或二进制安装包。
- 不破坏非交互式 Shell 的启动行为；`scp`、`rsync`、Git 远程命令、VS Code Remote-SSH 等场景必须保持安静。
- 当用户期望一个工具成为直接可用命令时，不要把它安装成只能在 Conda 环境中使用的命令。

## 新增组件

新增一个组件时，至少补齐四类内容：

1. `components/<name>.sh`
2. 必要时在 `envpilot.ps1` 中补 Windows 支持
3. `manifests/<name>.json`
4. 测试用例和 README 使用示例

Shell 组件必须暴露两个函数：

```bash
ep_doctor_<name>()
ep_install_<name>()
```

安装函数应该遵循以下顺序：

- 需要类 Unix 运行时时调用 `ep_require_unix_runtime`
- 先检测已有安装，避免重复安装
- 根据 OS、架构、libc、Shell、root 状态解析平台匹配资产
- 在修改文件或安装前输出摘要并确认
- 成功后调用 `ep_state_mark_done <name>`
- 对安装、跳过或失败状态调用 `ep_report_event <name> ...`

## Manifest 规则

每个 manifest 应说明：

- 上游来源
- stable 版本选择策略
- OS 和 CPU 架构映射
- offline 模式文件名匹配规则
- 需要排除的版本，例如 alpha、beta、rc、pre、prerelease
- 预期安装路径和配置文件

resolver 可以在运行时查询上游 API，但如果无法安全判断应安装哪个版本，必须停止并给出清晰提示，不要猜测安装。

## CI/CD 策略

当前设计保留三类 workflow：

- `test.yml`：每次 push/PR 执行语法检查、fixture 测试和 README 命令检查。
- `update-manifests.yml`：定时或手动运行 `scripts/update-manifests.py`，查询上游 stable 元数据并写入 manifest 的 `latest` 字段；如有变化自动开 PR，不直接提交到 `main`。
- `release-assets.yml`：维护者手动触发，用 tag 生成 envpilot 自身的 `.tar.gz`、`.zip` 和 `.sha256` release assets。

不要把大型二进制包放进 Git 历史。第三方离线安装包（包括 Miniconda 和 Miniforge）默认只进入本地 `downloads/`；如需集中缓存，使用单独 offline-cache 仓库或专用非版本 tag，不要混入 envpilot 的 `v0.x.y` 正式 release。

## 状态、恢复和回滚

状态文件：

```text
~/.config/envpilot/state
```

回滚记录：

```text
~/.config/envpilot/rollback.log
```

如果组件会写用户配置文件，必须先调用 `ep_backup_file`。如果一个组件会写多个文件，应分别备份；最关键、最需要用户恢复的文件建议最后备份，这样 `rollback` 默认恢复最近一条记录时更符合直觉。

## Shell 模板

`.bashrc`、`.zshrc` 和 PowerShell profile 的维护规则：

- 非交互式 Shell 必须安静返回
- 默认不自动启动 mihomo
- 默认不自动加载 secrets
- 默认不自动激活 Conda base
- 用户本地覆盖配置从 `~/.config/envpilot` 加载

如果后续平台差异变多，优先新增模板文件，不要把一个模板写成过大的条件分支集合。

## 新组件测试

新增组件时至少补以下 fixture：

- 缺少依赖时的行为
- 已安装时的跳过逻辑
- online resolver 排除 prerelease 的逻辑
- offline 缺少资产时的错误提示
- 安装报告事件是否生成
- 修改配置前是否生成 rollback 记录

优先写快速、不下载大型文件的测试。需要真实联网或下载大文件的检查，应放到 scheduled CI 或手动 release workflow 中。

## 维护建议

- 每次新增组件时同步更新 README、manifest、doctor 输出和安装报告字段。
- 任何涉及密钥、订阅链接、代理配置的功能都应默认交互确认。
- 默认行为应保守：能检测就检测，不能判断就停止，不要替用户做高风险猜测。
- Windows 支持应区分 PowerShell 原生能力和 WSL/MSYS2/Git Bash 能力，避免承诺 Windows 原生不具备的 Unix 工具行为。
## 离线资产收集

GitHub Actions 运行在 GitHub-hosted runner 上，不能访问维护者本机磁盘。因此从 `D:\software`、`E:\software`、`~/Downloads` 等预设位置搜索安装包，应在维护者本机执行。

Windows：

```powershell
.\scripts\collect-assets.ps1 -DryRun
.\scripts\collect-assets.ps1 -MaxSizeMB 2000
```

Unix-like：

```bash
ENVPILOT_ASSET_MAX_SIZE_MB=2000 bash scripts/collect-assets.sh --dry-run
ENVPILOT_ASSET_MAX_SIZE_MB=2000 bash scripts/collect-assets.sh
```

脚本会把匹配到的 stable Miniconda/Miniforge 安装包复制到被忽略的 `downloads/`，并写入 `downloads/assets-index.json`。`downloads/` 只作为本机离线缓存，不应提交二进制包到 Git 历史。

`-UploadRelease` / `--upload-release` 只用于单独的离线缓存仓库或专用非版本 tag；脚本会拒绝把第三方安装包上传到 `zhangyehao/envpilot` 的 `v0.x.y` 正式 release。
