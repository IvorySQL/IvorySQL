#!/usr/bin/env bash
set -Eeuo pipefail

readonly data_dir=/var/lib/ivorysql/data
readonly report_dir=${REPACK_REPORT_DIR:-/var/lib/ivorysql/reports}
readonly port=${IVORYSQL_PORT:-5334}
readonly database=${IVORYSQL_DATABASE:-maintenancedb}
readonly user=${IVORYSQL_USER:-ivorysql}
readonly password=${IVORYSQL_PASSWORD:?IVORYSQL_PASSWORD is required}
export PGPASSWORD=$password

die() {
    printf 'database-entrypoint: %s\n' "$*" >&2
    exit 1
}

initialize_database() {
    [[ -s "$data_dir/PG_VERSION" ]] && return
    local password_file
    password_file=$(mktemp)
    chmod 0600 "$password_file"
    printf '%s\n' "$password" > "$password_file"
    chown ivorysql:ivorysql "$password_file"
    gosu ivorysql initdb --pgdata="$data_dir" --username="$user" --dbmode=pg \
        --pwfile="$password_file" --auth-host=scram-sha-256 \
        --auth-local=trust --encoding=UTF8 --data-checksums
    rm -f "$password_file"
    {
        printf "port = %s\n" "$port"
        printf "listen_addresses = '*'\n"
        printf "password_encryption = scram-sha-256\n"
        printf "shared_buffers = 256MB\n"
        printf "maintenance_work_mem = 256MB\n"
        printf "max_locks_per_transaction = 128\n"
        printf "log_lock_waits = on\n"
        printf "deadlock_timeout = '1s'\n"
    } >> "$data_dir/postgresql.conf"
    printf "host all all 0.0.0.0/0 scram-sha-256\n" >> "$data_dir/pg_hba.conf"
    gosu ivorysql pg_ctl -D "$data_dir" -o "-h 127.0.0.1 -p $port" -w start
    gosu ivorysql createdb --host 127.0.0.1 --port "$port" \
        --username "$user" --owner "$user" "$database"
    gosu ivorysql pg_ctl -D "$data_dir" -m fast -w stop
}

main() {
    [[ ${#password} -ge 12 ]] || die "IVORYSQL_PASSWORD must contain at least 12 characters"
    install -d -o ivorysql -g ivorysql -m 0700 "$data_dir"
    install -d -o ivorysql -g ivorysql -m 0750 "$report_dir"
    chown -R ivorysql:ivorysql /var/lib/ivorysql
    initialize_database
    exec gosu ivorysql postgres -D "$data_dir"
}

main "$@"
