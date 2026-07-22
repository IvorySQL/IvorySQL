# pg_partman partition lifecycle integration

This integration builds IvorySQL with pg_partman 5.4.3 and configures a
least-privilege owner, declarative range-partitioned event table, background
maintenance, future partition premaking, default-partition protection, and
retention.

The cluster is initialized in IvorySQL native PostgreSQL mode because
pg_partman maintenance procedures use PostgreSQL transaction-control semantics.

Copy `.env.example` to `.env`, replace both passwords, then run:

```sh
make preflight
make plan
make config
make up
make verify
```

The verifier installs pg_partman, generates the current and future partitions,
loads a cross-boundary workload, runs `run_maintenance_proc()`, and audits the
catalog inventory. The audit detects missing or overlapping ranges, missing
future partitions, overdue retained partitions, reversed boundaries, and rows
stranded in the default partition.

`PARTMAN_DEFAULT_ROW_LIMIT=0` makes the default partition an operational alarm:
any stranded row fails verification. Adjust this only if a temporary backlog is
explicitly accepted. Retention defaults to dropping old child tables; set
`PARTMAN_RETENTION_KEEP_TABLE=true` to detach and retain them instead.

The background worker is loaded through `shared_preload_libraries` and runs as
the non-superuser partition owner. The harness restricts intervals to hourly,
daily, weekly, or monthly so boundary expectations can be independently audited.

Run unit tests without Docker:

```sh
python3 -m unittest discover -s tests -v
```
