#!/usr/bin/env bash
set -Eeuo pipefail

readonly host=127.0.0.1
readonly port=${IVORYSQL_PORT:-5333}
readonly database=${IVORYSQL_DATABASE:-cdcdb}
readonly user=${IVORYSQL_USER:-ivorysql}
readonly password=${IVORYSQL_PASSWORD:?IVORYSQL_PASSWORD is required}
readonly slot=${CDC_SLOT:-ivorysql_cdc}
readonly report_dir=${CDC_REPORT_DIR:-/var/lib/ivorysql/reports}
readonly events_file="$report_dir/events.jsonl"
readonly metrics_file="$report_dir/slot.json"
readonly audit_file="$report_dir/audit.json"
export PGPASSWORD=$password

run_psql() {
    psql --no-psqlrc --set ON_ERROR_STOP=1 --host "$host" --port "$port" \
        --username "$user" --dbname "$database" "$@"
}

cleanup_slot() {
    run_psql --tuples-only --no-align --set slot="$slot" <<'SQL' >/dev/null 2>&1 || true
SELECT pg_drop_replication_slot(:'slot')
WHERE EXISTS (SELECT FROM pg_replication_slots WHERE slot_name = :'slot');
SQL
}
trap cleanup_slot EXIT

main() {
    python3 /usr/local/libexec/cdc_harness.py preflight >/dev/null
    install -d -o ivorysql -g ivorysql -m 0750 "$report_dir"
    rm -f "$events_file" "$metrics_file" "$audit_file"
    cleanup_slot

    run_psql --set slot="$slot" <<'SQL'
DROP SCHEMA IF EXISTS cdc CASCADE;
DROP SCHEMA IF EXISTS private CASCADE;
CREATE SCHEMA cdc;
CREATE SCHEMA private;

CREATE TABLE cdc.accounts (
    account_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    email text NOT NULL UNIQUE,
    balance numeric(14,2) NOT NULL,
    status text NOT NULL,
    profile jsonb NOT NULL,
    updated_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
ALTER TABLE cdc.accounts REPLICA IDENTITY FULL;

CREATE TABLE cdc.staging (
    batch_id bigint NOT NULL,
    payload text NOT NULL,
    PRIMARY KEY (batch_id, payload)
);

CREATE TABLE private.customer_secrets (
    customer_id bigint PRIMARY KEY,
    secret text NOT NULL
);

SELECT pg_create_logical_replication_slot(:'slot', 'wal2json');

BEGIN;
INSERT INTO cdc.accounts(email, balance, status, profile) VALUES
    ('ada@example.test', 120.50, 'active', '{"tier":"gold"}'),
    ('linus@example.test', 80.00, 'active', '{"tier":"silver"}'),
    ('grace@example.test', 42.25, 'pending', '{"tier":"bronze"}'),
    ('margaret@example.test', 210.00, 'active', '{"tier":"gold"}');
INSERT INTO private.customer_secrets VALUES
    (1, 'this-value-must-never-enter-cdc');
COMMIT;

BEGIN;
UPDATE cdc.accounts
SET balance = balance + 10, profile = profile || '{"verified":true}'::jsonb
WHERE email IN ('ada@example.test', 'linus@example.test');
DELETE FROM cdc.accounts WHERE email = 'grace@example.test';
COMMIT;

BEGIN;
INSERT INTO cdc.staging VALUES (7, 'first'), (7, 'second');
TRUNCATE cdc.staging;
COMMIT;
SQL

    run_psql --tuples-only --no-align --set slot="$slot" <<'SQL' > "$events_file"
SELECT data
    FROM pg_logical_slot_get_changes(
        :'slot',
        NULL,
        NULL,
        'format-version', '2',
        'include-xids', '1',
        'include-timestamp', '1',
        'include-types', '1',
        'include-pk', '1',
        'include-transaction', '1',
        'actions', 'insert,update,delete,truncate',
        'add-tables', 'cdc.accounts,cdc.staging'
    );
SQL

    run_psql --tuples-only --no-align --set slot="$slot" <<'SQL' > "$metrics_file"
SELECT json_build_object(
    'slot_name', slot_name,
    'plugin', plugin,
    'slot_type', slot_type,
    'database', database,
    'active', active,
    'restart_lsn', restart_lsn::text,
    'confirmed_flush_lsn', confirmed_flush_lsn::text,
    'retained_bytes', pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn)::bigint
)::text
FROM pg_replication_slots
WHERE slot_name = :'slot';
SQL

    python3 /usr/local/libexec/cdc_harness.py audit \
        --events "$events_file" --slot-metrics "$metrics_file" \
        --output "$audit_file"
    test -s "$audit_file"
    grep -q '"passed": true' "$audit_file"
    printf 'wal2json CDC contract passed; report: %s\n' "$audit_file"
}

main "$@"
