--
-- DBMS_RLS
--
-- Regression tests for Oracle-compatible DBMS_RLS package:
--   - Package constants (policy types, sec_relevant_cols options)
--   - ADD_POLICY
--   - ENABLE_POLICY (disable and enable)
--   - REFRESH_POLICY
--   - Catalog table verification (sys.rls_policies)
--   - DROP_POLICY
--   - Error handling (NULL parameter checks)
--   - Internal function execute privilege revoked from PUBLIC (CWE-862)
--

-- Package constants
SELECT dbms_rls.dynamic;
SELECT dbms_rls.static_policy;
SELECT dbms_rls.shared_static;
SELECT dbms_rls.context_sensitive;
SELECT dbms_rls.shared_context_sensitive;
SELECT dbms_rls.all_rows;

-- Setup test table
CREATE TABLE emp_secure (
    empno int,
    ename varchar2(50),
    deptno int
);

-- ADD_POLICY
CALL dbms_rls.add_policy(
    object_schema   => 'public',
    object_name     => 'emp_secure',
    policy_name     => 'dept_security_policy',
    function_schema => 'public',
    policy_function => 'get_dept_predicate',
    statement_types => 'SELECT,UPDATE,DELETE',
    update_check    => TRUE,
    enable          => TRUE
);

-- Verify policy in sys.rls_policies
SELECT object_owner, object_name, policy_name, function_owner, policy_function, statement_types, update_check, enable
  FROM sys.rls_policies
 WHERE policy_name = 'dept_security_policy';

-- ENABLE_POLICY (disable)
CALL dbms_rls.enable_policy(
    object_schema => 'public',
    object_name   => 'emp_secure',
    policy_name   => 'dept_security_policy',
    enable        => FALSE
);

SELECT policy_name, enable
  FROM sys.rls_policies
 WHERE policy_name = 'dept_security_policy';

-- ENABLE_POLICY (re-enable)
CALL dbms_rls.enable_policy(
    object_schema => 'public',
    object_name   => 'emp_secure',
    policy_name   => 'dept_security_policy',
    enable        => TRUE
);

SELECT policy_name, enable
  FROM sys.rls_policies
 WHERE policy_name = 'dept_security_policy';

-- REFRESH_POLICY
CALL dbms_rls.refresh_policy('public', 'emp_secure', 'dept_security_policy');

-- DROP_POLICY
CALL dbms_rls.drop_policy(
    object_schema => 'public',
    object_name   => 'emp_secure',
    policy_name   => 'dept_security_policy'
);

SELECT COUNT(*) FROM sys.rls_policies WHERE policy_name = 'dept_security_policy';

-- Error handling: NULL parameters
SELECT sys.dbms_rls_add_policy_internal('public', NULL, 'p1', 'public', 'f1', 'SELECT', false, true, false, 1, NULL, 0);
SELECT sys.dbms_rls_add_policy_internal('public', 't1', NULL, 'public', 'f1', 'SELECT', false, true, false, 1, NULL, 0);
SELECT sys.dbms_rls_drop_policy_internal('public', NULL, 'p1');
SELECT sys.dbms_rls_enable_policy_internal('public', NULL, 'p1', true);

-- Verify internal functions execute privilege revoked from PUBLIC (CWE-862)
SELECT p.proname, has_function_privilege('public', p.oid, 'EXECUTE') AS public_can_execute
  FROM pg_catalog.pg_proc p
  JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'sys'
   AND p.proname IN ('dbms_rls_add_policy_internal',
                     'dbms_rls_drop_policy_internal',
                     'dbms_rls_enable_policy_internal')
 ORDER BY p.proname;

-- Clean up
DROP TABLE emp_secure;
