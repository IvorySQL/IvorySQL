SET IVORYSQL.COMPATIBLE_MODE TO ORACLE;
SET IVORYSQL.IDENTIFIER_CASE_SWITCH = INTERCHANGE;

CREATE ROLE regress_args_owner;
CREATE ROLE regress_args_reader;
CREATE SCHEMA ora_args AUTHORIZATION regress_args_owner;
SET ROLE regress_args_owner;
SET SEARCH_PATH = ora_args, sys, public;

-- No-argument procedures have no argument rows; functions retain their return.
CREATE PROCEDURE args_empty IS BEGIN NULL; END;
/
CREATE FUNCTION args_empty_f RETURN NUMBER IS BEGIN RETURN 1; END;
/
CREATE PROCEDURE args_mixed(a IN NUMBER, b OUT VARCHAR2, c IN OUT NUMBER,
                           d IN NUMBER DEFAULT NULL) IS
BEGIN b := 'ok'; END;
/
CREATE PROCEDURE args_out(a OUT NUMBER) IS BEGIN a := 1; END;
/
CREATE FUNCTION args_f(a IN NUMBER DEFAULT 10) RETURN NUMBER IS
BEGIN RETURN a; END;
/
SELECT object_name, argument_name, position, sequence, in_out, defaulted
FROM user_arguments WHERE object_name LIKE 'ARGS_%'
ORDER BY object_name, sequence;
SELECT (SELECT count(*) FROM all_arguments WHERE object_name = 'ARGS_EMPTY') AS all_rows,
       (SELECT count(*) FROM dba_arguments WHERE object_name = 'ARGS_EMPTY') AS dba_rows;

-- Public package declarations, including overloads, are visible without a body.
CREATE PACKAGE args_pkg AS
  PROCEDURE empty_p;
  FUNCTION empty_f RETURN NUMBER;
  PROCEDURE mixed(a IN NUMBER, b OUT VARCHAR2, c IN OUT NUMBER,
                  d IN NUMBER DEFAULT NULL);
  FUNCTION twice(a NUMBER) RETURN NUMBER;
  FUNCTION twice(a VARCHAR2) RETURN VARCHAR2;
END;
/
SELECT package_name, object_name, overload, subprogram_id, argument_name,
       position, sequence, in_out, defaulted, data_type
FROM all_arguments WHERE package_name = 'ARGS_PKG'
ORDER BY subprogram_id, sequence;
SELECT count(*) AS argument_rows,
       count(DISTINCT object_id) AS package_objects,
       bool_and(object_id = (SELECT oid::TEXT::NUMBER FROM pg_package WHERE pkgname = 'args_pkg'
                           AND pkgnamespace = 'ora_args'::REGNAMESPACE)) AS package_oid,
       bool_and(data_level = 0) AS top_level
FROM user_arguments WHERE package_name = 'ARGS_PKG';
SELECT count(*) AS dba_rows FROM dba_arguments WHERE package_name = 'ARGS_PKG';

-- Dictionary reads must not execute package initialization or expose private code.
CREATE TABLE args_init_log(n NUMBER);
CREATE PACKAGE BODY args_pkg AS
  FUNCTION private_f(a NUMBER) RETURN NUMBER IS BEGIN RETURN a; END;
  PROCEDURE empty_p IS BEGIN NULL; END;
  FUNCTION empty_f RETURN NUMBER IS BEGIN RETURN 1; END;
  PROCEDURE mixed(a IN NUMBER, b OUT VARCHAR2, c IN OUT NUMBER,
                  d IN NUMBER DEFAULT NULL) IS BEGIN b := 'ok'; END;
  FUNCTION twice(a NUMBER) RETURN NUMBER IS BEGIN RETURN a * 2; END;
  FUNCTION twice(a VARCHAR2) RETURN VARCHAR2 IS BEGIN RETURN a || a; END;
BEGIN
  INSERT INTO args_init_log VALUES (1);
END;
/
SELECT count(*) AS public_rows,
       count(*) FILTER (WHERE object_name = 'PRIVATE_F') AS private_rows
FROM all_arguments WHERE package_name = 'ARGS_PKG';
CREATE FUNCTION args_read_dict RETURN NUMBER IS
  n NUMBER;
BEGIN
  SELECT count(*) INTO n FROM all_arguments WHERE package_name = 'ARGS_PKG';
  RETURN n;
