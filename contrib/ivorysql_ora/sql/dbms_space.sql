--
-- DBMS_SPACE
--
-- Regression tests for Oracle-compatible DBMS_SPACE package:
--   - UNUSED_SPACE
--   - SPACE_USAGE
--   - Schema qualification & parameter error checks
--   - Non-existent relation error checks
--   - Internal function execute privilege revoked from PUBLIC (CWE-862)
--

-- Setup test table
CREATE TABLE space_test_tab (
    id int,
    val varchar2(200)
);

INSERT INTO space_test_tab SELECT generate_series(1, 100), 'space test row value';

-- Test UNUSED_SPACE via anonymous block
DO $$
DECLARE
    tb  NUMBER;
    tb_bytes NUMBER;
    ub  NUMBER;
    ub_bytes NUMBER;
    lu_fid NUMBER;
    lu_bid NUMBER;
    lu_blk NUMBER;
BEGIN
    dbms_space.unused_space(NULL, 'space_test_tab', 'TABLE',
                            tb, tb_bytes, ub, ub_bytes,
                            lu_fid, lu_bid, lu_blk);
    RAISE NOTICE 'UNUSED_SPACE: total_blocks >= 1: %, total_bytes >= 8192: %',
                 (tb >= 1), (tb_bytes >= 8192);
    RAISE NOTICE 'UNUSED_SPACE: last_used_extent_file_id: %, last_used_block >= 1: %',
                 lu_fid, (lu_blk >= 1);
END;
$$;

-- Test SPACE_USAGE via anonymous block
DO $$
DECLARE
    ublocks NUMBER;
    ubytes  NUMBER;
    fs1b NUMBER; fs1by NUMBER;
    fs2b NUMBER; fs2by NUMBER;
    fs3b NUMBER; fs3by NUMBER;
    fs4b NUMBER; fs4by NUMBER;
    fullb NUMBER; fullby NUMBER;
BEGIN
    dbms_space.space_usage(NULL, 'space_test_tab', 'TABLE',
                           ublocks, ubytes,
                           fs1b, fs1by, fs2b, fs2by, fs3b, fs3by, fs4b, fs4by,
                           fullb, fullby);
    RAISE NOTICE 'SPACE_USAGE: full_blocks >= 1: %, full_bytes >= 8192: %',
                 (fullb >= 1), (fullby >= 8192);
    RAISE NOTICE 'SPACE_USAGE: unformatted_blocks: %', ublocks;
END;
$$;

-- Direct internal resolver function tests
SELECT total_blocks >= 1 AS tb_ok,
       total_bytes >= 8192 AS tb_bytes_ok,
       unused_blocks,
       unused_bytes,
       last_used_extent_file_id,
       last_used_extent_block_id,
       last_used_block >= 1 AS lu_blk_ok
  FROM sys.dbms_space_unused_space_internal(NULL, 'space_test_tab', 'TABLE', NULL);

SELECT unformatted_blocks,
       unformatted_bytes,
       fs1_blocks,
       fs2_blocks,
       fs3_blocks,
       fs4_blocks,
       full_blocks >= 1 AS full_blocks_ok,
       full_bytes >= 8192 AS full_bytes_ok
  FROM sys.dbms_space_space_usage_internal(NULL, 'space_test_tab', 'TABLE', NULL);

-- Error handling: NULL or empty segment name
SELECT sys.dbms_space_unused_space_internal(NULL, NULL, 'TABLE', NULL);
SELECT sys.dbms_space_unused_space_internal(NULL, '', 'TABLE', NULL);
SELECT sys.dbms_space_space_usage_internal(NULL, NULL, 'TABLE', NULL);

-- Error handling: Non-existent object
SELECT sys.dbms_space_unused_space_internal(NULL, 'non_existent_table_xyz', 'TABLE', NULL);
SELECT sys.dbms_space_space_usage_internal('public', 'non_existent_table_xyz', 'TABLE', NULL);

-- Verify internal functions execute privilege revoked from PUBLIC (CWE-862)
SELECT p.proname, has_function_privilege('public', p.oid, 'EXECUTE') AS public_can_execute
  FROM pg_catalog.pg_proc p
  JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'sys'
   AND p.proname IN ('dbms_space_unused_space_internal',
                     'dbms_space_space_usage_internal')
 ORDER BY p.proname;

-- Clean up
DROP TABLE space_test_tab;
