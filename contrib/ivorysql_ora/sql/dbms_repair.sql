--
-- DBMS_REPAIR
--
-- Regression tests for Oracle-compatible DBMS_REPAIR package:
--   - Package constants (table types, admin actions, skip flags)
--   - ADMIN_TABLES (CREATE, PURGE, DROP) for repair and orphan tables
--   - CHECK_OBJECT procedure (detects corrupt blocks)
--   - FIX_CORRUPT_BLOCKS procedure
--   - SKIP_CORRUPT_BLOCKS procedure
--   - Error handling (non-existent object, NULL parameters)
--   - Internal function execute privilege revoked from PUBLIC (CWE-862)
--

-- Package constants
SELECT dbms_repair.repair_table;
SELECT dbms_repair.orphan_table;
SELECT dbms_repair.create_action;
SELECT dbms_repair.purge_action;
SELECT dbms_repair.drop_action;
SELECT dbms_repair.skip_flag;
SELECT dbms_repair.noskip_flag;

-- Setup test table
CREATE TABLE repair_test_tab (
    id int,
    val varchar2(200)
);

INSERT INTO repair_test_tab VALUES (1, 'repair test data'), (2, 'repair test row 2');

-- ADMIN_TABLES: create repair table
CALL dbms_repair.admin_tables(
    table_name => 'my_repair_table',
    table_type => dbms_repair.repair_table,
    action     => dbms_repair.create_action
);

-- Verify repair table structure
SELECT column_name, data_type
  FROM information_schema.columns
 WHERE table_name = 'my_repair_table'
 ORDER BY ordinal_position;

-- ADMIN_TABLES: create orphan table
CALL dbms_repair.admin_tables(
    table_name => 'my_orphan_table',
    table_type => dbms_repair.orphan_table,
    action     => dbms_repair.create_action
);

SELECT column_name, data_type
  FROM information_schema.columns
 WHERE table_name = 'my_orphan_table'
 ORDER BY ordinal_position;

-- CHECK_OBJECT
DO $$
DECLARE
    cc NUMBER;
BEGIN
    dbms_repair.check_object(
        schema_name       => 'public',
        object_name       => 'repair_test_tab',
        corrupt_count     => cc,
        repair_table_name => 'my_repair_table'
    );
    RAISE NOTICE 'CHECK_OBJECT: corrupt_count: %', cc;
END;
$$;

-- FIX_CORRUPT_BLOCKS
DO $$
DECLARE
    fc NUMBER;
BEGIN
    dbms_repair.fix_corrupt_blocks(
        schema_name => 'public',
        object_name => 'repair_test_tab',
        fix_count   => fc
    );
    RAISE NOTICE 'FIX_CORRUPT_BLOCKS: fix_count: %', fc;
END;
$$;

-- SKIP_CORRUPT_BLOCKS
CALL dbms_repair.skip_corrupt_blocks(
    schema_name => 'public',
    object_name => 'repair_test_tab',
    flags       => dbms_repair.skip_flag
);

-- ADMIN_TABLES: purge repair table
CALL dbms_repair.admin_tables(
    table_name => 'my_repair_table',
    table_type => dbms_repair.repair_table,
    action     => dbms_repair.purge_action
);

-- ADMIN_TABLES: drop tables
CALL dbms_repair.admin_tables(
    table_name => 'my_repair_table',
    table_type => dbms_repair.repair_table,
    action     => dbms_repair.drop_action
);

CALL dbms_repair.admin_tables(
    table_name => 'my_orphan_table',
    table_type => dbms_repair.orphan_table,
    action     => dbms_repair.drop_action
);

-- Error handling: non-existent object
SELECT sys.dbms_repair_check_object_internal('public', 'non_existent_table_xyz', 'my_repair_table');

-- Error handling: NULL parameter checks
SELECT sys.dbms_repair_admin_tables_internal(NULL, 1, 1, NULL);
SELECT sys.dbms_repair_check_object_internal('public', NULL, 'my_repair_table');
SELECT sys.dbms_repair_fix_corrupt_blocks_internal('public', NULL);
SELECT sys.dbms_repair_skip_corrupt_blocks_internal('public', NULL, 1);

-- Verify internal functions execute privilege revoked from PUBLIC (CWE-862)
SELECT p.proname, has_function_privilege('public', p.oid, 'EXECUTE') AS public_can_execute
  FROM pg_catalog.pg_proc p
  JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'sys'
   AND p.proname IN ('dbms_repair_admin_tables_internal',
                     'dbms_repair_check_object_internal',
                     'dbms_repair_fix_corrupt_blocks_internal',
                     'dbms_repair_skip_corrupt_blocks_internal')
 ORDER BY p.proname;

-- Clean up
DROP TABLE repair_test_tab;
