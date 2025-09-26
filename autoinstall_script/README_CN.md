
[English](README.md) | 中文
## 1. 项目介绍

IvorySQL-AutoInstall 是一个专业的自动化安装脚本，旨在简化 IvorySQL 数据库的编译安装过程。通过简单的配置文件设置，用户可以一键完成从源码编译到服务启动的全过程，无需手动执行复杂的编译命令和配置步骤。

### 1.1 核心功能
- **环境检测与验证**：自动检测操作系统类型和版本，验证系统兼容性。
- **智能依赖管理**：自动安装编译所需依赖包，支持多平台包管理器。
- **自动化安装配置**：自动设置安装目录、数据目录和日志目录的权限。
- **服务集成**：自动创建 systemd 服务（或在无 systemd 时创建辅助脚本）并配置环境变量。
- **全面日志记录**：详细记录安装过程，便于故障排查。
- **错误处理与回滚**：完善的错误检测与处理机制。

### 1.2 支持的操作系统
| 家族 | 发行版/ID | 脚本中的版本门槛 | 说明 |
|---|---|---|---|
| RHEL 系 | rhel / centos / almalinux / rocky / oracle | 明确 **屏蔽 7**；涵盖 8/9/10 的分支 | Oracle Linux 有专项处理 |
| Debian/Ubuntu | debian / ubuntu | 版本会被校验；不支持的版本 **快速失败** | 依赖安装使用 `apt` |
| SUSE 系 | opensuse-leap / sles | openSUSE Leap **15**；SLES **12.5 / 15** | 使用 `zypper` |
| Arch | arch | 滚动发布 | 使用 `pacman` |

> **注意**：本项目不支持 CentOS 7。

---

## 2. 项目细节

### 2.1 配置文件详解（`ivorysql.conf`）
| 配置项 | 是否必需 | 默认值 | 说明 |
|---|---|---|---|
| INSTALL_DIR | 是 | 无 | IvorySQL 安装目录（必须为绝对路径） |
| DATA_DIR | 是 | 无 | 数据目录（必须为绝对路径） |
| LOG_DIR | 是 | 无 | 日志目录（必须为绝对路径） |
| SERVICE_USER | 是 | 无 | 服务用户（不可为保留系统账户） |
| SERVICE_GROUP | 是 | 无 | 服务用户组（不可为保留系统组） |

**注意**
- 所有路径必须为绝对路径，且不得包含空格。
- 用户/组名称不得为系统保留名称（如 `root`、`bin`、`daemon`）。

**示例**
```ini
INSTALL_DIR=/usr/ivorysql
DATA_DIR=/var/lib/ivorysql/data
LOG_DIR=/var/log/ivorysql
SERVICE_USER=ivorysql
SERVICE_GROUP=ivorysql
```

### 2.2 依赖管理系统

#### 核心依赖（必装，自动执行）
- 工具链：GCC、Make、Flex、Bison
- 核心库：readline、zlib、openssl
- Perl 环境：perl-core、perl-devel、perl-IPC-Run

#### 可选依赖（智能检测，缺失则禁用对应特性）
| 依赖库 | 检测路径 | 自动处理 |
|---|---|---|
| ICU | `/usr/include/icu.h` 或 `/usr/include/unicode/utypes.h` | 未检测到则添加 `--without-icu` |
| libxml2 | `/usr/include/libxml2/libxml/parser.h` | 未检测到则添加 `--without-libxml` |
| Tcl | `/usr/include/tcl.h` | 未检测到则添加 `--without-tcl` |
| Perl 开发 | 头文件存在 | 未检测到则添加 `--without-perl` |

#### 各发行版安装命令
| 系统 | 命令 |
|---|---|
| CentOS/RHEL/Rocky/AlmaLinux/Oracle | `dnf group install "Development Tools"` <br> `dnf install readline-devel zlib-devel openssl-devel` |
| Debian/Ubuntu | `apt-get install build-essential libreadline-dev zlib1g-dev libssl-dev` |
| SUSE/SLES | `zypper install gcc make flex bison readline-devel zlib-devel libopenssl-devel` |
| Arch Linux | `pacman -S base-devel readline zlib openssl` |

