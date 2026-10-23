--
-- PLS_INTEGER / BINARY_INTEGER declaration support
--

DO LANGUAGE plisql $$
DECLARE
    p PLS_INTEGER := 1.5;
    b BINARY_INTEGER := -1.5;
BEGIN
    RAISE NOTICE 'pls_integer=%, binary_integer=%', p, b;
END;
$$;

CREATE OR REPLACE FUNCTION pls_integer_add(
    p PLS_INTEGER,
    b BINARY_INTEGER
) RETURN PLS_INTEGER
LANGUAGE plisql
AS $$
BEGIN
    RETURN p + b;
END;
$$;
/

SELECT pls_integer_add(2, 3) AS standalone_result;
SELECT pg_get_function_identity_arguments('pls_integer_add'::regproc)
       AS stored_argument_types;
SELECT pg_get_function_result('pls_integer_add'::regproc)
       AS stored_return_type;

-- Preserve SETOF when an alias is rewritten to int4 in a routine signature.
CREATE OR REPLACE FUNCTION pls_integer_setof()
RETURNS SETOF PLS_INTEGER
LANGUAGE SQL
AS $$ VALUES (1), (2) $$;
/

SELECT proretset AS stored_setof
FROM pg_proc
WHERE oid = 'pls_integer_setof'::regproc;
SELECT * FROM pls_integer_setof();

CREATE OR REPLACE PACKAGE pls_integer_pkg IS
    FUNCTION echo_value(p IN PLS_INTEGER) RETURN BINARY_INTEGER;
END pls_integer_pkg;
/

CREATE OR REPLACE PACKAGE BODY pls_integer_pkg IS
    FUNCTION echo_value(p IN BINARY_INTEGER) RETURN PLS_INTEGER IS
    BEGIN
        RETURN p;
    END;
END pls_integer_pkg;
/

SELECT pls_integer_pkg.echo_value(7) AS package_alias_result;

-- Both spellings use signed 32-bit arithmetic.
DO LANGUAGE plisql $$
DECLARE
    p PLS_INTEGER := 2147483647;
BEGIN
    p := p + 1;
END;
$$;

-- The PL/SQL-only aliases must not become ordinary SQL column or cast types.
CREATE TABLE bad_pls_integer_column (p PLS_INTEGER);
SELECT 1::PLS_INTEGER;

-- Quoted names remain ordinary user-defined SQL types.
CREATE DOMAIN "pls_integer" AS text;

CREATE OR REPLACE FUNCTION quoted_pls_integer(p "pls_integer")
RETURN text
LANGUAGE SQL IMMUTABLE
AS $$ SELECT p::text $$;
/

SELECT quoted_pls_integer('domain-value'::"pls_integer") AS quoted_type_result;
SELECT pg_get_function_identity_arguments('quoted_pls_integer'::regproc)
       AS quoted_stored_type;

CREATE OR REPLACE FUNCTION unicode_quoted_pls_integer(p U&"pls_integer")
RETURN text
LANGUAGE SQL IMMUTABLE
AS $$ SELECT p::text $$;
/

SELECT pg_get_function_identity_arguments('unicode_quoted_pls_integer'::regproc)
       AS unicode_quoted_stored_type;

CREATE SCHEMA alias_guard;
CREATE DOMAIN alias_guard.pls_integer AS text;

CREATE OR REPLACE FUNCTION qualified_pls_integer(p alias_guard.pls_integer)
RETURN text
LANGUAGE SQL IMMUTABLE
AS $$ SELECT p::text $$;
/

SELECT pg_get_function_identity_arguments('qualified_pls_integer'::regproc)
       AS qualified_stored_type;

DO LANGUAGE plisql $$
DECLARE
    q "pls_integer" := 'local-domain';
    u U&"pls_integer" := 'unicode-domain';
BEGIN
    RAISE NOTICE 'quoted=%, unicode=%', q, u;
END;
$$;

DROP FUNCTION qualified_pls_integer(alias_guard.pls_integer);
DROP DOMAIN alias_guard.pls_integer;
DROP SCHEMA alias_guard;
DROP FUNCTION unicode_quoted_pls_integer("pls_integer");
DROP FUNCTION quoted_pls_integer("pls_integer");
DROP DOMAIN "pls_integer";
DROP PACKAGE pls_integer_pkg;
DROP FUNCTION pls_integer_setof();
DROP FUNCTION pls_integer_add(integer, integer);
