#!/usr/bin/env bash
set -Eeuo pipefail
# Ensure ERR trap inherits into functions/subshells
set -E

# -----------------------------
# Global variables
# -----------------------------
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
OS_TYPE=""
OS_VERSION=""
RHEL_VERSION=""
XML_SUPPORT=0
UUID_SUPPORT=0

# -----------------------------
# Pretty printers
# -----------------------------
LAST_STAGE=""
CURRENT_STAGE() {
  LAST_STAGE="$1"
  echo -e "\n\033[34m[$(date '+%H:%M:%S')] $1\033[0m"
}
STEP_BEGIN()   { echo -e "  → $1..."; }
STEP_SUCCESS() { echo -e "  \033[32m✓ $1\033[0m"; }
STEP_WARNING() { echo -e "  \033[33m⚠ $1\033[0m"; }
STEP_FAIL() {
  local msg="$1"
  echo -e "  \033[31m✗ ${msg}\033[0m" >&2
  [[ -n "$LAST_STAGE" ]] && echo "  Stage : ${LAST_STAGE}" >&2
  dba_hint
  echo -e "  Exiting." >&2
  exit 1
}

# -----------------------------
# DBA troubleshooting hint
# -----------------------------
dba_hint() {
  local log_hint
  if [[ -n "${LOG_DIR:-}" ]]; then
    log_hint="${LOG_DIR}/error_${TIMESTAMP}.log"
  else
    log_hint="(Log directory not initialized; if redirection is enabled, check error_${TIMESTAMP}.log under the install directory)"
  fi
  echo "—— Troubleshooting ———————————————————————————————" >&2
  echo "1) Service status: systemctl status ivorysql" >&2
  echo "2) Recent logs   : journalctl -u ivorysql --no-pager | tail -n 80" >&2
  echo "3) Install log   : ${log_hint}" >&2
  echo "4) Connectivity  : pg_isready -h 127.0.0.1 -p \${PGPORT:-5432}" >&2
  echo "5) Directory ACL : ls -ld \"${DATA_DIR:-/var/lib/ivorysql/data}\" && ls -l \"${DATA_DIR:-/var/lib/ivorysql/data}\"" >&2
  echo "———————————————————————————————————————————————" >&2
}

# -----------------------------
# Service helpers (systemd / non-systemd)
# -----------------------------
has_cmd()      { command -v "$1" >/dev/null 2>&1; }
has_systemd()  { has_cmd systemctl && [[ -d /run/systemd/system ]]; }
sc()           { env PYTHONWARNINGS=ignore systemctl "$@"; }

