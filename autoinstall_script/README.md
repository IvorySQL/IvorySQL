English | [中文](README_CN.md)
# IvorySQL Automated Installation Script

The IvorySQL automated installation script provides a fast and easy way to compile and install the IvorySQL database from source code on supported Linux systems.

## Table of Contents

- [Features](#features)
- [Supported Operating Systems](#supported-operating-systems)
- [File Description](#file-description)
- [Configuration File](#configuration-file)
- [Environment Variables](#environment-variables)
- [Command Line Options](#command-line-options)
- [Usage](#usage)
- [Logging and Troubleshooting](#logging-and-troubleshooting)

## Features

- Automatically detects operating system and package manager
- Automatically installs all necessary dependencies
- Compiles and installs IvorySQL from source code
- Configures database service (supports both systemd and non-systemd systems)
- Initializes database instance
- Provides detailed logging and error handling
- Supports Docker container environments
- Supports Nix development environments

## Supported Operating Systems

- RHEL/Rocky/AlmaLinux/Oracle Linux 8/9/10
- Ubuntu 20.04/22.04/24.04
- Debian 12/13

## File Description

The autoinstall_script directory contains the following files:

- `AutoInstall.sh` - Main installation script
- `ivorysql.conf` - Installation configuration file
- `flake.nix` - Nix package manager environment definition
- `flake.lock` - Nix environment version lock file
- `nix_support.patch` - Nix environment support patch for AutoInstall.sh
- `README_CN.md` - Chinese version of this document
- `README.md` - This document

## Configuration File

Installation configuration is done through the `ivorysql.conf` file, which contains the following configuration items:

```bash
# IvorySQL Automated Installation Configuration
INSTALL_DIR=/usr/ivorysql      # Installation directory
DATA_DIR=/var/lib/ivorysql/data # Data directory
SERVICE_USER=ivorysql           # Service user
SERVICE_GROUP=ivorysql          # Service group
LOG_DIR=/var/log/ivorysql       # Log directory
```

## Environment Variables

The following environment variables can be used to customize the installation process:

- `INIT_MODE` - Database initialization mode (oracle or pg, default is oracle)
- `CASE_MODE` - Case sensitivity mode (interchange, normal, or lowercase, default is interchange)
- `READY_TIMEOUT` - Service readiness check timeout in seconds (default is 90)
- `RUN_TESTS` - Whether to run TAP tests (default is 0, do not run)

## Command Line Options

The AutoInstall.sh script supports the following command line options:

```bash
# Display help information
./AutoInstall.sh -h
./AutoInstall.sh --help

# Display version information
./AutoInstall.sh -v
./AutoInstall.sh --version
```

## Usage

### Basic Installation

1. Ensure the script is run with root privileges:
   ```bash
   sudo bash AutoInstall.sh
   ```

2. The script will automatically perform the following steps:
   - Detect operating system
   - Install dependencies
   - Compile and install IvorySQL
   - Initialize database
   - Configure and start service

### Nix Environment Usage

In a Nix environment, you can use the provided flake.nix file to set up the development environment:

```bash
# Enter Nix development environment
nix develop

# Apply Nix support patch (if needed)
patch -p1 < nix_support.patch

# Run installation script
bash AutoInstall.sh
```

### Docker Environment Usage

In a Docker container, the script will automatically adapt to the container environment and use pg_ctl for service management.

## Logging and Troubleshooting

### Log Files

The following log files are generated during the installation process:

- `$LOG_DIR/install_${TIMESTAMP}.log` - Installation log
- `$LOG_DIR/error_${TIMESTAMP}.log` - Error log
- `$LOG_DIR/initdb_${TIMESTAMP}.log` - Database initialization log
- `$LOG_DIR/server_${TIMESTAMP}.log` - Server startup log

### Service Management

#### systemd Systems

```bash
# Check service status
systemctl status ivorysql

# Start/stop/restart service
systemctl start ivorysql
systemctl stop ivorysql
systemctl restart ivorysql

# View service logs
journalctl -u ivorysql -f
```

#### Non-systemd Systems

```bash
# Use provided control script
$INSTALL_DIR/ivorysql-ctl status
$INSTALL_DIR/ivorysql-ctl start
$INSTALL_DIR/ivorysql-ctl stop
$INSTALL_DIR/ivorysql-ctl reload

# View logs
tail -f $LOG_DIR/*.log
```

### Common Issues

1. **Permission issues**: Ensure the script is run with root privileges
2. **Dependency installation failures**: Check if the system package manager is working properly
3. **Compilation failures**: Check error messages in the installation log
4. **Service startup failures**: Check configuration files and log files
