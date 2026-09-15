# 升级与恢复

[English](UPGRADE.md)

已有命令入口时运行 `envpilot self-update`。Git 安装要求工作区干净且可快进到稳定版；分叉或未提交修改会保留，不强制覆盖。平台包安装验证 SHA-256 后使用新的版本目录。

从 0.3.0 或更早版本首次升级，可先更新源码或解压平台包，再执行：

```bash
bash envpilot.sh setup-command
export PATH="$PATH:$HOME/.local/bin"
envpilot init --lang zh-CN
envpilot config show
envpilot plan
envpilot apply
```

已有 YAML 时跳过 `init`。旧的 Shell 开关、端口、模块列表及 `shell.local` 会尽量按确定的字面值导入；迁移不执行旧脚本。密钥和 `auth.json` 保留。

旧 profile 与历史模板精确匹配时自动迁移到短加载块。若 profile 中有自定义修改，文件保持原样，配置目录出现 `migration-pending.txt`；先对照备份把所需自定义内容放入用户自有 profile，再执行 `apply-shell`。程序不会猜测或删掉复杂函数。

变更前会创建新的受管文件快照，旧快照不覆盖。`doctor` 不再创建或替换恢复基线。

```bash
envpilot doctor
envpilot snapshot
envpilot restore
# 指定某个快照：
envpilot restore /实际配置目录/snapshots/时间戳
```

快照覆盖受管配置和脚本，不承诺回退包管理器的所有外部操作、第三方数据库或 Codex 会话。没有新快照时，`restore` 仍可使用旧 `baseline/baseline.tsv`。`rollback` 继续用于最近一次单文件备份。

更新 Codex 时，原服务运行则切换新版本并重启；原服务停止则不自动启动。手动恢复文件后，根据需要运行 `envpilot codex remote restart`。
