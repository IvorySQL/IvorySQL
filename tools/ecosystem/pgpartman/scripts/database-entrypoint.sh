#!/usr/bin/env bash
set -Eeuo pipefail

readonly data_dir=/var/lib/ivorysql/data
readonly port=${IVORYSQL_PORT:-5333}
readonly database=${IVORYSQL_DATABASE:-partitiondb}
readonly superuser=${IVORYSQL_SUPERUSER:-ivorysql}
readonly superpass=${IVORYSQL_SUPERUSER_PASSWORD:?IVORYSQL_SUPERUSER_PASSWORD is required}
readonly owner=${PARTMAN_OWNER:-partition_owner}
readonly ownerpass=${PARTMAN_OWNER_PASSWORD:?PARTMAN_OWNER_PASSWORD is required}
readonly bgw_interval=${PARTMAN_BGW_INTERVAL:-60}
export PGPASSWORD=$superpass

die() {
    printf 'database-entrypoint: %s\n' "$*" >&2
    exit 1
}

psql_super() {
    gosu ivorysql psql --no-psqlrc --set ON_ERROR_STOP=1 \
        --host 127.0.0.1 --port "$port" --username "$superuser" --dbname postgres "$@"
}

initialize_database() {
    [[ -s "$data_dir/PG_VERSION" ]] && return
    local password_file
    password_file=$(mktemp)
    chown ivorysql:ivorysql "$password_file"
    chmod 0600 "$password_file"
    printf '%s\n' "$superpass" > "$password_file"
    gosu ivorysql initdb --pgdata="$data_dir" --username="$superuser" \
        --pwfile="$password_file" --auth-host=scram-sha-256 \
        --auth-local=trust --encoding=UTF8 --data-checksums
    rm -f "$password_file"
    {
        printf "port = %s\n" "$port"
        printf "listen_addresses = '*'\n"
        printf "password_encryption = scram-sha-256\n"
        printf "shared_preload_libraries = 'pg_partman_bgw'\n"
        printf "pg_partman_bgw.dbname = '%s'\n" "$database"
        printf "pg_partman_bgw.role = '%s'\n" "$owner"
        printf "pg_partman_bgw.interval = %s\n" "$bgw_interval"
        printf "pg_partman_bgw.analyze = off\n"
        printf "pg_partman_bgw.jobmon = off\n"
        printf "ivorysql.compatible_mode = oracle\n"
    } >> "$data_dir/postgresql.conf"

    gosu ivorysql pg_ctl -D "$data_dir" -o "-h 127.0.0.1 -p $port" -w start
    psql_super --set owner="$owner" --set owner_password="$ownerpass" \
        --set database="$database" <<'SQL'
SELECT format('CREATE ROLE %I LOGIN', :'owner')
WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = :'owner') \gexec
SELECT format('ALTER ROLE %I PASSWORD %L', :'owner', :'owner_password') \gexec
SELECT format('CREATE DATABASE %I OWNER %I', :'database', :'owner')
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = :'database') \gexec
SQL
    gosu ivorysql pg_ctl -D "$data_dir" -m fast -w stop
}

main() {
    [[ ${#superpass} -ge 12 ]] || die "IVORYSQL_SUPERUSER_PASSWORD is too short"
    [[ ${#ownerpass} -ge 12 ]] || die "PARTMAN_OWNER_PASSWORD is too short"
    install -d -o ivorysql -g ivorysql -m 0700 "$data_dir"
    chown -R ivorysql:ivorysql /var/lib/ivorysql
    initialize_database
    exec gosu ivorysql postgres -D "$data_dir"
}

main "$@"
