#!/bin/bash
set -eo pipefail
# Ensure ERR trap inherits into functions/subshells
set -E

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
OS_TYPE=""
OS_VERSION=""
XML_SUPPORT=0  

LAST_STAGE=""
CURRENT_STAGE() {
    LAST_STAGE="$1"
    echo -e "\n\033[34m[$(date '+%H:%M:%S')] $1\033[0m"
}

STEP_BEGIN() {
    echo -e "  → $1..."
}

STEP_SUCCESS() {
    echo -e "  \033[32m✓ $1\033[0m"
}

STEP_FAIL() {
    local msg="$1"
    echo -e "  \033[31m✗ ${msg}\033[0m" >&2
    [[ -n "$LAST_STAGE" ]] && echo "  Stage : ${LAST_STAGE}" >&2
    dba_hint
    echo -e "  Exiting." >&2
    exit 1
}

STEP_WARNING() {
    echo -e "  \033[33m⚠ $1\033[0m"
}

# Short DBA-oriented troubleshooting checklist (English only)
dba_hint() {
    local log_hint
    if [[ -n "$LOG_DIR" ]]; then
        log_hint="${LOG_DIR}/error_${TIMESTAMP}.log"
    else
        log_hint="(Log directory not initialized; if redirection is enabled, check error_${TIMESTAMP}.log under the install directory)"
    fi
    echo "—— Troubleshooting ———————————————————————————————" >&2
    echo "1) Service status: systemctl status ivorysql" >&2
    echo "2) Recent logs   : journalctl -u ivorysql --no-pager | tail -n 80" >&2
    echo "3) Install log   : ${log_hint}" >&2
    echo "4) Connectivity  : pg_isready -h 127.0.0.1 -p ${PGPORT:-5432}" >&2
    echo "5) Directory ACL : ls -ld \"${DATA_DIR}\" && ls -l \"${DATA_DIR}\"" >&2
    echo "———————————————————————————————————————————————" >&2
}

has_cmd() { command -v "$1" >/dev/null 2>&1; }
has_systemd() { has_cmd systemctl && [ -d /run/systemd/system ]; }

sc() { env PYTHONWARNINGS=ignore systemctl "$@"; }

svc_daemon_reload(){ if has_systemd; then sc daemon-reload; fi; }
svc_enable(){ if has_systemd; then sc enable "$1"; fi; }
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
    su - "$SERVICE_USER" -c "$INSTALL_DIR/bin/pg_ctl stop -D $DATA_DIR -s -m fast"
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

die() {
    local msg="$1"; shift || true
    STEP_FAIL "${msg}"
}
handle_error() {
    local line="$1"
    local cmd="$2"

    echo -e "\033[31m✗ Installation failed\033[0m" >&2
    [[ -n "$LAST_STAGE" ]] && echo "Stage : ${LAST_STAGE}" >&2
    echo "Line  : ${line}" >&2
    echo "Command: ${cmd}" >&2

    dba_hint

    echo "Exiting." >&2
    exit 1
}

trap 'handle_error "${LINENO}" "${BASH_COMMAND}"' ERR

validate_config() {
    local key=$1 value=$2
    
    case $key in
        INSTALL_DIR|DATA_DIR|LOG_DIR)
            if [[ ! "$value" =~ ^/[^[:space:]]+$ ]]; then
                STEP_FAIL  "Configuration error: $key must be an absolute path (current: '$value')."
            fi
            
            if [[ -e "$value" ]]; then
                if [[ -f "$value" ]]; then
                    STEP_FAIL  "Configuration error: $key must be a directory path; found a file (current: '$value')."
                fi
                
                if ! [[ -w "$value" ]]; then
                    if [[ -O "$value" ]]; then
                        STEP_FAIL  "Configuration error: $key path is not writable (current user)."
                    else
                        STEP_FAIL  "Configuration error: $key path is not writable (requires $USER)."
                    fi
                fi
            else
                local parent_dir=$(dirname "$value")
                mkdir -p "$parent_dir" || STEP_FAIL  "Create parent directory failed: $parent_dir"
                if [[ ! -w "$parent_dir" ]]; then
                    STEP_FAIL  "Configuration error: $key parent directory is not writable (path: '$parent_dir')"
                fi
            fi
            ;;
            
        SERVICE_USER|SERVICE_GROUP)
            local reserved_users="root bin daemon adm lp sync shutdown halt mail operator games ftp"
            if grep -qw "$value" <<< "$reserved_users"; then
                STEP_FAIL  "Configuration error: $key uses a reserved system account (current: '$value')."
            fi
            
            if [[ ! "$value" =~ ^[a-zA-Z_][a-zA-Z0-9_-]{0,31}$ ]]; then
                STEP_FAIL  "Configuration error: $key invalid name (current value: '$value')"
                echo  "Naming rules: start with [A-Za-z_], then [A-Za-z0-9_-], length 1–32."
            fi
            
            if [[ $key == "SERVICE_USER" ]]; then
                if ! getent passwd "$value" &>/dev/null; then
                    STEP_SUCCESS  "Will Create user: $value"
                fi
            else
                if ! getent group "$value" &>/dev/null; then
                    STEP_SUCCESS  "Will Create group: $value"
                fi
            fi
            ;;

    esac
}