END;
/
DISCARD PACKAGE;
SELECT args_read_dict() AS nested_dictionary_read FROM dual;
SELECT count(*) AS initializations FROM args_init_log;
SELECT args_pkg.empty_f() AS package_call FROM dual;
SELECT count(*) AS initializations_after_call FROM args_init_log;

-- Package %TYPE metadata: unconstrained numbers have no precision/scale;
-- constrained numbers retain a signed scale, including for function returns.
CREATE TABLE args_types(n NUMBER(6,-2), v VARCHAR2(12));
CREATE PACKAGE args_types_pkg AS
  FUNCTION typed(a args_types.n%TYPE, b args_types.v%TYPE) RETURN args_types.n%TYPE;
  PROCEDURE unconstrained(n NUMBER);
  PROCEDURE row_arg(a args_types%ROWTYPE);
END;
/
SELECT object_name, argument_name, position, sequence, data_type,
       data_length, data_precision, data_scale
FROM all_arguments WHERE package_name = 'ARGS_TYPES_PKG'
ORDER BY subprogram_id, sequence;

SELECT object_name, type_name, type_object_type, data_type, data_level
FROM all_arguments WHERE package_name = 'ARGS_TYPES_PKG' AND object_name = 'ROW_ARG';

-- A replacement specification must invalidate cached argument metadata.
CREATE PACKAGE args_replace AS PROCEDURE p(a NUMBER); END;
/
SELECT object_name, argument_name, position, defaulted FROM user_arguments
WHERE package_name = 'ARGS_REPLACE' ORDER BY sequence;
CREATE OR REPLACE PACKAGE args_replace AS
  PROCEDURE p(a NUMBER, b VARCHAR2 DEFAULT 'x');
END;
/
SELECT object_name, argument_name, position, defaulted FROM user_arguments
WHERE package_name = 'ARGS_REPLACE' ORDER BY sequence;

-- An invalid specification must not block metadata for other routines.
CREATE TABLE args_dependency(n NUMBER);
CREATE PACKAGE args_broken AS
  PROCEDURE p(a args_dependency.n%TYPE);
END;
/
SELECT count(*) AS before_drop FROM all_arguments WHERE package_name = 'ARGS_BROKEN';
DROP TABLE args_dependency;
SELECT count(*) AS other_rows FROM all_arguments WHERE package_name = 'ARGS_PKG';
SELECT count(*) AS broken_rows FROM all_arguments WHERE package_name = 'ARGS_BROKEN';
RESET ROLE;
SET ROLE regress_args_reader;
SELECT count(*) AS foreign_package_rows FROM dba_arguments WHERE package_name = 'ARGS_PKG';
SELECT current_user = 'regress_args_reader' AS reader_identity_restored;
RESET ROLE;
SET ROLE regress_args_owner;
SELECT current_user = 'regress_args_owner' AS identity_restored,
       current_setting('search_path') = 'ora_args, sys, public' AS path_restored;
CREATE TABLE args_dependency(n NUMBER);
SELECT count(*) AS recovered_rows FROM all_arguments WHERE package_name = 'ARGS_BROKEN';
DROP PACKAGE args_broken;
DROP TABLE args_dependency;

-- Unnamed PostgreSQL arguments still produce rows, unlike an empty procedure.
SET IVORYSQL.COMPATIBLE_MODE TO PG;
CREATE FUNCTION ora_args.args_unnamed(integer, text) RETURNS integer
AS 'SELECT $1' LANGUAGE SQL;
/
SET IVORYSQL.COMPATIBLE_MODE TO ORACLE;
SELECT object_name, argument_name, position, sequence, in_out
FROM user_arguments WHERE object_name = 'ARGS_UNNAMED' ORDER BY sequence;

