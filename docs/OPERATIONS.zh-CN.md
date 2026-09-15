# 生命周期与运维

[配置](CONFIG.zh-CN.md) · [升级和恢复](UPGRADE.zh-CN.md) · [Shell 接入](SHELL-CONFIG.zh-CN.md)

推荐流程：`init` 创建配置 → `config edit` 编辑 → `plan` 预览 → `apply` 应用。Mihomo 在其他网络组件之前安装；已有配置和用户选定端口会保留。

`doctor` 只诊断。变更前创建版本化快照，`snapshot` 可显式创建恢复点；`restore` 恢复快照或旧 baseline；`rollback` 恢复最近一次单文件备份。`resume` 继续中断安装，`reset` 只清除状态。

`self-update` 更新 envpilot 和受管脚本，`update COMPONENT` 更新所选组件。升级不要求先 reset。Git 工作区有修改或分叉时不会被强制覆盖。

维护者发布前更新 VERSION 和 CHANGELOG，完成 Bash、PowerShell、Go、ShellCheck 和工作流检查，再发布不可变标签。两端 main 和标签必须一致。GitHub App 只需要本仓库 Contents/Pull requests 读写权限；私钥放在 ENVPILOT_APP_PRIVATE_KEY，App ID 放在 ENVPILOT_APP_ID 变量。