load_config() {
    CURRENT_STAGE "Load configuration"
    
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

CONFIG_FILE="${SCRIPT_DIR}/ivorysql.conf"

STEP_BEGIN  "Checking configuration file"
    if [[ ! -f "$CONFIG_FILE" ]]; then
        STEP_FAIL  "Configuration file not found: $CONFIG_FILE. Ensure 'ivorysql.conf' exists in the script directory."
    fi
STEP_SUCCESS  "Configuration file detected"

STEP_BEGIN  "Loading configuration file"
if grep -Evq '^\s*([A-Z_][A-Z0-9_]*\s*=\s*.*|#|$)' "$CONFIG_FILE"; then
    STEP_FAIL  "Invalid configuration format: only KEY=VALUE pairs and comments are allowed."
fi
source "$CONFIG_FILE" || STEP_FAIL  "Failed to load configuration file: $CONFIG_FILE. Check file format."
STEP_SUCCESS  "Configuration loaded"
    
    STEP_BEGIN  "Validating configuration"
    declare -a required_vars=("INSTALL_DIR" "DATA_DIR" "SERVICE_USER" "SERVICE_GROUP" "LOG_DIR")
    for var in "${required_vars[@]}"; do
        [[ -z "${!var}" ]] && STEP_FAIL  "Missing required configuration: $var"
    done
    STEP_SUCCESS  "Configuration validated"
    
    STEP_BEGIN  "Checking configuration values"
    while IFS='=' read -r key value; do
        [[ $key =~ ^[[:space:]]*# || -z $key ]] && continue
        key=$(echo $key | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        validate_config "$key" "$value"
    done < "$CONFIG_FILE"
    STEP_SUCCESS  "Configuration validated"
}

init_logging() {
    CURRENT_STAGE "Logging"
    
    STEP_BEGIN  "Creating log directory"
    mkdir -p "$LOG_DIR" || STEP_FAIL  "Failed to create log directory: $LOG_DIR"
    
    if id -u "$SERVICE_USER" &>/dev/null && getent group "$SERVICE_GROUP" &>/dev/null; then
        chown "$SERVICE_USER:$SERVICE_GROUP" "$LOG_DIR" || STEP_WARNING  "Failed to set ownership on log directory (continuing)."
        STEP_SUCCESS  "Log directory ownership set"
    else
        STEP_WARNING  "Service user or group not found; skipping ownership (continuing)."
        STEP_SUCCESS  "Log directory created"
    fi
    
    STEP_BEGIN  "Redirecting output streams to log files"
    exec > >(tee -a "${LOG_DIR}/install_${TIMESTAMP}.log")
    exec 2> >(tee -a "${LOG_DIR}/error_${TIMESTAMP}.log" >&2)
    STEP_SUCCESS  "Log redirection configured"
}

check_root() {
    CURRENT_STAGE "Privilege check"
    
    STEP_BEGIN  "Validating privileges"
    [[ "$(id -u)" -ne 0 ]] && {
        echo -e "Please run: \033[33msudo \"$0\" \"$@\"\033[0m" >&2
        STEP_FAIL  "Root privileges are required."
    }
    STEP_SUCCESS  "Root privileges validated"
}

detect_environment() {
    CURRENT_STAGE "Detect system"
    
    get_major_version() {
        grep -Eo 'VERSION_ID="?[0-9.]+' /etc/os-release | 
        cut -d= -f2 | tr -d '"' | cut -d. -f1
    }

    STEP_BEGIN  "Detecting operating system"
    [[ ! -f /etc/os-release ]] && STEP_FAIL  "Unable to detect operating system (missing /etc/os-release)."
    source /etc/os-release
    
    OS_TYPE="$ID"
    OS_VERSION="$VERSION_ID"
    
    PKG_MANAGER=""
    STEP_SUCCESS  "Detected OS: $PRETTY_NAME"
    
    # Special handling for Oracle Linux
    if [[ -f /etc/oracle-release ]]; then
        OS_TYPE="oracle"
        ORACLE_VERSION=$(grep -oE '([0-9]+)\.?([0-9]+)?' /etc/oracle-release | head -1)
        STEP_SUCCESS  "Detected Oracle Linux $ORACLE_VERSION"
    fi
    
    case "$OS_TYPE" in
        centos|rhel|almalinux|rocky|oracle)
            RHEL_VERSION=$(get_major_version)
            [[ -z $RHEL_VERSION ]] && STEP_FAIL  "Failed to detect major version"
            
            if [[ $RHEL_VERSION -eq 7 ]]; then
                STEP_FAIL  "CentOS/RHEL 7 is not supported by this script."
            elif [[ $RHEL_VERSION =~ ^(8|9|10)$ ]]; then
                if command -v dnf &>/dev/null; then
                    PKG_MANAGER="dnf"
                    STEP_SUCCESS  "Using package manager: dnf"
                else
                    PKG_MANAGER="yum"
                    STEP_WARNING  "dnf not available; falling back to yum"
                fi
            else
                STEP_FAIL  "Unsupported version: $RHEL_VERSION"
            fi
            ;;
            
        ubuntu|debian)
            OS_VERSION=$(grep -Po '(?<=VERSION_ID=")[0-9.]+' /etc/os-release)
            MAJOR_VERSION=${OS_VERSION%%.*}
            
            case "$OS_TYPE" in
                ubuntu)
                    [[ $MAJOR_VERSION =~ ^(18|20|22|24)$ ]] || 
                    STEP_FAIL  "Unsupported Ubuntu version: $OS_VERSION" ;;
                debian)
                    [[ $MAJOR_VERSION =~ ^(10|11|12|13)$ ]] || 
                    STEP_FAIL  "Unsupported Debian version: $OS_VERSION" ;;
            esac
            PKG_MANAGER="apt-get"
            STEP_SUCCESS  "Using package manager: apt-get"
            ;;
        
        opensuse*|sles)
            PKG_MANAGER="zypper"
            STEP_SUCCESS  "Using package manager: zypper"
            ;;
        
        arch)
            PKG_MANAGER="pacman"
            STEP_SUCCESS  "Using package manager: pacman"
            ;;
        
        *)
            STEP_FAIL  "Unsupported or unrecognized OS: $OS_TYPE"
            ;;
    esac
}

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

    STEP_BEGIN  "Refreshing package metadata"
    case "$OS_TYPE" in
        centos|rhel|almalinux|rocky|oracle)
            $PKG_MANAGER install -y epel-release 2>/dev/null || true
            # Ensure config-manager is available before using it
            $PKG_MANAGER install -y dnf-plugins-core 2>/dev/null || $PKG_MANAGER install -y yum-utils 2>/dev/null || true
            
            # EL10-specific handling - enhanced XML library installation
            if [[ $RHEL_VERSION -eq 10 ]]; then
                STEP_BEGIN  "EL10: enabling CRB repo and installing XML development library"
                if [[ "$OS_TYPE" == "rocky" ]]; then
                    # Ensure CRB repository is enabled
                    if ! $PKG_MANAGER config-manager --set-enabled crb 2>/dev/null; then
                        STEP_WARNING  "Failed to enable CRB; trying devel repository"
                        $PKG_MANAGER config-manager --set-enabled devel 2>/dev/null || true
                    fi
                    
                    # Explicitly attempt to install libxml2-devel
                    if $PKG_MANAGER install -y libxml2-devel; then
                        XML_SUPPORT=1
                        STEP_SUCCESS  "Installed libxml2-devel; enabling XML support"
                    else
                        # Try alternative package names
                        STEP_BEGIN  "Attempting alternative XML package name"
                        if $PKG_MANAGER install -y libxml2-dev; then
                            XML_SUPPORT=1
                            STEP_SUCCESS  "Installed libxml2-dev; enabling XML support"
                        else
                            XML_SUPPORT=0
                            STEP_WARNING  "Failed to install XML development library; XML support disabled."
                        fi
                    fi
                elif [[ "$OS_TYPE" == "oracle" ]]; then
                    # Oracle Linux 10 specific repo handling
                    STEP_BEGIN  "Oracle Linux 10: enabling additional repositories"
                    if $PKG_MANAGER repolist | grep -q "ol10_developer"; then
                        $PKG_MANAGER config-manager --enable ol10_developer || true
                    elif $PKG_MANAGER repolist | grep -q "ol10_addons"; then
                        $PKG_MANAGER config-manager --enable ol10_addons || true
                    fi
                    STEP_SUCCESS  "Repository configuration updated"
                else
                    $PKG_MANAGER config-manager --set-enabled codeready-builder || true
                fi
                STEP_SUCCESS  "Repository configuration updated"
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
    STEP_SUCCESS  "Package metadata refreshed"