svc_daemon_reload(){ if has_systemd; then sc daemon-reload; fi; }
svc_enable()       { if has_systemd; then sc enable "$1"; fi; }
svc_start(){
  if has_systemd; then
    sc start "$1"
  else
    local CMD="env LD_LIBRARY_PATH='$INSTALL_DIR/lib:$INSTALL_DIR/lib/postgresql:${LD_LIBRARY_PATH:-}' \
      PATH='$INSTALL_DIR/bin:${PATH:-/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin}' \
      '$INSTALL_DIR/bin/pg_ctl' start -D '$DATA_DIR' -s -w -t 90 -l '$LOG_DIR/server_${TIMESTAMP}.log'"
    if command -v runuser >/dev/null 2>&1; then
      runuser -u "$SERVICE_USER" -- bash -c "$CMD"
    else
      su -s /bin/bash - "$SERVICE_USER" -c "$CMD"
    fi
  fi
}
svc_stop(){
  if has_systemd; then
    sc stop "$1"
  else
    su -s /bin/bash - "$SERVICE_USER" -c "$INSTALL_DIR/bin/pg_ctl stop -D $DATA_DIR -s -m fast"
  fi
}
svc_is_active(){
  if has_systemd; then
    sc is-active --quiet "$1"
  else
    pgrep -f "$INSTALL_DIR/bin/postgres.*-D $DATA_DIR" >/dev/null 2>&1
  fi
}
svc_status_dump(){ if has_systemd; then sc status "$1" -l --no-pager; fi; }
svc_logs_tail(){
  if has_systemd && has_cmd journalctl; then
    journalctl -u "$1" -n 50 --no-pager
  else
    tail -n 100 "$LOG_DIR"/*.log 2>/dev/null || true
  fi
}

# -----------------------------
# Error trap
# -----------------------------
handle_error() {
  local line="$1" cmd="$2"
  echo -e "\033[31m✗ Installation failed\033[0m" >&2
  [[ -n "$LAST_STAGE" ]] && echo "Stage : ${LAST_STAGE}" >&2
  echo "Line  : ${line}" >&2
  echo "Command: ${cmd}" >&2
  dba_hint
  echo "Exiting." >&2
  exit 1
}
trap 'handle_error "${LINENO}" "${BASH_COMMAND}"' ERR

# -----------------------------
# Config loading & validation
# -----------------------------
validate_config() {
  local key=$1 value=$2
  case $key in
    INSTALL_DIR|DATA_DIR|LOG_DIR)
      if [[ ! "$value" =~ ^/[^[:space:]]+$ ]]; then
        STEP_FAIL "Configuration error: $key must be an absolute path (current: '$value')."
      fi
      if [[ -e "$value" ]]; then
        if [[ -f "$value" ]]; then
          STEP_FAIL "Configuration error: $key must be a directory path; found a file (current: '$value')."
        fi
        if ! [[ -w "$value" ]]; then
          if [[ -O "$value" ]]; then
            STEP_FAIL "Configuration error: $key path is not writable (current user)."
          else
            STEP_FAIL "Configuration error: $key path is not writable (requires $USER)."
          fi
        fi
      else
        local parent_dir
        parent_dir=$(dirname "$value")
        mkdir -p "$parent_dir" || STEP_FAIL "Create parent directory failed: $parent_dir"
        [[ -w "$parent_dir" ]] || STEP_FAIL "Configuration error: $key parent directory is not writable (path: '$parent_dir')"
      fi
      ;;
    SERVICE_USER|SERVICE_GROUP)
      local reserved_users="root bin daemon adm lp sync shutdown halt mail operator games ftp"
      if grep -qw "$value" <<< "$reserved_users"; then
        STEP_FAIL "Configuration error: $key uses a reserved system account (current: '$value')."
      fi
      if [[ ! "$value" =~ ^[a-zA-Z_][a-zA-Z0-9_-]{0,31}$ ]]; then
        STEP_FAIL "Configuration error: $key invalid name (current value: '$value')"
      fi
      ;;
  esac
}

load_config() {
  CURRENT_STAGE "Load configuration"
  local script_dir config_file
  script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
  config_file="${script_dir}/ivorysql.conf"

  STEP_BEGIN "Checking configuration file"
  [[ -f "$config_file" ]] || STEP_FAIL "Configuration file not found: $config_file. Ensure 'ivorysql.conf' exists in the script directory."
  STEP_SUCCESS "Configuration file detected"

  STEP_BEGIN "Loading configuration file"
  if grep -Evq '^\s*([A-Z_][A-Z0-9_]*\s*=\s*.*|#|$)' "$config_file"; then
    STEP_FAIL "Invalid configuration format: only KEY=VALUE pairs and comments are allowed."
  fi
  source "$config_file" || STEP_FAIL "Failed to load configuration file: $config_file. Check file format."
  STEP_SUCCESS "Configuration loaded"

  STEP_BEGIN "Validating configuration"
  local required_vars=(INSTALL_DIR DATA_DIR SERVICE_USER SERVICE_GROUP LOG_DIR)
  for var in "${required_vars[@]}"; do
    [[ -z "${!var:-}" ]] && STEP_FAIL "Missing required configuration: $var"
  done

  # Per-key checks
  while IFS='=' read -r key value; do
    [[ $key =~ ^[[:space:]]*# || -z $key ]] && continue
    key=$(echo "$key" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    validate_config "$key" "$value"
  done < "$config_file"
  STEP_SUCCESS "Configuration validated"
}

# -----------------------------
# Privilege check
# -----------------------------
check_root() {
  CURRENT_STAGE "Privilege check"
  STEP_BEGIN "Validating privileges"
  if [[ "$(id -u)" -ne 0 ]]; then
    echo -e "Please run: \033[33msudo \"$0\"\033[0m" >&2
    STEP_FAIL "Root privileges are required."
  fi
  STEP_SUCCESS "Root privileges validated"
}

# -----------------------------
# Environment detection
# -----------------------------
detect_environment() {
  CURRENT_STAGE "Detect system"

  get_major_version() {
    grep -Eo 'VERSION_ID="?[0-9.]+' /etc/os-release | cut -d= -f2 | tr -d '"' | cut -d. -f1
  }

  STEP_BEGIN "Detecting operating system"
  [[ -f /etc/os-release ]] || STEP_FAIL "Unable to detect operating system (missing /etc/os-release)."
  source /etc/os-release

  OS_TYPE="$ID"
  OS_VERSION="${VERSION_ID:-}"
  local pretty="${PRETTY_NAME:-$ID}"
  STEP_SUCCESS "Detected OS: $pretty"

  case "$OS_TYPE" in
    centos|rhel|almalinux|rocky|oracle)
      RHEL_VERSION="$(get_major_version)"
      [[ -n "$RHEL_VERSION" ]] || STEP_FAIL "Failed to detect major version"
      if [[ "$RHEL_VERSION" -eq 7 ]]; then
        STEP_FAIL "CentOS/RHEL 7 is not supported by this script."
      elif [[ "$RHEL_VERSION" =~ ^(8|9|10)$ ]]; then
        if command -v dnf >/dev/null 2>&1; then
          PKG_MANAGER="dnf"
        else
          PKG_MANAGER="yum"
          STEP_WARNING "dnf not available; falling back to yum"
        fi
      else
        STEP_FAIL "Unsupported version: $RHEL_VERSION"
      fi
      STEP_SUCCESS "Using package manager: $PKG_MANAGER"
      ;;
    ubuntu|debian)
      local major="${OS_VERSION%%.*}"
      if [[ "$OS_TYPE" == "ubuntu" ]]; then
        [[ $major =~ ^(18|20|22|24)$ ]] || STEP_FAIL "Unsupported Ubuntu version: $OS_VERSION"
      else
        [[ $major =~ ^(10|11|12|13)$ ]] || STEP_FAIL "Unsupported Debian version: $OS_VERSION"
      fi
      PKG_MANAGER="apt-get"
      STEP_SUCCESS "Using package manager: apt-get"
      ;;
    opensuse*|sles)
      PKG_MANAGER="zypper"
      STEP_SUCCESS "Using package manager: zypper"
      ;;
    arch)
      PKG_MANAGER="pacman"
      STEP_SUCCESS "Using package manager: pacman"
      ;;
    *)
      STEP_FAIL "Unsupported or unrecognized OS: $OS_TYPE"
      ;;
  esac
}

# -----------------------------
# Create service user/group
# -----------------------------
setup_user() {
  CURRENT_STAGE "Configure service user and group"

  STEP_BEGIN "Creating service group"
  if ! getent group "$SERVICE_GROUP" &>/dev/null; then
    groupadd "$SERVICE_GROUP" || STEP_FAIL "Failed to create group: $SERVICE_GROUP"
    STEP_SUCCESS "Group created: $SERVICE_GROUP"
  else
    STEP_SUCCESS "Group exists: $SERVICE_GROUP"
  fi

  STEP_BEGIN "Creating service user"
  if ! id -u "$SERVICE_USER" &>/dev/null; then
    useradd -r -g "$SERVICE_GROUP" -s "/bin/bash" -m -d "/home/$SERVICE_USER" "$SERVICE_USER" \
      || STEP_FAIL "Failed to create user: $SERVICE_USER"
    STEP_SUCCESS "User created: $SERVICE_USER"
  else
    STEP_SUCCESS "User exists: $SERVICE_USER"
  fi
}

# -----------------------------
# Initialize logging
# -----------------------------
init_logging() {
  CURRENT_STAGE "Logging"

  STEP_BEGIN "Creating log directory"
  mkdir -p "$LOG_DIR" || STEP_FAIL "Failed to create log directory: $LOG_DIR"

  if id -u "$SERVICE_USER" &>/dev/null && getent group "$SERVICE_GROUP" &>/dev/null; then
    chown "$SERVICE_USER:$SERVICE_GROUP" "$LOG_DIR" \
      || STEP_WARNING "Failed to set ownership on log directory (continuing)."
    STEP_SUCCESS "Log directory ownership set"
  else
    STEP_WARNING "Service user or group not found; skipping ownership (continuing)."
    STEP_SUCCESS "Log directory created"
  fi

  STEP_BEGIN "Redirecting output streams to log files"
  exec > >(tee -a "${LOG_DIR}/install_${TIMESTAMP}.log")
  exec 2> >(tee -a "${LOG_DIR}/error_${TIMESTAMP}.log" >&2)
  STEP_SUCCESS "Log redirection configured"
}

# -----------------------------
# Dependency installation
# -----------------------------
install_dependencies() {
  CURRENT_STAGE "Install system dependencies"

  declare -A OS_SPECIFIC_DEPS=(
    [rhel_base]="zlib-devel openssl-devel perl-ExtUtils-Embed"
    [rhel_tools]="gcc make flex bison"
    [rhel_group]="Development Tools"
    [perl_deps]="perl-Test-Simple perl-Data-Dumper perl-devel"
    [libxml_dep]="libxml2-devel"
    [debian_base]="zlib1g-dev libssl-dev"
    [debian_tools]="build-essential flex bison"
    [debian_libxml]="libxml2-dev"
    [suse_base]="zlib-devel libopenssl-devel"
    [suse_tools]="gcc make flex bison"
    [suse_libxml]="libxml2-devel"
    [arch_base]="zlib openssl perl"
    [arch_tools]="base-devel"
    [arch_libxml]="libxml2"
    [uuid_dep]="uuid-dev"
    [rhel_uuid]="libuuid-devel"
    [suse_uuid]="libuuid-devel"
    [arch_uuid]="util-linux"
  )

  STEP_BEGIN "Refreshing package metadata"
  case "$OS_TYPE" in
    centos|rhel|almalinux|rocky|oracle)
      $PKG_MANAGER install -y epel-release 2>/dev/null || true
      $PKG_MANAGER install -y dnf-plugins-core 2>/dev/null || $PKG_MANAGER install -y yum-utils 2>/dev/null || true

      # EL10: repositories for devel headers (esp. libxml2-devel)
      if [[ "${RHEL_VERSION:-0}" -eq 10 ]]; then
        if [[ "$OS_TYPE" == "rocky" ]]; then
          $PKG_MANAGER config-manager --set-enabled crb 2>/dev/null || $PKG_MANAGER config-manager --set-enabled devel 2>/dev/null || true
        elif [[ "$OS_TYPE" == "oracle" ]]; then
          $PKG_MANAGER repolist | grep -q "ol10_developer" && $PKG_MANAGER config-manager --enable ol10_developer || true
          $PKG_MANAGER repolist | grep -q "ol10_addons"    && $PKG_MANAGER config-manager --enable ol10_addons    || true
        else
          $PKG_MANAGER config-manager --set-enabled codeready-builder || true
        fi
      fi

      $PKG_MANAGER update -y || true
      ;;
    ubuntu|debian)
      export DEBIAN_FRONTEND=noninteractive
      $PKG_MANAGER update -y || true
      ;;
    opensuse*|sles)
      $PKG_MANAGER refresh || true
      ;;
    arch)
      pacman -Sy --noconfirm
      ;;
  esac
  STEP_SUCCESS "Package metadata refreshed"

  STEP_BEGIN "Installing pkg-config"
  case "$OS_TYPE" in
    centos|rhel|almalinux|rocky|oracle) $PKG_MANAGER install -y pkgconf-pkg-config || $PKG_MANAGER install -y pkgconfig || true ;;
    ubuntu|debian)                      $PKG_MANAGER install -y pkg-config || true ;;
    opensuse*|sles)                     $PKG_MANAGER install -y pkgconf-pkg-config || $PKG_MANAGER install -y pkg-config || true ;;
    arch)                               pacman -S --noconfirm pkgconf || true ;;
  esac
  if command -v pkg-config >/dev/null 2>&1; then
    STEP_SUCCESS "pkg-config installed: $(pkg-config --version)"
  else
    STEP_WARNING "pkg-config not found; some feature auto-detection may be limited."
  fi

  STEP_BEGIN "Install dependencies"
  case "$OS_TYPE" in
    centos|rhel|almalinux|rocky|oracle)
      # Group (toolchain)
      if [[ "$PKG_MANAGER" == "dnf" ]]; then
        $PKG_MANAGER group install -y "${OS_SPECIFIC_DEPS[rhel_group]}" || true
      else
        $PKG_MANAGER groupinstall -y "${OS_SPECIFIC_DEPS[rhel_group]}" || true
      fi
      $PKG_MANAGER install -y ${OS_SPECIFIC_DEPS[rhel_tools]} || true

      # readline (required)
      STEP_BEGIN "Installing readline-devel"
      $PKG_MANAGER install -y readline-devel || STEP_FAIL "Failed to install readline-devel (required dependency)."
      STEP_SUCCESS "Readline installation succeeded"

      # XML headers
      if [[ $XML_SUPPORT -eq 0 ]]; then
        $PKG_MANAGER install -y ${OS_SPECIFIC_DEPS[libxml_dep]} || true
      fi

      $PKG_MANAGER install -y ${OS_SPECIFIC_DEPS[rhel_base]} ${OS_SPECIFIC_DEPS[perl_deps]} perl-devel perl-core ca-certificates perl-App-cpanminus || true
      command -v curl >/dev/null 2>&1 || $PKG_MANAGER install -y curl-minimal 2>/dev/null || true
      ;;
    ubuntu|debian)
      STEP_BEGIN "Installing libreadline-dev"
      $PKG_MANAGER install -y libreadline-dev || STEP_FAIL "Failed to install libreadline-dev (required dependency)."
      STEP_SUCCESS "Readline installation succeeded"

      $PKG_MANAGER install -y ${OS_SPECIFIC_DEPS[debian_tools]} ${OS_SPECIFIC_DEPS[debian_base]} ${OS_SPECIFIC_DEPS[debian_libxml]} \
        libperl-dev perl-modules curl ca-certificates cpanminus || true
      ;;
    opensuse*|sles)
      STEP_BEGIN "Installing readline-devel"
      $PKG_MANAGER install -y readline-devel || STEP_FAIL "Failed to install readline-devel (required dependency)."
      STEP_SUCCESS "Readline installation succeeded"

      $PKG_MANAGER install -y ${OS_SPECIFIC_DEPS[suse_tools]} ${OS_SPECIFIC_DEPS[suse_base]} ${OS_SPECIFIC_DEPS[suse_libxml]} \
        perl-devel perl-ExtUtils-Embed curl ca-certificates perl-App-cpanminus || true
      [[ -f /usr/include/openssl/ssl.h ]] || $PKG_MANAGER install -y openssl-devel || true
      ;;
    arch)
      STEP_BEGIN "Installing readline"
      pacman -S --noconfirm readline || STEP_FAIL "readline installation failed, must install readline"
      STEP_SUCCESS "Readline installation succeeded"

      pacman -S --noconfirm ${OS_SPECIFIC_DEPS[arch_base]} ${OS_SPECIFIC_DEPS[arch_tools]} ${OS_SPECIFIC_DEPS[arch_libxml]} \
        perl curl perl-app-cpanminus || true
      ;;
  esac
  STEP_SUCCESS "System dependencies installed"

  # Perl modules
  STEP_BEGIN "Install Perl modules"
  case "$OS_TYPE" in
    centos|rhel|almalinux|rocky|oracle)
      $PKG_MANAGER install -y perl-core perl-devel || true
      command -v cpanm >/dev/null 2>&1 || $PKG_MANAGER install -y perl-App-cpanminus curl || true
      if ! $PKG_MANAGER install -y perl-IPC-Run 2>/dev/null; then
        STEP_WARNING "perl-IPC-Run not available in repo; trying CPAN/CPANM"
        PERL_MM_USE_DEFAULT=1 cpan -i IPC::Run FindBin || {
          curl -fsSL https://cpanmin.us | perl - App::cpanminus || true
          cpanm IPC::Run FindBin || STEP_WARNING "Failed to install Perl modules (continuing)."
        }
      fi
      ;;
    ubuntu|debian)
      $PKG_MANAGER install -y perl-modules libipc-run-perl || true
      command -v cpanm >/dev/null 2>&1 || $PKG_MANAGER install -y cpanminus curl || true
      ;;
    opensuse*|sles)
      $PKG_MANAGER install -y perl-IPC-Run || true
      command -v cpanm >/dev/null 2>&1 || $PKG_MANAGER install -y perl-App-cpanminus curl || true
      ;;
    arch)
      pacman -S --noconfirm perl-ipc-run || true
      command -v cpanm >/dev/null 2>&1 || pacman -S --noconfirm perl-app-cpanminus curl || true
      ;;
  esac
  STEP_SUCCESS "Perl modules installed"

  # Validate toolchain presence
  STEP_BEGIN "Validating build prerequisites"
  for cmd in gcc make flex bison; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      STEP_WARNING "Missing dependency: $cmd (build may fail)"
    else
      echo "Found $cmd: $(command -v "$cmd")"
    fi
  done
  if ! command -v perl >/dev/null 2>&1; then
    STEP_WARNING "Perl interpreter not found; build may fail."
  else
    echo "Found Perl: $(command -v perl)"
    echo "Perl version: $(perl --version | head -n 2 | tail -n 1)"
  fi

  # XML support detection
  STEP_BEGIN "Detecting XML support"
  if [[ -f /usr/include/libxml2/libxml/parser.h || -f /usr/include/libxml/parser.h ]]; then
    XML_SUPPORT=1
    STEP_SUCCESS "XML development headers found; enabling XML support"
  else
    XML_SUPPORT=0
    STEP_WARNING "XML development headers not found; consider installing libxml2-devel/libxml2-dev."
    # Attempt install once
    case "$OS_TYPE" in
      centos|rhel|almalinux|rocky|oracle) $PKG_MANAGER install -y ${OS_SPECIFIC_DEPS[libxml_dep]} || true ;;
      ubuntu|debian)                       $PKG_MANAGER install -y libxml2-dev || true ;;
      opensuse*|sles)                      $PKG_MANAGER install -y libxml2-devel || true ;;
      arch)                                pacman -S --noconfirm libxml2 || true ;;
    esac
    if [[ -f /usr/include/libxml2/libxml/parser.h || -f /usr/include/libxml/parser.h ]]; then
      XML_SUPPORT=1
      STEP_SUCCESS "XML development headers installed; enabling XML support"
    else
      STEP_WARNING "XML development headers not installed; XML support disabled"
    fi
  fi

  # UUID support detection
  STEP_BEGIN "Detecting UUID support"
  if [[ -f /usr/include/uuid/uuid.h || -f /usr/include/uuid.h || -f /usr/include/linux/uuid.h ]]; then
    UUID_SUPPORT=1
    STEP_SUCCESS "UUID development headers found; enabling UUID support"
  else
    UUID_SUPPORT=0
    STEP_WARNING "UUID development headers not found; attempting to install UUID development libraries."
    case "$OS_TYPE" in
      centos|rhel|almalinux|rocky|oracle) $PKG_MANAGER install -y ${OS_SPECIFIC_DEPS[rhel_uuid]} || true ;;
      ubuntu|debian)                       $PKG_MANAGER install -y ${OS_SPECIFIC_DEPS[uuid_dep]} || true ;;
      opensuse*|sles)                      $PKG_MANAGER install -y ${OS_SPECIFIC_DEPS[suse_uuid]} || true ;;
      arch)                                pacman -S --noconfirm ${OS_SPECIFIC_DEPS[arch_uuid]} || true ;;
    esac
    if [[ -f /usr/include/uuid/uuid.h || -f /usr/include/uuid.h || -f /usr/include/linux/uuid.h ]]; then
      UUID_SUPPORT=1
      STEP_SUCCESS "UUID development headers installed; enabling UUID support"
    else
      STEP_WARNING "UUID development headers not installed; uuid-ossp will be disabled."
    fi
  fi
  STEP_SUCCESS "Build environment validated"

  # Ensure runtime libraries that we do rely on (no ICU here)
  STEP_BEGIN "Ensuring runtime libraries (libxml2, pkg-config)"
  case "$OS_TYPE" in
    arch)   pacman -S --noconfirm libxml2 pkgconf || true ;;
    debian|ubuntu)
      apt-get update -y || true
      apt-get install -y libxml2 pkg-config || true
      ;;
    opensuse*|sles) zypper -n in -y libxml2 pkg-config || true ;;
    centos|rhel|almalinux|rocky|oracle)
      if command -v dnf >/dev/null 2>&1; then
        dnf install -y libxml2 pkgconf || true
      else
        yum install -y libxml2 pkgconf-pkg-config || true
      fi
      ;;
  esac
  STEP_SUCCESS "Runtime libraries ensured"
}

# -----------------------------
# Build & Install
# -----------------------------
compile_install() {
  CURRENT_STAGE "Build and install"

  # Locate repo root: script lives in IvorySQL-AutoInstaller/ under repo root
  local script_dir repo_root
  script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
  repo_root="$(realpath "$script_dir/.." 2>/dev/null || readlink -f "$script_dir/..")"

  [[ -f "$repo_root/configure" && -d "$repo_root/src" ]] \
    || STEP_FAIL "Cannot locate IvorySQL source at repo root: $repo_root (missing 'configure' or 'src')."

  STEP_BEGIN "Using local IvorySQL source tree at $repo_root"
  STEP_SUCCESS "Source ready"
  cd "$repo_root" || STEP_FAIL "Failed to enter source dir: $repo_root"

  STEP_BEGIN "Validate Perl environment"
  local REQUIRED_PERL_MODULES=(FindBin IPC::Run)
  local MISSING_MODULES=()
  for module in "${REQUIRED_PERL_MODULES[@]}"; do
    perl -M"$module" -e 1 2>/dev/null || MISSING_MODULES+=("$module")
  done
  if ((${#MISSING_MODULES[@]})); then
    STEP_WARNING "Missing Perl modules: ${MISSING_MODULES[*]}"
    STEP_BEGIN "Attempt to install missing Perl modules"
    for module in "${MISSING_MODULES[@]}"; do
      if command -v cpanm >/dev/null 2>&1; then
        cpanm "$module" || STEP_WARNING "Failed to install Perl module: $module"
      else
        cpan "$module" || STEP_WARNING "Failed to install Perl module: $module"
      fi
    done
    STEP_SUCCESS "Attempted to install missing Perl modules"
  fi
  for module in "${REQUIRED_PERL_MODULES[@]}"; do
    perl -M"$module" -e 1 2>/dev/null || STEP_FAIL "Perl module $module still missing; build cannot proceed."
  done
  STEP_SUCCESS "Perl environment validated"

  STEP_BEGIN "Configuring build options"
  local CONFIGURE_OPTS="--prefix=$INSTALL_DIR --with-readline"

  # OpenSSL: enable only if headers+libs exist
  local OPENSSL_OK=0
  if [[ -f /usr/include/openssl/ssl.h || -f /usr/local/include/openssl/ssl.h ]]; then
    if command -v pkg-config >/dev/null 2>&1 && pkg-config --exists openssl; then
      OPENSSL_OK=1
    else
      ls /usr/lib64/libcrypto.so* /usr/lib/x86_64-linux-gnu/libcrypto.so* >/dev/null 2>&1 && OPENSSL_OK=1 || true
    fi
  fi
  if [[ $OPENSSL_OK -eq 1 ]]; then
    CONFIGURE_OPTS+=" --with-openssl"
    STEP_SUCCESS "OpenSSL detected; TLS enabled"
  else
    CONFIGURE_OPTS+=" --without-openssl"
    STEP_WARNING "OpenSSL development files not found; building without TLS support. Install 'openssl-devel' to enable."
  fi

  # ICU is forcefully disabled for portability/stability across distros
  CONFIGURE_OPTS+=" --without-icu"
  STEP_SUCCESS "ICU support disabled explicitly"

  # UUID support (uuid-ossp)
  if [[ $UUID_SUPPORT -eq 1 ]]; then
    CONFIGURE_OPTS+=" --with-uuid=e2fs"
    STEP_SUCCESS "UUID headers found; enabling uuid-ossp via e2fs/libuuid"
  else
    CONFIGURE_OPTS+=" --without-uuid"
    STEP_WARNING "UUID headers missing; uuid-ossp will be disabled."
  fi

  # XML support
  if [[ $XML_SUPPORT -eq 1 ]]; then
    CONFIGURE_OPTS+=" --with-libxml"
    STEP_SUCCESS "XML support enabled"
  else
    CONFIGURE_OPTS+=" --without-libxml"
    STEP_WARNING "libxml2 development files not found; XML support disabled."
  fi

  # Tcl
  local tcl_paths=("/usr/include/tcl.h" "/usr/include/tcl8.6/tcl.h")
  if [[ -f "${tcl_paths[0]}" || -f "${tcl_paths[1]}" ]]; then
    CONFIGURE_OPTS+=" --with-tcl"
    STEP_SUCCESS "Tcl development headers found; enabling support"
  else
    CONFIGURE_OPTS+=" --without-tcl"
    STEP_WARNING "Tcl development headers not found; Tcl support disabled."
  fi

  echo "Configure options: $CONFIGURE_OPTS"
  ./configure $CONFIGURE_OPTS || { echo "config.log (tail):"; tail -20 config.log || true; STEP_FAIL "Configure step failed."; }
  STEP_SUCCESS "Configuration completed"

  # Compatibility tweak for flex 'lex.backup' removal
  STEP_BEGIN "Applying flex/lex.backup compatibility fix"
  for mf in "src/Makefile.global" "src/bin/psql/Makefile"; do
    if [[ -f "$mf" ]] && grep -q "lex.backup" "$mf"; then
      sed -i -E 's/rm[[:space:]]+lex\.backup/rm -f lex.backup/g' "$mf" || true
    fi
  done
  if grep -R --include=Makefile\* -n "lex.backup" src >/dev/null 2>&1; then
    echo "Makefile entries referencing 'lex.backup' remain (now tolerant)."
  fi
  STEP_SUCCESS "Compatibility fix applied"

  STEP_BEGIN "Building (using $(nproc) threads)"
  make -j"$(nproc)" || STEP_FAIL "Build failed."
  STEP_SUCCESS "Build completed"

  STEP_BEGIN "Installing files"
  make install || STEP_FAIL "Installation step failed."
  chown -R "$SERVICE_USER:$SERVICE_GROUP" "$INSTALL_DIR" || STEP_FAIL "Set install directory ownership failed."
  STEP_SUCCESS "Installed to $INSTALL_DIR"
}

# -----------------------------
# Post-install & service setup
# -----------------------------
check_ora_runtime() {
  local so="$INSTALL_DIR/lib/postgresql/ivorysql_ora.so"
  if [[ -f "$so" ]] && command -v ldd >/dev/null 2>&1; then
    if ldd "$so" | grep -q "not found"; then
      XML_SUPPORT=0
      STEP_WARNING "ivorysql_ora dependency missing (ldd reports 'not found'); will switch initdb to -m pg."
    fi
  fi
}

post_install() {
  CURRENT_STAGE "Post-install configuration"
  check_ora_runtime

  STEP_BEGIN "Preparing data directory"
  mkdir -p "$DATA_DIR" || STEP_FAIL "Failed to create data directory: $DATA_DIR"

  if [ -n "$(ls -A "$DATA_DIR" 2>/dev/null)" ]; then
    STEP_BEGIN "Clearing data directory"
    svc_stop ivorysql 2>/dev/null || true
    rm -rf "${DATA_DIR:?}"/* "${DATA_DIR:?}"/.[^.]* "${DATA_DIR:?}"/..?* 2>/dev/null || true
    STEP_SUCCESS "Data directory cleared."
  else
    STEP_SUCCESS "Data directory is empty"
  fi

  chown "$SERVICE_USER:$SERVICE_GROUP" "$DATA_DIR"

  STEP_BEGIN "Setting environment for service user"
  local user_home
  user_home=$(getent passwd "$SERVICE_USER" | cut -d: -f6)
  cat > "$user_home/.bash_profile" <<EOF
# for ivorysql service user
PATH="$INSTALL_DIR/bin:\${PATH:-/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin}"
export PATH
PGDATA="$DATA_DIR"
export PGDATA
LD_LIBRARY_PATH="$INSTALL_DIR/lib:$INSTALL_DIR/lib/postgresql:\${LD_LIBRARY_PATH:-}"
export LD_LIBRARY_PATH
EOF
  chown "$SERVICE_USER:$SERVICE_GROUP" "$user_home/.bash_profile"
  chmod 600 "$user_home/.bash_profile"
  su - "$SERVICE_USER" -c "source ~/.bash_profile" || STEP_WARNING "Failed to load service user profile (continuing)."
  STEP_SUCCESS "Environment variables set"

  STEP_BEGIN "Initializing database (initdb)"
  local INIT_LOG="${LOG_DIR}/initdb_${TIMESTAMP}.log"
  local INIT_MODE="oracle"
  if [[ $XML_SUPPORT -eq 0 ]]; then
    INIT_MODE="pg"
    STEP_WARNING "XML/ORA runtime unavailable; switching initdb to PG mode (-m pg) to avoid loading ivorysql_ora during bootstrap."
  fi

  local INIT_CMD="env PGDATA='$DATA_DIR' \
    LD_LIBRARY_PATH='$INSTALL_DIR/lib:$INSTALL_DIR/lib/postgresql:${LD_LIBRARY_PATH:-}' \
    PATH='$INSTALL_DIR/bin:${PATH:-/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin}' \
    '$INSTALL_DIR/bin/initdb' -D '$DATA_DIR' --locale=C --encoding=UTF8 -m \"$INIT_MODE\" --debug"

  if command -v runuser >/dev/null 2>&1; then
    runuser -u "$SERVICE_USER" -- bash -c "$INIT_CMD" > "$INIT_LOG" 2>&1 \
      || { echo "======= initdb log (tail) ======="; tail -n 200 "$INIT_LOG" || true; STEP_FAIL "initdb failed"; }
  else
    su -s /bin/bash - "$SERVICE_USER" -c "$INIT_CMD" > "$INIT_LOG" 2>&1 \
      || { echo "======= initdb log (tail) ======="; tail -n 200 "$INIT_LOG" || true; STEP_FAIL "initdb failed"; }
  fi

  if grep -q "FATAL" "$INIT_LOG"; then
    echo "======= FATAL excerpts ======="
    grep -A 10 "FATAL" "$INIT_LOG" || true
    STEP_FAIL "Detected FATAL errors in initdb log."
  fi
  STEP_SUCCESS "Database initialized"

  STEP_BEGIN "Configuring system service"
  if has_systemd; then
    cat > /etc/systemd/system/ivorysql.service <<EOF
[Unit]
Description=IvorySQL Database Server
Documentation=https://www.ivorysql.org
Requires=network.target local-fs.target
After=network.target local-fs.target

[Service]
Type=forking
User=$SERVICE_USER
Group=$SERVICE_GROUP
Environment=PGDATA=$DATA_DIR
Environment=LD_LIBRARY_PATH=$INSTALL_DIR/lib:$INSTALL_DIR/lib/postgresql
PIDFile=$DATA_DIR/postmaster.pid
OOMScoreAdjust=-1000
ExecStart=$INSTALL_DIR/bin/pg_ctl start -D \${PGDATA} -s -w -t 90
ExecStop=$INSTALL_DIR/bin/pg_ctl stop -D \${PGDATA} -s -m fast
ExecReload=$INSTALL_DIR/bin/pg_ctl reload -D \${PGDATA}
TimeoutSec=120
Restart=on-failure
RestartSec=5s

[Install]
WantedBy=multi-user.target
EOF
    svc_daemon_reload
    svc_enable ivorysql
    STEP_SUCCESS "Systemd unit installed"
  else
    STEP_WARNING "systemd not detected; creating helper script"
    cat > "$INSTALL_DIR/ivorysql-ctl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

PGDATA="${PGDATA:-__PGDATA_PLACEHOLDER__}"
INSTALL_DIR="__INSTALL_DIR_PLACEHOLDER__"
LOG_DIR="__LOG_DIR_PLACEHOLDER__"

export LD_LIBRARY_PATH="$INSTALL_DIR/lib:$INSTALL_DIR/lib/postgresql:${LD_LIBRARY_PATH:-}"
export PATH="$INSTALL_DIR/bin:${PATH:-/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin}"

case "${1:-}" in
  start)  "$INSTALL_DIR/bin/pg_ctl" start  -D "$PGDATA" -s -w -t 90 -l "$LOG_DIR/server_ctl.log" ;;
  stop)   "$INSTALL_DIR/bin/pg_ctl" stop   -D "$PGDATA" -s -m fast ;;
  reload) "$INSTALL_DIR/bin/pg_ctl" reload -D "$PGDATA" ;;
  status) "$INSTALL_DIR/bin/pg_ctl" status -D "$PGDATA" || true ;;
  *) echo "Usage: $0 {start|stop|reload|status}" ; exit 1 ;;
esac
EOF
    sed -i "s#__PGDATA_PLACEHOLDER__#$DATA_DIR#g" "$INSTALL_DIR/ivorysql-ctl"
    sed -i "s#__INSTALL_DIR_PLACEHOLDER__#$INSTALL_DIR#g" "$INSTALL_DIR/ivorysql-ctl"
    sed -i "s#__LOG_DIR_PLACEHOLDER__#$LOG_DIR#g" "$INSTALL_DIR/ivorysql-ctl"
    chmod +x "$INSTALL_DIR/ivorysql-ctl"
    STEP_SUCCESS "Helper script created: $INSTALL_DIR/ivorysql-ctl"
  fi
}

# -----------------------------
# Verify installation
# -----------------------------
verify_installation() {
  CURRENT_STAGE "Validate installation"

  STEP_BEGIN "Starting service"
  if ! svc_start ivorysql; then
    echo "======= systemctl status ======="
    svc_status_dump ivorysql
    echo "======= recent logs ======="
    svc_logs_tail ivorysql
    STEP_FAIL "Failed to start service."
  fi
  STEP_SUCCESS "Service started; checking readiness..."

  db_is_ready() {
    for port in 5432 1521 5433; do
      su -s /bin/bash - "$SERVICE_USER" -c "env LD_LIBRARY_PATH='$INSTALL_DIR/lib:$INSTALL_DIR/lib/postgresql:${LD_LIBRARY_PATH:-}' PATH='$INSTALL_DIR/bin:${PATH:-/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin}' $INSTALL_DIR/bin/pg_isready -q -h /tmp -p $port -t 1" >/dev/null 2>&1 && return 0
      su -s /bin/bash - "$SERVICE_USER" -c "env LD_LIBRARY_PATH='$INSTALL_DIR/lib:$INSTALL_DIR/lib/postgresql:${LD_LIBRARY_PATH:-}' PATH='$INSTALL_DIR/bin:${PATH:-/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin}' $INSTALL_DIR/bin/pg_isready -q -h 127.0.0.1 -p $port -t 1" >/dev/null 2>&1 && return 0
    done
    return 1
  }

  STEP_BEGIN "Checking service readiness"
  local ready=0
  for _ in $(seq 1 90); do
    if svc_is_active ivorysql || db_is_ready; then
      STEP_SUCCESS "Service is ready"
      ready=1
      break
    fi
    sleep 1
  done
  if [[ "$ready" -ne 1 ]]; then
    svc_status_dump ivorysql
    svc_logs_tail ivorysql >&2
    STEP_FAIL "Service readiness check timed out."
  fi

  STEP_BEGIN "Validating SQL connectivity"
  if su - "$SERVICE_USER" -c "$INSTALL_DIR/bin/psql -d postgres -Atc \"SELECT 1\"" >/dev/null 2>&1; then
    STEP_SUCCESS "Basic connectivity OK"
  else
    STEP_WARNING "psql connectivity failed; please review logs."
  fi
}

# -----------------------------
# Success banner
# -----------------------------
show_success_message() {
  echo -e "\n\033[32m================ Installation succeeded ================\033[0m"
  local SERVICE_STATUS SERVICE_HELP LOG_FOLLOW

  if has_systemd; then
    if env PYTHONWARNINGS=ignore systemctl is-active --quiet ivorysql; then
      SERVICE_STATUS="$(env PYTHONWARNINGS=ignore systemctl is-active ivorysql 2>/dev/null || echo "unknown")"
    else
      SERVICE_STATUS="inactive"
    fi
    SERVICE_HELP='systemctl [start|stop|status] ivorysql'
    LOG_FOLLOW='journalctl -u ivorysql -f'
  else
    SERVICE_STATUS="(systemd not present; managed via pg_ctl helper)"
    SERVICE_HELP="$INSTALL_DIR/ivorysql-ctl {start|stop|reload|status}"
    LOG_FOLLOW="tail -f $LOG_DIR/*.log"
  fi

  cat <<EOF
Install directory: $INSTALL_DIR
Data directory: $DATA_DIR
Log directory: $LOG_DIR
Service: $SERVICE_STATUS
Version: $(${INSTALL_DIR}/bin/postgres --version)

Useful commands:
  $SERVICE_HELP
  $LOG_FOLLOW
  sudo -u $SERVICE_USER '${INSTALL_DIR}/bin/psql'

Install time: $(date)
Elapsed: ${SECONDS}s
OS: $OS_TYPE $OS_VERSION
Build: local-source   Commit: N/A
EOF
}

main() {
  CURRENT_STAGE "Start installation"
  SECONDS=0

  check_root          # 1. Check root permission
  load_config         # 2. Load configuration
  detect_environment  # 3. Detect environment
  setup_user          # 4. Create user & group
  init_logging        # 5. Initialize logging
  install_dependencies # 6. Install dependencies
  compile_install     # 7. Build & install (ICU disabled)
  post_install        # 8. Post-install configuration
  verify_installation # 9. Validate installation
  show_success_message
}

main "$@"
