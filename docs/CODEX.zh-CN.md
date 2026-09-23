# Codex

## 完整运行包（0.4.3）

0.4.0–0.4.2 的复制逻辑错误地把包根目录的顶层文件筛选后放进 `bin/`，遗漏了 `bin/codex-code-mode-host`、`codex-path/` 和 `codex-resources/`。0.3.0 整体复制选中的 `bin/`，保留同层辅助程序，但也没有保证复制包根目录的兄弟资源。启动成功和协议握手通过不代表全部组件齐全。

0.4.3 根据 `codex-package.json` 识别完整包，保留目录结构、可执行权限和包内符号链接。包内全部文件（包括新增资源）参与指纹计算；只有完整复制、内容校验和版本探测成功后才切换运行目录。资源单独更新、缓存文件丢失或损坏都会触发新一代缓存；安装来源不完整时保留原运行版本。npm vendor 使用独立的平台目录；普通 PATH 目录仍不会被整体复制。

```bash
envpilot codex remote enable
envpilot codex remote verify    # 只读：比较来源与缓存的全部文件、路径、权限和链接
envpilot codex remote repair    # 强制重建并重启
```

每代缓存中的 `.runtime-manifest.json` 记录布局，`.source.signature` 记录完整内容指纹。自定义 `config.toml`、模型目录 JSON、认证和会话保留在持久 `CODEX_HOME`，不放进可清理的运行包。

主程序采用 musl 不意味着所有附带程序都没有 glibc 要求。例如官方 0.156.0 包中的 zsh 需要较新的 glibc。完整性校验说明文件复制正确；辅助程序能否执行还取决于主机兼容性。不要为此替换系统 glibc。

## 模型发现与刷新

默认不设置 `model_catalog_json`。模型发现应交给 Codex 和所选供应商；下载缓存或 Codex 内置目录是网络发现的回退，不应为了补齐下拉列表而手工伪造模型能力数据。

内置目录编译在 Codex 可执行文件中，不能单独在线刷新；升级 Codex 才会更新这份目录。执行 `envpilot update codex`，再用 `codex --version` 检查版本。目标服务此前运行时，envpilot 会切换完整运行包并重启 app-server。删除缓存或仅重启旧版本不会改变其内置目录。例如 0.156.1 的官方更新新增了 GPT-6 Sol/Luna，无需设置本地目录覆盖。

Codex 0.156.0 的 API-key 模型发现受 `features.api_key_model_discovery` 开关控制（该版本默认关闭），自定义供应商还需要支持 Codex 原生模型目录并配置 `model_providers.<id>.model_catalog_url`。普通 OpenAI 兼容 `/v1/models` 通常只返回 ID，不能直接代替包含上下文长度、推理选项等信息的 Codex 原生目录。是否能从上游更新，需要核对所选供应商、认证方式、接口格式及缓存状态，不能仅以模型数量判断。

## 可选：固定的自定义模型目录

以下配置只用于用户明确选择本地固定目录的情况；它会切换到静态目录，不能作为自动上游刷新的解决方案。envpilot 默认不创建、不启用此引用。

把模型 JSON 文件放到 `~/.codex` 并不会自动启用它。在 `~/.codex/config.toml` 的**顶层、所有 `[section]` 之前**加入实际绝对路径：

```toml
model_catalog_json = "/实际用户目录/.codex/models.json"
```

修改后执行 `envpilot codex remote restart`。该配置在 app-server 启动时加载；目录中的 `visibility: "hide"` 条目默认仍隐藏，`model/list` 的 `includeHidden: true` 才会返回它们。文件内容是否包含某模型、服务是否加载该文件、客户端是否显示隐藏模型，是三个不同检查点。模型出现在目录中也不代表上游供应商一定允许调用。

配置依据：[Codex 配置参考](https://developers.openai.com/codex/config-reference/)；列表接口依据：[app-server 文档](https://developers.openai.com/codex/app-server/)。

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
