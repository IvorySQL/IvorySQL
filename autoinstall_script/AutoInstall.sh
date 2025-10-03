#!/usr/bin/env bash

set -Eeuo pipefail

# ---------------- Globals ----------------
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
SECONDS=0

OS_ID=""; OS_VER=""; PKG=""; EL_MAJOR=""
XML_SUPPORT=0; UUID_SUPPORT=0

# TAP tests switch: default off (do not install IPC::Run)
RUN_TESTS="${RUN_TESTS:-0}"
INSTALL_DIR=""; DATA_DIR=""; SERVICE_USER=""; SERVICE_GROUP=""; LOG_DIR=""
INIT_MODE="${INIT_MODE:-oracle}"          # oracle | pg (IvorySQL default is oracle)
CASE_MODE="${CASE_MODE:-interchange}"     # interchange | normal | lowercase
READY_TIMEOUT="${READY_TIMEOUT:-90}"

LAST_STAGE=""

# ---------------- Printing ----------------
CURRENT_STAGE() { LAST_STAGE="$1"; printf "\n[%s] %s\n" "$(date '+%H:%M:%S')" "$1"; }
STEP()          { printf "  -> %s...\n" "$1"; }
OK()            { printf "  OK: %s\n" "$1"; }
WARN()          { printf "  WARN: %s\n" "$1"; }
FAIL() {
  printf "  ERROR: %s\n" "${1:-Unexpected error}" >&2
  [ -n "$LAST_STAGE" ] && printf "  Stage: %s\n" "$LAST_STAGE" >&2
  hint
  exit 1
}

hint() {
  cat >&2 <<EOF

---- Troubleshooting ----
1) Service status:
     systemctl status ivorysql
     (no systemd): \$INSTALL_DIR/ivorysql-ctl status

