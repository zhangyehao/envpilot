# Mihomo

本文说明 envpilot 管理的 Mihomo 安装、端口、进程、订阅、缓存和代理行为。适用于 Linux、macOS、WSL 和 Git Bash 等 Unix-like 环境。

## 文件和运行目录

持久文件位于用户目录：

~~~text
~/software/mihomo/mihomo
~/.config/mihomo/config.yaml
~/.config/mihomo/country.mmdb
~/.config/mihomo/geoip.metadb
~~~

运行时会把二进制、配置和 geodata 复制到当前节点的：

~~~text
/tmp/\${USER}_mihomo_\${HOSTNAME}/
~~~

这样可以减少 NFS、Lustre、GPFS、BeeGFS 等共享文件系统上的执行和元数据问题。节点切换或 /tmp 被清理后，重新执行 mihomo start 即可重建运行目录。

## 安装和更新

~~~bash
bash envpilot.sh install mihomo
bash envpilot.sh update mihomo
bash envpilot.sh install mihomo --mode offline
bash envpilot.sh install mihomo --asset-path downloads/mihomo-linux-amd64-compatible-v1.19.29.gz
~~~

安装源的优先级为：当前 OS/架构匹配的 downloads 缓存、最新 stable GitHub Release。alpha、beta、rc 和其他 prerelease 不会被选择。

安装前如果发现用户自己的 Mihomo，envpilot 会列出进程、版本和端口；确认接管后发送 SIGTERM，等待退出，必要时再 SIGKILL。配置、运行状态和接管过程写入：

~~~text
~/.config/envpilot/mihomo-takeover-report.json
~~~

envpilot 管理的实例在升级前运行，升级后会恢复运行并保留现有订阅配置。外部 Mihomo 没有新订阅时，旧配置会备份为 config.yaml.disabled.TIMESTAMP，避免旧代理渠道继续生效。

## 双端口配置

所有安装、启动、状态和订阅操作统一读取两个端口：

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
mihomo ports 42290 60290
~~~

兼容旧命令，只修改代理端口并保留 API 端口：

~~~bash
mihomo port 42291
~~~

未执行 apply-shell 时，可以直接从仓库执行：

~~~bash
bash envpilot.sh mihomo ports 42290 60290
~~~

envpilot 只修改本地监听项，不会改订阅节点的远端 server、port、uuid、public-key 或 short-id。

## 进程命令

~~~bash
mihomo start
mihomo stop
mihomo status
mihomo run [mihomo 参数]
~~~

mihomo stop 只停止当前用户、当前节点、envpilot 运行目录中的实例，不会停止其他用户或其他路径的进程。

mihomo status 检查：

- envpilot 管理的进程和启动参数；
- proxy/API 两个端口是否真实监听；
- API /version 健康状态；
- 通过代理访问外网时的出口；
- 当前节点运行目录中的最近日志。

## 订阅更新

先在兼容服务商处取得 Clash/Mihomo 订阅 URL。真实 URL 不要写入 Git、README、Issue 或聊天记录。

交互输入新链接：

~~~bash
mihomo update-subscription
~~~

直接传入：

~~~bash
mihomo update-subscription 'https://example.invalid/clash-meta'
bash envpilot.sh mihomo update-subscription 'https://example.invalid/clash-meta'
~~~

更新过程会下载临时文件、拒绝空文件和 HTML 错误页、备份旧配置、修正两个本地端口；运行中的实例会停止并重启。新配置启动失败时会恢复旧配置。

## 代理开关

~~~bash
proxy_on
proxy_off
proxy_status
~~~

proxy_on 先检查 MIHOMO_PROXY_HOST:MIHOMO_PROXY_PORT 是否监听；未监听时返回错误且不会留下失效代理变量。默认只设置 HTTP/HTTPS：

~~~text
http_proxy / HTTP_PROXY
https_proxy / HTTPS_PROXY
~~~

需要 SOCKS 时，在 ~/.config/envpilot/shell.local 设置：

~~~bash
BASHRC_PROXY_ENABLE_SOCKS=1
~~~

envpilot 只向已有 no_proxy/NO_PROXY 追加 localhost、127.0.0.1 和 ::1，不会覆盖集群内部域名或网段。proxy_off 只清理代理地址，保留 no_proxy。

非交互 SSH/Codex shell 会静默尝试启动配置完整且尚未监听的 Mihomo；启动失败时不输出错误，也不设置错误代理变量。多个 SSH 窗口共享同一用户、同一节点的一个 Mihomo 进程，但代理环境变量仍然只属于当前 shell。

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
bash envpilot.sh update-mihomo-cache
~~~

仓库的 update-mihomo-cache.yml 定时检查 stable 版本和 geodata，并通过 PR 更新缓存。普通用户安装时始终优先使用本地匹配架构的缓存。
