#!/usr/bin/env bash
set -Eeuo pipefail

readonly host=${PGBOUNCER_HOST:-pgbouncer}
readonly port=${PGBOUNCER_PORT:-6432}
readonly database=${IVORYSQL_DATABASE:-appdb}
readonly app_user=${PGBOUNCER_APPLICATION_USER:-app_user}
export PGPASSWORD=${PGBOUNCER_APPLICATION_PASSWORD:?PGBOUNCER_APPLICATION_PASSWORD is required}

main() {
    psql --no-psqlrc --set ON_ERROR_STOP=1 --host "$host" --port "$port" \
        --username "$app_user" --dbname "$database" <<'SQL'
CREATE TABLE IF NOT EXISTS pool_verification (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    client_tag text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
TRUNCATE pool_verification;
INSERT INTO pool_verification(client_tag)
SELECT 'seed-' || value FROM generate_series(1, 1000) AS value;
SELECT version();
SELECT current_setting('ivorysql.compatible_mode');
SQL

    python3 /usr/local/libexec/pool_harness.py --host "$host" load \
        --clients "${LOAD_CLIENTS:-200}" \
        --concurrency "${LOAD_CONCURRENCY:-100}" \
        --statements 100 \
        --hold-ms "${LOAD_HOLD_MS:-50}"
    python3 /usr/local/libexec/pool_harness.py --host "$host" audit
    printf 'PgBouncer connection reuse and pool policy checks passed.\n'
}

main "$@"
