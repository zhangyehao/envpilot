# Shell 接入

[English](SHELL-CONFIG.md)

0.4.0 使用短加载块，不替换原 profile：

```bash
envpilot apply-shell
# 移除接入：
envpilot shell remove
```

受管块以 `# >>> envpilot >>>` 和 `# <<< envpilot <<<` 标记。块外内容保持原样；重复执行不会追加第二份。独立脚本和生成配置位于 `~/.config/envpilot/shell/`，Shell 启动时不下载或解析 YAML。

新用户默认只接入 envpilot 命令。通过主 YAML 显式开启 Conda、代理、module、历史或旧快捷别名。内部函数使用 envpilot 命名空间；旧 `proxy_on`、`proxy_off`、`mihomo`、`codex_ready` 名称只有开启兼容选项且没有同名命令时才提供。

`envpilot_proxy_on` 在端口就绪后为当前 Shell 导出代理，`envpilot_proxy_off` 清除当前 Shell 的代理。普通子进程无法修改父 Shell 的环境；需要独立环境时使用 `envpilot run -- COMMAND ...`。

保留现有的 `shell.local`，仅在选择 `shell.legacy_local` 的交互式 Shell 中加载。常规环境变量可放入 YAML 的 `env`，路径放入 `shell.paths`。API key 使用受保护引用。非交互 shell 不初始化 Conda、module 或交互历史，代理准备保持静默且有界。

旧 profile 与历史模板精确匹配时可以自动迁移。含有自定义修改的旧 profile 保持可用，并在配置目录生成 `migration-pending.txt`；需对照备份完成一次人工核对，程序不会猜测复杂函数的含义。旧模板中的 `BASHRC_PROFILE_ACTIVE`、`ENVPILOT_LAST_*` 只用于兼容，不是新配置选项。

更新或移动仓库后使用 `envpilot self-update` 或从新位置重新 `setup-command`，再应用配置。快照与恢复见 [升级说明](UPGRADE.zh-CN.md)。
