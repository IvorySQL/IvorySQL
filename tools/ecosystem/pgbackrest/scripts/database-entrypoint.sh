#!/usr/bin/env bash
set -Eeuo pipefail

readonly data_dir=${IVORYSQL_DATA_DIR:-/var/lib/ivorysql/data}
readonly port=${IVORYSQL_PORT:-5333}
readonly user=${IVORYSQL_USER:-ivorysql}
readonly password=${IVORYSQL_PASSWORD:?IVORYSQL_PASSWORD is required}
readonly config=${BACKUP_CONFIG_PATH:-/etc/pgbackrest/pgbackrest.conf}
readonly stanza=${BACKUP_STANZA:-ivorysql}

die() {
    printf 'database-entrypoint: %s\n' "$*" >&2
    exit 1
}

prepare_directories() {
    install -d -o ivorysql -g ivorysql -m 0700 "$data_dir"
    install -d -o ivorysql -g ivorysql -m 0750 "$(dirname "$config")"
    install -d -o ivorysql -g ivorysql -m 0750 \
        /var/lib/pgbackrest /var/log/pgbackrest /var/spool/pgbackrest /tmp/pgbackrest
    chown -R ivorysql:ivorysql \
        "$data_dir" /var/lib/pgbackrest /var/log/pgbackrest \
        /var/spool/pgbackrest /tmp/pgbackrest "$(dirname "$config")"
}

initialize_database() {
    [[ -s "$data_dir/PG_VERSION" ]] && return
    local password_file
    password_file=$(mktemp)
    chmod 0600 "$password_file"
    printf '%s\n' "$password" > "$password_file"
    chown ivorysql:ivorysql "$password_file"
    gosu ivorysql initdb \
        --pgdata="$data_dir" \
        --username="$user" \
        --dbmode=oracle \
        --pwfile="$password_file" \
        --auth-host=scram-sha-256 \
        --auth-local=trust \
        --encoding=UTF8 \
        --data-checksums
    rm -f "$password_file"

    {
        printf "port = %s\n" "$port"
        printf "listen_addresses = '*'\n"
        printf "wal_level = replica\n"
        printf "max_wal_senders = 10\n"
        printf "archive_mode = on\n"
        printf "archive_command = 'pgbackrest --config=%s --stanza=%s archive-push %%p'\n" \
            "$config" "$stanza"
        printf "restore_command = 'pgbackrest --config=%s --stanza=%s archive-get %%f \"%%p\"'\n" \
            "$config" "$stanza"
        printf "archive_timeout = 60s\n"
        printf "password_encryption = scram-sha-256\n"
    } >> "$data_dir/postgresql.conf"
    printf "host all all 0.0.0.0/0 scram-sha-256\n" >> "$data_dir/pg_hba.conf"
}

main() {
    [[ ${#password} -ge 12 ]] || die "IVORYSQL_PASSWORD must contain at least 12 characters"
    prepare_directories
    gosu ivorysql python3 /usr/local/libexec/backup_harness.py render --output "$config"
    initialize_database
    exec gosu ivorysql postgres -D "$data_dir"
}

main "$@"
