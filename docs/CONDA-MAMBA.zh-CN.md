# Conda 和 Mamba

## 安装命令

~~~bash
bash envpilot.sh install conda
bash envpilot.sh install conda --conda-distribution anaconda
bash envpilot.sh update conda
bash envpilot.sh install mamba
bash envpilot.sh update mamba
~~~

默认选择官方 Miniconda，不使用 Miniforge。Linux 会根据架构、libc 和 glibc 版本选择仍可运行的官方安装器；CentOS 7 等 glibc 2.17 主机使用官方归档的 Miniconda 24.11.1，而不是要求 glibc 2.28 的最新版安装器。

Windows 原生入口安装 Conda，但 mamba 目前应在已初始化的 WSL、Git Bash 或其他 Unix-like Conda 环境中执行；PowerShell 入口会明确提示这一点。

## .condarc 管理

envpilot 的唯一受控模板是仓库内：

~~~text
templates/condarc
~~~

安装或更新 Conda 时，envpilot 会：

1. 备份已有 ~/.condarc；
2. 写入模板内容；
3. 将 CONDARC 指向 ~/.condarc 执行 Conda 命令；
4. 清除会污染求解的 LD_LIBRARY_PATH、PYTHONHOME、PYTHONPATH 和外部 channel/solver 环境变量。

当前模板只保留：

~~~yaml
channels:
  - https://mirrors.tuna.tsinghua.edu.cn/anaconda/cloud/conda-forge
  - https://mirrors.tuna.tsinghua.edu.cn/anaconda/cloud/bioconda
default_channels: []
channel_priority: strict
auto_activate_base: false
~~~

doctor 会报告 ~/.condarc 是否存在以及是否与模板一致。配置不一致时，执行 install conda 或 update conda 会再次备份并统一配置。`install mamba` 和 `update mamba` 不会重写或备份现有 `~/.condarc`。

检查实际来源：

~~~bash
conda config --show-sources
conda config --show channels default_channels channel_priority auto_activate_base
~~~

如果希望保留自定义频道，Mamba 安装不会覆盖现有配置；但执行 Conda install/update 时，envpilot 仍会按模板恢复受管频道。需要长期使用自定义频道时，应先确认这是否属于项目的统一策略。

## Mamba 的 solver 和配置行为

Mamba 安装会把镜像和 solver 作为本次 Conda 事务的命令行参数传入，不依赖重写 `~/.condarc`：

- bootstrap 只使用清华 conda-forge 镜像；bioconda 不提供 Mamba，因此不参与这次索引和求解；
- 如果 Conda base 中检测到 `conda_libmamba_solver` 插件，使用 `--solver libmamba`；
- 如果插件不存在，使用 `--solver classic`，避免旧配置中的 `solver: libmamba` 在不支持时直接失败；
- 现有 `~/.condarc`、包括用户写入的 `solver: libmamba` 和其他设置，都会原样保留；
- `conda config --set solver libmamba` 可以由用户在确认插件可用后持久设置，envpilot 后续不会在安装 Mamba 时抹掉它。

因此，envpilot 会在支持时尽可能使用 libmamba，但不会为了安装 Mamba 覆盖用户的 Conda 配置。

## 旧 Miniconda 的处理

Miniconda 23.5.x 自带的旧 libmamba 在强制 conda-forge 事务中可能反复输出：

~~~text
Selected channel specific (or force-reinstall) job,
but package is not available from channel.
~~~

它也可能退出 139。单纯把 `~/.condarc` 改成 conda-forge/bioconda 并不能解决，因为 Miniconda 安装器已经用官方 base 包完成了 bootstrap。

当 `install mamba` 发现标准 Miniconda prefix 的 Conda 版本低于 24.11.1 时，会先显示升级计划并询问确认。确认后使用官方、架构和 glibc 兼容的 Miniconda 安装器执行原地更新：

- base 更新到可可靠使用新 libmamba 的版本；
- `envs/` 中已有环境不移动、不删除；
- `~/.condarc` 不被 Mamba 流程重写；
- 更新完成后只用清华 conda-forge 安装 Mamba。

实际执行的 Mamba 事务等价于：

~~~bash
conda install -n base -y \
  --override-channels \
  -c https://mirrors.tuna.tsinghua.edu.cn/anaconda/cloud/conda-forge \
  --solver libmamba \
  mamba
~~~

在 glibc 2.17 节点上的临时全新 Miniconda 24.11.1 验证中，该事务在一分钟内完成并安装 Mamba 2.8.1；具体时间仍取决于节点和网络。

## 为什么不在安装器里直接迁移频道

envpilot 会在 Miniconda 安装完成后立即写入受管 `~/.condarc`，因此后续用户环境默认使用清华 conda-forge/bioconda。但是 Miniconda 安装器自己的 base 仍来自官方 bootstrap 包。强行把整个 base 迁移到另一套底层库既慢又容易产生 ABI 混用，因此这里采用“更新到兼容 Miniconda + 单一 conda-forge Mamba 事务”，不手工拼装底层包。

当前实现会：

- 用 --override-channels 只指定清华 conda-forge，避免继承 defaults、bioconda 或登录环境的 channel 设置；
- 如果 base 中已有 conda-libmamba-solver，使用 libmamba；
- 否则显式使用 classic solver，并提示首次求解可能较慢。

日志中出现：

~~~text
Collecting package metadata ... done
Solving environment: ...
~~~

通常说明镜像已经完成 metadata 下载，慢点在依赖求解，而不是网络下载。可以先等待；如果长时间没有变化，按 Ctrl-C 中断，不会删除现有 Conda。

验证镜像连通性和包可见性：

~~~bash
conda search --override-channels \
  -c https://mirrors.tuna.tsinghua.edu.cn/anaconda/cloud/conda-forge mamba
~~~

## 双安装策略

如果 Anaconda 和 Miniconda 同时存在，envpilot 的交互式 profile 默认优先 Miniconda，同时发现标准 Anaconda 环境目录：

~~~text
$HOME/software/miniconda3/envs
$HOME/miniconda3/envs
$HOME/software/anaconda3/envs
$HOME/anaconda3/envs
$HOME/.conda/envs
~~~

因此可以：

~~~bash
command -v conda
conda info --base
conda env list
conda activate tools
~~~

如果只有 Anaconda，默认 install conda 仍会按需并存安装 Miniconda，不会因为检测到了任意 conda 就错误跳过。只有同发行版已存在时才会跳过。

非标准 Miniconda 路径可以在 ~/.config/envpilot/shell.local 设置绝对路径：

~~~bash
BASHRC_CONDA_PRIMARY_PREFIX="/work/home/your-user/miniconda3"
~~~

## Shell 初始化和 base

~~~bash
bash envpilot.sh apply-shell
source ~/.bashrc
~~~

envpilot 不向 .bashrc 追加 Conda 自己的 conda init 大代码块，而是在受管模板中只对交互式真实 TTY 加载已选中的 conda.sh。templates/condarc 的 auto_activate_base: false 使新终端可以使用 conda 和 conda activate，但不会自动进入 base。

如需关闭交互式 Conda shell 集成：

~~~bash
printf '%s\n' 'BASHRC_INIT_CONDA=0' >> ~/.config/envpilot/shell.local
source ~/.bashrc
~~~
