#!/usr/bin/env bash
set -Eeuo pipefail

readonly host=127.0.0.1
readonly port=${IVORYSQL_PORT:-5334}
readonly database=${IVORYSQL_DATABASE:-maintenancedb}
readonly user=${IVORYSQL_USER:-ivorysql}
readonly password=${IVORYSQL_PASSWORD:?IVORYSQL_PASSWORD is required}
readonly schema=${REPACK_SCHEMA:-maintenance}
readonly table=${REPACK_TABLE:-orders}
readonly rows=${REPACK_INITIAL_ROWS:-24000}
readonly delete_percent=${REPACK_DELETE_PERCENT:-75}
readonly payload_bytes=${REPACK_PAYLOAD_BYTES:-1024}
readonly wait_timeout=${REPACK_WAIT_TIMEOUT:-60}
readonly report_dir=${REPACK_REPORT_DIR:-/var/lib/ivorysql/reports}
readonly before_file="$report_dir/before.json"
readonly after_file="$report_dir/after.json"
readonly writer_file="$report_dir/writer.json"
readonly execution_file="$report_dir/execution.json"
readonly audit_file="$report_dir/audit.json"
readonly repack_log="$report_dir/pg_repack.log"
export PGPASSWORD=$password

run_psql() {
    psql --no-psqlrc --set ON_ERROR_STOP=1 --host "$host" --port "$port" \
        --username "$user" --dbname "$database" "$@"
}

capture_metrics() {
    local destination=$1
    run_psql --tuples-only --no-align --set schema="$schema" --set table="$table" <<'SQL' > "$destination"
SELECT format(
    'SELECT json_build_object(' ||
    '''total_size'', pg_total_relation_size(%L::regclass),' ||
    '''heap_size'', pg_relation_size(%L::regclass),' ||
    '''index_size'', pg_indexes_size(%L::regclass),' ||
    '''row_count'', count(*)::bigint,' ||
    '''stable_rows'', count(*) FILTER (WHERE external_id NOT LIKE ''writer-%%%%''),' ||
    '''stable_checksum'', md5(coalesce(string_agg(external_id || status || payload, '''' ORDER BY external_id) ' ||
        'FILTER (WHERE external_id NOT LIKE ''writer-%%%%''), '''')),' ||
    '''index_count'', (SELECT count(*) FROM pg_index WHERE indrelid = %L::regclass),' ||
    '''indexes_healthy'', (SELECT bool_and(indisvalid AND indisready) FROM pg_index WHERE indrelid = %L::regclass),' ||
    '''extension_version'', (SELECT extversion FROM pg_extension WHERE extname = ''pg_repack''),' ||
    '''server_version'', version()' ||
    ')::text FROM %I.%I',
    format('%I.%I', :'schema', :'table'),
    format('%I.%I', :'schema', :'table'),
    format('%I.%I', :'schema', :'table'),
    format('%I.%I', :'schema', :'table'),
    format('%I.%I', :'schema', :'table'),
    :'schema',
    :'table'
)
\gexec
SQL
}

main() {
    python3 /usr/local/libexec/repack_harness.py preflight >/dev/null
    install -d -o ivorysql -g ivorysql -m 0750 "$report_dir"
    rm -f "$before_file" "$after_file" "$writer_file" "${writer_file}.started" "$execution_file" \
        "$audit_file" "$repack_log"

    run_psql --set schema="$schema" --set table="$table" \
        --set rows="$rows" --set delete_percent="$delete_percent" \
        --set payload_bytes="$payload_bytes" <<'SQL'
CREATE EXTENSION IF NOT EXISTS pg_repack;
SELECT format('DROP SCHEMA IF EXISTS %I CASCADE', :'schema') \gexec
SELECT format('CREATE SCHEMA %I', :'schema') \gexec
SELECT format(
    'CREATE TABLE %I.%I (' ||
    'id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,' ||
    'external_id text NOT NULL UNIQUE,' ||
    'status text NOT NULL,' ||
    'payload text NOT NULL,' ||
    'created_at timestamptz NOT NULL DEFAULT clock_timestamp(),' ||
    'updated_at timestamptz NOT NULL DEFAULT clock_timestamp())',
    :'schema',
    :'table'
) \gexec
SELECT format('CREATE INDEX %I ON %I.%I (status, updated_at)', :'table' || '_status_idx', :'schema', :'table') \gexec
SELECT format('CREATE INDEX %I ON %I.%I USING hash (external_id)', :'table' || '_external_hash_idx', :'schema', :'table') \gexec
SELECT format(
    'INSERT INTO %I.%I (external_id, status, payload) ' ||
    'SELECT ''seed-'' || value, CASE value %% 4 WHEN 0 THEN ''closed'' ELSE ''open'' END, ' ||
    'left(repeat(md5(value::text), 64), %s) FROM generate_series(1, %s) value',
    :'schema',
    :'table',
    :'payload_bytes',
    :'rows'
) \gexec
CHECKPOINT;
SELECT format(
    'DELETE FROM %I.%I WHERE id %% 100 < %s',
    :'schema',
    :'table',
    :'delete_percent'
) \gexec
SELECT format('VACUUM (ANALYZE) %I.%I', :'schema', :'table') \gexec
SQL

    capture_metrics "$before_file"

    /usr/local/bin/concurrent-writer "$writer_file" &
    writer_pid=$!
    for _ in {1..100}; do
        [[ -s "${writer_file}.started" ]] && break
        kill -0 "$writer_pid" 2>/dev/null || {
            wait "$writer_pid"
            return 1
        }
        sleep 0.05
    done
    [[ -s "${writer_file}.started" ]] || {
        printf 'concurrent writer did not start within five seconds\n' >&2
        kill "$writer_pid" 2>/dev/null || true
        wait "$writer_pid" 2>/dev/null || true
        return 1
    }

    repack_started=$(date +%s%3N)
    set +e
    pg_repack --host="$host" --port="$port" --username="$user" \
        --dbname="$database" --table="$schema.$table" \
        --wait-timeout="$wait_timeout" --no-kill-backend --no-order --echo \
        >"$repack_log" 2>&1
    repack_exit=$?
    set -e
    repack_finished=$(date +%s%3N)
    writer_exit=0
    wait "$writer_pid" || writer_exit=$?

    printf '{"started_ms":%s,"finished_ms":%s,"exit_code":%s}\n' \
        "$repack_started" "$repack_finished" "$repack_exit" > "$execution_file"

    capture_metrics "$after_file"
    audit_exit=0
    python3 /usr/local/libexec/repack_harness.py audit \
        --before "$before_file" --after "$after_file" \
        --writer "$writer_file" --execution "$execution_file" \
        --output "$audit_file" || audit_exit=$?

    if ((repack_exit != 0)); then
        cat "$repack_log" >&2
        return "$repack_exit"
    fi
    if ((writer_exit != 0)); then
        printf 'concurrent writer exited with status %s\n' "$writer_exit" >&2
        return "$writer_exit"
    fi
    ((audit_exit == 0)) || return "$audit_exit"
    grep -q '"passed": true' "$audit_file"
    printf 'pg_repack online maintenance contract passed; report: %s\n' "$audit_file"
}

main "$@"
