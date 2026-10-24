# DBMS_STATS: transactional optimizer statistics management

This invoker-rights package supports collecting, reading, changing, deleting,
exporting and importing PostgreSQL optimizer statistics through Oracle-style
package calls. It is part of `ivorysql_ora`; initialize a new Oracle-mode cluster
with the updated extension SQL. Copying the shared library does not add SQL
objects to an existing cluster.

```sql
CREATE TABLE public.stats_demo AS
SELECT g AS id, 'group ' || g % 7 AS category FROM generate_series(1,1000) g;

DECLARE
  rows_est NUMBER;
  blocks_est NUMBER;
  avg_len NUMBER;
BEGIN
  dbms_stats.gather_table_stats('public', 'stats_demo');
  dbms_stats.create_stat_table('public', 'stats_backup');
  dbms_stats.export_table_stats(ownname=>'public', tabname=>'stats_demo',
                              stattab=>'stats_backup', statid=>'before');
  dbms_stats.set_table_stats(ownname=>'public', tabname=>'stats_demo', numrows=>50000);
  dbms_stats.import_table_stats(ownname=>'public', tabname=>'stats_demo',
                              stattab=>'stats_backup', statid=>'before');
  dbms_stats.get_table_stats(ownname=>'public', tabname=>'stats_demo',
                            numrows=>rows_est, numblks=>blocks_est, avgrlen=>avg_len);
  dbms_output.put_line(rows_est);
  dbms_stats.drop_stat_table('public', 'stats_backup');
END;
/
```

`GATHER_SCHEMA_STATS`, `DELETE_TABLE_STATS` and `DELETE_COLUMN_STATS` complete
the ten-procedure interface. Collection runs actual `ANALYZE`. The setter and
importer use the core statistics-manipulation functions, so changes affect
optimizer estimates and participate in the caller's transaction.

Export stores relation statistics and the `pg_stats` fields for the table and
its indexes, including expression-index column statistics. Array, range,
histogram and most-common-value fields are included. Import validates table
column names/types/collations and the index set/definitions before clearing
existing statistics. A failed conversion raises an error and rolls the entire
call back. Multiple snapshots are selected by `statid`; exporting the same
object/id replaces its snapshot. The versioned staging format is specific to
this implementation and is not Oracle's statistics table format.

Every operation runs as the invoking role. Changing statistics requires
`MAINTAIN` or database ownership, and schema `USAGE`. Export additionally
requires table `SELECT` and unrestricted row visibility; staging-table DDL and
DML retain ordinary privileges. No helper is `SECURITY DEFINER`. Names use
PostgreSQL identifier folding; double-quoted components preserve case. Owner
and object arguments each accept one component, never interpolated SQL text.
Helpers pin their parsing dialect, identifier mode and search path, so package
calls also work in the three supported identifier-case modes.

Compatibility boundaries:

- The signatures preserve the implemented Oracle positional prefixes. Named
  arguments are recommended. Parameters after those prefixes are not exposed.
- Ordinary tables and materialized views are supported. Partitioned parent
  tables and foreign tables are rejected. Collection uses PostgreSQL automatic
  sampling, its statistics targets, and its index-analysis rules. Explicit
  `estimate_percent`, non-default `method_opt`, `degree`, `cascade` or
  `granularity` options are rejected rather than ignored.
- Export/import implement `cascade => TRUE` (table, columns and indexes).
  Partition selection and `cascade => FALSE` are rejected. GET/SET operate on
  catalog statistics, not a staging table. `numrows` and `numblks` map to
  `reltuples` and `relpages`; `avgrlen` is returned as NULL because PostgreSQL
  does not store Oracle's average-row-length statistic.
- No Oracle implicit commits, statistics locks, history retention, incremental
  partition statistics, extended-statistics export, or Oracle histogram format
  equivalence is claimed. Autovacuum or a later ANALYZE may overwrite restored
  statistics. Staging tables should be treated as trusted maintenance data.
- Column type OIDs and PostgreSQL representations are checked. This first
  format is intended for the same database, not arbitrary cross-version or
  cross-database statistics transport. No live Oracle comparison was performed.

`t/004_dbms_stats.pl` exercises the public package, optimizer estimates,
round-trip data, quoted identifiers, permission boundaries and transactional
failure recovery on a freshly initialized cluster.
