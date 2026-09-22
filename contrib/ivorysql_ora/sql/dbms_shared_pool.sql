--
-- DBMS_SHARED_POOL
--
-- Regression tests for Oracle-compatible DBMS_SHARED_POOL package:
--   - KEEP procedure
--   - UNKEEP procedure
--   - PURGE procedure
--   - MARKHOT / UNMARKHOT procedures
--   - Pinned objects catalog table verification (sys.pinned_shared_objects)
--   - ABORTED_REQUEST_THRESHOLD configuration
--   - SIZES procedure
--   - Error handling (NULL parameter, negative threshold)
--   - Internal function execute privilege revoked from PUBLIC (CWE-862)
--

-- KEEP a package and a sequence
CALL dbms_shared_pool.keep('SYS.STANDARD', 'P');
CALL dbms_shared_pool.keep('TEST_SEQ', 'Q');

-- Verify pinned objects catalog table
SELECT name, flag, status FROM sys.pinned_shared_objects ORDER BY name;

-- KEEP idempotency (update existing entry)
CALL dbms_shared_pool.keep('SYS.STANDARD', 'P');
SELECT name, flag, status FROM sys.pinned_shared_objects WHERE name = 'SYS.STANDARD';

-- MARKHOT procedure
CALL dbms_shared_pool.markhot('SYS', 'HOT_PKG', 1);
SELECT name, flag, status FROM sys.pinned_shared_objects WHERE name = 'SYS.HOT_PKG';

-- UNMARKHOT procedure
CALL dbms_shared_pool.unmarkhot('SYS', 'HOT_PKG', 1);
SELECT COUNT(*) FROM sys.pinned_shared_objects WHERE name = 'SYS.HOT_PKG';

-- SIZES procedure
CALL dbms_shared_pool.sizes(100);

-- ABORTED_REQUEST_THRESHOLD procedure
CALL dbms_shared_pool.aborted_request_threshold(50000000);

-- PURGE procedure
CALL dbms_shared_pool.purge('TEST_SEQ', 'Q');
SELECT name, flag, status FROM sys.pinned_shared_objects ORDER BY name;

-- UNKEEP objects
CALL dbms_shared_pool.unkeep('SYS.STANDARD');
SELECT COUNT(*) FROM sys.pinned_shared_objects;

-- Error handling: NULL parameter
SELECT sys.dbms_shared_pool_keep_internal(NULL, 'P');
SELECT sys.dbms_shared_pool_unkeep_internal(NULL, 'P');
SELECT sys.dbms_shared_pool_purge_internal(NULL, 'P', 1);
SELECT sys.dbms_shared_pool_markhot_internal('SYS', NULL, 1);
SELECT sys.dbms_shared_pool_aborted_request_threshold_internal(-100);

-- Verify internal functions execute privilege revoked from PUBLIC (CWE-862)
SELECT p.proname, has_function_privilege('public', p.oid, 'EXECUTE') AS public_can_execute
  FROM pg_catalog.pg_proc p
  JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'sys'
   AND p.proname IN ('dbms_shared_pool_keep_internal',
                     'dbms_shared_pool_unkeep_internal',
                     'dbms_shared_pool_purge_internal',
                     'dbms_shared_pool_markhot_internal',
                     'dbms_shared_pool_unmarkhot_internal',
                     'dbms_shared_pool_aborted_request_threshold_internal')
 ORDER BY p.proname;
