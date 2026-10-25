-- Compatibility mode is required by the Oracle dictionary views.
SET IVORYSQL.COMPATIBLE_MODE TO ORACLE;
SET IVORYSQL.IDENTIFIER_CASE_SWITCH = INTERCHANGE;

-- Parameterless procedures have no rows, while functions retain their return row.
CREATE OR REPLACE PACKAGE args_test_pkg AS
  FUNCTION f(p_id IN NUMBER) RETURN NUMBER;
  PROCEDURE p(p_id IN NUMBER, p_name OUT VARCHAR2);
  PROCEDURE no_args;
END;
/

CREATE OR REPLACE PROCEDURE args_test_empty IS
BEGIN
  NULL;
END;
/

CREATE OR REPLACE FUNCTION args_test_empty_f RETURN NUMBER IS
BEGIN
  RETURN 1;
END;
/

SELECT object_name, package_name, argument_name, position, sequence, in_out
FROM sys.all_arguments
WHERE package_name = 'ARGS_TEST_PKG'
   OR object_name IN ('ARGS_TEST_EMPTY', 'ARGS_TEST_EMPTY_F')
ORDER BY package_name NULLS FIRST, object_name, sequence;

SELECT object_name, package_name, argument_name, position, sequence, in_out
FROM sys.user_arguments
WHERE package_name = 'ARGS_TEST_PKG'
   OR object_name IN ('ARGS_TEST_EMPTY', 'ARGS_TEST_EMPTY_F')
ORDER BY package_name NULLS FIRST, object_name, sequence;

SELECT object_name, package_name, argument_name, position, sequence, in_out
FROM sys.dba_arguments
WHERE package_name = 'ARGS_TEST_PKG'
   OR object_name IN ('ARGS_TEST_EMPTY', 'ARGS_TEST_EMPTY_F')
ORDER BY package_name NULLS FIRST, object_name, sequence;

DROP FUNCTION IF EXISTS args_test_empty_f;
DROP PROCEDURE IF EXISTS args_test_empty;
DROP PACKAGE args_test_pkg;
