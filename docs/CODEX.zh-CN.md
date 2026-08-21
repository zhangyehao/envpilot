# Codex

## 安装和更新

~~~bash
bash envpilot.sh install codex
bash envpilot.sh update codex
~~~

普通 install codex 会先真正执行现有 codex --version：如果已有可执行 Codex，只更新配置和认证，不重新安装 Codex，也不会额外安装 Node.js/npm。需要重新解析稳定版本时使用 update codex。

缺少 Codex 时，在线模式优先使用官方独立安装器，失败后才回退 npm；离线模式不会偷偷访问 npm。

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

api.env 可包含其他软件所需的环境变量。受管交互和非交互 shell 会在权限检查通过后静默导出其中全部赋值；Codex wrapper 也会独立加载它。不要把真实文件提交到 Git。

## 老 glibc 和 Node.js

HPC 常见 glibc 2.17 主机不能运行官方 Node.js 22/24 Linux x64 预编译包。npm 回退时，envpilot 会为 Linux amd64 老 glibc 选择 Node.js 22 x64-glibc-217 用户态构建，默认路径：

~~~text
$HOME/software/node22
~~~

不要替换系统 glibc，也不要把无法执行的官方 Node.js 24 强行放到 PATH 前面。安装失败时保留 GLIBC_* not found 等原始诊断。

## 共享文件系统上的 Remote Runtime

如果共享文件系统上的 codex --version 很慢，启用节点本地 runtime：

~~~bash
bash envpilot.sh codex remote status
bash envpilot.sh codex remote enable
bash envpilot.sh codex remote ready
bash envpilot.sh codex remote repair
bash envpilot.sh codex remote stop
bash envpilot.sh codex remote disable
~~~

日常切换节点后执行：

~~~bash
codex_ready
~~~

持久目录保持在 ~/.codex，包括 config、auth、sessions 和 app-server control；只把可重建的完整 bin/ runtime 暂存到 /tmp/\${USER}-envpilot-codex-\${HOSTNAME}。不要把 ~/.codex/app-server-control 软链接到 /tmp。

wrapper 和 remote manager 会在启动 CLI/app-server 前加载受保护的 api.env。当前进程显式设置的同名变量优先于文件内容。可用 ENVPILOT_CODEX_LOAD_SECRETS=0 关闭 Codex 进程级注入。
