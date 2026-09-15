# 统一配置

[English](CONFIG.md)

运行 `envpilot init --lang zh-CN` 创建主配置，再用 `envpilot config edit` 编辑。已有配置不会被覆盖。`config validate` 检查语法和取值；`config show` 输出有效配置和来源。来源未列出的字段使用默认值。

默认文件为 `~/.config/envpilot/config.yaml`；`ENVPILOT_CONFIG_DIR` 修改配置目录，`--config PATH` 选择本次使用的配置文件。

优先级：显式参数 → 声明的环境变量 → YAML → 默认值。支持 `ENVPILOT_LANG`、`ENVPILOT_MODE`、`ENVPILOT_PREFIX`、`ENVPILOT_RELEASE_SOURCE`、`ENVPILOT_CONDA_DISTRIBUTION`、`CODEX_HOME`、`ENVPILOT_CODEX_RUNTIME_DIR`、`ENVPILOT_CODEX_REMOTE_READY_TIMEOUT`、`MIHOMO_PROXY_PORT` 和 `MIHOMO_API_PORT`。

| 配置 | 含义与默认值 |
| --- | --- |
| `version` | 配置格式版本，当前为 `1`。 |
| `language` | `auto`、`en` 或 `zh-CN`。 |
| `install.components` | 要安装的组件列表，默认空。 |
| `install.mode` | `online` 或 `offline`。 |
| `install.prefix` | 用户态安装位置，默认 `~/software`。 |
| `install.release_source` | envpilot 发布来源，`github` 或 `gitee`。 |
| `shell.enabled` | 是否安装 Shell 接入，默认 true。 |
| `shell.conda` | 是否初始化 Conda，默认 false，不自动进入 base。 |
| `shell.modules` | 交互式 Shell 要加载的 module 列表。 |
| `shell.auto_start_proxy` | 自动准备已配置的 Mihomo，默认 false。 |
| `shell.auto_enable_proxy` | 端口监听后导出代理变量，默认 false。 |
| `shell.load_secrets` | 将受保护文件加载到 Shell，默认 false。 |
| `shell.history_sync` | Bash 历史同步，默认 false。 |
| `shell.legacy_aliases` | 提供没有同名命令时的旧快捷别名，默认 false。 |
| `shell.legacy_local` | 交互时加载原 `shell.local`，迁移时按原状态保留。 |
| `shell.paths` | 追加的路径列表，不覆盖现有命令优先级。 |
| `mihomo.proxy_port/api_port` | 默认 42290/60290，须不同且在 1–65535 范围内。 |
| `mihomo.socks` | 是否导出 SOCKS 代理，默认 false。 |
| `mihomo.subscription.file/env` | 订阅文件或环境变量引用，二选一。 |
| `conda.distribution` | `miniconda` 或 `anaconda`。 |
| `conda.prefix` | 可选的现有 Conda 位置。 |
| `codex.remote` | 是否应用 Codex 节点本地运行设置，默认 false。 |
| `codex.home` | 默认 `~/.codex`。 |
| `codex.runtime` | 可选节点本地缓存位置。 |
| `codex.ready_timeout` | 就绪等待秒数，默认 60，范围 1–600。 |
| `codex.base_url` | 新建 Codex 配置时使用的 API 地址；现有配置保留。 |
| `codex.api_key.file/env` | API key 的文件或环境变量引用。 |
| `secrets.file` | 赋值格式的受保护环境文件，默认 `~/.config/secrets/api.env`。 |
| `env` | 常规环境变量映射；密钥类字段须改用受保护引用。 |

配置采用严格 YAML：未知字段、重复字段、多个文档和无效端口会报错。配置不会作为 Shell 脚本执行。Shell 配置在 `apply` 时生成，修改 YAML 后需再次应用并重新加载 profile。

Linux/macOS 的密钥文件必须属于当前用户且权限为 600 或 400。API key 和订阅内容不会出现在配置预览中；不要把凭据嵌入普通 URL 或 `env` 字段。Windows 使用文件 ACL 控制访问。

```bash
envpilot plan
envpilot apply --yes --non-interactive
envpilot run -- python3 --version
```

非交互模式不会等待输入。未选择的备用安装方式不会自动启用。第三方安装器的原始输出保留原文。
