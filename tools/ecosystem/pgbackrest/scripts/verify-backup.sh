#!/usr/bin/env bash
set -Eeuo pipefail

readonly host=${IVORYSQL_HOST:-database}
readonly port=${IVORYSQL_PORT:-5333}
readonly user=${IVORYSQL_USER:-ivorysql}
readonly database=${IVORYSQL_DATABASE:-postgres}
readonly config=${BACKUP_CONFIG_PATH:-/etc/pgbackrest/pgbackrest.conf}
readonly stanza=${BACKUP_STANZA:-ivorysql}
export PGPASSWORD=${IVORYSQL_PASSWORD:?IVORYSQL_PASSWORD is required}

run_psql() {
    psql --no-psqlrc --set ON_ERROR_STOP=1 --host "$host" --port "$port" \
        --username "$user" --dbname "$database" "$@"
}

wait_for_database() {
    local attempts=60
    until run_psql --tuples-only --no-align --command 'SELECT 1' >/dev/null 2>&1; do
        (( attempts-- > 0 )) || return 1
        sleep 2
    done
}

main() {
    wait_for_database
    python3 /usr/local/libexec/backup_harness.py render --output "$config"

    run_psql <<'SQL'
CREATE TABLE IF NOT EXISTS pgbackrest_restore_probe (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    marker uuid NOT NULL DEFAULT gen_random_uuid(),
    payload text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
TRUNCATE pgbackrest_restore_probe;
INSERT INTO pgbackrest_restore_probe(payload)
SELECT (
    SELECT string_agg(md5(value::text || ':' || chunk::text), '' ORDER BY chunk)
    FROM generate_series(1, 32) AS chunk
)
FROM generate_series(1, 4096) AS value;
CHECKPOINT;
SELECT pg_create_restore_point('ivorysql_pgbackrest_probe');
SQL

    pgbackrest --config="$config" --stanza="$stanza" stanza-create
    pgbackrest --config="$config" --stanza="$stanza" check
    pgbackrest --config="$config" --stanza="$stanza" --type=full backup
    python3 /usr/local/libexec/backup_harness.py audit
    run_psql --tuples-only --no-align \
        --command 'SELECT count(*) FROM pgbackrest_restore_probe' | grep -qx '4096'
    printf 'Encrypted full backup and repository policy audit passed.\n'
}

main "$@"
