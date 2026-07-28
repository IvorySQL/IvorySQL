#!/usr/bin/env bash

set -euo pipefail

readonly database=pg_show_plans_test

dropdb --if-exists --force "${database}"
createdb "${database}"
psql -X -v ON_ERROR_STOP=1 -d "${database}" \
    -c 'CREATE EXTENSION pg_show_plans;'

psql -X -v ON_ERROR_STOP=1 -d "${database}" \
    -c 'SELECT pg_sleep(8) FROM generate_series(1, 1);' \
    >/tmp/pg-show-plans-workload.log 2>&1 &
workload_pid=$!

cleanup()
{
    kill "${workload_pid}" 2>/dev/null || true
    wait "${workload_pid}" 2>/dev/null || true
}
trap cleanup EXIT

observed=false
for _ in $(seq 1 20); do
    snapshot=$(
        psql -X -A -t -v ON_ERROR_STOP=1 -d "${database}" -c "
            SELECT pid, level, plan, query
            FROM pg_show_plans_q
            WHERE query LIKE
                'SELECT pg_sleep(8) FROM generate_series(1, 1)%';
        "
    )

    if grep -Fq 'Function Scan on generate_series' <<<"${snapshot}"; then
        observed=true
        break
    fi

    sleep 0.5
done

wait "${workload_pid}"
trap - EXIT

if [[ "${observed}" != true ]]; then
    echo "pg_show_plans did not expose the active workload plan" >&2
    exit 1
fi

extension_version=$(
    psql -X -A -t -v ON_ERROR_STOP=1 -d "${database}" -c "
        SELECT extversion
        FROM pg_extension
        WHERE extname = 'pg_show_plans';
    "
)
server_version_num=$(
    psql -X -A -t -v ON_ERROR_STOP=1 -d "${database}" \
        -c 'SHOW server_version_num;'
)

[[ "${extension_version}" == 2.1 ]]
[[ "${server_version_num}" == 180004 ]]

printf 'verified IvorySQL %s with pg_show_plans %s\n' \
    "${server_version_num}" \
    "${extension_version}"
