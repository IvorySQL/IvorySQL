/***************************************************************
 *
 * DBMS_DESCRIBE Package
 *
 * Oracle-compatible procedure and function parameter introspection.
 *
 * contrib/ivorysql_ora/src/builtin_packages/dbms_describe/dbms_describe--1.0.sql
 *
 ***************************************************************/

-- Composite record type for described parameter
CREATE TYPE sys.describe_arg_record AS (
    position        integer,
    argument_name   text,
    datatype        integer,
    in_out          integer,
    length          integer
);

-- Internal C resolver
CREATE FUNCTION sys.dbms_describe_describe_procedure_internal(object_name text)
RETURNS SETOF sys.describe_arg_record
AS 'MODULE_PATHNAME', 'dbms_describe_describe_procedure_internal'
LANGUAGE C STABLE;

/* Revoke PUBLIC execute on internal functions (CWE-862) */
REVOKE ALL ON FUNCTION sys.dbms_describe_describe_procedure_internal(text) FROM PUBLIC;

-- Helper query function for PL/iSQL and SQL callers
CREATE FUNCTION sys.dbms_describe_procedure(object_name text)
RETURNS SETOF sys.describe_arg_record
AS $$ SELECT * FROM sys.dbms_describe_describe_procedure_internal(object_name) $$
LANGUAGE SQL STABLE;

-- PL/iSQL package specification
CREATE OR REPLACE PACKAGE dbms_describe AS

    /*
     * DESCRIBE_PROCEDURE
     * Introspects parameter list and types of a procedure or function.
     */
    PROCEDURE describe_procedure(object_name            IN VARCHAR2,
                                 reserved1              IN VARCHAR2 DEFAULT NULL,
                                 reserved2              IN VARCHAR2 DEFAULT NULL,
                                 overload               OUT NUMBER,
                                 position               OUT NUMBER,
                                 level                  OUT NUMBER,
                                 argument_name          OUT VARCHAR2,
                                 datatype               OUT NUMBER,
                                 default_value          OUT NUMBER,
                                 in_out                 OUT NUMBER,
                                 length                 OUT NUMBER,
                                 precision              OUT NUMBER,
                                 scale                  OUT NUMBER,
                                 radix                  OUT NUMBER,
                                 spare                  OUT NUMBER);

END dbms_describe;

-- PL/iSQL package body
CREATE OR REPLACE PACKAGE BODY dbms_describe AS

    PROCEDURE describe_procedure(object_name            IN VARCHAR2,
                                 reserved1              IN VARCHAR2 DEFAULT NULL,
                                 reserved2              IN VARCHAR2 DEFAULT NULL,
                                 overload               OUT NUMBER,
                                 position               OUT NUMBER,
                                 level                  OUT NUMBER,
                                 argument_name          OUT VARCHAR2,
                                 datatype               OUT NUMBER,
                                 default_value          OUT NUMBER,
                                 in_out                 OUT NUMBER,
                                 length                 OUT NUMBER,
                                 precision              OUT NUMBER,
                                 scale                  OUT NUMBER,
                                 radix                  OUT NUMBER,
                                 spare                  OUT NUMBER) IS
        rec sys.describe_arg_record;
    BEGIN
        SELECT * INTO rec FROM sys.dbms_describe_describe_procedure_internal(object_name::text) LIMIT 1;
        overload        := 1;
        position        := rec.position;
        level           := 0;
        argument_name   := rec.argument_name::varchar2;
        datatype        := rec.datatype;
        default_value   := 0;
        in_out          := rec.in_out;
        length          := rec.length;
        precision       := 0;
        scale           := 0;
        radix           := 10;
        spare           := 0;
    EXCEPTION WHEN NO_DATA_FOUND THEN
        overload        := 0;
        position        := 0;
        level           := 0;
        argument_name   := '';
        datatype        := 0;
        default_value   := 0;
        in_out          := 0;
        length          := 0;
        precision       := 0;
        scale           := 0;
        radix           := 10;
        spare           := 0;
    END;

END dbms_describe;
