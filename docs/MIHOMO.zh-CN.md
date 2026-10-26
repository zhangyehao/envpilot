# Mihomo

[English](MIHOMO.md)

Mihomo 提供本地 HTTP/SOCKS 代理。envpilot 管理安装、订阅、端口和节点选择；不需要自己拼接控制接口、安装 Python 或 jq。

## 日常使用：更新、选节点、检查

已经配置订阅后，通常只需要：

```bash
envpilot mihomo update-subscription
envpilot mihomo start
envpilot mihomo select
envpilot mihomo status
```

`select` 无参数时列出可手动选择的策略组和组内选项，按提示输入编号。代理原来已运行时，订阅更新成功会重启并恢复选择；原来停止时保持停止，再执行 `start`。只有切换节点时不需要更新订阅或重启。

| 命令 | 用途 |
| --- | --- |
| `envpilot mihomo nodes` | 查看策略组、当前选择和可选节点。 |
| `envpilot mihomo nodes "策略组"` | 只查看指定组。 |
| `envpilot mihomo select` | 交互选择策略组和节点。 |
| `envpilot mihomo select "策略组" "节点名"` | 按完整名称直接切换，适合脚本。 |
| `envpilot mihomo test "策略组"` | 测试组内直接列出的代理节点，跳过嵌套组及 DIRECT/REJECT。 |
| `envpilot mihomo test "策略组" "节点名"` | 测试一个候选项，不改变当前选择。 |
| `envpilot mihomo restart` | 重启当前节点上的受管服务并恢复可用的选择。 |

组名和节点名使用 `nodes` 输出的完整名称，包含空格时加引号。非交互运行 `select` 必须提供组和节点，不会等待输入。测试结果表示本次探测的可达性，不保证所有网站都能访问，也不会自动替你选择最快节点。

`test "策略组" "节点名"` 可以明确指定该组中的一个成员，包括嵌套策略组、`DIRECT` 或 `REJECT`。例如 `envpilot mihomo test "手动选择" "自动选择"`；请将两个名称替换为 `nodes` 显示的实际名称。只传组名时不会递归测试嵌套组。

`nodes`、`select`、`test` 支持 `--json`；JSON 模式不会弹出选择菜单。脚本可以使用：

```bash
envpilot mihomo nodes --json
envpilot mihomo select "策略组" "节点名" --non-interactive --json
```

PowerShell 使用相同的子命令和位置参数，选项可写为 `-Json`、`-NonInteractive`。订阅操作的选项对应 `-Network` 和 `-SubscriptionFile`，也兼容 `--network`、`--file`：

```powershell
envpilot mihomo nodes -Json
envpilot mihomo select "策略组" "节点名" -NonInteractive -Json
envpilot mihomo update-subscription -Network direct
envpilot mihomo update-subscription -SubscriptionFile "$HOME/subscription.yaml"
```

“自动选择”和“故障转移”通常是策略组，不是两条独立线路。手动选择组可以选择一个实际节点，也可以把选择交给这样的自动策略组。如果组内只有一个实际节点，换成“自动选择”不会产生新的线路；需要订阅本身提供更多节点。

选择记录按当前节点保存在 `~/.config/envpilot/mihomo-selections/`，独立于 `/tmp` 运行目录。`stop → start`、`restart` 和更新订阅后，会恢复仍存在的组与节点。订阅删除或改名后会提示无法恢复的选项，保留订阅默认行为，不猜测替代节点；运行 `nodes` 和 `select` 重新选择即可。共享 HOME 的不同计算节点分别记录选择。

控制命令会核实 API 监听进程属于当前用户的受管 Mihomo。端口被其他实例占用或无法确认归属时，不发送控制请求；`nodes` 可回退显示持久配置，`select` 会给出诊断。共享服务器上的 localhost 端口并非每个用户独有。

## 文件和运行目录

持久文件位于用户目录：

~~~text
~/software/mihomo/mihomo
~/.config/mihomo/config.yaml
~/.config/mihomo/subscription.url
~/.config/mihomo/country.mmdb
~/.config/mihomo/geoip.metadb
~/.config/envpilot/mihomo-selections/
~~~

运行时会把二进制、配置和 geodata 复制到当前节点的：

~~~text
/tmp/${USER}_mihomo_${HOSTNAME}/
~~~

这样可以减少 NFS、Lustre、GPFS、BeeGFS 等共享文件系统上的执行和元数据问题。节点切换或 `/tmp` 被清理后，执行 `envpilot mihomo start` 即可重建运行目录。

## 安装和更新