# Ensure pkg-config exists (needed by ICU detection)
STEP_BEGIN  "Installing pkg-config"
case "$OS_TYPE" in
    centos|rhel|almalinux|rocky|oracle)
        $PKG_MANAGER install -y pkgconf-pkg-config || $PKG_MANAGER install -y pkgconfig || true
        ;;
    ubuntu|debian)
        $PKG_MANAGER install -y pkg-config || true
        ;;
    opensuse*|sles)
        $PKG_MANAGER install -y pkgconf-pkg-config || $PKG_MANAGER install -y pkg-config || true
        ;;
    arch)
        pacman -S --noconfirm pkgconf || true
        ;;
esac
if command -v pkg-config >/dev/null 2>&1; then
    STEP_SUCCESS  "pkg-config installed: $(pkg-config --version)"
else
    STEP_WARNING  "pkg-config not found; ICU and related features will be disabled."
fi

    STEP_BEGIN  "Install dependencies"
    case "$OS_TYPE" in
        centos|rhel|almalinux|rocky|oracle)
            # Oracle Linux specific settings
            if [[ "$OS_TYPE" == "oracle" ]]; then
                STEP_BEGIN  "Install Oracle Linux dependencies"
                $PKG_MANAGER install -y oraclelinux-developer-release-el${RHEL_VERSION} 2>/dev/null || true
                $PKG_MANAGER group install -y "Development Tools" 2>/dev/null || true
                STEP_SUCCESS  "Oracle dependencies installed."
            fi
            
            # General EL dependency installation
            if [[ "$PKG_MANAGER" == "dnf" ]]; then
                $PKG_MANAGER group install -y "${OS_SPECIFIC_DEPS[rhel_group]}" || true
            else
                $PKG_MANAGER groupinstall -y "${OS_SPECIFIC_DEPS[rhel_group]}" || true
            fi
            # Ensure base toolchain even if group metadata is absent (minimal images)
            $PKG_MANAGER install -y ${OS_SPECIFIC_DEPS[rhel_tools]} || true
            
            # Force install readline-devel
            STEP_BEGIN  "Installing readline"
            $PKG_MANAGER install -y readline-devel || STEP_FAIL  "Failed to install readline-devel (required dependency)."
            STEP_SUCCESS  "Readline installation succeeded"
            
            # Special handling: ensure XML development library is installed (for non-EL10 or EL10 cases not covered above)
            if [[ $XML_SUPPORT -eq 0 && $RHEL_VERSION -ne 10 ]]; then
                STEP_BEGIN  "Installing XML development library"
                if $PKG_MANAGER install -y ${OS_SPECIFIC_DEPS[libxml_dep]}; then
                    XML_SUPPORT=1
                    STEP_SUCCESS  "XML development library installation succeeded"
                else
                    STEP_WARNING  "XML development library installation failed; XML support disabled."
                fi
            fi
            
            $PKG_MANAGER install -y \
                ${OS_SPECIFIC_DEPS[rhel_base]} \
                ${OS_SPECIFIC_DEPS[perl_deps]} \
                perl-devel perl-core ca-certificates perl-App-cpanminus || true
            # Ensure libxml2 runtime is present
            $PKG_MANAGER install -y libxml2 || true
            # if curl command is missing, prefer curl-minimal to avoid conflict
            command -v curl >/dev/null 2>&1 || $PKG_MANAGER install -y curl-minimal 2>/dev/null || true
            ;;
        ubuntu|debian)
            # Force install libreadline-dev
            STEP_BEGIN  "Installing libreadline-dev"
            $PKG_MANAGER install -y libreadline-dev || STEP_FAIL  "Failed to install libreadline-dev (required dependency)."
            STEP_SUCCESS  "Readline installation succeeded"
            
            $PKG_MANAGER install -y \
                ${OS_SPECIFIC_DEPS[debian_tools]} \
                ${OS_SPECIFIC_DEPS[debian_base]} \
                ${OS_SPECIFIC_DEPS[debian_libxml]} \
                libperl-dev perl-modules curl ca-certificates cpanminus || true
            # Ensure libxml2 runtime is present
            $PKG_MANAGER install -y libxml2 || true
            ;;
        opensuse*|sles)
            # Force install readline-devel
            STEP_BEGIN  "Installing readline-devel"
            $PKG_MANAGER install -y readline-devel || STEP_FAIL  "Failed to install readline-devel (required dependency)."
            STEP_SUCCESS  "Readline installation succeeded"
            
            $PKG_MANAGER install -y \
                ${OS_SPECIFIC_DEPS[suse_tools]} \
                ${OS_SPECIFIC_DEPS[suse_base]} \
                ${OS_SPECIFIC_DEPS[suse_libxml]} \
                perl-devel perl-ExtUtils-Embed curl ca-certificates perl-App-cpanminus || true
            # Ensure libxml2 runtime is present
            $PKG_MANAGER install -y libxml2 || true
            # Fallback: if openssl headers still missing, try alternate package name
            [[ -f /usr/include/openssl/ssl.h ]] || $PKG_MANAGER install -y openssl-devel || true
            ;;
        arch)
            # Force install readline
            STEP_BEGIN  "Installing readline"
            pacman -S --noconfirm readline || STEP_FAIL  "readline installation failed, must install readline"
            STEP_SUCCESS  "Readline installation succeeded"
            
            pacman -S --noconfirm \
                ${OS_SPECIFIC_DEPS[arch_base]} \
                ${OS_SPECIFIC_DEPS[arch_tools]} \
                ${OS_SPECIFIC_DEPS[arch_libxml]} \
                perl curl perl-app-cpanminus || true
            # Ensure libxml2 runtime is present
            pacman -S --noconfirm libxml2 || true
            ;;
    esac
    STEP_SUCCESS  "System dependencies installed"

    # Install required Perl modules
    STEP_BEGIN  "Install Perl modules"
    case "$OS_TYPE" in
        centos|rhel|almalinux|rocky|oracle)
            # Install Perl core modules and dev tools
            $PKG_MANAGER install -y perl-core perl-devel || true
            # Ensure cpanminus exists for reliable noninteractive installs
            command -v cpanm >/dev/null 2>&1 || $PKG_MANAGER install -y perl-App-cpanminus curl || true
            
            # Try installing IPC-Run
            if ! $PKG_MANAGER install -y perl-IPC-Run 2>/dev/null; then
                STEP_WARNING  "perl-IPC-Run not available in repo; trying CPAN"
                # Use CPAN to install missing modules
                PERL_MM_USE_DEFAULT=1 cpan -i IPC::Run FindBin || {
                    STEP_WARNING  "CPAN installation failed; trying cpanm"
                    # If CPAN is unavailable, try cpanm
                    curl -fsSL https://cpanmin.us | perl - App::cpanminus || true
                    cpanm IPC::Run FindBin || STEP_WARNING  "Failed to install Perl modules (continuing)."
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
    STEP_SUCCESS  "Perl modules installed"

    STEP_BEGIN  "Validating build prerequisites"
    for cmd in gcc make flex bison; do
        if ! command -v $cmd >/dev/null 2>&1; then
            STEP_WARNING  "Missing dependency: $cmd (build may fail)"
        else
            echo  "Found $cmd: $(command -v $cmd)"
        fi
    done
    
    if ! command -v perl >/dev/null 2>&1; then
        STEP_WARNING  "Perl interpreter not found; build may fail."
    else
        echo  "Found Perl: $(command -v perl)"
        echo  "Perl version: $(perl --version | head -n 2 | tail -n 1)"
    fi
    
    # Enhanced XML support detection
    STEP_BEGIN  "Detecting XML support"
    if [[ -f /usr/include/libxml2/libxml/parser.h || -f /usr/include/libxml/parser.h ]]; then
        XML_SUPPORT=1
        STEP_SUCCESS  "XML development headers found; enabling XML support"
    else
        XML_SUPPORT=0
        STEP_WARNING  "XML development headers not found; consider installing libxml2-devel/libxml2-dev."
    fi
    
    if [[ $XML_SUPPORT -eq 0 ]]; then
        STEP_BEGIN  "Attempting to install libxml2 development headers"
        case "$OS_TYPE" in
            centos|rhel|almalinux|rocky|oracle)
                # Rocky Linux 10, UsingInstall
                if [[ "$OS_TYPE" == "rocky" && $RHEL_VERSION -eq 10 ]]; then
                    STEP_BEGIN  "Rocky Linux 10: trying multiple methods to install libxml2-devel"
                    # 1: try enable CRB repository install
                    $PKG_MANAGER config-manager --set-enabled crb 2>/dev/null || true
                    if $PKG_MANAGER install -y libxml2-devel; then
                        XML_SUPPORT=1
                        STEP_SUCCESS  "Installed libxml2-devel via CRB repository"
                    else
                        # 2: try enable devel repository install
                        $PKG_MANAGER config-manager --set-enabled devel 2>/dev/null || true
                        if $PKG_MANAGER install -y libxml2-devel; then
                            XML_SUPPORT=1
                            STEP_SUCCESS  "Installed libxml2-devel via devel repository"
                        else
                            # 3: try using dnf --allowerasing
                            if $PKG_MANAGER install -y --allowerasing libxml2-devel; then
                                XML_SUPPORT=1
                                STEP_SUCCESS  "Installed libxml2-devel with --allowerasing"
                            else
                                XML_SUPPORT=0
                                STEP_WARNING  "Failed to install libxml2-devel"
                            fi
                        fi
                    fi
                else
                    # system, Using
                    $PKG_MANAGER install -y libxml2-devel || true
                fi
                ;;
            ubuntu|debian)
                $PKG_MANAGER install -y libxml2-dev || true
                ;;
            opensuse*|sles)
                $PKG_MANAGER install -y libxml2-devel || true
                ;;
            arch)
                pacman -S --noconfirm libxml2 || true
                ;;
        esac
        
        # Check
        if [[ -f /usr/include/libxml2/libxml/parser.h || -f /usr/include/libxml/parser.h ]]; then
            XML_SUPPORT=1
            STEP_SUCCESS  "XML development headers installed; enabling XML support"
        else
            XML_SUPPORT=0
            STEP_WARNING  "XML development headers not installed; XML support disabled"
        fi
    fi
        # Enhanced UUID support detection
    STEP_BEGIN  "Detecting UUID support"
    if [[ -f /usr/include/uuid/uuid.h || -f /usr/include/uuid.h || -f /usr/include/linux/uuid.h ]]; then
        UUID_SUPPORT=1
        STEP_SUCCESS  "UUID development headers found; enabling UUID support"
    else
        UUID_SUPPORT=0
        STEP_WARNING  "UUID development headers not found; attempting to install UUID development libraries."
    fi
    
    if [[ $UUID_SUPPORT -eq 0 ]]; then
        STEP_BEGIN  "Installing UUID development libraries"
        case "$OS_TYPE" in
            centos|rhel|almalinux|rocky|fedora|oracle)
                $PKG_MANAGER install -y ${OS_SPECIFIC_DEPS[rhel_uuid]} || true
                ;;
            ubuntu|debian)
                $PKG_MANAGER install -y ${OS_SPECIFIC_DEPS[uuid_dep]} || true
                ;;
            opensuse*|sles)
                $PKG_MANAGER install -y ${OS_SPECIFIC_DEPS[suse_uuid]} || true
                ;;
            arch)
                pacman -S --noconfirm ${OS_SPECIFIC_DEPS[arch_uuid]} || true
                ;;
        esac
        
        # Verify installation
        if [[ -f /usr/include/uuid/uuid.h || -f /usr/include/uuid.h || -f /usr/include/linux/uuid.h ]]; then
            UUID_SUPPORT=1
            STEP_SUCCESS  "UUID development headers installed; enabling UUID support"
        else
            UUID_SUPPORT=0
            STEP_WARNING  "UUID development headers not installed; UUID support disabled"
        fi
    fi
    STEP_SUCCESS  "Build environment validated"
}