**工具链自检**
```bash
for cmd in gcc make flex bison; do
  command -v "$cmd" >/dev/null || echo "警告: 未安装 $cmd"
done
```

### 2.3 编译流程
#### 配置命令
```bash
./configure --prefix="$INSTALL_DIR" --with-openssl --with-readline             --without-icu \        # 未检测到 ICU 时
            --without-libxml \     # 未检测到 libxml2 时
            --without-tcl \        # 未检测到 Tcl 时
            --without-perl         # 未检测到 Perl 开发环境时
```

#### 并行编译
```bash
make -j"$(nproc)"
make install
```

#### 安装后处理
- 确保 `$DATA_DIR` 存在，设置 `chmod 700`，并修正属主。
- 可在服务用户的 PATH 中加入 `$INSTALL_DIR/bin`。

### 2.4 服务管理系统

#### **systemd 路径**
脚本生成的单元
```ini
[Unit]
Description=IvorySQL Database Server
Documentation=https://www.ivorysql.org
Requires=network.target local-fs.target
After=network.target local-fs.target

[Service]
Type=forking
User=ivorysql
Group=ivorysql
Environment=PGDATA=/var/lib/ivorysql/data
Environment=LD_LIBRARY_PATH=/usr/ivorysql/lib:/usr/ivorysql/lib/postgresql
PIDFile=/var/lib/ivorysql/data/postmaster.pid
OOMScoreAdjust=-1000
ExecStart=/usr/ivorysql/bin/pg_ctl start -D ${PGDATA} -s -w -t 90
ExecStop=/usr/ivorysql/bin/pg_ctl stop -D ${PGDATA} -s -m fast
ExecReload=/usr/ivorysql/bin/pg_ctl reload -D ${PGDATA}
TimeoutSec=120
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
```

**说明**
- 生成的单元包含 `PIDFile`。
- `ExecStart` 使用 `-t 90`，`TimeoutSec` 为 **120**，与脚本一致。
- 配置了 `OOMScoreAdjust=-1000` 与 `Type=forking`。

#### **非 systemd 路径**
- 辅助脚本：`"$INSTALL_DIR/ivorysql-ctl"`（由脚本生成）
  - `start` → `pg_ctl start -D "$DATA_DIR" -s -w -t 90`
  - `stop`  → `pg_ctl stop  -D "$DATA_DIR" -s -m fast`
  - `reload`→ `pg_ctl reload -D "$DATA_DIR"`
- **提示**：脚本还存在内部回退的 `svc_start` 路径，在不使用辅助脚本时采用 `-t 60`；辅助脚本默认 **90 秒**。

### 2.5 日志系统
```
/var/log/ivorysql/
├── install_YYYYmmdd_HHMMSS.log  # 安装器标准输出
├── error_YYYYmmdd_HHMMSS.log    # 安装器标准错误
├── initdb_YYYYmmdd_HHMMSS.log   # 初始化日志
└── postgresql.log               # 运行期日志
```

- 目录属主：`ivorysql:ivorysql`
- 安装日志带时间戳与步骤标记
- 运行期使用 PostgreSQL 内置日志

**运行期日志（PostgreSQL 服务器）**：
- 在基于 systemd 的发行版上，PostgreSQL **默认写入 journald**。查看命令：
  ```bash
  journalctl -u ivorysql -f
  ```
- 若需要写入文件，请在 `postgresql.conf` 启用：
  ```conf
  logging_collector = on
  log_directory    = 'log'
  log_filename     = 'postgresql-%Y-%m-%d_%H%M%S.log'
  ```
  然后在 `$DATA_DIR/log/` 查看（如需要，可将该路径软链接到 `LOG_DIR`）。

---

## 3. 使用指南

### 3.1 准备工作
0. **放置路径（重要）**：
   - 本脚本**必须位于 IvorySQL 源码仓库中**，推荐路径：
     ```
     <repo-root>/IvorySQL-AutoInstaller/
     ```
   - 本脚本**直接使用本地源码树进行编译**，**不负责拉取源码**。
1. **使用 root 权限**：
   ```bash
   su -
   # 或
   sudo -i
   ```
2. **进入目录添加执行权限**：
   ```bash
   cd IvorySQL/IvorySQL-AutoInstaller
   ```
   **添加执行权限**：
   ```bash
   chmod +x AutoInstall.sh
   ```

