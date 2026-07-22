#!/usr/bin/env bash
set -Eeuo pipefail

readonly primary_host=${PRIMARY_HOST:-haproxy}
readonly primary_port=${PRIMARY_PORT:-5432}
readonly replica_host=${REPLICA_HOST:-haproxy}
readonly replica_port=${REPLICA_PORT:-5433}
readonly database=${PATRONI_DATABASE:-postgres}
readonly user=${PATRONI_SUPERUSER:-postgres}
readonly timeout=${VERIFY_TIMEOUT:-180}
export PGPASSWORD=${PATRONI_SUPERUSER_PASSWORD:?PATRONI_SUPERUSER_PASSWORD is required}

psql_at() {
    local host=$1
    local port=$2
    shift 2
    psql --no-psqlrc --set ON_ERROR_STOP=1 --host "$host" --port "$port" \
        --username "$user" --dbname "$database" "$@"
}

wait_for_sql() {
    local host=$1
    local port=$2
    local deadline=$((SECONDS + timeout))
    until psql_at "$host" "$port" --tuples-only --no-align \
        --command 'SELECT 1' >/dev/null 2>&1; do
        (( SECONDS < deadline )) || return 1
        sleep 2
    done
}

wait_for_value() {
    local host=$1
    local port=$2
    local sql=$3
    local expected=$4
    local deadline=$((SECONDS + timeout))
    local value
    while (( SECONDS < deadline )); do
        value=$(psql_at "$host" "$port" --tuples-only --no-align \
            --command "$sql" 2>/dev/null | tr -d '[:space:]') || true
        [[ $value == "$expected" ]] && return 0
        sleep 2
    done
    printf 'timed out waiting for %s, last value was %s\n' "$expected" "${value:-<none>}" >&2
    return 1
}

main() {
    wait_for_sql "$primary_host" "$primary_port"
    wait_for_sql "$replica_host" "$replica_port"

    psql_at "$primary_host" "$primary_port" <<'SQL'
CREATE TABLE IF NOT EXISTS patroni_failover_probe (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    payload text NOT NULL,
    writer text NOT NULL DEFAULT inet_server_addr()::text
);
TRUNCATE patroni_failover_probe;
INSERT INTO patroni_failover_probe(payload)
SELECT 'probe-' || value FROM generate_series(1, 100) AS value;
SELECT version();
SELECT current_setting('ivorysql.compatible_mode');
SQL

    wait_for_value "$replica_host" "$replica_port" \
        'SELECT count(*) FROM patroni_failover_probe' '100'
    wait_for_value "$primary_host" "$primary_port" \
        'SELECT pg_is_in_recovery()' 'f'
    wait_for_value "$replica_host" "$replica_port" \
        'SELECT pg_is_in_recovery()' 't'

    python3 /usr/local/libexec/patroni_harness.py wait --timeout "${timeout}s"
    printf 'IvorySQL Patroni topology and replication checks passed.\n'
}

main "$@"
