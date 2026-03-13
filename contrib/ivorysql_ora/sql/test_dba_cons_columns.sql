-- Test if DBA_CONS_COLUMNS view exists
SELECT count(*) > 0 AS view_exists
FROM information_schema.views
WHERE table_schema = 'sys' AND table_name = 'dba_cons_columns';

-- Test if query can return data (at least no error)
SELECT * FROM sys.dba_cons_columns LIMIT 1;
