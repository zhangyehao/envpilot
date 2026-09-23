# Codex

## 服务管理（0.4.0）

```bash
envpilot codex remote enable
envpilot codex remote status
envpilot codex remote restart
envpilot codex remote stop
envpilot codex remote enable
```

所有命令识别同一用户、当前节点和目标控制 socket 的实例，包括 Desktop/SSH 创建的服务。停止不再依赖 PID 文件必须存在；每次发信号前核对进程身份。其他 CODEX_HOME 和无法确认归属的进程保持不变。

`restart` 必须确认新进程、实际运行文件和协议握手；`ready` 可复用健康且版本匹配的实例；`repair` 强制重建运行文件。`stop` 后再次 `enable` 会使用当前版本启动。更新前服务运行时，`update codex` 会刷新运行文件并重启；此前停止则保持停止。

请在独立终端操作。重启可能中断当前请求，持久配置、认证和 sessions 保留。控制目录不迁往临时存储；可重建的运行文件位于按用户、节点和 CODEX_HOME 区分的版本化缓存中。

0.4.1 修复了 Codex 0.156.0 的 socket 识别：`app-server-control.sock` 可以是指向 `/tmp/codex-daemon-UID/...` 的符号链接，监听检查与进程归属检查均使用其实际目标。0.4.0 用户如遇到“进程存在但 socket 未就绪”，按[升级命令](UPGRADE.zh-CN.md)更新后执行 `envpilot codex remote enable`，无需先手动杀进程。旧日志中的 `unrecognized configuration settings` 是 Codex 对过时配置项的警告，不代表服务未启动；envpilot 不会自动删除用户配置。

0.154.0 的原生命令为 `codex app-server daemon start/stop/restart/version`。原生启动依赖固定的 standalone 路径，因此 envpilot 会同时检查能力与安装布局；不能由原生命令启动目标缓存时，使用已校验的本地文件直接启动。

0.4.2 进一步处理 Desktop/SSH 自动重连：如果旧服务退出后，Desktop 抢先拉起新服务，envpilot 会重新识别 socket 归属，并核对用户、CODEX_HOME、运行文件和协议版本，确认新 PID 后才报告重启成功。支持 `Codex Desktop/0.156.0` 等名称带空格的版本标识；未知归属或其他配置目录的进程保持不变。若停止过程中服务被持续重新拉起，`stop` 会返回失败并提示服务尚未完全停止。

## 安装和更新

~~~bash
envpilot install codex
envpilot update codex
~~~

官方 standalone 是 Linux/macOS 的默认安装方式。它不依赖 Node.js/npm，envpilot 通过官方的 `CODEX_NON_INTERACTIVE=1` 模式调用安装器，因此不会出现 `Start Codex now?`，不会在安装流程中启动 Codex 登录界面，也不会提示卸载另一种安装。

普通 `install codex` 会复用已有安装，保留已有配置和认证。`codex --version` 仍用于验证真实运行状态，但不再是判断安装产物是否存在的唯一依据：共享文件系统上超过 5 秒会被归类为“已安装、探测超时”，不会触发 Node.js/npm 回退。需要重新解析稳定版本时使用 `update codex`。

更新会保持原安装方法：已有 standalone 使用官方 standalone 更新器；只有 npm 安装时继续使用 npm。两者同时存在时，envpilot 优先 standalone、保留 npm 副本并提示 PATH 顺序，不会自动在两种方式之间卸载和重装。

缺少 Codex 时，在线模式先使用官方独立安装器。只有首次官方安装明确失败、且用户再次确认后，才尝试需要 Node.js 的旧 npm 路径；默认不回退。离线模式不会偷偷访问 npm。

## API key 和配置

Codex 配置使用：

~~~toml
env_key = "OPENAI_API_KEY"
~~~

正确的 shell 变量是 OPENAI_API_KEY，不是 env_key。密钥查找顺序：

1. 当前 shell 的 OPENAI_API_KEY；
2. 权限为 600/400 且属于当前用户的 ~/.config/secrets/api.env；
3. 交互提示用户输入。

已有 ~/.codex/auth.json 时，envpilot 保留原文件，不删除、不覆盖、不强制重新输入。只有新用户尚无该文件时，才会从当前环境或 api.env 导入并在确认后创建。

相关文件：

~~~text
~/.codex/config.toml
~/.codex/auth.json
~/.config/secrets/api.env
~~~

api.env 可包含其他软件所需的环境变量。显式开启 shell.load_secrets 后，Shell 会在权限检查通过后静默导出其中的赋值；Codex wrapper 也会独立加载它。不要把真实文件提交到 Git。

## 老 glibc 和 Node.js

HPC 常见 glibc 2.17 主机不能运行官方 Node.js 22/24 Linux x64 预编译包，但官方 standalone Codex 是 musl 构建，不需要为它安装 Node.js 或升级 glibc。只有保留已有 npm 安装或用户明确选择 npm fallback 时，envpilot 才会为 Linux amd64 老 glibc 选择 Node.js 22 x64-glibc-217 用户态构建，默认路径：

~~~text
$HOME/software/node22
~~~

不要替换系统 glibc，也不要把无法执行的官方 Node.js 24 强行放到 PATH 前面。安装失败时保留 GLIBC_* not found 等原始诊断。

`codex --version` 返回 137 若发生在 envpilot 的等待上限之后，会统一归类为探测超时；立即返回的 137 仍作为真实运行失败报告。

## 共享文件系统上的 Remote Runtime

如果共享文件系统上的 codex --version 很慢，启用节点本地 runtime：

~~~bash
envpilot codex remote status
envpilot codex remote enable
envpilot codex remote ready
envpilot codex remote repair
envpilot codex remote stop
envpilot codex remote disable
~~~

日常切换节点后执行：

~~~bash
envpilot codex remote ready
~~~

持久目录保持在 ~/.codex，包括 config、auth、sessions 和 app-server control；只把可重建的二进制及必要 helper 放入按用户、节点和 CODEX_HOME 区分的 /tmp 版本目录。不要把 ~/.codex/app-server-control 软链接到 /tmp。

wrapper 和 remote manager 会在启动 CLI/app-server 前加载受保护的 api.env。当前进程显式设置的同名变量优先于文件内容。可用 ENVPILOT_CODEX_LOAD_SECRETS=0 关闭 Codex 进程级注入。

`remote enable/ready` 使用持久启动锁，只复用健康且版本匹配的目标服务。stop/restart 可以管理已核实的 Desktop/SSH 实例，不再只依赖 envpilot PID 文件；未知归属时保留现场并给出诊断。不同节点共享 CODEX_HOME 时，不能擅自清理另一节点的控制记录。

失败时按提示提供以下只读信息即可诊断：

~~~bash
envpilot codex remote status
ps -o pid,ppid,stat,etime,args -u "$USER" | grep -E '[c]odex|[a]pp-server'
socket="${CODEX_HOME:-$HOME/.codex}/app-server-control/app-server-control.sock"
ls -l "$socket"
target="$(readlink -f "$socket")"
grep -F -- "$target" /proc/net/unix 2>/dev/null || ss -xlpn | grep -F -- "$target"
tail -100 "$HOME/.codex/app-server-control/app-server.log"
~~~

Linux 上 Codex 官方推荐安装 `bubblewrap`。如果 PATH 中没有 `bwrap`，Codex 会提示并尝试内置 helper；这条警告本身不等于 socket 冲突。HPC 无管理员权限时不要自行替换系统组件，可把缺少 `bwrap` 和 user namespace 限制交给集群管理员确认。
