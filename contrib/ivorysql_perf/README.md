# IvorySQL performance history

`ivorysql_perf` is an optional extension providing bounded active-session
sampling, database/SQL counter snapshots and JSON interval reports. It is a
first implementation toward the ASH/AWR requests (#952 and #953), not an Oracle
AWR/ADDM API or report-format clone.

Build/install through the contrib build, or with `make USE_PGXS=1` and the
target installation's `pg_config`. The extension itself needs no shared
preload entry. For SQL execution counters, additionally preload and install
`pg_stat_statements` before starting the server; database/session reports also
work without it. Install using the PostgreSQL parser/port.

```sql
CREATE EXTENSION ivorysql_perf;
-- Optional, after shared_preload_libraries includes pg_stat_statements:
CREATE EXTENSION pg_stat_statements;
GRANT pg_monitor TO monitoring_user;

-- Run after CREATE EXTENSION has committed:
SELECT ivorysql_perf.start_collector();
SELECT * FROM ivorysql_perf.collector_status;
SELECT ivorysql_perf.take_snapshot(); -- save the returned id, e.g. 10
-- Execute application workload in other sessions.
SELECT ivorysql_perf.take_snapshot(); -- e.g. 11
SELECT jsonb_pretty(ivorysql_perf.report(10,11));
SELECT ivorysql_perf.stop_collector();
```

The report contains database counter deltas, observed waits, blocker identities
and comparable Top SQL deltas. It rejects intervals crossing a database stats
reset or server restart. Global statement resets are reported separately as
`sql_status = reset`; entry resets and counter decreases are not subtracted.
New SQL entries are usable only if their `stats_since` starts within the
interval. Truncation and statement eviction are surfaced as limited coverage.

Defaults: one-second sampling, one-minute snapshots, one-day retention,
100,000 sample rows, 1,440 snapshots and 1,000 statements per snapshot. Change
these atomically through `configure`, for example:

```sql
SELECT ivorysql_perf.configure(sample_interval_ms=>1000,
  snapshot_interval_s=>60, sample_limit=>50000, snapshot_limit=>120,
  retention=>interval '2 hours', sql_limit=>500);
```

Intervals are restricted to 100–60,000 ms; retention and row counts have hard
validation bounds. Every collection/snapshot prunes old and excess rows;
deleting a snapshot cascades to its SQL history. `purge` also works manually.
The configured sample limit is a row count, not a count of ticks. Many active
sessions shorten the retained observation interval. Inactive client backends,
other databases and the sampler itself are excluded; query text is capped at
2,000 characters. No-wait observations mean running or runnable, not measured
CPU time. Sample counts are not exact wait durations, and reports aggregate
only retained samples. Output shows at most twenty wait/blocker/SQL groups.

The collector is a dynamic background worker connected as the role starting
it. A session advisory lock permits only one active collector per database;
concurrent starts may briefly launch a contender which immediately exits.
Settings are read on each tick. The worker uses a latch, exits on postmaster
death/SIGTERM, and enforces a five-second statement timeout on each tick.
It stops on a collection error instead of retrying indefinitely. Check the
server log and `collector_status`, resolve the cause, then start it again.
History survives server restart; collection requires an explicit restart.
Starting/stopping a worker is an administrative side effect, not undone by
rolling back its initiating SQL transaction. A free `max_worker_processes`
slot and database CONNECT privilege are required.

Schema/table/function access is restricted to `pg_monitor` and the extension
owner. Monitoring roles can use the maintenance API but cannot directly write
history/configuration tables. Fixed-path definer functions read privileged
activity and write only extension-owned objects. SQL text may contain sensitive
application data, so historical access deliberately has the same monitoring
privilege boundary; revoking membership also removes that access.

`t/001_perf.pl` tests actual waiting/blocked clients, SQL workloads, reset and
restart handling, ACLs, collector lifecycle and storage bounds. Its small
single-client timing is a smoke measurement, not a production overhead result;
benchmark the chosen settings against your application's concurrency and SQL
cardinality before deploying. Make was exercised; Meson wiring is provided but
a separate Meson build is not claimed.