### 3.2 配置修改（可选）
1. **编辑配置文件**：
   ```bash
   nano ivorysql.conf
   ```
2. **配置参考**（路径须为绝对路径；`LOG_DIR` 必填）：
   ```ini
   INSTALL_DIR=/usr/ivorysql
   DATA_DIR=/var/lib/ivorysql/data
   SERVICE_USER=ivorysql
   SERVICE_GROUP=ivorysql
   LOG_DIR=/var/log/ivorysql
   ```

### 3.3 开始安装
```bash
sudo bash AutoInstall.sh
```


### 3.4 安装验证（脚本实际输出格式）
```
================ Installation succeeded ================

Install directory: /usr/ivorysql
Data directory: /var/lib/ivorysql/data
Log directory: /var/log/ivorysql
Service: active
Version: /usr/ivorysql/bin/postgres --version output

Useful commands:
  systemctl [start|stop|status] ivorysql
  journalctl -u ivorysql -f
  sudo -u ivorysql '/usr/ivorysql/bin/psql'

Install time: <date>
Elapsed: <seconds>s
Build: local-source   Commit: N/A
OS: <os_type> <os_version>
```

### 3.5 服务管理命令
| 功能 | 命令 | 说明 |
|---|---|---|
| 启动 | `systemctl start ivorysql` | 启动数据库服务 |
| 停止 | `systemctl stop ivorysql`  | 停止数据库服务 |
| 状态 | `systemctl status ivorysql`| 查看服务状态   |
| 日志 | `journalctl -u ivorysql -f`| 跟踪服务日志   |
| 重载 | `systemctl reload ivorysql`| 重载配置       |
| 连接 | `sudo -u ivorysql /usr/ivorysql/bin/psql` | 连接数据库 |
| 版本 | `/usr/ivorysql/bin/postgres --version` | 查看版本 |
| 基础备份 | `sudo -u ivorysql /usr/ivorysql/bin/pg_basebackup` | 创建基础备份 |

---

## 4. 故障排查

### 4.1 常见错误处理
| 错误现象 | 可能原因 | 解决方案 |
|---|---|---|
| 配置文件缺失 | 路径错误 | 检查项目目录下是否存在 `ivorysql.conf` |
| 依赖安装失败 | 网络或镜像问题 | 检查网络并尝试切换镜像 |
| 构建错误 | 环境不受支持 | 检查系统版本并查看错误日志 |
| initdb 失败 | 属主或权限问题 | `chown ivorysql:ivorysql /var/lib/ivorysql/data` |
| 服务失败 | 端口冲突或配置错误 | `ss -tulnp | grep 5432` |

### 4.2 诊断命令
```bash
systemctl status ivorysql -l --no-pager
journalctl -u ivorysql --since "1 hour ago" --no-pager
sudo -u ivorysql /usr/ivorysql/bin/postgres -D /var/lib/ivorysql/data -c logging_collector=on
ls -l IvorySQL-AutoInstaller/ivorysql.conf
cat IvorySQL-AutoInstaller/ivorysql.conf
```

### 4.3 日志位置
- 安装日志：`/var/log/ivorysql/install_<timestamp>.log`
- 错误日志：`/var/log/ivorysql/error_<timestamp>.log`
- 初始化日志：`/var/log/ivorysql/initdb_<timestamp>.log`
- 数据库日志：`$DATA_DIR/log/postgresql-*.log`（如启用 logging_collector；可将该目录软链接到 LOG_DIR）

### 4.4 特殊处理
#### Rocky Linux 10 / Oracle Linux 10
- 自动启用 CRB/Devel 仓库以获取开发头文件（如 `libxml2-devel`）。
- 需要时采用 `--allowerasing` 的回退策略。
- 状态检查：
  ```bash
  grep "XML_SUPPORT" /var/log/ivorysql/install_*.log
  ```

#### Perl 环境
- 自动检查 `FindBin`、`IPC::Run`；缺失时通过包管理器或 CPAN 安装。
```bash
dnf install -y perl-IPC-Run
PERL_MM_USE_DEFAULT=1 cpan -i IPC::Run FindBin
perl -MFindBin -e 1
perl -MIPC::Run -e 1
```