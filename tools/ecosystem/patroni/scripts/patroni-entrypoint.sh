#!/usr/bin/env bash
set -Eeuo pipefail

readonly DATA_DIR=/var/lib/ivorysql/data
readonly CONFIG_DIR=/run/patroni
readonly HARNESS=/usr/local/libexec/patroni_harness.py

die() {
    printf 'patroni-entrypoint: %s\n' "$*" >&2
    exit 1
}

require_secret() {
    local name=$1
    local value=${!name:-}
    [[ -n $value ]] || die "$name must be set"
    [[ ${#value} -ge 8 ]] || die "$name must contain at least eight characters"
}

prepare_directories() {
    install -d -o ivorysql -g ivorysql -m 0700 "$DATA_DIR"
    install -d -o ivorysql -g ivorysql -m 0755 "$CONFIG_DIR" /var/run/ivorysql
    chown -R ivorysql:ivorysql /var/lib/ivorysql /var/run/ivorysql "$CONFIG_DIR"
}

render_config() {
    local node=$1
    python3 "$HARNESS" render --output "$CONFIG_DIR" >/dev/null
    [[ -f "$CONFIG_DIR/$node.yml" ]] || die "node $node is not listed in PATRONI_NODES"
    chown ivorysql:ivorysql "$CONFIG_DIR/$node.yml"
    chmod 0600 "$CONFIG_DIR/$node.yml"
}

write_pgpass() {
    local password=${PATRONI_REPLICATION_PASSWORD}
    printf '*:*:*:%s:%s\n' "${PATRONI_REPLICATION_USER:-replicator}" "$password" \
        > /var/lib/ivorysql/.pgpass
    chown ivorysql:ivorysql /var/lib/ivorysql/.pgpass
    chmod 0600 /var/lib/ivorysql/.pgpass
}

main() {
    [[ $# -eq 1 ]] || die "usage: patroni-entrypoint NODE_NAME"
    local node=$1
    require_secret PATRONI_SUPERUSER_PASSWORD
    require_secret PATRONI_REPLICATION_PASSWORD
    require_secret PATRONI_API_PASSWORD
    prepare_directories
    render_config "$node"
    write_pgpass
    exec gosu ivorysql patroni "$CONFIG_DIR/$node.yml"
}

main "$@"
