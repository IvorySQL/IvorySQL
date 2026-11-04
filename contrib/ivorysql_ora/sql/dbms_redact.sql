--
-- DBMS_REDACT
--
-- Regression tests for Oracle-compatible DBMS_REDACT package:
--   - Package constants (full, partial, random, none, regexp)
--   - ADD_POLICY
--   - DISABLE_POLICY / ENABLE_POLICY
--   - Catalog tables verification (sys.redaction_policies, sys.redaction_columns)
--   - DROP_POLICY
--   - Error handling (NULL arguments, invalid function_type)
--   - Internal function execute privilege revoked from PUBLIC (CWE-862)
--

-- Package constants
SELECT dbms_redact.full;
SELECT dbms_redact.partial;
SELECT dbms_redact.random;
SELECT dbms_redact.none;
SELECT dbms_redact.regexp;

-- Setup test table
CREATE TABLE customer_data (
    cust_id int,
    id_card varchar2(50),
    phone varchar2(50)
);

-- ADD_POLICY: full redaction on id_card
CALL dbms_redact.add_policy(
    object_schema       => 'public',
    object_name         => 'customer_data',
    policy_name         => 'redact_cust_id_card',
    column_name         => 'id_card',
    function_type       => dbms_redact.full,
    expression          => '1=1',
    enable              => TRUE,
    policy_description  => 'Full redaction policy for customer ID card'
);

-- Verify policy in catalog
SELECT object_owner, object_name, policy_name, enable, policy_description
  FROM sys.redaction_policies
 WHERE policy_name = 'redact_cust_id_card';

SELECT object_owner, object_name, policy_name, column_name, function_type
  FROM sys.redaction_columns
 WHERE policy_name = 'redact_cust_id_card';

-- DISABLE_POLICY
CALL dbms_redact.disable_policy(
    object_schema => 'public',
    object_name   => 'customer_data',
    policy_name   => 'redact_cust_id_card'
);

SELECT policy_name, enable
  FROM sys.redaction_policies
 WHERE policy_name = 'redact_cust_id_card';

-- ENABLE_POLICY
CALL dbms_redact.enable_policy(
    object_schema => 'public',
    object_name   => 'customer_data',
    policy_name   => 'redact_cust_id_card'
);

SELECT policy_name, enable
  FROM sys.redaction_policies
 WHERE policy_name = 'redact_cust_id_card';

-- DROP_POLICY
CALL dbms_redact.drop_policy(
    object_schema => 'public',
    object_name   => 'customer_data',
    policy_name   => 'redact_cust_id_card'
);

SELECT COUNT(*) FROM sys.redaction_policies WHERE policy_name = 'redact_cust_id_card';
SELECT COUNT(*) FROM sys.redaction_columns WHERE policy_name = 'redact_cust_id_card';

-- Error handling: NULL object_name or policy_name
SELECT sys.dbms_redact_add_policy_internal('public', NULL, 'p1', '1=1', 1, 'c1', NULL, NULL, true);
SELECT sys.dbms_redact_add_policy_internal('public', 't1', 'p1', '1=1', 99, 'c1', NULL, NULL, true);
SELECT sys.dbms_redact_drop_policy_internal('public', NULL, 'p1');

-- Verify internal functions execute privilege revoked from PUBLIC (CWE-862)
SELECT p.proname, has_function_privilege('public', p.oid, 'EXECUTE') AS public_can_execute
  FROM pg_catalog.pg_proc p
  JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'sys'
   AND p.proname IN ('dbms_redact_add_policy_internal',
                     'dbms_redact_drop_policy_internal',
                     'dbms_redact_enable_policy_internal',
                     'dbms_redact_disable_policy_internal')
 ORDER BY p.proname;

-- Clean up
DROP TABLE customer_data;
