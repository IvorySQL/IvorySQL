#!/usr/bin/env bash

set -euo pipefail

if [[ ! -s "${PGDATA}/PG_VERSION" ]]; then
    initdb \
        --auth-host=trust \
        --auth-local=trust \
        --no-instructions \
        -C normal \
        -D "${PGDATA}" \
        -m pg
fi

exec postgres \
    -D "${PGDATA}" \
    -c listen_addresses='*' \
    -c shared_preload_libraries=pg_show_plans
