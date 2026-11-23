--
-- DBMS_ERRLOG
--
-- Regression tests for Oracle-compatible DBMS_ERRLOG package:
--   - CREATE_ERROR_LOG with default error log table name (ERR$_<table_name>)
--   - CREATE_ERROR_LOG with explicit custom error log table name
--   - Verify schema and column structure of created error log tables
--   - Verify sys.errlog_tables registry
--   - PURGE_ERROR_LOG procedure
--   - DROP_ERROR_LOG procedure
--   - Error handling (non-existent table, NULL parameter)
--   - Internal function execute privilege revoked from PUBLIC (CWE-862)
--

-- Setup sample base tables
CREATE TABLE base_customer (
    cust_id int,
    cust_name varchar2(100),
    balance numeric(10,2)
);

CREATE TABLE base_orders (
    order_id int,
    order_date date,
    amount numeric(12,2)
);

-- CREATE_ERROR_LOG with default name (ERR$_base_customer)
CALL dbms_errlog.create_error_log(
    dml_table_name => 'base_customer'
);

-- Verify ERR$_base_customer columns
SELECT column_name, data_type
  FROM information_schema.columns
 WHERE table_name = 'err$_base_customer'
 ORDER BY ordinal_position;

-- Verify registry in sys.errlog_tables
SELECT dml_table_name, err_log_table_name, err_log_owner
  FROM sys.errlog_tables
 WHERE dml_table_name = 'base_customer';

-- CREATE_ERROR_LOG with explicit name
CALL dbms_errlog.create_error_log(
    dml_table_name     => 'base_orders',
    err_log_table_name => 'custom_orders_errlog'
);

-- Verify custom_orders_errlog columns
SELECT column_name, data_type
  FROM information_schema.columns
 WHERE table_name = 'custom_orders_errlog'
 ORDER BY ordinal_position;

-- PURGE_ERROR_LOG
CALL dbms_errlog.purge_error_log('base_customer');

-- DROP_ERROR_LOG
CALL dbms_errlog.drop_error_log('base_customer');
SELECT COUNT(*) FROM sys.errlog_tables WHERE dml_table_name = 'base_customer';

CALL dbms_errlog.drop_error_log('base_orders', 'custom_orders_errlog');
SELECT COUNT(*) FROM sys.errlog_tables WHERE dml_table_name = 'base_orders';

-- Error handling: non-existent table
SELECT sys.dbms_errlog_create_error_log_internal('non_existent_table_xyz', NULL, NULL, false);
SELECT sys.dbms_errlog_drop_error_log_internal(NULL, NULL);
SELECT sys.dbms_errlog_purge_error_log_internal(NULL, NULL);

-- Error handling: NULL parameter
SELECT sys.dbms_errlog_create_error_log_internal(NULL, NULL, NULL, false);

-- Verify internal functions execute privilege revoked from PUBLIC (CWE-862)
SELECT p.proname, has_function_privilege('public', p.oid, 'EXECUTE') AS public_can_execute
  FROM pg_catalog.pg_proc p
  JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'sys'
   AND p.proname IN ('dbms_errlog_create_error_log_internal',
                     'dbms_errlog_drop_error_log_internal',
                     'dbms_errlog_purge_error_log_internal')
 ORDER BY p.proname;

-- Clean up
DROP TABLE base_orders;
DROP TABLE base_customer;
