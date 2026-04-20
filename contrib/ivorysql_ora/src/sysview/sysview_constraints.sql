-- DBA_CONS_COLUMNS
CREATE OR REPLACE VIEW sys.dba_cons_columns AS
SELECT
    SYS.ORA_CASE_TRANS(pg_get_userbyid(n.oid)::varchar2(128)) AS owner,
    SYS.ORA_CASE_TRANS(c.conname::varchar2(128)) AS constraint_name,
    SYS.ORA_CASE_TRANS(cl.relname::varchar2(128)) AS table_name,
    SYS.ORA_CASE_TRANS(a.attname::varchar2(128)) AS column_name,
    (row_number() OVER (PARTITION BY c.oid ORDER BY a.attnum))::int AS position,
    CASE WHEN a.attnotnull THEN 'Y' ELSE 'N' END AS nullable
FROM pg_constraint c
JOIN pg_class cl ON c.conrelid = cl.oid
JOIN pg_namespace n ON cl.relnamespace = n.oid
JOIN pg_attribute a ON a.attrelid = cl.oid AND a.attnum = ANY(c.conkey)
WHERE cl.relkind = 'r'
  AND a.attisdropped = false
  AND n.nspname NOT IN ('pg_catalog', 'information_schema');

GRANT SELECT ON sys.dba_cons_columns TO PUBLIC;