~~~bash
envpilot install mihomo
envpilot update mihomo
envpilot install mihomo --mode offline
envpilot install mihomo --asset-path downloads/mihomo-linux-amd64-compatible-v1.19.31.gz
~~~

安装源的优先级为：当前 OS/架构匹配的 downloads 缓存、最新 stable GitHub Release。alpha、beta、rc 和其他 prerelease 不会被选择。

安装前如果发现用户自己的 Mihomo，envpilot 会列出进程、版本和端口；确认接管后发送 SIGTERM，等待退出，必要时再 SIGKILL。配置、运行状态和接管过程写入：

~~~text
~/.config/envpilot/mihomo-takeover-report.json
~~~

envpilot 管理的实例在升级前运行，升级后会恢复运行并保留现有订阅配置。外部 Mihomo 没有新订阅时，旧配置会备份为 config.yaml.disabled.TIMESTAMP，避免旧代理渠道继续生效。

## 双端口配置

新安装且没有显式或持久端口时，envpilot 从 proxy `42290` 和 API `60290` 分别开始探测。优先执行 `nc -z -w 1 127.0.0.1 PORT`；端口被占用就加 1，直到找到两个不同的空闲端口或到达 65535。缺少 `nc` 时依次使用 `ss`、有界 `/dev/tcp` 或有界 `lsof`。选定结果写入 `~/.config/envpilot/shell.local`。

已有非默认环境变量、`shell.local` 或 `config.yaml` 中的有效端口属于显式/持久选择，不会在更新时自动漂移。若要固定使用恰好为默认值的端口，请用 `envpilot mihomo ports 42290 60290` 持久写入，而不要只依赖 profile 自动导出的默认值。所有安装、启动、状态和订阅操作统一读取两个端口：

~~~bash
export MIHOMO_PROXY_HOST=127.0.0.1
export MIHOMO_PROXY_PORT=42290
export MIHOMO_API_PORT=60290
~~~

规则：

- MIHOMO_PROXY_PORT 是 HTTP/SOCKS5 mixed port。
- MIHOMO_API_PORT 是 external controller API。
- 两个端口必须不同，非 root 用户通常应使用大于 1024 的端口。
- 写入配置、启动和切换端口前都会检查端口格式和占用情况。

持久修改两个端口并自动完成配置、停止、检查和重启：

~~~bash
envpilot mihomo ports 42290 60290
~~~

兼容旧命令，只修改代理端口并保留 API 端口：

~~~bash
envpilot mihomo port 42291
~~~

envpilot 只修改本地顶层监听项 `mixed-port`、`external-controller`、`allow-lan` 和 `bind-address`，不会改订阅节点的远端 `server`、`port`、`uuid`、`public-key` 或 `short-id`。因此 `MIHOMO_PROXY_PORT` 和 `MIHOMO_API_PORT` 不是机场节点端口。

## 进程命令

~~~bash
envpilot mihomo start
envpilot mihomo stop
envpilot mihomo restart
envpilot mihomo status
~~~

`envpilot mihomo stop` 只停止当前用户、当前节点、envpilot 运行目录中的实例。它不会清除调用终端里的 `http_proxy`、`https_proxy` 等变量；父 Shell 的环境需要用 `envpilot_proxy_off` 修改。

`envpilot mihomo status` 检查：

- envpilot 管理的进程和启动参数；
- proxy/API 两个端口是否真实监听；
- API /version 健康状态；
- 通过代理访问外网时的出口；
- 当前节点运行目录中的最近日志。

## 订阅更新

先在兼容服务商处取得**完整 Clash/Mihomo YAML 配置**的订阅地址。HTML 登录页、单个节点链接或 base64 节点列表不能当作完整配置导入。真实 URL 不要写入 Git、README、Issue 或聊天记录。

推荐把链接放进受保护文件，后续无参数复用：

~~~bash
install -d -m 700 "$HOME/.config/mihomo"
(umask 077; touch "$HOME/.config/mihomo/subscription.url")
chmod 600 "$HOME/.config/mihomo/subscription.url"
${EDITOR:-vi} "$HOME/.config/mihomo/subscription.url"
envpilot mihomo update-subscription
~~~

文件只写一行真实 URL。主配置 `~/.config/envpilot/config.yaml` 的已有 `mihomo` 段保持引用：

~~~yaml
mihomo:
  subscription_network: auto
  subscription:
    file: ~/.config/mihomo/subscription.url
~~~

也可使用 `subscription.env` 引用环境变量，同时清空 `file`；详见[配置说明](CONFIG.zh-CN.md)。旧的 `envpilot mihomo update-subscription 'URL'` 参数方式保留兼容，但真实 URL 可能进入终端历史，建议使用文件引用。

