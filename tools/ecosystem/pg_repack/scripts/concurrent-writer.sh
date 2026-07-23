#!/usr/bin/env bash
set -Eeuo pipefail

readonly host=127.0.0.1
readonly port=${IVORYSQL_PORT:-5334}
readonly database=${IVORYSQL_DATABASE:-maintenancedb}
readonly user=${IVORYSQL_USER:-ivorysql}
readonly password=${IVORYSQL_PASSWORD:?IVORYSQL_PASSWORD is required}
readonly schema=${REPACK_SCHEMA:-maintenance}
readonly table=${REPACK_TABLE:-orders}
readonly writes=${REPACK_CONCURRENT_WRITES:-40}
readonly output=${1:?writer output path is required}
export PGPASSWORD=$password

success=0
errors=0
max_latency_ms=0
started_ms=$(date +%s%3N)
printf '%s\n' "$started_ms" > "${output}.started"

for ((operation = 1; operation <= writes; operation++)); do
    operation_started=$(date +%s%3N)
    if psql --no-psqlrc --set ON_ERROR_STOP=1 \
        --host "$host" --port "$port" --username "$user" --dbname "$database" \
        --set schema="$schema" --set table="$table" --set op="$operation" \
        --quiet <<'SQL' >/dev/null
BEGIN;
SELECT format(
    'INSERT INTO %I.%I (external_id, status, payload) VALUES (%L, %L, %L)',
    :'schema',
    :'table',
    'writer-' || :'op',
    'new',
    repeat(md5('writer-' || :'op'), 8)
) \gexec
SELECT format(
    'UPDATE %I.%I SET status = %L, updated_at = clock_timestamp() WHERE external_id = %L',
    :'schema',
    :'table',
    'committed',
    'writer-' || :'op'
) \gexec
COMMIT;
SQL
    then
        ((success += 1))
    else
        ((errors += 1))
    fi
    operation_finished=$(date +%s%3N)
    latency=$((operation_finished - operation_started))
    if ((latency > max_latency_ms)); then
        max_latency_ms=$latency
    fi
    sleep 0.10
done

finished_ms=$(date +%s%3N)
printf '{"started_ms":%s,"finished_ms":%s,"attempted":%s,"succeeded":%s,"errors":%s,"max_latency_ms":%s}\n' \
    "$started_ms" "$finished_ms" "$writes" "$success" "$errors" "$max_latency_ms" \
    > "$output"

((errors == 0))
