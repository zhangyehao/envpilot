# Git 和 Python

## 版本策略

envpilot 不会因为命令存在就盲目覆盖系统软件：

- Git 最低版本为 2.30；系统 Git 达标时直接复用。
- Python 最低版本为 3.9；优先复用系统 Python 3.9+ 或已有 Conda Python。
- 不满足最低版本时，在用户目录安装兼容版本，保留系统文件和系统解释器。
- Linux/macOS 根据 OS、架构、libc 和 glibc 选择 stable 资产，不为追求最新版破坏老系统兼容性。

## 命令

先在负责夜间任务的节点和账号执行 `envpilot preflight git` 和 `envpilot preflight python`。前者实际编译、链接并运行小程序；后者检查包支持的平台以及安装文件系统的执行与符号链接能力。两者都支持 `--json`。

在 Linux 的 Git 2.56 构建中，缺少可用的 `getrandom` 时可使用 OpenSSL。可选的 Rust 功能无需安装 Cargo。为旧集群指定开发库、编译器或并行数时，在主配置中合并：

```yaml
git:
  dependency_prefix: ~/anaconda3
  toolchain_bin: ""   # 需要时填编译器和 make 所在目录
  build_jobs: 2       # 按节点分配的 CPU 调整
```

普通主机可保留默认值。手动和定时构建 Git 都会读取这些设置。无需在生成的定时启动脚本里追加参数。

独立 Python 下载时使用与具体版本、平台和归档名称匹配的上游 SHA-256。离线包需要清单中的校验值，或在归档旁放可信来源的 `SHA256SUMS` 或 `<归档名>.sha256`。下载、摘要和新解释器通过验证后才切换现有入口。

~~~bash
envpilot doctor
envpilot install git
envpilot update git
envpilot install python
envpilot update python
~~~

Git 的用户态安装位置：

~~~text
$HOME/software/git/current/bin/git
~~~

Python standalone 的用户态安装位置：

~~~text
$HOME/software/python/current/bin/python3
~~~

Linux/macOS 更新时先在独立版本目录解压。归档内的 `bin/python3` 可以是指向版本化解释器的符号链接。envpilot 核实入口和目标均在包内，再用隔离模式运行解释器，核对精确版本并导入标准库。验证通过后才切换 `python/current`。验证失败时仍可使用旧解释器。

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
