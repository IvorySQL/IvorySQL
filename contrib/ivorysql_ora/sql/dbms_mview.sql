--
-- DBMS_MVIEW
--
-- Regression tests for Oracle-compatible DBMS_MVIEW package:
--   - REFRESH on a single materialized view
--   - REFRESH on multiple comma-separated materialized views
--   - REFRESH_ALL_MVIEWS procedure
--   - PURGE_MVIEW_FROM_LOG procedure
--   - Error handling (NULL parameter, non-existent view)
--   - Internal function execute privilege revoked from PUBLIC (CWE-862)
--

-- Setup base tables and materialized views
CREATE TABLE mview_base_tab1 (
    id int,
    val text
);

CREATE TABLE mview_base_tab2 (
    id int,
    num_val numeric
);

INSERT INTO mview_base_tab1 VALUES (1, 'initial val');
INSERT INTO mview_base_tab2 VALUES (10, 100.50);

CREATE MATERIALIZED VIEW mv_test_view1 AS SELECT * FROM mview_base_tab1;
CREATE MATERIALIZED VIEW mv_test_view2 AS SELECT * FROM mview_base_tab2;

-- Verify initial data in materialized views
SELECT * FROM mv_test_view1;
SELECT * FROM mv_test_view2;

-- Update base tables
INSERT INTO mview_base_tab1 VALUES (2, 'second val');
INSERT INTO mview_base_tab2 VALUES (20, 200.75);

-- REFRESH single materialized view
CALL dbms_mview.refresh('mv_test_view1');
SELECT COUNT(*) FROM mv_test_view1;

-- REFRESH multiple comma-separated views
CALL dbms_mview.refresh('mv_test_view1, mv_test_view2');
SELECT COUNT(*) FROM mv_test_view1;
SELECT COUNT(*) FROM mv_test_view2;

-- REFRESH_ALL_MVIEWS
DO $$
DECLARE
    fails NUMBER;
BEGIN
    dbms_mview.refresh_all_mviews(fails);
    RAISE NOTICE 'REFRESH_ALL_MVIEWS: failures=%', fails;
END;
$$;

-- PURGE_MVIEW_FROM_LOG
CALL dbms_mview.purge_mview_from_log('mv_test_view1');

-- Error handling: NULL parameter
SELECT sys.dbms_mview_refresh_internal(NULL, '?', NULL, true, false, true, 0, false, true);
SELECT sys.dbms_mview_purge_mview_from_log_internal(NULL);

-- Verify internal functions execute privilege revoked from PUBLIC (CWE-862)
SELECT p.proname, has_function_privilege('public', p.oid, 'EXECUTE') AS public_can_execute
  FROM pg_catalog.pg_proc p
  JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'sys'
   AND p.proname IN ('dbms_mview_refresh_internal',
                     'dbms_mview_refresh_all_mviews_internal',
                     'dbms_mview_purge_mview_from_log_internal')
 ORDER BY p.proname;

-- Clean up
DROP MATERIALIZED VIEW mv_test_view1;
DROP MATERIALIZED VIEW mv_test_view2;
DROP TABLE mview_base_tab1;
DROP TABLE mview_base_tab2;
