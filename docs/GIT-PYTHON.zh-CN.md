# Git 和 Python

## 版本策略

envpilot 不会因为命令存在就盲目覆盖系统软件：

- Git 最低版本为 2.30；系统 Git 达标时直接复用。
- Python 最低版本为 3.9；优先复用系统 Python 3.9+ 或已有 Conda Python。
- 不满足最低版本时，在用户目录安装兼容版本，保留系统文件和系统解释器。
- Linux/macOS 根据 OS、架构、libc 和 glibc 选择 stable 资产，不为追求最新版破坏老系统兼容性。

## 命令

~~~bash
bash envpilot.sh doctor
bash envpilot.sh install git
bash envpilot.sh update git
bash envpilot.sh install python
bash envpilot.sh update python
~~~

Git 的用户态安装位置：

~~~text
$HOME/software/git/current/bin/git
~~~

Python standalone 的用户态安装位置：

~~~text
$HOME/software/python/current/bin/python3
~~~

旧 glibc 主机如果已有 Conda Python 3.9+，envpilot 优先使用 Conda，不再创建第二个解释器。缺少编译器、开发库或可用资产时，安装会停止并给出原因，不会记录虚假的完成状态。

## 非交互 shell

受管 Bash/zsh 模板会在真实 TTY 判断之前加入用户态 Git/Python 路径，因此 SSH 命令、scp/rsync、批处理和 Codex 子进程可以找到已安装版本。这里的 PATH 设置必须保持安静；不要在非交互 profile 中执行模块加载、输出提示或耗时探测。

## 验证

~~~bash
command -v git
git --version
command -v python3
python3 --version
~~~

安装报告和 doctor 输出会记录实际选择的路径、版本、架构和 libc 判断。
