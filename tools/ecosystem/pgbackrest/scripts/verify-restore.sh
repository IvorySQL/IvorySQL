#!/usr/bin/env bash
set -Eeuo pipefail

readonly data_dir=${IVORYSQL_DATA_DIR:-/var/lib/ivorysql/restore-data}
readonly socket_dir=${IVORYSQL_SOCKET_DIR:-/var/run/ivorysql}
readonly port=${IVORYSQL_PORT:-5434}
readonly user=${IVORYSQL_USER:-ivorysql}
readonly config=${BACKUP_CONFIG_PATH:-/etc/pgbackrest/pgbackrest.conf}
export PGPASSWORD=${IVORYSQL_PASSWORD:?IVORYSQL_PASSWORD is required}

cleanup() {
    if [[ -s "$data_dir/postmaster.pid" ]]; then
        gosu ivorysql pg_ctl -D "$data_dir" -m fast stop >/dev/null 2>&1 || true
    fi
}
trap cleanup EXIT

run_psql() {
    psql --no-psqlrc --set ON_ERROR_STOP=1 --host 127.0.0.1 --port "$port" \
        --username "$user" --dbname postgres "$@"
}

wait_for_promotion() {
    local attempts=120
    until run_psql --tuples-only --no-align \
        --command 'SELECT pg_is_in_recovery()' 2>/dev/null | grep -qx 'f'; do
        (( attempts-- > 0 )) || {
            printf 'Restored cluster did not leave recovery within 120 seconds.\n' >&2
            return 1
        }
        sleep 1
    done
}

main() {
    install -d -o ivorysql -g ivorysql -m 0700 "$data_dir"
    install -d -o ivorysql -g ivorysql -m 0750 "$(dirname "$config")" \
        /var/log/pgbackrest /var/spool/pgbackrest /tmp/pgbackrest
    install -d -o ivorysql -g ivorysql -m 0770 "$socket_dir"
    chown -R ivorysql:ivorysql "$data_dir" "$socket_dir" "$(dirname "$config")" \
        /var/log/pgbackrest /var/spool/pgbackrest /tmp/pgbackrest

    gosu ivorysql python3 /usr/local/libexec/backup_harness.py render --output "$config"
    gosu ivorysql python3 /usr/local/libexec/backup_harness.py restore \
        --type=immediate --timeline=latest --action=promote --yes
    printf "port = %s\nlisten_addresses = '127.0.0.1'\n" "$port" \
         >> "$data_dir/postgresql.auto.conf"
    gosu ivorysql pg_ctl -D "$data_dir" -w -t 120 start

    wait_for_promotion
    run_psql --tuples-only --no-align \
        --command 'SELECT count(*) FROM pgbackrest_restore_probe' | grep -qx '4096'
    printf 'Restored IvorySQL cluster contains the expected verification dataset.\n'
}

main "$@"
