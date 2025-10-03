
[English](README.md) | 中文
## 1. 这是做什么的

一个**全英文、ASCII 输出**的无人值守安装器，用于**从源码构建 IvorySQL**并注册为服务，分阶段打印清晰日志。

- 脚本要求放在源码树 **子目录** `autoinstall_script/`：
  ```text
  IvorySQL/                # 源码根目录
  ├─ configure
  ├─ src/
  └─ autoinstall_script/
     ├─ AutoInstall.sh
     └─ ivorysql.conf
  ```
- 脚本将其**上一级目录**视为源码根目录（用于找到 `configure` 与 `src/`）。

运行方式：
```bash
cd autoinstall_script
sudo bash ./AutoInstall.sh
```

---

## 2. 支持的操作系统

- **EL 家族**：RHEL / Rocky / Alma / Oracle Linux **8 / 9 / 10**
- **CentOS Stream**：**9 / 10**
- **Ubuntu**：**20.04 / 22.04 / 24.04**
- **Debian**：**12（Bookworm）/ 13（Trixie）**

脚本自动读取 `/etc/os-release` 识别系统，并选择 `dnf|yum` 或 `apt-get`。在 EL/OL 上会**尽力启用** **CRB / PowerTools / CodeReady Builder** 与 **EPEL**。

> **需要 root**：必须以 root 身份（或 sudo）执行。

---

## 3. 配置文件（`ivorysql.conf`）

将 `ivorysql.conf` 与脚本放在**同一目录**。配置文件只允许出现 **`KEY=VALUE`** 行、注释（`#`）和空行。

**必填键**（要求为**绝对路径**；不存在会自动创建）：

| 键 | 作用 | 备注 |
|---|---|---|
| `INSTALL_DIR` | 安装前缀目录（`bin/`、`lib/` 等） | 如 `/usr/ivorysql` |
| `DATA_DIR` | 数据目录 | 如 `/var/lib/ivorysql/data` |
| `SERVICE_USER` | 运行服务的系统用户 | 若不存在会自动创建 |
| `SERVICE_GROUP` | 服务所属系统用户组 | 若不存在会自动创建 |
| `LOG_DIR` | 安装与服务日志目录 | 如 `/var/log/ivorysql` |

**示例**（与你当前的 `ivorysql.conf` 一致）：
```ini
# IvorySQL Automated Installation Configuration
INSTALL_DIR=/usr/ivorysql
DATA_DIR=/var/lib/ivorysql/data
SERVICE_USER=ivorysql
SERVICE_GROUP=ivorysql
LOG_DIR=/var/log/ivorysql
```

---

## 4. 可调环境变量

以下变量可在执行脚本时通过环境变量覆盖：

| 变量 | 默认值 | 用途 |
|---|---:|---|
| `RUN_TESTS` | `0` | 设为 `1` 时安装并校验 Perl 的 `IPC::Run`，以支持 TAP 风格测试；为 `0` 时不装测试依赖。 |
| `INIT_MODE` | `oracle` | 初始化模式：`oracle` 或 `pg`。 |
| `CASE_MODE` | `interchange` | 标识符大小写：`interchange` \| `normal` \| `lowercase`。 |
| `READY_TIMEOUT` | `90` | 等待服务就绪的时长（`pg_ctl -w -t` 与就绪轮询）。 |

**示例**
```bash
# 默认安装（不安装 TAP 测试依赖）
sudo bash ./AutoInstall.sh

# 启用 TAP 测试（将安装 libipc-run-perl/perl-IPC-Run 与 cpanminus）
sudo RUN_TESTS=1 bash ./AutoInstall.sh

# 以 PostgreSQL 模式、普通大小写初始化
sudo INIT_MODE=pg CASE_MODE=normal bash ./AutoInstall.sh

# 将就绪超时提高到 180 秒
sudo READY_TIMEOUT=180 bash ./AutoInstall.sh
```

---

## 5. 安装流程（脚本的阶段）

