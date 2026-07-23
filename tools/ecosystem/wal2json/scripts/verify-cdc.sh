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
    local -a policy tables
    mapfile -t policy < <(
        python3 /usr/local/libexec/cdc_harness.py preflight --json |
            python3 -c 'import json,sys; p=json.load(sys.stdin); print(p["schema"]); print(p["minimum_actions"]["I"]); print(p["minimum_actions"]["U"]); print(p["minimum_actions"]["D"]); print(p["minimum_actions"]["T"]); print("\n".join(p["tables"]))'
    )
    local schema=${policy[0]}
    local inserts=${policy[1]}
    local updates=${policy[2]}
    local deletes=${policy[3]}
    local truncates=${policy[4]}
    tables=("${policy[@]:5}")
    local private_schema="${schema:0:55}_private"
    local plugin_options
    plugin_options=$(
        python3 /usr/local/libexec/cdc_harness.py options --json |
            python3 -c 'import json,sys; q=chr(39); pairs=json.load(sys.stdin); print("ARRAY[" + ",".join(q+str(value).replace(q,q+q)+q for pair in pairs for value in pair) + "]::text[]")'
    )

    install -d -o ivorysql -g ivorysql -m 0750 "$report_dir"
    rm -f "$events_file" "$metrics_file" "$audit_file"
    cleanup_slot

    run_psql --set schema="$schema" --set private_schema="$private_schema" <<'SQL'
SELECT format('DROP SCHEMA IF EXISTS %I CASCADE', :'schema') \gexec
SELECT format('DROP SCHEMA IF EXISTS %I CASCADE', :'private_schema') \gexec
SELECT format('CREATE SCHEMA %I', :'schema') \gexec
SELECT format('CREATE SCHEMA %I', :'private_schema') \gexec
SELECT format(
    'CREATE TABLE %I.customer_secrets (customer_id bigint PRIMARY KEY, secret text NOT NULL)',
    :'private_schema'
) \gexec
SQL

    local table_ref table
    for table_ref in "${tables[@]}"; do
        table=${table_ref#*.}
        run_psql --set schema="$schema" --set table="$table" \
            --set updates="$updates" --set deletes="$deletes" <<'SQL'
SELECT format(
    'CREATE TABLE %I.%I (' ||
    'id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,' ||
    'external_id text NOT NULL UNIQUE,' ||
    'status text NOT NULL,' ||
    'payload text NOT NULL,' ||
    'updated_at timestamptz NOT NULL DEFAULT clock_timestamp())',
    :'schema',
    :'table'
) \gexec
SELECT format(
    'ALTER TABLE %I.%I REPLICA IDENTITY FULL',
    :'schema',
    :'table'
) \gexec
SELECT format(
    'INSERT INTO %I.%I (external_id, status, payload) ' ||
    'SELECT ''update-seed-'' || value, ''seed'', repeat(md5(value::text), 4) ' ||
    'FROM generate_series(1, %s) value',
    :'schema',
    :'table',
    :'updates'
) \gexec
SELECT format(
    'INSERT INTO %I.%I (external_id, status, payload) ' ||
    'SELECT ''delete-seed-'' || value, ''seed'', repeat(md5(value::text), 4) ' ||
    'FROM generate_series(1, %s) value',
    :'schema',
    :'table',
    :'deletes'
) \gexec
SQL
    done

    run_psql --set slot="$slot" <<'SQL'
SELECT pg_create_logical_replication_slot(:'slot', 'wal2json');
SQL

    for table_ref in "${tables[@]}"; do
        table=${table_ref#*.}
        run_psql --set schema="$schema" --set table="$table" \
            --set inserts="$inserts" --set truncates="$truncates" <<'SQL'
BEGIN;
SELECT format(
    'INSERT INTO %I.%I (external_id, status, payload) ' ||
    'SELECT ''stream-insert-'' || value, ''inserted'', repeat(md5(value::text), 4) ' ||
    'FROM generate_series(1, %s) value',
    :'schema',
    :'table',
    :'inserts'
) \gexec
SELECT format(
    'UPDATE %I.%I SET status = ''updated'', updated_at = clock_timestamp() ' ||
    'WHERE external_id LIKE ''update-seed-%%''',
    :'schema',
    :'table'
) \gexec
SELECT format(
    'DELETE FROM %I.%I WHERE external_id LIKE ''delete-seed-%%''',
    :'schema',
    :'table'
) \gexec
SELECT format('TRUNCATE %I.%I', :'schema', :'table')
FROM generate_series(1, :'truncates'::integer) \gexec
COMMIT;
SQL
    done

    run_psql --set private_schema="$private_schema" <<'SQL'
SELECT format(
    'INSERT INTO %I.customer_secrets VALUES (1, ''this-value-must-never-enter-cdc'')',
    :'private_schema'
) \gexec
SQL

    run_psql --tuples-only --no-align --set slot="$slot" \
        --set plugin_options="$plugin_options" <<'SQL' > "$events_file"
SELECT data
    FROM pg_logical_slot_get_changes(
        :'slot',
        NULL,
        NULL,
        VARIADIC :plugin_options
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
