#!/usr/bin/env bash
set -Eeuo pipefail

readonly host=127.0.0.1
readonly port=${IVORYSQL_PORT:-5335}
readonly database=${IVORYSQL_DATABASE:-migrationdb}
readonly user=${IVORYSQL_USER:-ivorysql}
readonly password=${IVORYSQL_PASSWORD:?IVORYSQL_PASSWORD is required}
readonly contract=${ORAFCE_CONTRACT:-/usr/local/share/orafce/compatibility_contract.json}
readonly report_dir=${ORAFCE_REPORT_DIR:-/var/lib/ivorysql/reports}
readonly sql_file=/usr/local/share/orafce/migration_contract.sql
readonly results_file="$report_dir/results.jsonl"
readonly metadata_file="$report_dir/metadata.json"
readonly audit_file="$report_dir/audit.json"
export PGPASSWORD=$password

run_psql() {
    psql --no-psqlrc --set ON_ERROR_STOP=1 --host "$host" --port "$port" \
        --username "$user" --dbname "$database" "$@"
}

main() {
    python3 /usr/local/libexec/migration_harness.py preflight \
        --contract "$contract" >/dev/null
    install -d -o ivorysql -g ivorysql -m 0750 "$report_dir"
    rm -f "$results_file" "$metadata_file" "$audit_file"

    run_psql --file "$sql_file"
    run_psql --tuples-only --no-align <<'SQL' > "$results_file"
SELECT json_build_object(
    'id', case_id,
    'actual', actual,
    'actual_type', actual_type
)::text
FROM migration.contract_results
ORDER BY case_id;
SQL
    run_psql --tuples-only --no-align <<'SQL' > "$metadata_file"
SELECT json_build_object(
    'extension_version', (SELECT extversion FROM pg_extension WHERE extname = 'orafce'),
    'server_version', version(),
    'database_mode', current_setting('ivorysql.database_mode', true),
    'plisql_installed', EXISTS (
        SELECT FROM pg_language WHERE lanname = 'plisql'
    ),
    'result_count', (SELECT count(*) FROM migration.contract_results)
)::text;
SQL

    python3 /usr/local/libexec/migration_harness.py audit \
        --contract "$contract" --results "$results_file" \
        --metadata "$metadata_file" --output "$audit_file"
    grep -q '"passed": true' "$audit_file"
    printf 'orafce migration contract passed; report: %s\n' "$audit_file"
}

main "$@"