1. **加载配置**：读取 `ivorysql.conf`，校验必填键与绝对路径。  
2. **准备文件系统与账号**：创建 `INSTALL_DIR`、`DATA_DIR`、`LOG_DIR`；确保 `SERVICE_USER`/`SERVICE_GROUP`；日志目录授权到服务账号。  
3. **检测操作系统**：选择包管理器并校验受支持版本。  
4. **启用 EL/OL 仓库**（尽力而为）：在 EL/OL 上启用 CRB/PowerTools/CodeReady Builder 与 EPEL。  
5. **安装依赖**：编译器、头文件与工具（readline、zlib、OpenSSL、libxml2/xslt、ICU、uuid、gettext、tcl 等）。EL 系列安装 **Development Tools** 组。  
6. **构建特性探测**（据此决定 `configure` 开关）：
   - 发现 OpenSSL 头文件则 `--with-openssl`（否则 `--without-openssl`）
   - 发现 ICU 则 `--with-icu`（否则 `--without-icu`）
   - 发现 `uuid/uuid.h` 则 `--with-uuid=e2fs`（否则 `--without-uuid`）
   - 发现 libxml2 头文件则 `--with-libxml`（否则 `--without-libxml`）
7. **配置与编译安装**：
   - 执行 `./configure --prefix="$INSTALL_DIR" --with-readline ...`
   - 在 Debian/Ubuntu 上仅对**编译阶段**增加 `-fPIE`，避免把 `-pie` 作用到共享库链接。
   - `make -j$(nproc)` 并 `make install`
8. **初始化集群**：以 `SERVICE_USER` 执行 `initdb -m "$INIT_MODE" -C "$CASE_MODE"`。  
   - 脚本会设置 `DATA_DIR` 权限；**`initdb` 可能会收紧到 700**（符合 PostgreSQL/IvorySQL 默认）。
9. **服务注册**：
   - **systemd 环境**：生成 `/etc/systemd/system/ivorysql.service`，设置 `PGDATA`、`LD_LIBRARY_PATH` 与 `pg_ctl`（尊重 `READY_TIMEOUT`），并 `systemctl enable ivorysql`。  
   - **无 systemd 环境**：生成 `"$INSTALL_DIR/ivorysql-ctl"` 辅助脚本，支持 `start|stop|reload|status`。
10. **启动与就绪校验**：
    - 通过 `systemctl` 或辅助脚本启动。
    - 使用 `pg_isready` 在本地 socket/`127.0.0.1` 上轮询就绪。
    - 以 `SERVICE_USER` 运行一次 `psql -Atc 'SELECT 1'` 做最小 SQL 验证。
11. **汇总信息**：打印目录、服务状态、版本与常用命令备忘。

---

## 6. 日志与排障

- **安装日志**：  
  - `{LOG_DIR}/install_YYYYmmdd_HHMMSS.log`  
  - `{LOG_DIR}/error_YYYYmmdd_HHMMSS.log`
- **服务日志**：`{LOG_DIR}/server_*.log`、`{LOG_DIR}/server_ctl.log`（无 systemd 场景）。
- **常用排障命令**：
  ```bash
  # 状态
  systemctl status ivorysql    # 或：$INSTALL_DIR/ivorysql-ctl status

  # 实时日志
  journalctl -u ivorysql -f    # 或：tail -f $LOG_DIR/*.log

  # 连通性
  pg_isready -h 127.0.0.1 -p ${PGPORT:-5432}

  # 权限
  ls -ld "$DATA_DIR" && ls -l "$DATA_DIR"
  ```

> 脚本**不会**修改防火墙/SELinux。若需远程访问，请按环境策略开放端口与策略。

---



## 7. 常见问题

- **脚本必须放在哪里？** 放在源码根目录下的 `autoinstall_script/` 中。脚本会把其**上一级目录**当作源码根，查找 `configure` 与 `src/`。  
- **如何改端口？** 按 PostgreSQL 常规方式调整（如编辑 `postgresql.conf`）。脚本在就绪判定时会读取 `postmaster.pid` 的真实端口。  
- **为什么要在服务/辅助脚本里设置 `LD_LIBRARY_PATH`？** 为了优先使用 `{INSTALL_DIR}/lib` 下新安装的 IvorySQL 库。
