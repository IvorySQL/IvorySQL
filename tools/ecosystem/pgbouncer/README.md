# PgBouncer connection pooling integration

This integration builds IvorySQL and PgBouncer 1.25.2, installs a least-
privilege dynamic authentication function, and applies explicit client,
database, user, reserve, timeout, and prepared-statement limits. The default
transaction pool exposes 500 clients while capping the IvorySQL backend at 50
connections.

Copy `.env.example` to `.env`, replace all four passwords, then run:

```sh
make preflight
make config
make up
make verify
```

The verification workload opens concurrent clients through PgBouncer, records
observed backend process reuse, reports latency percentiles, parses `SHOW POOLS`
and `SHOW STATS`, and fails when server limits, waiting ratio, pool mode, or
average query latency violate policy.

Dynamic authentication reads password hashes through a `SECURITY DEFINER`
function with a fixed safe `search_path`; direct `pg_authid` access is not
granted to the pooler role. The generated userlist contains only the auth and
console users and is written mode 0600.

Transaction pooling does not preserve session state. Applications must not rely
on session advisory locks, `LISTEN`, session GUC changes, or SQL-level `PREPARE`.
Protocol-level prepared statements are supported through PgBouncer's bounded
`max_prepared_statements` cache.

Run the unit suite without Docker:

```sh
python3 -m unittest discover -s tests -v
```
