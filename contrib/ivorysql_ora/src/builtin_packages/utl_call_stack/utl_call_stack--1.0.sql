/***************************************************************
 *
 * UTL_CALL_STACK Package
 *
 * Oracle-compatible PL/SQL call stack and error backtrace introspection.
 *
 * contrib/ivorysql_ora/src/builtin_packages/utl_call_stack/utl_call_stack--1.0.sql
 *
 ***************************************************************/

-- Internal C resolvers
CREATE FUNCTION sys.utl_call_stack_backtrace_depth_internal()
RETURNS integer
AS 'MODULE_PATHNAME', 'utl_call_stack_backtrace_depth_internal'
LANGUAGE C STABLE;

CREATE FUNCTION sys.utl_call_stack_backtrace_line_internal(backtrace_index integer)
RETURNS integer
AS 'MODULE_PATHNAME', 'utl_call_stack_backtrace_line_internal'
LANGUAGE C STABLE;

CREATE FUNCTION sys.utl_call_stack_backtrace_unit_internal(backtrace_index integer)
RETURNS text
AS 'MODULE_PATHNAME', 'utl_call_stack_backtrace_unit_internal'
LANGUAGE C STABLE;

CREATE FUNCTION sys.utl_call_stack_dynamic_depth_internal()
RETURNS integer
AS 'MODULE_PATHNAME', 'utl_call_stack_dynamic_depth_internal'
LANGUAGE C STABLE;

CREATE FUNCTION sys.utl_call_stack_current_edition_internal()
RETURNS text
AS 'MODULE_PATHNAME', 'utl_call_stack_current_edition_internal'
LANGUAGE C IMMUTABLE PARALLEL SAFE;

CREATE FUNCTION sys.utl_call_stack_owner_internal(dynamic_depth integer)
RETURNS text
AS 'MODULE_PATHNAME', 'utl_call_stack_owner_internal'
LANGUAGE C STABLE;

CREATE FUNCTION sys.utl_call_stack_subprogram_internal(dynamic_depth integer)
RETURNS text
AS 'MODULE_PATHNAME', 'utl_call_stack_subprogram_internal'
LANGUAGE C STABLE;

CREATE FUNCTION sys.utl_call_stack_unit_line_internal(dynamic_depth integer)
RETURNS integer
AS 'MODULE_PATHNAME', 'utl_call_stack_unit_line_internal'
LANGUAGE C STABLE;

/* Revoke PUBLIC execute on internal functions (CWE-862) */
REVOKE ALL ON FUNCTION sys.utl_call_stack_backtrace_depth_internal() FROM PUBLIC;
REVOKE ALL ON FUNCTION sys.utl_call_stack_backtrace_line_internal(integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION sys.utl_call_stack_backtrace_unit_internal(integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION sys.utl_call_stack_dynamic_depth_internal() FROM PUBLIC;
REVOKE ALL ON FUNCTION sys.utl_call_stack_current_edition_internal() FROM PUBLIC;
REVOKE ALL ON FUNCTION sys.utl_call_stack_owner_internal(integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION sys.utl_call_stack_subprogram_internal(integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION sys.utl_call_stack_unit_line_internal(integer) FROM PUBLIC;

-- PL/iSQL package specification
CREATE OR REPLACE PACKAGE utl_call_stack AS

    /*
     * BACKTRACE_DEPTH
     * Returns the number of backtrace stack frames.
     */
    FUNCTION backtrace_depth RETURN INTEGER;

    /*
     * BACKTRACE_LINE
     * Returns line number in backtrace stack at specified index.
     */
    FUNCTION backtrace_line(backtrace_index IN INTEGER) RETURN INTEGER;

    /*
     * BACKTRACE_UNIT
     * Returns program unit name in backtrace stack at specified index.
     */
    FUNCTION backtrace_unit(backtrace_index IN INTEGER) RETURN VARCHAR2;

    /*
     * DYNAMIC_DEPTH
     * Returns dynamic call stack call depth.
     */
    FUNCTION dynamic_depth RETURN INTEGER;

    /*
     * CURRENT_EDITION
     * Returns current edition name (default 'ORA$BASE').
     */
    FUNCTION current_edition RETURN VARCHAR2;

    /*
     * OWNER
     * Returns schema owner of subprogram at dynamic depth.
     */
    FUNCTION owner(dynamic_depth IN INTEGER) RETURN VARCHAR2;

    /*
     * SUBPROGRAM
     * Returns subprogram name at dynamic depth.
     */
    FUNCTION subprogram(dynamic_depth IN INTEGER) RETURN VARCHAR2;

    /*
     * UNIT_LINE
     * Returns line number of execution point at dynamic depth.
     */
    FUNCTION unit_line(dynamic_depth IN INTEGER) RETURN INTEGER;

END utl_call_stack;

-- PL/iSQL package body
CREATE OR REPLACE PACKAGE BODY utl_call_stack AS

    FUNCTION backtrace_depth RETURN INTEGER IS
    BEGIN
        RETURN sys.utl_call_stack_backtrace_depth_internal();
    END;

    FUNCTION backtrace_line(backtrace_index IN INTEGER) RETURN INTEGER IS
    BEGIN
        RETURN sys.utl_call_stack_backtrace_line_internal(backtrace_index);
    END;

    FUNCTION backtrace_unit(backtrace_index IN INTEGER) RETURN VARCHAR2 IS
    BEGIN
        RETURN sys.utl_call_stack_backtrace_unit_internal(backtrace_index)::varchar2;
    END;

    FUNCTION dynamic_depth RETURN INTEGER IS
    BEGIN
        RETURN sys.utl_call_stack_dynamic_depth_internal();
    END;

    FUNCTION current_edition RETURN VARCHAR2 IS
    BEGIN
        RETURN sys.utl_call_stack_current_edition_internal()::varchar2;
    END;

    FUNCTION owner(dynamic_depth IN INTEGER) RETURN VARCHAR2 IS
    BEGIN
        RETURN sys.utl_call_stack_owner_internal(dynamic_depth)::varchar2;
    END;

    FUNCTION subprogram(dynamic_depth IN INTEGER) RETURN VARCHAR2 IS
    BEGIN
        RETURN sys.utl_call_stack_subprogram_internal(dynamic_depth)::varchar2;
    END;

    FUNCTION unit_line(dynamic_depth IN INTEGER) RETURN INTEGER IS
    BEGIN
        RETURN sys.utl_call_stack_unit_line_internal(dynamic_depth);
    END;

END utl_call_stack;
