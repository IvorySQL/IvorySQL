#!/usr/bin/env bash
set -Eeuo pipefail

readonly rows=${PARTMAN_WORKLOAD_ROWS:-100000}

main() {
    python3 /usr/local/libexec/partition_harness.py preflight
    python3 /usr/local/libexec/partition_harness.py install
    python3 /usr/local/libexec/partition_harness.py workload --rows "$rows"
    python3 /usr/local/libexec/partition_harness.py maintenance
    python3 /usr/local/libexec/partition_harness.py audit

    PGPASSWORD=${PARTMAN_OWNER_PASSWORD} psql --no-psqlrc --set ON_ERROR_STOP=1 \
        --host "${IVORYSQL_HOST:-database}" --port "${IVORYSQL_PORT:-5333}" \
        --username "${PARTMAN_OWNER:-partition_owner}" \
        --dbname "${IVORYSQL_DATABASE:-partitiondb}" --tuples-only --no-align \
        --command "SELECT count(*) FROM ${PARTMAN_SCHEMA:-app}.${PARTMAN_TABLE:-events}" \
        | grep -qx "$rows"
    printf 'pg_partman lifecycle, retention, and boundary checks passed.\n'
}

main "$@"
