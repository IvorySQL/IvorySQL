English | [中文](README_CN.md)
# IvorySQL Source Install Script — Usage Guide (English)


## 1. What this is

This is a non-interactive, PR/CI‑friendly installer that **builds IvorySQL from source** and sets it up as a service.  
All output is **ASCII, English‑only** with clear staged logs.

- Script expects to live **inside** your source tree at `autoinstall_script/`:
  ```text
  IvorySQL/                # the source tree root
  ├─ configure
  ├─ src/
  └─ autoinstall_script/
     ├─ AutoInstall.sh
     └─ ivorysql.conf
  ```
- The script locates the source root as the **parent** directory of its own folder.

Run:
```bash
cd autoinstall_script
sudo bash ./AutoInstall.sh
```

---

## 2. Supported Platforms

- **EL family**: RHEL / Rocky / Alma / Oracle Linux **8 / 9 / 10**
- **CentOS Stream**: **9 / 10**
- **Ubuntu**: **20.04 / 22.04 / 24.04**
- **Debian**: **12 (Bookworm) / 13 (Trixie)**

The script auto-detects the OS (`/etc/os-release`) and selects `dnf|yum` or `apt-get`. For EL/OL, it best‑effort enables **CRB / PowerTools / CodeReady Builder** and **EPEL** when applicable.

> **Root required**: the script must be run as root (or with sudo).

---

## 3. Configuration (`ivorysql.conf`)

Place `ivorysql.conf` in the **same directory** as the script. It must contain **only** `KEY=VALUE` lines, comments (`#`), or blank lines.

**Required keys** (absolute paths are enforced and created if missing):

| Key | What it sets | Notes |
|---|---|---|
| `INSTALL_DIR` | Installation prefix (binaries in `bin/`, libs in `lib/`) | e.g. `/usr/ivorysql` |
| `DATA_DIR` | Cluster data directory | e.g. `/var/lib/ivorysql/data` |
| `SERVICE_USER` | System user to run the service | auto‑created if absent |
| `SERVICE_GROUP` | System group for the service | auto‑created if absent |
| `LOG_DIR` | Install + server logs directory | e.g. `/var/log/ivorysql` |

**Example** (matches your uploaded `ivorysql.conf`):
```ini
# IvorySQL Automated Installation Configuration
INSTALL_DIR=/usr/ivorysql
DATA_DIR=/var/lib/ivorysql/data
SERVICE_USER=ivorysql
SERVICE_GROUP=ivorysql
LOG_DIR=/var/log/ivorysql
```

---

## 4. Environment variables (tunables)

These can be overridden via the shell when invoking the script.

| Variable | Default | Purpose |
|---|---:|---|
| `RUN_TESTS` | `0` | If `1`, install & verify `IPC::Run` (Perl) to enable TAP‑style tests. If `0`, skip installing test deps. |
| `INIT_MODE` | `oracle` | IvorySQL initdb mode: `oracle` or `pg`. |
| `CASE_MODE` | `interchange` | Case handling for identifiers: `interchange` \| `normal` \| `lowercase`. |
| `READY_TIMEOUT` | `90` | Seconds to wait for service readiness (`pg_ctl -w -t`, readiness loop). |

**Examples**
```bash
# Default install (no TAP tests)
sudo bash ./AutoInstall.sh

# Enable TAP tests (installs libipc-run-perl/perl-IPC-Run & cpanminus as needed)
sudo RUN_TESTS=1 bash ./AutoInstall.sh

# Initialize in PostgreSQL mode, normal case
sudo INIT_MODE=pg CASE_MODE=normal bash ./AutoInstall.sh

# Increase readiness timeout to 180s
sudo READY_TIMEOUT=180 bash ./AutoInstall.sh
```

---

## 5. What the script does (stages)

1. **Load configuration**: read `ivorysql.conf`, validate required keys and absolute paths.  
2. **Prepare filesystem & identities**: create `INSTALL_DIR`, `DATA_DIR`, `LOG_DIR`; ensure `SERVICE_USER`/`SERVICE_GROUP`; chown logs.  
3. **Detect OS**: choose package manager; verify supported versions.  
4. **Enable EL/OL repos** (best‑effort): CRB/PowerTools/CodeReady Builder + EPEL where applicable.  
5. **Install dependencies**: compilers, headers and tools (readline, zlib, OpenSSL, libxml2/xslt, ICU, uuid, gettext, tcl, etc.). On EL, installs **Development Tools** group.  
6. **Feature detection** for build flags:
   - `--with-openssl` if OpenSSL headers found (else `--without-openssl`)
   - `--with-icu` if ICU present (else `--without-icu`)
   - `--with-uuid=e2fs` if `uuid/uuid.h` present (else `--without-uuid`)
   - `--with-libxml` if libxml2 headers present (else `--without-libxml`)
7. **Configure & build**:
   - Runs `./configure --prefix="$INSTALL_DIR" --with-readline ...`
   - On Debian/Ubuntu uses PIE **at compile time only** (`CFLAGS='-fPIE'`) to avoid leaking `-pie` into shared libs.
   - `make -j$(nproc)` && `make install`
8. **Initialize cluster**: `initdb -m "$INIT_MODE" -C "$CASE_MODE"` under `SERVICE_USER`.  
   - The script sets `DATA_DIR` permissions; **initdb may tighten to 700** per PostgreSQL/IvorySQL defaults.
9. **Service setup**:
   - **systemd**: writes `/etc/systemd/system/ivorysql.service` with `PGDATA`, `LD_LIBRARY_PATH`, and `pg_ctl` (`READY_TIMEOUT` respected). `systemctl enable ivorysql`.
   - **no systemd**: creates a helper `"$INSTALL_DIR/ivorysql-ctl"` with `start|stop|reload|status`.
10. **Start & verify**:
    - Start via `systemctl` or helper.
    - Readiness loop using `pg_isready` on local socket/`127.0.0.1` fallback.
    - Sanity SQL: `psql -Atc 'SELECT 1'` as `SERVICE_USER`.
11. **Summary**: prints directories, service status, version, and useful commands.

---

## 6. Logs & troubleshooting

- **Install logs**:  
  - `{LOG_DIR}/install_YYYYmmdd_HHMMSS.log`  
  - `{LOG_DIR}/error_YYYYmmdd_HHMMSS.log`
- **Server logs**: `{LOG_DIR}/server_*.log`, `{LOG_DIR}/server_ctl.log` (non‑systemd helper).
- **Quick checks**:
  ```bash
  # Status
  systemctl status ivorysql    # or: $INSTALL_DIR/ivorysql-ctl status

  # Live logs
  journalctl -u ivorysql -f    # or: tail -f $LOG_DIR/*.log

  # Connectivity
  pg_isready -h 127.0.0.1 -p ${PGPORT:-5432}

  # Permissions
  ls -ld "$DATA_DIR" && ls -l "$DATA_DIR"
  ```

> The script **does not** change firewall/SELinux. Open ports & policies as needed for your environment.

---


## 7. FAQ

- **Where must the script live?** In `autoinstall_script/` **under the source root**. It expects `configure` and `src/` one level up.  
- **Can I change the port?** Use standard PostgreSQL methods (e.g., `postgresql.conf`). The script reads the actual port from `postmaster.pid` for readiness.  
- **Why `LD_LIBRARY_PATH` in service/helper?** To prefer the freshly installed IvorySQL libs under `INSTALL_DIR/lib`.


