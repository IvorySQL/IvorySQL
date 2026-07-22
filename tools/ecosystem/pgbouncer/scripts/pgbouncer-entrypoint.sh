#!/usr/bin/env bash
set -Eeuo pipefail

readonly config_dir=/etc/pgbouncer
readonly run_dir=/var/run/pgbouncer

main() {
    install -d -o pgbouncer -g pgbouncer -m 0750 "$config_dir" "$run_dir"
    install -o pgbouncer -g pgbouncer -m 0640 /dev/null /var/log/pgbouncer.log
    python3 /usr/local/libexec/pool_harness.py render --output "$config_dir" >/dev/null
    chown -R pgbouncer:pgbouncer "$config_dir" "$run_dir"
    chmod 0600 "$config_dir/pgbouncer.ini" "$config_dir/userlist.txt"
    exec gosu pgbouncer pgbouncer "$config_dir/pgbouncer.ini"
}

main "$@"