保存的订阅文件权限为 600，状态和诊断只报告路径，不显示链接。自动读取前检查当前用户属主及 600/400 权限；链接替换时保留受保护备份。旧版只有 `config.yaml` 时，通常无法从中可靠还原原始完整订阅地址，需要先补充订阅文件。

更新先下载和校验临时配置，再备份旧配置、保留本地端口并替换。下载或校验失败时，旧配置和运行中的服务保持可用。重启失败时恢复旧配置。成功后恢复仍有效的节点选择；订阅更新可能中断已有代理连接。

### 下载失败时选择网络路径

默认 `mihomo.subscription_network: auto` 先直连，失败后尝试环境代理或可用的本机受管代理。它避免把更新订阅完全依赖于当前已经失效的代理节点。可以只对本次命令覆盖：

```bash
envpilot mihomo update-subscription --network direct
envpilot mihomo update-subscription --network proxy
```

| 方式 | 行为 |
| --- | --- |
| `auto` | 先直连，失败后尝试可用的代理路径。 |
| `direct` | 忽略当前 Shell 的代理变量，只使用直连。 |
| `proxy` | 使用代理路径；代理端口未监听时给出明确错误。 |

错误区分 DNS 解析、连接超时或拒绝、TLS、HTTP 状态和配置格式，不打印订阅凭据。可重试的连接错误和 HTTP 429/5xx 使用有界重试。停止代理后，Shell 中旧代理变量仍可能存在；使用 `--network direct` 无需先修改这些变量。程序无法修复集群出口限制或不可用的供应商服务器。

程序遵守服务端的 `Retry-After`；等待时间超过本次下载剩余时限时，提示稍后重试，不缩短等待或立即换代理绕过。认证失败、订阅地址失效和持续限流需要先处理对应的上游问题。

### 服务器无法下载：导入本地文件

在能访问订阅的电脑或浏览器里下载完整 Clash/Mihomo YAML，上传到服务器后：

```bash
chmod 600 "$HOME/subscription.yaml"
envpilot mihomo update-subscription --file "$HOME/subscription.yaml"
envpilot mihomo start
envpilot mihomo select
```

`--file` 要求来源为普通文件；Unix 下必须属于当前用户且权限为 `600` 或 `400`，上面的 `chmod 600` 不能省略。Windows 使用用户 ACL 保护文件。配置本身包含代理凭据，不要上传到公开仓库。

`--file` 不访问订阅地址，保留已有订阅 URL 引用，按同样的校验、备份和恢复流程应用配置；不要同时传入 URL 和 `--file`。导入配置不代表代理节点本身可达；仍需用 `test` 和 `status` 检查。

### 完整配置与 provider 刷新

`envpilot update mihomo` 更新程序，`envpilot mihomo update-subscription` 更新完整订阅配置。定时组件更新不隐含订阅更新频率。如果配置使用 `proxy-providers` 并设置 `interval: 3600`，Mihomo 会自行按该间隔刷新 provider；这与重新下载整个 `config.yaml` 是两种机制。

## 代理开关

~~~bash
envpilot_proxy_on
envpilot_proxy_off
~~~

执行 `envpilot apply-shell` 并重新加载 Shell 后，`envpilot_proxy_on` 先检查代理端口；未监听时不设置代理变量。默认只设置 HTTP/HTTPS：

~~~text
http_proxy / HTTP_PROXY
https_proxy / HTTPS_PROXY
~~~

需要 SOCKS 时，在统一配置的已有 `mihomo` 段设置并重新应用 Shell 接入：

~~~yaml
mihomo:
  socks: true
~~~

envpilot 保留已有 `no_proxy`/`NO_PROXY`，追加本机地址。`envpilot_proxy_off` 清理代理地址，保留 `no_proxy`。

新安装默认不自动启动或导出代理，按需设置 `shell.auto_start_proxy` 和 `shell.auto_enable_proxy`。多个 SSH 窗口共享同一用户、同一节点的一个 Mihomo 进程，但代理环境变量属于各自的 Shell。旧快捷名需显式启用 `shell.legacy_aliases`；文档统一使用 `envpilot ...`。

## 缓存和自动更新

仓库受控缓存包括：

~~~text
downloads/mihomo-linux-amd64-compatible-*.gz
downloads/mihomo-windows-amd64-compatible-*.zip
downloads/country.mmdb
downloads/geoip.metadb
~~~

可手动刷新：

~~~bash
envpilot update-mihomo-cache
~~~

仓库的 update-mihomo-cache.yml 定时检查 stable 版本和 geodata，并通过 PR 更新缓存。普通用户安装时始终优先使用本地匹配架构的缓存。
