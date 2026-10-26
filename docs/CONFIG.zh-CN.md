# 统一配置

[English](CONFIG.md)

运行 `envpilot init --lang zh-CN` 创建主配置，再用 `envpilot config edit` 编辑。已有配置不会被覆盖。`config validate` 检查语法和取值；`config show` 输出有效配置和来源。来源未列出的字段使用默认值。

默认文件为 `~/.config/envpilot/config.yaml`；`ENVPILOT_CONFIG_DIR` 修改配置目录，`--config PATH` 选择本次使用的配置文件。

优先级：显式参数 → 声明的环境变量 → YAML → 默认值。支持 `ENVPILOT_LANG`、`ENVPILOT_MODE`、`ENVPILOT_PREFIX`、`ENVPILOT_RELEASE_SOURCE`、`ENVPILOT_CONDA_DISTRIBUTION`、`CODEX_HOME`、`ENVPILOT_CODEX_RUNTIME_DIR`、`ENVPILOT_CODEX_REMOTE_READY_TIMEOUT`、`MIHOMO_PROXY_PORT`、`MIHOMO_API_PORT` 和 `ENVPILOT_SUBSCRIPTION_NETWORK`。

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
| `mihomo.group_order` | 策略组显示顺序，字符串列表（名称不得空白或重复），默认 `[]`。例如 `["烟火云"]` 将该组优先显示；其余组按名称排序，不存在的组名忽略。 |
| `mihomo.subscription.file/env` | 订阅文件或环境变量引用，二选一。 |
| `mihomo.subscription_network` | 订阅下载路径：`auto`（默认，先直连、失败后尝试代理）、`direct` 或 `proxy`；命令行 `--network` 可覆盖。 |
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

## 完整样例、更新与命令优先级

[完整中文样例](../examples/config.example.zh-CN.yaml) 与 [英文样例](../examples/config.example.en.yaml) 包含全部字段及参数说明；请合并所需字段，不要覆盖已有用户配置。

新增 `shell.prefer_managed: [git, python]` 可让已安装的受管 Git/Python 在普通 Shell 中优先。默认 `[]` 保留原优先级。执行 `envpilot apply-shell` 并打开新 Shell，使用 `command -v git`、`command -v python3` 检查。用户函数/alias 保留；已激活的 Conda/venv Python 不被覆盖。

`updates` 字段：`enabled: true`、`interval_days: 3`（1–365）、`auto_apply: false`、`components: [mihomo, git, python, conda, mamba, codex, github, tmux]`、`envpilot: true`、`window_start: "03:00"`、`window_end: "05:00"`、`timezone: Local`。北京时间使用 `Asia/Shanghai`。详见 [更新与历史](UPDATES.zh-CN.md)。

### 实际密钥与订阅写在哪里

```bash
install -d -m 700 "$HOME/.config/secrets" "$HOME/.config/mihomo"
(umask 077; touch "$HOME/.config/secrets/api.env" "$HOME/.config/mihomo/subscription.url")
chmod 600 "$HOME/.config/secrets/api.env" "$HOME/.config/mihomo/subscription.url"
${EDITOR:-vi} "$HOME/.config/secrets/api.env"
${EDITOR:-vi} "$HOME/.config/mihomo/subscription.url"
```

`api.env` 内写 `OPENAI_API_KEY='你的真实密钥'`；`subscription.url` 内只写一行真实订阅 URL。配置保留 `secrets.file` 和 `mihomo.subscription.file` 的路径，`codex.api_key.env` 填 `OPENAI_API_KEY`。不需要 `shell.load_secrets: true` 才能给 Codex 使用受保护文件。

另一种密钥方案：`codex.api_key.file: ~/.config/secrets/codex.key`，文件仅一行密钥；同时设置 `codex.api_key.env: ""`。订阅也可配置 `mihomo.subscription.env: MIHOMO_SUBSCRIPTION_URL`，同时清空 `file`。定时任务不继承交互终端临时导出的变量，建议使用文件引用。`secrets` 仅支持赋值文件 `file`；不执行命令。Windows 同样使用这些路径和引用，通过用户 ACL 保护文件。

`mihomo.subscription_network` 只控制订阅下载，不改变整个 Shell 或所有软件的联网方式；环境覆盖为 `ENVPILOT_SUBSCRIPTION_NETWORK`，命令覆盖为 `--network`（PowerShell：`-Network`）。停止 Mihomo 不会清除当前 Shell 的旧代理变量；`--network direct` 会忽略这些变量。离线导入使用 `envpilot mihomo update-subscription --file PATH`（PowerShell：`-SubscriptionFile PATH`），无需配置新 URL。导入文件在 Unix 下须属于当前用户且权限为 600/400，先执行 `chmod 600 PATH`。

节点选择用 `envpilot mihomo select`，实际选择按服务器保存在配置目录的 `mihomo-selections/` 下。新配置中已删除或改名的节点会提示重新选择。

### 常用策略组优先显示

从 0.4.7 起，可以将下面字段合并到主配置已有的 `mihomo` 段，让“烟火云”排在 `nodes` 的组列表和 `select` 的策略组菜单前面：

```yaml
mihomo:
  group_order: ["烟火云"]
```

`group_order` 是按优先顺序排列的完整组名列表，默认 `[]`。每个名称必须非空、不能重复，大小写和空格须与实际组名一致。实际存在且可显示的组先按列表顺序排列，其余组按名称排序；订阅里暂不存在的名称会被忽略，之后出现时才采用这个顺序。`select` 仍只提供可手动选择的组。保存 YAML 后下次命令生效，无需 `apply` 或重启 Mihomo。

它只调整组的显示顺序，不改变组内节点顺序、已保存的节点选择、订阅配置或代理路由。详见 [Mihomo](MIHOMO.zh-CN.md)。
