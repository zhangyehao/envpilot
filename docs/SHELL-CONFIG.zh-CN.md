# Shell 配置和环境变量

## BASHRC_PROFILE_ACTIVE 是什么

BASHRC_PROFILE_ACTIVE 是 envpilot profile 的内部标记，不是用户需要设置的开关。每次受管 profile 加载时，envpilot_record_managed_settings 会将它设为 1，并记录 envpilot 上一次写入的 Mihomo 端口、代理模式、非交互预启动和临时目录值。

下一次 apply-shell 或 source 时，模板用这些记录判断当前环境中的值是否仍是 envpilot 自己设置的：

- 如果值和上次记录相同，视为 envpilot 管理值，可以用 shell.local 的新配置覆盖；
- 如果用户在外部 profile、SSH 启动器或当前环境中改过值，视为外部值，模板会保留它，不强行覆盖。

这样做是为了让 profile 更新不会覆盖用户刚刚设置的端口或临时目录。一般不需要手工设置或删除 BASHRC_PROFILE_ACTIVE。

## ~/.bashrc、shell.local、api.env

三者职责不同：

| 文件 | 作用 |
| --- | --- |
| ~/.bashrc / ~/.zshrc | envpilot 受管入口、函数、路径和静默启动逻辑。由 apply-shell 生成。 |
| ~/.config/envpilot/shell.local | 用户覆盖项和安全的 PATH/module 配置。交互 shell 完整加载；非交互 shell 只读取白名单设置。 |
| ~/.config/secrets/api.env | 需要被多个软件和子进程继承的环境变量，包括 API key。权限必须是 600/400，且属于当前用户。 |

`apply-shell` 不会因为 `shell.local` 或 `api.env` 已存在就跳过迁移。它会保留目标文件中的已有内容和同名变量，再从原 profile 增量补充缺失项：

- 普通的单行 `export NAME=value` 和简单 `module load NAME` 进入 `shell.local`；
- 名称含 `KEY`、`TOKEN`、`SECRET`、`PASSWORD`、`PASSWD` 或 `AUTH` 的变量进入 `api.env`；
- 代理、Mihomo 和 envpilot 内部变量不从旧 profile 迁移；
- 命令替换、管道、重定向、复合语句、函数、循环和条件均不迁移，也不会被执行；
- 如果当前 profile 已由 envpilot 管理，只检查最近的非 envpilot 备份，避免把模板自身迁移进 `shell.local`。

因此 `api.env` 不是 Mihomo 或 Codex 专属文件，它是多个应用共享的受保护变量入口。迁移日志只报告数量和路径，不显示值。

api.env 只应包含安静的变量赋值，例如：

~~~bash
export OPENAI_API_KEY="..."
export NCBI_API_KEY="..."
~~~

不要在 api.env 中写 module load、conda activate、网络请求、输出或交互逻辑。

## 默认开关

受管 Bash/zsh 默认把以下六个开关设为 1：

~~~bash
BASHRC_INIT_CONDA=1
BASHRC_AUTO_LOAD_MODULES=1
BASHRC_AUTO_START_MIHOMO=1
BASHRC_AUTO_ENABLE_PROXY=1
BASHRC_AUTO_LOAD_SECRETS=1
BASHRC_ENABLE_HISTORY_SYNC=1
~~~

在 `~/.config/envpilot/shell.local` 将任一项设为 0 即可关闭。开关会在对应功能执行前读取，所以关闭 history、module、Mihomo、代理或 secrets 都能在本次 profile 加载中生效。

默认开启不等于无条件执行：Conda 只初始化交互式真实 TTY 且不自动激活 base；没有 `modules.list` 时不探测 module；缺少 Mihomo 启动脚本或有效配置时不启动；代理端口未监听时不导出代理。

## 静默 shell 的内容

非交互 shell 在真实 TTY 守卫之前只做最小准备：

1. 加载权限安全的 api.env 全部变量；
2. 加入用户态 Git/Python/Node 路径；
3. 根据白名单读取 Mihomo 端口和节点临时目录；
4. 必要时安静地启动 Mihomo，并在端口真实监听后导出 HTTP/HTTPS 代理；
5. 不加载 Conda conda.sh、历史同步、module、交互提示或大段函数执行。

因此 ssh host command、Codex Desktop 的无返回 SSH 启动器可以继承 API key 和代理，但不会触发完整交互初始化。完全不读取 .bashrc 的 supervisor 或启动器仍需要显式使用 bash -lc 或受信任的 BASH_ENV。

## 为什么函数目前仍在 .bashrc

proxy_on、mihomo、conda 初始化和非交互预启动之间存在顺序依赖；同时某些 SSH、Codex 和 scp 路径只读取一个 profile 文件。把函数全部移到另一个脚本理论上可行，例如：

~~~bash
source "$HOME/.config/envpilot/shell.functions"
~~~

但会带来三个实际问题：

- 非交互 shell 仍需要先安全加载该文件，否则代理和 API key 继承顺序会变化；
- 外部 profile、BASH_ENV、zsh 和 Bash 的加载规则不一致；
- apply-shell 还要管理函数文件的版本、备份和路径发现。

因此当前设计把小型、无输出的函数保留在模板中，把用户变量放到 shell.local/api.env。如果以后要拆分，应先建立独立函数文件的版本化接口和非交互测试，再迁移，不应只把函数剪切出去。
