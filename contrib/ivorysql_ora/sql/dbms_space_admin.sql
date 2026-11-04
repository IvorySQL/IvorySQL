--
-- DBMS_SPACE_ADMIN
--
-- Regression tests for Oracle-compatible DBMS_SPACE_ADMIN package:
--   - Package constants
--   - TABLESPACE_VERIFY
--   - SEGMENT_VERIFY
--   - TABLESPACE_FIX_SEGMENT_STATES
--   - Error handling (non-existent tablespace, missing segment, NULL parameters)
--   - Internal function execute privilege revoked from PUBLIC (CWE-862)
--

-- Package constants
SELECT dbms_space_admin.segment_verify_basic;
SELECT dbms_space_admin.segment_verify_deep;
SELECT dbms_space_admin.tablespace_verify_basic;
SELECT dbms_space_admin.tablespace_verify_extents;

-- Setup test segment
CREATE TABLE space_admin_tab (
    id int,
    data text
);

INSERT INTO space_admin_tab VALUES (1, 'space admin test data');

-- TABLESPACE_VERIFY on default tablespace
CALL dbms_space_admin.tablespace_verify('pg_default');
CALL dbms_space_admin.tablespace_verify('pg_default', dbms_space_admin.tablespace_verify_extents);

-- SEGMENT_VERIFY on test table
CALL dbms_space_admin.segment_verify(
    schema_name  => 'public',
    segment_name => 'space_admin_tab',
    segment_type => 'TABLE',
    verify_mode  => dbms_space_admin.segment_verify_basic
);

CALL dbms_space_admin.segment_verify(
    segment_name => 'space_admin_tab'
);

-- TABLESPACE_FIX_SEGMENT_STATES
CALL dbms_space_admin.tablespace_fix_segment_states('pg_default');

-- Error handling: non-existent tablespace
SELECT sys.dbms_space_admin_tablespace_verify_internal('non_existent_tablespace_xyz', 1);
SELECT sys.dbms_space_admin_tablespace_fix_segment_states_internal('non_existent_tablespace_xyz');

-- Error handling: non-existent segment
SELECT sys.dbms_space_admin_segment_verify_internal('public', 'non_existent_table_xyz', 'TABLE', 1);

-- Error handling: NULL parameter checks
SELECT sys.dbms_space_admin_tablespace_verify_internal(NULL, 1);
SELECT sys.dbms_space_admin_segment_verify_internal('public', NULL, 'TABLE', 1);
SELECT sys.dbms_space_admin_tablespace_fix_segment_states_internal(NULL);

-- Verify internal functions execute privilege revoked from PUBLIC (CWE-862)
SELECT p.proname, has_function_privilege('public', p.oid, 'EXECUTE') AS public_can_execute
  FROM pg_catalog.pg_proc p
  JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'sys'
   AND p.proname IN ('dbms_space_admin_tablespace_verify_internal',
                     'dbms_space_admin_segment_verify_internal',
                     'dbms_space_admin_tablespace_fix_segment_states_internal')
 ORDER BY p.proname;

-- Clean up
DROP TABLE space_admin_tab;