2) Logs:
     journalctl -u ivorysql --no-pager | tail -n 120
     or: tail -n 120 \$LOG_DIR/*.log

3) Install logs:
     \$LOG_DIR/install_${TIMESTAMP}.log
     \$LOG_DIR/error_${TIMESTAMP}.log

4) Connectivity:
     pg_isready -h 127.0.0.1 -p \${PGPORT:-5432}

5) Permissions:
     ls -ld "$DATA_DIR" && ls -l "$DATA_DIR"
-------------------------
EOF
}

trap_err() {
  printf "ERROR: Installation failed\n" >&2
  [ -n "$LAST_STAGE" ] && printf "Stage: %s\n" "$LAST_STAGE" >&2
  printf "Line : %s\nCmd  : %s\n" "$1" "$2" >&2
  hint
  exit 1
}
trap 'trap_err "${LINENO}" "${BASH_COMMAND}"' ERR

cmd_exists(){ command -v "$1" >/dev/null 2>&1; }
has_systemd(){ cmd_exists systemctl && [ -d /run/systemd/system ]; }

retry() { 
  local t="$1"; shift || true
  local n=0
  until "$@"; do
    n=$((n+1)); [ "$n" -ge "$t" ] && return 1
    sleep $((2**n))
  done
}

# ---------------- Steps ----------------
check_root(){
  CURRENT_STAGE "Privilege check"
  STEP "Checking effective uid"
  [ "$(id -u)" -eq 0 ] || FAIL "Root privileges are required (use sudo)."
  OK "Root privileges confirmed"
}

load_config(){
  CURRENT_STAGE "Load configuration"
  local dir cfg
  dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
  cfg="${dir}/ivorysql.conf"

  STEP "Checking config file"
  [ -f "$cfg" ] || FAIL "Config not found: $cfg"
  OK "Config found"

  STEP "Sourcing config"
  if grep -Evq '^\s*([A-Z_][A-Z0-9_]*\s*=\s*.*|#|$)' "$cfg"; then
    FAIL "Invalid lines detected in config (only KEY=VALUE, # comments, blanks)."
  fi
  . "$cfg"
  OK "Config loaded"

  STEP "Validating required keys"
  for k in INSTALL_DIR DATA_DIR SERVICE_USER SERVICE_GROUP LOG_DIR; do
    [ -n "${!k:-}" ] || FAIL "Missing config key: $k"
  done
  OK "Config validated"
}

prepare_fs_and_users(){
  CURRENT_STAGE "Prepare filesystem and identities"
  for key in INSTALL_DIR DATA_DIR LOG_DIR; do
    local val="${!key}"
    [[ "$val" =~ ^/[^[:space:]]+$ ]] || FAIL "$key must be absolute path (got '$val')"
    [ -e "$val" ] && [ -f "$val" ] && FAIL "$key points to a file: $val"
    mkdir -p "$val" || FAIL "Cannot create: $val"
  done

  getent group "$SERVICE_GROUP" >/dev/null || groupadd "$SERVICE_GROUP"
  id -u "$SERVICE_USER" >/dev/null 2>&1 || \
    useradd -r -g "$SERVICE_GROUP" -s /bin/bash -m -d "/home/$SERVICE_USER" "$SERVICE_USER"

  chown -R "$SERVICE_USER:$SERVICE_GROUP" "$LOG_DIR" || true
  OK "Directories and identities are ready"
}

init_logging(){
  CURRENT_STAGE "Enable logging"
  mkdir -p "$LOG_DIR" || FAIL "Cannot create log dir: $LOG_DIR"
  exec > >(tee -a "${LOG_DIR}/install_${TIMESTAMP}.log")
  exec 2> >(tee -a "${LOG_DIR}/error_${TIMESTAMP}.log" >&2)
  OK "Log redirection enabled"
}

detect_os(){
  CURRENT_STAGE "Detect OS"
  [ -f /etc/os-release ] || FAIL "Missing /etc/os-release"
  . /etc/os-release
  OS_ID="$ID"; OS_VER="${VERSION_ID:-}"

  case "$OS_ID" in
    rhel|rocky|almalinux|oracle|ol|oraclelinux|centos)
      EL_MAJOR="$(echo "$OS_VER" | cut -d. -f1)"
      [[ "$EL_MAJOR" =~ ^(8|9|10)$ ]] || FAIL "Unsupported EL major: $EL_MAJOR"
      PKG="$(command -v dnf >/dev/null 2>&1 && echo dnf || echo yum)"
      ;;
    ubuntu)
      local mj="${OS_VER%%.*}"
      [[ "$mj" =~ ^(20|22|24)$ ]] || FAIL "Unsupported Ubuntu: $OS_VER"
      PKG="apt-get"
      ;;
    debian)
      local mj="${OS_VER%%.*}"
      [[ "$mj" =~ ^(12|13)$ ]] || FAIL "Unsupported Debian: $OS_VER"
      PKG="apt-get"
      ;;
    *)
      FAIL "Unsupported or unrecognized OS: $OS_ID $OS_VER"
      ;;
  esac
  OK "OS: ${PRETTY_NAME:-$OS_ID $OS_VER}; Package manager: $PKG"
}

enable_el_repos(){
  case "$OS_ID" in
    rocky|almalinux|centos)
      if cmd_exists dnf; then
        retry 3 dnf install -y epel-release dnf-plugins-core || true
        if [ "$EL_MAJOR" = "8" ]; then
          dnf config-manager --set-enabled powertools >/dev/null 2>&1 || true
        else
          dnf config-manager --set-enabled crb        >/dev/null 2>&1 || true
        fi
      else
        retry 3 yum install -y epel-release yum-utils || true
        yum config-manager --enable crb >/dev/null 2>&1 || \
        yum config-manager --enable powertools >/dev/null 2>&1 || true
      fi
      ;;
    oracle|ol|oraclelinux)
      if cmd_exists dnf; then
        retry 3 dnf -y install dnf-plugins-core || true
        dnf config-manager --enable "ol${EL_MAJOR}_codeready_builder" >/dev/null 2>&1 || true
        retry 3 dnf -y install "oracle-epel-release-el${EL_MAJOR}" || true
        dnf clean all >/dev/null 2>&1 || true
        dnf makecache >/dev/null 2>&1 || true
      else
        retry 3 yum -y install yum-utils || true
        yum-config-manager --enable "ol${EL_MAJOR}_codeready_builder" >/dev/null 2>&1 || true
        retry 3 yum -y install "oracle-epel-release-el${EL_MAJOR}" || true
        yum makecache >/dev/null 2>&1 || true
      fi
      ;;
    *) : ;;
  esac

}

install_deps(){
  CURRENT_STAGE "Install build and runtime dependencies"

  STEP "Refresh package metadata"
  case "$PKG" in
    dnf|yum) retry 3 "$PKG" -y makecache || true ;;
    apt-get) export DEBIAN_FRONTEND=noninteractive; retry 3 "$PKG" update || true ;;
  esac
  OK "Metadata refreshed"

  if [[ "$OS_ID" =~ ^(rocky|almalinux|centos|oracle|ol|oraclelinux)$ ]]; then
    STEP "Enable optional repos (best effort: EPEL/CRB/PowerTools)"
    enable_el_repos || true
    case "$PKG" in dnf|yum) retry 3 "$PKG" -y makecache || true ;; esac
    OK "Optional repos processed"
  fi

  STEP "Install compilers and headers"
  case "$PKG" in
    dnf|yum)
    
      if [ "$PKG" = "dnf" ]; then retry 3 dnf group install -y "Development Tools" || true
      else retry 3 yum groupinstall -y "Development Tools" || true; fi

     
      EL_PKGS=(
        gcc make flex bison
        readline-devel zlib-devel openssl-devel
        libxml2 libxml2-devel libxslt libxslt-devel
        libicu libicu-devel libuuid libuuid-devel
        perl
        python3-devel tcl-devel pkgconf-pkg-config
        gettext ca-certificates which
      )

      if ! rpm -q curl-minimal >/dev/null 2>&1; then
        EL_PKGS+=(curl)
      fi

   
      if ! dnf install -y --allowerasing "${EL_PKGS[@]}"; then
        # Try a softer fallback on older yum
        if [ "$PKG" = "yum" ]; then
          yum install -y "${EL_PKGS[@]}" || FAIL "Package installation failed on EL (yum)"
        else
          FAIL "Package installation failed on EL (dnf). Consider enabling CRB/EPEL or using a fuller base image."
        fi
      fi


      if [ "${RUN_TESTS:-0}" = "1" ]; then
        if [ "$PKG" = "dnf" ]; then
          dnf install -y --allowerasing perl-IPC-Run || true
          dnf install -y --allowerasing perl-App-cpanminus || true
        else
          yum install -y perl-IPC-Run || true
          yum install -y perl-App-cpanminus || true
        fi
      fi
      ;;

    apt-get)
      APT_PKGS=(
        build-essential flex bison
        libreadline-dev zlib1g-dev libssl-dev
        libxml2 libxml2-dev libxslt1-dev
        libicu-dev uuid-dev
        perl
        python3-dev tcl-dev gettext
        pkg-config curl ca-certificates gnupg dirmngr
      )
    apt-get install -y --no-install-recommends "${APT_PKGS[@]}" \
      || FAIL "Package installation failed on Debian/Ubuntu"

    if [ "$RUN_TESTS" = "1" ]; then
      apt-get install -y --no-install-recommends libipc-run-perl cpanminus || true
    fi
      ;;
  esac
  OK "Dependencies installed"

  # ---- Post-install checks: headers and Perl modules ----
  STEP "Probe feature headers"
  if [ -f /usr/include/libxml2/libxml/parser.h ] || [ -f /usr/include/libxml/parser.h ]; then
    XML_SUPPORT=1; OK "libxml2 headers: found"
  else
    XML_SUPPORT=0; WARN "libxml2 headers: not found (XML features disabled)"
  fi
  if [ -f /usr/include/uuid/uuid.h ] || [ -f /usr/local/include/uuid/uuid.h ]; then
    UUID_SUPPORT=1; OK "libuuid headers: found"
  else
    UUID_SUPPORT=0; WARN "libuuid headers: not found (uuid-ossp disabled)"
  fi

  STEP "Verify Perl modules (FindBin${RUN_TESTS:+, IPC::Run})"

  if ! perl -MFindBin -e1 2>/dev/null; then
    case "$PKG" in
      dnf|yum) dnf install -y --allowerasing perl || yum install -y perl || true ;;
      apt-get) apt-get install -y perl || true ;;
    esac
  fi
  perl -MFindBin -e1 2>/dev/null || FAIL "Perl core module FindBin still missing"

  if [ "$RUN_TESTS" = "1" ]; then
  if ! perl -MIPC::Run -e1 2>/dev/null; then
    case "$PKG" in
      dnf|yum) dnf install -y --allowerasing perl-IPC-Run || yum install -y perl-IPC-Run || true ;;
      apt-get) apt-get install -y libipc-run-perl || true ;;
    esac
  fi
  if ! perl -MIPC::Run -e1 2>/dev/null; then
    if command -v cpanm >/dev/null 2>&1; then
      cpanm -n IPC::Run || true
    fi
  fi
  perl -MIPC::Run -e1 2>/dev/null || FAIL "Perl module IPC::Run still missing (check repos or enable EPEL/CRB)"
fi
  OK "Perl environment ready"
}


compile_install(){
  CURRENT_STAGE "Build and install IvorySQL (from source)"
  local script_dir src_root
  script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
  src_root="$(readlink -f "$script_dir/..")"

  [ -f "$src_root/configure" ] && [ -d "$src_root/src" ] || FAIL "Cannot locate IvorySQL source: $src_root"

  STEP "Configure"
  local OPTS="--prefix=$INSTALL_DIR --with-readline"
  if { cmd_exists pkg-config && pkg-config --exists openssl; } || [ -f /usr/include/openssl/ssl.h ]; then
    OPTS+=" --with-openssl"
  else
    OPTS+=" --without-openssl"; WARN "OpenSSL dev headers not found; TLS disabled"
  fi
  if { cmd_exists pkg-config && pkg-config --exists icu-uc icu-i18n; }; then
    OPTS+=" --with-icu"
  else
    OPTS+=" --without-icu"; WARN "ICU not found; ICU disabled"
  fi
  if [ "$UUID_SUPPORT" -eq 1 ]; then OPTS+=" --with-uuid=e2fs"; else OPTS+=" --without-uuid"; fi
  if [ "$XML_SUPPORT"  -eq 1 ]; then OPTS+=" --with-libxml"; else OPTS+=" --without-libxml"; fi

  local CFG_CFLAGS=""
  case "$OS_ID" in
    ubuntu|debian) CFG_CFLAGS="$CFG_CFLAGS -fPIE" ;;
    *) : ;;
  esac

  echo "  Configure options: $OPTS"
  (cd "$src_root" && CFLAGS="${CFLAGS:-} ${CFG_CFLAGS}" ./configure $OPTS) \
    || { tail -n 120 "$src_root/config.log" || true; FAIL "Configure failed"; }
  OK "Configure completed"

  STEP "Clean previous build outputs"
  (cd "$src_root" && make clean) || true
  OK "Clean completed"

  STEP "Build (parallel)"
  local JOBS
  if cmd_exists nproc; then JOBS="$(nproc)"; else JOBS="$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 2)"; fi
  (cd "$src_root" && make -j"$JOBS") || FAIL "Build failed"
  OK "Build completed"

  STEP "Install"
  (cd "$src_root" && make install) || FAIL "Install failed"
  chown -R "$SERVICE_USER:$SERVICE_GROUP" "$INSTALL_DIR" || true
  OK "Installed to $INSTALL_DIR"
}

init_db_and_service(){
  CURRENT_STAGE "Initialize database and install service"

  STEP "Prepare data directory"
  mkdir -p "$DATA_DIR"
  chown -R "$SERVICE_USER:$SERVICE_GROUP" "$DATA_DIR"
  chmod 750 "$DATA_DIR"
  
  if [ -n "$(find "$DATA_DIR" -mindepth 1 -prune -print -quit 2>/dev/null)" ]; then
    WARN "Data directory is not empty; cleaning it for re-init"
    su -s /bin/bash - "$SERVICE_USER" -c "rm -rf '${DATA_DIR:?}/'* '${DATA_DIR:?}/'.[!.]* '${DATA_DIR:?}/'..?*" 2>/dev/null || true
  fi
  OK "Data directory ready"

  STEP "Setup service user environment"
  local HOME_DIR; HOME_DIR="$(getent passwd "$SERVICE_USER" | cut -d: -f6)"
  cat > "$HOME_DIR/.bash_profile" <<EOF
export PATH="$INSTALL_DIR/bin:\${PATH:-/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin}"
export PGDATA="$DATA_DIR"
export LD_LIBRARY_PATH="$INSTALL_DIR/lib:$INSTALL_DIR/lib/postgresql:\${LD_LIBRARY_PATH:-}"
EOF
  chown "$SERVICE_USER:$SERVICE_GROUP" "$HOME_DIR/.bash_profile"
  chmod 600 "$HOME_DIR/.bash_profile"
  OK "Service user environment configured"

  STEP "Run initdb (mode and case options)"
  
  local INIT_LOG="$LOG_DIR/initdb_${TIMESTAMP}.log"
  local INIT_CMD="env PATH='$INSTALL_DIR/bin:\$PATH' LD_LIBRARY_PATH='$INSTALL_DIR/lib:$INSTALL_DIR/lib/postgresql:\$LD_LIBRARY_PATH' \
    '$INSTALL_DIR/bin/initdb' -D '$DATA_DIR' --locale=C --encoding=UTF8 -m '$INIT_MODE' -C '$CASE_MODE'"
  if cmd_exists runuser; then
    runuser -u "$SERVICE_USER" -- bash -lc "$INIT_CMD" >"$INIT_LOG" 2>&1 \
      || { tail -n 200 "$INIT_LOG" || true; FAIL "initdb failed"; }
  else
    su -s /bin/bash - "$SERVICE_USER" -c "$INIT_CMD" >"$INIT_LOG" 2>&1 \
      || { tail -n 200 "$INIT_LOG" || true; FAIL "initdb failed"; }
  fi
  OK "Database initialized (mode: $INIT_MODE, case: $CASE_MODE)"

  STEP "Install service"
  if has_systemd; then
    cat >/etc/systemd/system/ivorysql.service <<EOF
[Unit]
Description=IvorySQL Database Server
After=network.target local-fs.target

[Service]
Type=forking
User=$SERVICE_USER
Group=$SERVICE_GROUP
Environment=PGDATA=$DATA_DIR
Environment=LD_LIBRARY_PATH=$INSTALL_DIR/lib:$INSTALL_DIR/lib/postgresql
PIDFile=$DATA_DIR/postmaster.pid
ExecStart=$INSTALL_DIR/bin/pg_ctl start  -D \${PGDATA} -s -w -t ${READY_TIMEOUT}
ExecStop=$INSTALL_DIR/bin/pg_ctl stop   -D \${PGDATA} -s -m fast
ExecReload=$INSTALL_DIR/bin/pg_ctl reload -D \${PGDATA}
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable ivorysql
    OK "systemd unit installed"
  else
    cat >"$INSTALL_DIR/ivorysql-ctl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
PGDATA="${PGDATA:-__PGDATA__}"
INSTALL_DIR="__INSTALL__"
LOG_DIR="__LOG__"
export PATH="$INSTALL_DIR/bin:${PATH:-/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin}"
export LD_LIBRARY_PATH="$INSTALL_DIR/lib:$INSTALL_DIR/lib/postgresql:${LD_LIBRARY_PATH:-}"
case "${1:-}" in
  start)  "$INSTALL_DIR/bin/pg_ctl" start  -D "$PGDATA" -s -w -t __READY_TIMEOUT__ -l "$LOG_DIR/server_ctl.log" ;;
  stop)   "$INSTALL_DIR/bin/pg_ctl" stop   -D "$PGDATA" -s -m fast ;;
  reload) "$INSTALL_DIR/bin/pg_ctl" reload -D "$PGDATA" ;;
  status) "$INSTALL_DIR/bin/pg_ctl" status -D "$PGDATA" || true ;;
  *) echo "Usage: $0 {start|stop|reload|status}"; exit 1 ;;
esac
EOF
    sed -i "s#__PGDATA__#$DATA_DIR#g; s#__INSTALL__#$INSTALL_DIR#g; s#__LOG__#$LOG_DIR#g; s#__READY_TIMEOUT__#${READY_TIMEOUT}#g" "$INSTALL_DIR/ivorysql-ctl"
    chmod +x "$INSTALL_DIR/ivorysql-ctl"
    OK "Helper created: $INSTALL_DIR/ivorysql-ctl"
  fi
}

start_and_verify(){
  CURRENT_STAGE "Start service and verify readiness"
  STEP "Start service"
  if has_systemd; then
    systemctl start ivorysql || { systemctl status ivorysql -l --no-pager || true; FAIL "Failed to start service"; }
  else
    local CMD
    CMD="env LD_LIBRARY_PATH='$INSTALL_DIR/lib:$INSTALL_DIR/lib/postgresql:${LD_LIBRARY_PATH:-}' \
         PATH='$INSTALL_DIR/bin:${PATH:-/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin}' \
         '$INSTALL_DIR/bin/pg_ctl' start -D '$DATA_DIR' -s -w -t ${READY_TIMEOUT} -l '$LOG_DIR/server_${TIMESTAMP}.log'"
    if cmd_exists runuser; then runuser -u "$SERVICE_USER" -- bash -lc "$CMD"
    else su -s /bin/bash - "$SERVICE_USER" -c "$CMD"; fi
  fi
  OK "Service started"

  STEP "Wait for readiness (timeout: ${READY_TIMEOUT}s)"
  local pid="$DATA_DIR/postmaster.pid" port="5432" ok=0
  [ -r "$pid" ] && port="$(awk 'NR==4{print;exit}' "$pid" 2>/dev/null || echo 5432)"
  for _ in $(seq 1 "$READY_TIMEOUT"); do
    su -s /bin/bash - "$SERVICE_USER" -c "env PATH='$INSTALL_DIR/bin:\$PATH' $INSTALL_DIR/bin/pg_isready -q -h /tmp -p $port -t 1" \
      || su -s /bin/bash - "$SERVICE_USER" -c "env PATH='$INSTALL_DIR/bin:\$PATH' $INSTALL_DIR/bin/pg_isready -q -h /var/run/postgresql -p $port -t 1" \
      || su -s /bin/bash - "$SERVICE_USER" -c "env PATH='$INSTALL_DIR/bin:\$PATH' $INSTALL_DIR/bin/pg_isready -q -h 127.0.0.1 -p $port -t 1" \
      && { ok=1; break; }
    sleep 1
  done
  [ "$ok" -eq 1 ] || { has_systemd && systemctl status ivorysql -l --no-pager || true; FAIL "Readiness check timed out"; }
  OK "Ready (port: $port)"

  STEP "Basic SQL connectivity"
  su - "$SERVICE_USER" -c "$INSTALL_DIR/bin/psql -d postgres -Atc 'SELECT 1'" >/dev/null 2>&1 \
    && OK "Connectivity confirmed" || WARN "psql test failed; check logs"
}

summary(){
  printf "\n================ Installation succeeded ================\n"
  local SERVICE_STATUS SERVICE_HELP LOG_FOLLOW
  if has_systemd; then
    systemctl is-active --quiet ivorysql && SERVICE_STATUS="active" || SERVICE_STATUS="inactive"
    SERVICE_HELP='systemctl [start|stop|status|reload] ivorysql'
    LOG_FOLLOW='journalctl -u ivorysql -f'
  else
    SERVICE_STATUS="no systemd (use helper)"
    SERVICE_HELP="$INSTALL_DIR/ivorysql-ctl {start|stop|reload|status}"
    LOG_FOLLOW="tail -f $LOG_DIR/*.log"
  fi
  cat <<EOF
Install directory: $INSTALL_DIR
Data directory   : $DATA_DIR
Log directory    : $LOG_DIR
Service          : $SERVICE_STATUS
Version          : $("$INSTALL_DIR/bin/postgres" --version || echo unknown)

Useful commands:
  $SERVICE_HELP
  $LOG_FOLLOW
  sudo -u $SERVICE_USER '$INSTALL_DIR/bin/psql'

Install time     : $(date)
Elapsed          : ${SECONDS}s
OS               : $OS_ID $OS_VER
==========================================================
EOF
}

main(){
  CURRENT_STAGE "IvorySQL source build and install"
  check_root
  load_config
  prepare_fs_and_users
  init_logging
  detect_os
  install_deps
  compile_install
  init_db_and_service
  start_and_verify
  summary
}
main "$@"
