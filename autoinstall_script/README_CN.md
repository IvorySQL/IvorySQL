[English](README.md) | 中文
# IvorySQL 自动安装脚本

IvorySQL 自动安装脚本提供了一种快速、简便的方式来在支持的 Linux 系统上从源代码编译和安装 IvorySQL 数据库。

## 功能特性

- 自动检测操作系统和包管理器
- 自动安装所有必需的依赖项
- 从源代码编译并安装 IvorySQL
- 配置数据库服务（支持 systemd 和非 systemd 系统）
- 初始化数据库实例
- 提供详细的日志记录和错误处理
- 支持 Docker 容器环境
- 支持 Nix 开发环境

## 支持的操作系统

- RHEL/Rocky/AlmaLinux/Oracle Linux 8/9/10
- Ubuntu 20.04/22.04/24.04
- Debian 12/13

## 文件说明

autoinstall_script 目录包含以下文件：

- `AutoInstall.sh` - 主安装脚本
- `ivorysql.conf` - 安装配置文件
- `flake.nix` - Nix 包管理器环境定义
- `flake.lock` - Nix 环境版本锁定文件
- `README_CN.md` - 本文档
- `README.md` - 英文版文档

## 配置文件

安装配置通过 `ivorysql.conf` 文件进行，该文件包含以下配置项：

```bash
# IvorySQL Automated Installation Configuration
INSTALL_DIR=/usr/ivorysql      # 安装目录
DATA_DIR=/var/lib/ivorysql/data # 数据目录
SERVICE_USER=ivorysql           # 服务用户
SERVICE_GROUP=ivorysql          # 服务组
LOG_DIR=/var/log/ivorysql       # 日志目录
```

## 环境变量

以下环境变量可用于自定义安装过程：

- `INIT_MODE` - 数据库初始化模式（oracle 或 pg，默认为 oracle）
- `CASE_MODE` - 大小写敏感模式（interchange、normal 或 lowercase，默认为 interchange）
- `READY_TIMEOUT` - 服务就绪检查超时时间（秒，默认为 90）
- `RUN_TESTS` - 是否运行 TAP 测试（默认为 0，不运行）

## 命令行选项

AutoInstall.sh 脚本支持以下命令行选项：

```bash
# 显示帮助信息
./AutoInstall.sh -h
./AutoInstall.sh --help

# 显示版本信息
./AutoInstall.sh -v
./AutoInstall.sh --version
```

## 使用方法

### 基本安装

1. 确保以 root 权限运行脚本：
   ```bash
   sudo bash AutoInstall.sh
   ```

2. 脚本将自动执行以下步骤：
   - 检测操作系统
   - 安装依赖项
   - 编译并安装 IvorySQL
   - 初始化数据库
   - 配置并启动服务

### Nix 环境使用

在 Nix 环境中，可以使用提供的 flake.nix 文件设置开发环境：

```bash
# 进入 Nix 开发环境
nix develop

# 运行安装脚本（Nix 环境支持已直接集成）
bash AutoInstall.sh
```

AutoInstall.sh 脚本包含内置的 Nix 环境检测，并自动适应 Nix 环境，无需额外的补丁。

### Docker 环境使用

在 Docker 容器中，脚本会自动适应容器环境，使用 pg_ctl 进行服务管理。

## 日志与排障

### 日志文件

安装过程中会生成以下日志文件：

- `$LOG_DIR/install_${TIMESTAMP}.log` - 安装日志
- `$LOG_DIR/error_${TIMESTAMP}.log` - 错误日志
- `$LOG_DIR/initdb_${TIMESTAMP}.log` - 数据库初始化日志
- `$LOG_DIR/server_${TIMESTAMP}.log` - 服务器启动日志

### 服务管理

#### systemd 系统

```bash
# 查看服务状态
systemctl status ivorysql

# 启动/停止/重启服务
systemctl start ivorysql
systemctl stop ivorysql
systemctl restart ivorysql

# 查看服务日志
journalctl -u ivorysql -f
```

#### 非 systemd 系统

```bash
# 使用提供的控制脚本
$INSTALL_DIR/ivorysql-ctl status
$INSTALL_DIR/ivorysql-ctl start
$INSTALL_DIR/ivorysql-ctl stop
$INSTALL_DIR/ivorysql-ctl reload

# 查看日志
tail -f $LOG_DIR/*.log
```

### 常见问题

1. **权限问题**：确保以 root 权限运行脚本
2. **依赖安装失败**：检查系统包管理器是否正常工作
3. **编译失败**：查看安装日志中的错误信息
4. **服务启动失败**：检查配置文件和日志文件
