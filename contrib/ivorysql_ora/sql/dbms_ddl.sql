--
-- Tests for the DBMS_DDL package
--

SET ivorysql.compatible_mode = oracle;

CREATE TABLE ddl_t (a INT);
INSERT INTO ddl_t SELECT generate_series(1, 10);

CREATE OR REPLACE FUNCTION ddl_f RETURN int AS
BEGIN
    RETURN 1;
END;
/

CREATE OR REPLACE PROCEDURE ddl_p AS
BEGIN
    NULL;
END;
/

CREATE OR REPLACE PACKAGE ddl_pkg AS
    PROCEDURE p;
END;
/

CREATE OR REPLACE PACKAGE BODY ddl_pkg AS
    PROCEDURE p IS
    BEGIN
        NULL;
    END;
END;
/

-- ALTER_COMPILE: function, procedure and package; names may be passed in
-- Oracle's upper-case dictionary spelling.
CALL dbms_ddl.alter_compile('FUNCTION', current_schema, 'ddl_f');
CALL dbms_ddl.alter_compile('FUNCTION', current_schema, 'DDL_F');
CALL dbms_ddl.alter_compile('PROCEDURE', current_schema, 'ddl_p');
CALL dbms_ddl.alter_compile('PACKAGE', current_schema, 'ddl_pkg');

-- ANALYZE_OBJECT: COMPUTE and ESTIMATE both refresh the statistics.
CALL dbms_ddl.analyze_object('TABLE', current_schema, 'ddl_t', 'COMPUTE');
CALL dbms_ddl.analyze_object('TABLE', current_schema, 'ddl_t', 'ESTIMATE');

SELECT count(*) > 0 AS has_stats
FROM pg_stats
WHERE schemaname = current_schema AND tablename = 'ddl_t';

-- Error paths
CALL dbms_ddl.alter_compile('BOGUS', current_schema, 'ddl_f');
CALL dbms_ddl.alter_compile('FUNCTION', current_schema, 'no_such_object');
CALL dbms_ddl.alter_compile('PACKAGE', current_schema, 'no_such_package');
CALL dbms_ddl.analyze_object('INDEX', current_schema, 'ddl_t', 'COMPUTE');
CALL dbms_ddl.analyze_object('TABLE', current_schema, 'ddl_t', 'DELETE');
CALL dbms_ddl.alter_compile(NULL, current_schema, 'ddl_f');
CALL dbms_ddl.alter_compile('FUNCTION', current_schema, NULL);

DROP PACKAGE ddl_pkg;
DROP FUNCTION ddl_f;
DROP PROCEDURE ddl_p;
DROP TABLE ddl_t;
