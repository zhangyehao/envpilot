# 搬到新服务器

在原机器导出个人偏好。第一个文件包含 envpilot 的组件选择、策略组显示顺序和更新策略。第二个文件只包含 Codex 配置顶层已设置的 `model` 和 `model_reasoning_effort`。使用命名 profile 时，请在新机单独配置对应 profile。

```bash
envpilot config export --portable > envpilot-preferences.yaml
envpilot config export --codex-preferences > codex-preferences.toml
scp envpilot-preferences.yaml codex-preferences.toml new-host:
```

首次安装 envpilot 后，在新机的 SSH 会话中运行以下命令。若已有主配置，请用 `envpilot config edit` 将偏好文件里的字段合并到现有段落。

```bash
mkdir -p "$HOME/.config/envpilot"
if [ ! -e "$HOME/.config/envpilot/config.yaml" ]; then
  install -m 600 "$HOME/envpilot-preferences.yaml" "$HOME/.config/envpilot/config.yaml"
fi
envpilot config migrate --preview
envpilot config migrate --yes
envpilot preflight
envpilot config edit
envpilot config validate
envpilot doctor
```

在新机的 `~/.codex/config.toml` 顶层合并 TOML 片段中的字段。已有同名字段时修改其值，避免重复定义。安装目录、Codex home、运行包目录、代理端口、供应商、密钥和订阅引用按新机填写。Unix 下将拥有者专用的秘密文件权限设为 600。

预检报告本次会话解析到的 Codex 路径、系统架构与 Linux glibc、Home 所在文件系统、可写可执行的临时目录、调度器命令，并通过本机配置的 Mihomo 代理向所选发布站点发送 HTTPS HEAD 请求。指定 `--json` 可供脚本读取。要验证桌面实际启动环境，使用相同 SSH 用户、节点和启动方式执行 `envpilot preflight`，再执行 `envpilot codex remote verify`。

共享 Home 时，在 `updates.maintenance_host` 填负责更新持久安装的节点名。在该节点执行 `envpilot updates enable` 和 `envpilot doctor`，在每个需要访问的登录节点分别验证节点本地运行副本。一次预检只能观察当前节点。
