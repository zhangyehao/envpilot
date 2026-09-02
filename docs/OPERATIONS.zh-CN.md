# 生命周期、恢复和升级

## 主命令

~~~bash
bash envpilot.sh doctor
bash envpilot.sh install [all|git|python|mihomo|conda|mamba|codex|github|tmux]
bash envpilot.sh update [all|git|python|mihomo|conda|mamba|codex|github|tmux]
bash envpilot.sh apply-shell
bash envpilot.sh restore
bash envpilot.sh rollback
bash envpilot.sh resume
bash envpilot.sh reset
bash envpilot.sh update-manifests
bash envpilot.sh update-mihomo-cache
bash envpilot.sh self-test
~~~

常用参数：

~~~bash
bash envpilot.sh install --mode online
bash envpilot.sh install --mode offline
bash envpilot.sh install mihomo --asset-path downloads/mihomo-linux-amd64-compatible-v1.19.29.gz
bash envpilot.sh install conda --conda-distribution anaconda
bash envpilot.sh install --prefix "$HOME/software"
bash envpilot.sh install --yes
~~~

Windows 使用对应的 envpilot.ps1：

~~~powershell
.\envpilot.ps1 doctor
.\envpilot.ps1 install all
.\envpilot.ps1 update all
.\envpilot.ps1 apply-shell
.\envpilot.ps1 restore
.\envpilot.ps1 rollback
.\envpilot.ps1 self-test
~~~

## 推荐顺序

共享服务器上建议：

~~~bash
bash envpilot.sh doctor
bash envpilot.sh install mihomo
bash envpilot.sh apply-shell
source ~/.bashrc
mihomo start
mihomo status
proxy_on
bash envpilot.sh install
~~~

如果 Mihomo 已经存在并正在运行，install mihomo 会先列出接管计划；确认后才停止旧进程、检查端口和记录报告。安装失败时不需要手动逐项卸载，先运行 doctor 建立基线，再用 restore 恢复整组受管状态。

## doctor、restore、rollback 的区别

doctor 只检查环境，同时记录最近一次 baseline：

~~~text
~/.config/envpilot/baseline/baseline.tsv
~/.config/envpilot/baseline/files/
~~~

restore 恢复最近一次 doctor baseline，会处理受管 Mihomo、profile、.condarc、shell.local、配置和用户态安装目录。想保留最初状态时，不要在安装中途再次执行 doctor，因为新 baseline 会覆盖旧记录。

rollback 只恢复最近一次 envpilot 单文件备份，例如 .bashrc、.condarc 或配置文件；它不是完整环境恢复。

resume 使用状态文件继续未完成的 install all；reset 清除状态，使步骤可以重新执行。reset 不会删除软件或配置。

## 已有 envpilot 环境的升级

~~~bash
cd ~/envpilot
git pull --ff-only
bash envpilot.sh doctor
bash envpilot.sh apply-shell
source ~/.bashrc
bash envpilot.sh update
~~~

如果仓库不在 ~/envpilot，envpilot 会把实际路径写入 ~/.config/envpilot/repo-root，新 profile 会使用该记录。update 会绕过旧状态文件，重新判断当前平台兼容版本；不需要先 reset。

## 配置文件边界

仓库内的模板和代码：

~~~text
templates/bashrc
templates/zshrc
templates/condarc
templates/api.env.example
templates/shell.local.example
~~~

用户目录中的运行配置：

~~~text
~/.bashrc / ~/.zshrc
~/.config/envpilot/shell.local
~/.config/secrets/api.env
~/.condarc
~/.config/mihomo/
~/.codex/
~~~

apply-shell 会备份并替换 profile，并在不执行旧 profile 的前提下增量迁移可安全识别的配置。普通 export、按顺序累积的 PATH/库路径、简单 alias 和 module 设置进入 shell.local；API key、token、secret、password、auth 等受保护变量进入 api.env；目标文件已有同名标量不会被覆盖。命令结束前会要求立即对照旧 profile 和 shell.local，补回仍需要的交互式 PATH、alias、函数、工具变量、提示符或初始化逻辑。静默 shell 不会完整加载 shell.local。api.env 供多个软件共用，不是 Mihomo 专属；.condarc 由模板统一管理。真实订阅 URL、API key、auth.json、日志和运行目录不进入仓库。
