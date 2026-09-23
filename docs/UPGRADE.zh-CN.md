# 升级与恢复

[English](UPGRADE.md)

## 已安装 0.4.x：直接更新

```bash
envpilot self-update
envpilot version
envpilot config validate
envpilot plan
```

Git 安装要求工作区干净且可快进到稳定版；分叉或未提交修改会保留，不强制覆盖。平台包安装验证 SHA-256 后使用新的版本目录。更新 envpilot 不会自动更新所有组件；组件更新使用 `envpilot update COMPONENT`。

## 更新已有源码仓库

如果仓库已在 `~/envpilot`，执行以下命令。安装在其他位置时，修改第一行路径：

```bash
cd "$HOME/envpilot" && git pull --ff-only origin main
```

只有拉取成功后才继续下方“登记入口并应用配置”。不要再次向已有的 `envpilot` 目录执行 `git clone`，也不需要为普通升级重命名旧仓库。出现本地修改或分叉错误时，先用 `git status` 查看并保存自己的修改，不要使用强制重置。

若还没有仓库，才使用下面的首次克隆命令：

```bash
git clone https://github.com/zhangyehao/envpilot.git "$HOME/envpilot" && cd "$HOME/envpilot"
# 使用 Gitee 时，将上面的仓库地址换成：
# https://gitee.com/zhangyehao0422/envpilot.git
```

`bash envpilot.sh ...` 必须在仓库目录内执行；也可使用 `bash "$HOME/envpilot/envpilot.sh" ...`。克隆完成后仍停留在原目录，不会自动进入仓库。

## 改用平台包升级（Linux/macOS）

平台包附带匹配的配置工具。下面命令自动选择系统与架构，下载固定的 0.4.2 版本、校验 SHA-256，并解压到新的目录。它们不会覆盖旧源码目录：

```bash
(
  set -eu
  version=0.4.2
  case "$(uname -s)" in Linux) os=linux ;; Darwin) os=darwin ;; *) echo '请使用匹配系统的平台包'; exit 1 ;; esac
  case "$(uname -m)" in x86_64|amd64) arch=amd64 ;; aarch64|arm64) arch=arm64 ;; armv7l) arch=armv7 ;; *) echo '不支持此架构'; exit 1 ;; esac
  asset="envpilot-$version-$os-$arch.tar.gz"
  base="https://github.com/zhangyehao/envpilot/releases/download/v$version"
  # 仅当 Gitee 对应版本附件已齐全时改用：base="https://gitee.com/zhangyehao0422/envpilot/releases/download/v$version"
  mkdir -p "$HOME/Downloads/envpilot-$version"
  cd "$HOME/Downloads/envpilot-$version"
  curl -fL --retry 3 "$base/$asset" -o "$asset"
  curl -fL --retry 3 "$base/SHA256SUMS" -o SHA256SUMS
  awk -v name="$asset" '$2 == name {print}' SHA256SUMS > selected.sha256
  test -s selected.sha256
  if command -v sha256sum >/dev/null; then sha256sum -c selected.sha256; else shasum -a 256 -c selected.sha256; fi
  mkdir -p "$HOME/.local/share/envpilot/releases"
  test ! -e "$HOME/.local/share/envpilot/releases/envpilot-$version"
  tar -xzf "$asset" -C "$HOME/.local/share/envpilot/releases"
)
```

上一步全部成功后进入解压目录；目标目录已存在时，请先检查原有内容，不要强行覆盖：

```bash
cd "$HOME/.local/share/envpilot/releases/envpilot-0.4.2"
```

## 登记入口并应用配置

在已更新的仓库或已解压的平台包目录中执行：

```bash
bash envpilot.sh setup-command
export PATH="$PATH:$HOME/.local/bin"
# 已有 YAML 时不再初始化：
if [ ! -f "${ENVPILOT_CONFIG_DIR:-$HOME/.config/envpilot}/config.yaml" ]; then
  envpilot init --lang zh-CN
fi
envpilot config validate
envpilot config show
envpilot plan
envpilot apply
```

如果使用自定义 `--config` 路径，继续传入原路径并跳过 `init`。旧的 Shell 开关、端口、模块列表及 `shell.local` 会尽量按确定的字面值导入；迁移不执行旧脚本。密钥和 `auth.json` 保留。

从 0.4.0 升级并遇到 Codex 0.156.0 “进程存在但 socket 未就绪”的用户，在独立终端执行以下命令以刷新已复制的管理脚本并确认状态，无需先手动 `kill`：

```bash
envpilot codex remote enable
envpilot codex remote status
# 需要明确重建服务时：
envpilot codex remote restart
```

0.4.1 会识别 Codex 创建的 socket 符号链接和真实监听进程。`app-server-control` 目录仍应保留在持久存储中；其中的 socket 文件可以是 Codex 管理的符号链接。

## 迁移与恢复

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