setup_user() {
    CURRENT_STAGE "Configure service user and group"
    
    STEP_BEGIN  "Creating service group"
    if ! getent group "$SERVICE_GROUP" &>/dev/null; then
        groupadd "$SERVICE_GROUP" || STEP_FAIL  "Failed to create group: $SERVICE_GROUP"
        STEP_SUCCESS  "Group created: $SERVICE_GROUP"
    else
        STEP_SUCCESS  "Group exists: $SERVICE_GROUP"
    fi

    STEP_BEGIN  "Creating service user"
    if ! id -u "$SERVICE_USER" &>/dev/null; then
        useradd -r -g "$SERVICE_GROUP" -s "/bin/bash" -m -d "/home/$SERVICE_USER" "$SERVICE_USER" || STEP_FAIL  "Failed to create user: $SERVICE_USER"
        STEP_SUCCESS  "User created: $SERVICE_USER"
    else
        STEP_SUCCESS  "User exists: $SERVICE_USER"
    fi
}

compile_install() {
    CURRENT_STAGE "Build and install"

    # Locate repo root: script lives in IvorySQL-AutoInstaller/ under repo root
    local script_dir repo_root
    script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
    repo_root="$(realpath "$script_dir/.." 2>/dev/null || readlink -f "$script_dir/..")"

    if [[ ! -f "$repo_root/configure" || ! -d "$repo_root/src" ]]; then
        STEP_FAIL  "Cannot locate IvorySQL source at repo root: $repo_root (missing 'configure' or 'src')."
    fi

    STEP_BEGIN  "Using local IvorySQL source tree at $repo_root"
    STEP_SUCCESS  "Source ready"

    # Build directly in repo root (in-tree build, per project decision)
    cd "$repo_root" || STEP_FAIL  "Failed to enter source dir: $repo_root"

    STEP_BEGIN  "Validate Perl environment"
    REQUIRED_PERL_MODULES=("FindBin" "IPC::Run")
    MISSING_MODULES=()

    for module in "${REQUIRED_PERL_MODULES[@]}"; do
        if ! perl -M"$module" -e 1 2>/dev/null; then
            MISSING_MODULES+=("$module")
        fi
    done

    if [ ${#MISSING_MODULES[@]} -ne 0 ]; then
        STEP_WARNING  "Missing Perl modules: ${MISSING_MODULES[*]}"
        STEP_BEGIN  "Attempt to install missing Perl modules"
        for module in "${MISSING_MODULES[@]}"; do
            if command -v cpanm >/dev/null 2>&1; then
                cpanm "$module" || STEP_WARNING  "Failed to install Perl module: $module"
            else
                cpan "$module" || STEP_WARNING  "Failed to install Perl module: $module"
            fi
        done
        STEP_SUCCESS  "Attempted to install missing Perl modules"
    fi

    # Check
    for module in "${REQUIRED_PERL_MODULES[@]}"; do
        if ! perl -M"$module" -e 1 2>/dev/null; then
            STEP_FAIL  "Perl module $module still missing; build cannot proceed."
        fi
    done
    STEP_SUCCESS  "Perl environment validated"
    
    STEP_BEGIN  "Configuring build options"
    # always enable readline (dependency ensured)
    CONFIGURE_OPTS="--prefix=$INSTALL_DIR --with-readline"
    STEP_SUCCESS  "Readline support enabled"

    # OpenSSL: enable only if headers+libs exist
    OPENSSL_OK=0
    if [[ -f /usr/include/openssl/ssl.h || -f /usr/local/include/openssl/ssl.h ]]; then
        if command -v pkg-config >/dev/null 2>&1 && pkg-config --exists openssl; then
            OPENSSL_OK=1
        else
            ls /usr/lib64/libcrypto.so* /usr/lib/x86_64-linux-gnu/libcrypto.so* 1>/dev/null 2>&1 && OPENSSL_OK=1 || true
        fi
    fi
    if [[ $OPENSSL_OK -eq 1 ]]; then
        CONFIGURE_OPTS+=" --with-openssl"
        STEP_SUCCESS  "OpenSSL detected; TLS enabled"
    else
        CONFIGURE_OPTS+=" --without-openssl"
        STEP_WARNING  "OpenSSL development files not found; building without TLS support. Install 'openssl-devel' to enable."
    fi

    # Detect ICU via pkg-config (robust across distros)
    if command -v pkg-config >/dev/null 2>&1 && pkg-config --exists icu-uc icu-i18n; then
        CONFIGURE_OPTS+=" --with-icu"
        STEP_SUCCESS  "ICU detected via pkg-config; enabling support"
    else
        CONFIGURE_OPTS+=" --without-icu"
        if ! command -v pkg-config >/dev/null 2>&1; then
            STEP_WARNING  "pkg-config not found; ICU support disabled."
        else
            STEP_WARNING  "ICU .pc files not found; ICU support disabled."
        fi
    fi

    # ===== UUID support (uuid-ossp) =====
    # Prefer e2fs/libuuid on Linux (provided by util-linux)
    UUID_HDR_OK=0
    [[ -f /usr/include/uuid/uuid.h || -f /usr/local/include/uuid/uuid.h ]] && UUID_HDR_OK=1
    if [[ $UUID_HDR_OK -eq 0 ]]; then
        STEP_BEGIN  "UUID headers not found; attempting one-time installation"
        case "$OS_TYPE" in
            centos|rhel|almalinux|rocky|oracle)
                $PKG_MANAGER install -y libuuid-devel 2>/dev/null || true
                ;;
            ubuntu|debian)
                $PKG_MANAGER install -y uuid-dev 2>/dev/null || true
                ;;
            opensuse*|sles)
                $PKG_MANAGER install -y libuuid-devel 2>/dev/null || true
                ;;
            arch)
                pacman -S --noconfirm util-linux 2>/dev/null || true
                ;;
        esac
        [[ -f /usr/include/uuid/uuid.h || -f /usr/local/include/uuid/uuid.h ]] && UUID_HDR_OK=1
    fi
    if [[ $UUID_HDR_OK -eq 1 ]]; then
        CONFIGURE_OPTS+=" --with-uuid=e2fs"
        STEP_SUCCESS  "UUID headers found; enabling uuid-ossp via e2fs/libuuid"
    else
        CONFIGURE_OPTS+=" --without-uuid"
        STEP_WARNING  "UUID headers still missing; uuid-ossp will be disabled. Install 'libuuid-devel' (RHEL family) or 'uuid-dev' (Deb/Ub) to enable."
    fi

    # XML support Configuration
    if [[ $XML_SUPPORT -eq 1 ]]; then
        CONFIGURE_OPTS+=" --with-libxml"
        STEP_SUCCESS  "XML support enabled"
    else
        CONFIGURE_OPTS+=" --without-libxml"
        STEP_WARNING  "libxml2 development files not found; XML support disabled."
    fi
    
    # Detect TCL
    tcl_paths=("/usr/include/tcl.h" "/usr/include/tcl8.6/tcl.h")
    if [[ -f "${tcl_paths[0]}" || -f "${tcl_paths[1]}" ]]; then
        CONFIGURE_OPTS+=" --with-tcl"
        STEP_SUCCESS  "TCL development headers found, enabling support"
    else
        CONFIGURE_OPTS+=" --without-tcl"
        STEP_WARNING  "Tcl development headers not found; Tcl support disabled."
    fi
    
    # Detect Perl
    perl_paths=("/usr/bin/perl" "/usr/local/bin/perl")
    if command -v perl >/dev/null; then
        perl_header=$(find /usr -name perl.h 2>/dev/null | head -n1)
        if [[ -n "$perl_header" ]]; then
            CONFIGURE_OPTS+=" --with-perl"
            STEP_SUCCESS  "Perl development headers found; enabling support"
        else
            CONFIGURE_OPTS+=" --without-perl"
            STEP_WARNING  "perl.h not found; Perl support disabled."
        fi
    else
        STEP_WARNING  "Perl interpreter not found; Perl support disabled."
        CONFIGURE_OPTS+=" --without-perl"
    fi
    
    echo  "Configure options: $CONFIGURE_OPTS"
    ./configure $CONFIGURE_OPTS || {
        echo  "config.log (tail):"
        tail -20 config.log || true
        STEP_FAIL  "Configure step failed."
    }
    STEP_SUCCESS  "Configuration completed."
      STEP_BEGIN  "Applying flex/lex.backup compatibility fix"
    # On some distros flex does not emit 'lex.backup', but the build rules still try 'rm lex.backup'
    # Convert those calls to 'rm -f lex.backup' to avoid hard failures when the file is absent.
    for mf in "src/Makefile.global" "src/bin/psql/Makefile"; do
        if [[ -f "$mf" ]] && grep -q "lex.backup" "$mf"; then
            # Use -E for ERE; replace 'rm  lex.backup' (with any spaces) with a tolerant form.
            sed -i -E 's/rm[[:space:]]+lex\.backup/rm -f lex.backup/g' "$mf" || true
        fi
    done
    # Optional: show what we touched (silent if nothing matched)
    if grep -R --include=Makefile\* -n "lex.backup" src 1>/dev/null 2>&1; then
        echo  "Makefile entries referencing 'lex.backup' remain (now tolerant)."
    fi
    STEP_SUCCESS  "Compatibility fix applied"
    
    STEP_BEGIN  "Building (using $(nproc) threads)"
    make -j$(nproc) || STEP_FAIL  "Build failed."
    STEP_SUCCESS  "Build completed"
    
    STEP_BEGIN  "Installing files"
    make install || STEP_FAIL  "Installation step failed."
    chown -R "$SERVICE_USER:$SERVICE_GROUP" "$INSTALL_DIR" || STEP_FAIL  "Set install directory ownership failed."
}