-- ALL_ARGUMENTS checks schema and routine privileges, USER_ARGUMENTS ownership.
REVOKE ALL ON PACKAGE args_pkg FROM PUBLIC;
REVOKE ALL ON PROCEDURE args_mixed FROM PUBLIC;
GRANT EXECUTE ON PACKAGE args_pkg TO regress_args_reader;
GRANT EXECUTE ON PACKAGE args_types_pkg TO regress_args_reader;
GRANT EXECUTE ON PROCEDURE args_mixed TO regress_args_reader;
RESET ROLE;
SET ROLE regress_args_reader;
SELECT count(*) AS no_schema_usage FROM all_arguments
WHERE package_name = 'ARGS_PKG' OR object_name = 'ARGS_MIXED';
RESET ROLE;
GRANT USAGE ON SCHEMA ora_args TO regress_args_reader;
SET ROLE regress_args_reader;
SET SEARCH_PATH = public, sys;
DISCARD PACKAGE;
-- Compile %TYPE references in the package schema, independent of caller path.
SELECT count(*) AS typed_rows FROM all_arguments WHERE package_name = 'ARGS_TYPES_PKG';
-- Repeated cache resets must not reuse discarded compiler state.
DISCARD PACKAGE;
SELECT count(*) AS typed_rows FROM all_arguments WHERE package_name = 'ARGS_TYPES_PKG';
SELECT current_user = 'regress_args_reader'
       AND current_setting('search_path') = 'public, sys' AS context_restored;
SELECT package_name, object_name, count(*) AS argument_rows
FROM all_arguments WHERE package_name = 'ARGS_PKG' OR object_name = 'ARGS_MIXED'
GROUP BY package_name, object_name ORDER BY package_name NULLS FIRST, object_name;
SELECT count(*) AS not_owned FROM user_arguments
WHERE package_name = 'ARGS_PKG' OR object_name = 'ARGS_MIXED';
SELECT count(*) AS dba_rows FROM dba_arguments WHERE package_name = 'ARGS_PKG';
RESET ROLE;
REVOKE EXECUTE ON PACKAGE ora_args.args_pkg FROM regress_args_reader;
REVOKE EXECUTE ON PROCEDURE ora_args.args_mixed FROM regress_args_reader;
SET ROLE regress_args_reader;
SELECT count(*) AS no_execute FROM all_arguments
WHERE package_name = 'ARGS_PKG' OR object_name = 'ARGS_MIXED';
RESET ROLE;

SET ROLE regress_args_owner;
SELECT count(*) AS owned_rows FROM user_arguments WHERE package_name = 'ARGS_PKG';
SET SEARCH_PATH = ora_args, sys, public;
-- Equal package names in separate schemas do not share overload numbering.
RESET ROLE;
CREATE SCHEMA ora_args_other;
CREATE PACKAGE ora_args.args_scope AS
  FUNCTION f(a NUMBER) RETURN NUMBER;
  FUNCTION f(a VARCHAR2) RETURN NUMBER;
END;
/
CREATE PACKAGE ora_args_other.args_scope AS
  FUNCTION f(a NUMBER) RETURN NUMBER;
END;
/
SELECT object_name, overload, subprogram_id, position, sequence,
       object_id = (SELECT oid::TEXT::NUMBER FROM pg_package WHERE pkgname = 'args_scope'
                    AND pkgnamespace = 'ora_args'::REGNAMESPACE) AS first_schema
FROM all_arguments WHERE package_name = 'ARGS_SCOPE'
ORDER BY first_schema DESC, subprogram_id, sequence;
DROP PACKAGE ora_args.args_scope;
DROP PACKAGE ora_args_other.args_scope;
DROP SCHEMA ora_args_other;
SET ROLE regress_args_owner;
DROP PACKAGE args_replace;
DROP PACKAGE args_types_pkg;
DROP PACKAGE args_pkg;
DROP PROCEDURE args_mixed;
DROP PROCEDURE args_empty;
DROP PROCEDURE args_out;
DROP FUNCTION args_empty_f;
DROP FUNCTION args_f;
DROP FUNCTION args_read_dict;
DROP FUNCTION args_unnamed;
DROP TABLE args_types;
DROP TABLE args_init_log;
RESET ROLE;
RESET SEARCH_PATH;
DROP SCHEMA ora_args;
DROP OWNED BY regress_args_reader;
DROP ROLE regress_args_reader;
DROP ROLE regress_args_owner;

-- Ownership checks also handle quoted role names without regrole folding.
CREATE ROLE "ArgsOwner";
GRANT CREATE ON SCHEMA public TO "ArgsOwner";
SET ROLE "ArgsOwner";
CREATE PROCEDURE public.args_quoted_owner(a IN NUMBER) IS BEGIN NULL; END;
/
SELECT count(*) AS quoted_owner_rows FROM user_arguments
WHERE object_name = 'ARGS_QUOTED_OWNER';
DROP PROCEDURE public.args_quoted_owner;
RESET ROLE;
REVOKE CREATE ON SCHEMA public FROM "ArgsOwner";
DROP ROLE "ArgsOwner";
