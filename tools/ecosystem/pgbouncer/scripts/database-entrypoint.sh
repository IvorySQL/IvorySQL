#!/usr/bin/env bash
set -Eeuo pipefail

readonly data_dir=/var/lib/ivorysql/data
readonly port=${IVORYSQL_PORT:-5333}
readonly superuser=${IVORYSQL_SUPERUSER:-ivorysql}
readonly superpass=${IVORYSQL_SUPERUSER_PASSWORD:?IVORYSQL_SUPERUSER_PASSWORD is required}
readonly database=${IVORYSQL_DATABASE:-appdb}
readonly app_user=${PGBOUNCER_APPLICATION_USER:-app_user}
readonly app_pass=${PGBOUNCER_APPLICATION_PASSWORD:?PGBOUNCER_APPLICATION_PASSWORD is required}
readonly auth_user=${PGBOUNCER_AUTH_USER:-pool_auth}
readonly auth_pass=${PGBOUNCER_AUTH_PASSWORD:?PGBOUNCER_AUTH_PASSWORD is required}
export PGPASSWORD=$superpass

die() {
    printf 'database-entrypoint: %s\n' "$*" >&2
    exit 1
}

psql_super() {
    gosu ivorysql psql --no-psqlrc --set ON_ERROR_STOP=1 \
        --host 127.0.0.1 --port "$port" --username "$superuser" "$@"
}

initialize_roles() {
    local generated=/run/pgbouncer-bootstrap
    install -d -o ivorysql -g ivorysql -m 0700 "$generated"
    gosu ivorysql python3 /usr/local/libexec/pool_harness.py render --output "$generated" >/dev/null

    psql_super --dbname postgres \
        --set database="$database" \
        --set app_user="$app_user" --set app_password="$app_pass" \
        --set auth_user="$auth_user" --set auth_password="$auth_pass" <<'SQL'
SELECT format('CREATE ROLE %I LOGIN', :'app_user')
WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = :'app_user') \gexec
SELECT format('ALTER ROLE %I PASSWORD %L', :'app_user', :'app_password') \gexec
SELECT format('CREATE ROLE %I LOGIN', :'auth_user')
WHERE NOT EXISTS (SELECT FROM pg_roles WHERE rolname = :'auth_user') \gexec
SELECT format('ALTER ROLE %I PASSWORD %L', :'auth_user', :'auth_password') \gexec
SELECT format('CREATE DATABASE %I OWNER %I', :'database', :'app_user')
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = :'database') \gexec
SQL
    psql_super --dbname "$database" --file "$generated/install_auth.sql"
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
        printf "max_connections = 100\n"
        printf "ivorysql.compatible_mode = oracle\n"
    } >> "$data_dir/postgresql.conf"
    gosu ivorysql pg_ctl -D "$data_dir" -o "-h 127.0.0.1 -p $port" -w start
    export IVORYSQL_DATABASE=$database
    initialize_roles
    gosu ivorysql pg_ctl -D "$data_dir" -m fast -w stop
}

main() {
    [[ ${#superpass} -ge 12 ]] || die "IVORYSQL_SUPERUSER_PASSWORD is too short"
    install -d -o ivorysql -g ivorysql -m 0700 "$data_dir"
    chown -R ivorysql:ivorysql /var/lib/ivorysql
    initialize_database
    exec gosu ivorysql postgres -D "$data_dir"
}

main "$@"