# Verify ivorysql_ora runtime deps (libxml2 etc.); disable ORA if missing
check_ora_runtime() {
    local so="$INSTALL_DIR/lib/postgresql/ivorysql_ora.so"
    if [[ -f "$so" ]]; then
        if command -v ldd >/dev/null 2>&1; then
            # If any dependency is 'not found', we disable XML/ORA
            if ldd "$so" | grep -q "not found"; then
                XML_SUPPORT=0
                STEP_WARNING  "ivorysql_ora dependency missing (ldd reports 'not found'); will skip ivorysql_ora during initdb."
            fi
            # If specifically looks for unusual SONAME (e.g., libxml2.so.16) and not available, also disable
            if ldd "$so" | grep -E "libxml2\.so\.[0-9]+" | grep -q "not found"; then
                XML_SUPPORT=0
                STEP_WARNING  "libxml2 runtime not found for ivorysql_ora; will skip ivorysql_ora during initdb."
            fi
        else
            # Conservative: if we cannot check, don't break install—assume OK
            true
        fi
    fi
}

post_install() {
    CURRENT_STAGE "Post-install configuration"
    # Check runtime dependencies for ivorysql_ora (libxml2 etc.) and disable if broken
    check_ora_runtime
    
    STEP_BEGIN  "Preparing data directory"
    mkdir -p "$DATA_DIR" || STEP_FAIL  "Failed to create data directory: $DATA_DIR"
    
    if [ -n "$(ls -A "$DATA_DIR" 2>/dev/null)" ]; then
        STEP_BEGIN  "Clearing data directory"
        svc_stop ivorysql 2>/dev/null || true
        rm -rf "${DATA_DIR:?}"/* "${DATA_DIR:?}"/.[^.]* "${DATA_DIR:?}"/..?* 2>/dev/null || true
        STEP_SUCCESS  "Data directory cleared."
    else
        STEP_SUCCESS  "Data directory is empty"
    fi
    
    chown "$SERVICE_USER:$SERVICE_GROUP" "$DATA_DIR"

    STEP_BEGIN  "Setting environment variables for service user"
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
    
    su - "$SERVICE_USER" -c "source ~/.bash_profile" || STEP_WARNING  "Failed to load service user profile (continuing)."
    STEP_SUCCESS  "Environment variables set"

    STEP_BEGIN  "Initializing database (initdb)"
    INIT_LOG="${LOG_DIR}/initdb_${TIMESTAMP}.log"

    # Decide IvorySQL init mode: oracle (default) or pg (fallback when XML/ORA runtime missing)
    INIT_MODE="oracle"
    if [[ $XML_SUPPORT -eq 0 ]]; then
        INIT_MODE="pg"
        STEP_WARNING  "XML/ORA runtime unavailable; switching initdb to PG mode (-m pg) to avoid loading ivorysql_ora during bootstrap."
    fi

    INIT_CMD="env PGDATA='$DATA_DIR' \

  LD_LIBRARY_PATH='$INSTALL_DIR/lib:$INSTALL_DIR/lib/postgresql:${LD_LIBRARY_PATH:-}' \
  PATH='$INSTALL_DIR/bin:${PATH:-/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin}' \
  '$INSTALL_DIR/bin/initdb' \
    -D '$DATA_DIR' \
    --locale=C \
    --encoding=UTF8 \
    -m "$INIT_MODE" \
    --debug"

    if command -v runuser >/dev/null 2>&1; then
      runuser -u "$SERVICE_USER" -- bash -c "$INIT_CMD" > "$INIT_LOG" 2>&1 \
        || { echo "======= initdb log (tail) ======="; tail -n 200 "$INIT_LOG" || true; STEP_FAIL "initdb failed"; }
    else
      su -s /bin/bash - "$SERVICE_USER" -c "$INIT_CMD" > "$INIT_LOG" 2>&1 \
        || { echo "======= initdb log (tail) ======="; tail -n 200 "$INIT_LOG" || true; STEP_FAIL "initdb failed"; }
    fi

    if grep -q "FATAL" "$INIT_LOG"; then
        echo  "======= FATAL excerpts ======="
        grep -A 10 "FATAL" "$INIT_LOG" || true
        STEP_FAIL  "Detected FATAL errors in initdb log."
    fi

    STEP_SUCCESS  "Database initialized"

    STEP_BEGIN  "Configuring system service"
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
        STEP_SUCCESS  "Systemd unit installed"
    else
        STEP_WARNING  "systemd not detected; skipping service unit creation"
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
        STEP_SUCCESS  "Helper script created: $INSTALL_DIR/ivorysql-ctl"
    fi
}


verify_installation() {
    CURRENT_STAGE "Validate installation"

    STEP_BEGIN  "Starting service"
    svc_start ivorysql || {
        echo  "======= systemctl status ======="
        svc_status_dump ivorysql
        echo  "======= recent logs ======="
        svc_logs_tail ivorysql
        STEP_FAIL  "Failed to start service."
    }
    STEP_SUCCESS  "Service started; checking readiness..."

    
    get_pgport() {
        
        local pidf="$DATA_DIR/postmaster.pid"
        [[ -r "$pidf" ]] && awk 'NR==4{print;exit}' "$pidf" || echo 5432
    }

    db_is_ready() {
        # 1) try pg_isready on unix socket and localhost
        for port in 5432 1521 5433; do
            su -s /bin/bash - "$SERVICE_USER" -c "env LD_LIBRARY_PATH='$INSTALL_DIR/lib:$INSTALL_DIR/lib/postgresql:${LD_LIBRARY_PATH:-}' PATH='$INSTALL_DIR/bin:${PATH:-/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin}' $INSTALL_DIR/bin/pg_isready -q -h /tmp -p $port -t 1" >/dev/null 2>&1 \
              && return 0
            su -s /bin/bash - "$SERVICE_USER" -c "env LD_LIBRARY_PATH='$INSTALL_DIR/lib:$INSTALL_DIR/lib/postgresql:${LD_LIBRARY_PATH:-}' PATH='$INSTALL_DIR/bin:${PATH:-/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin}' $INSTALL_DIR/bin/pg_isready -q -h 127.0.0.1 -p $port -t 1" >/dev/null 2>&1 \
              && return 0
        done

        return 1
    }

    STEP_BEGIN  "Checking service readiness"
    
    ready=0
    for i in $(seq 1 90); do
        if svc_is_active ivorysql || db_is_ready; then
            STEP_SUCCESS   "Service is ready"
            ready=1
            break
        fi
        sleep 1
    done

    if [[ "$ready" -ne 1 ]]; then
        svc_status_dump ivorysql
        svc_logs_tail ivorysql >&2
        STEP_FAIL  "Service readiness check timed out."
    fi

    # Validate extension
    STEP_BEGIN  "Validating extensions"
    if su - "$SERVICE_USER" -c "$INSTALL_DIR/bin/psql -d postgres -Atc \"SELECT 1\"" >/dev/null 2>&1; then
        STEP_SUCCESS  "Basic connectivity OK"
    else
        STEP_WARNING  "psql connectivity failed; please review logs."
    fi
}



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
        SERVICE_HELP="$INSTALL_DIR/ivorysql-ctl {start|stop|reload}"
        LOG_FOLLOW="tail -f $LOG_DIR/*.log"
    fi
    # ----------------------------------------------------------------------

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
    echo  "Note: EL10 support included"
    
    SECONDS=0
    check_root          # 1. Check root permission
    load_config         # 2. Load configuration
    detect_environment  # 3. Detect environment
    setup_user          # 4. Create user & group
    init_logging        # 5. Initialize logging
    install_dependencies # 6. Install dependencies
    compile_install     # 7. Build & install
    post_install        # 8. Post-install configuration
    verify_installation # 9. Validate installation
    show_success_message
}

main "$@"
