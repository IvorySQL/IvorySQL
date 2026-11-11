/*-------------------------------------------------------------------------
 * Copyright 2026 IvorySQL Global Development Team
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *
 * dbms_xmlgen--1.0.sql
 *
 * Oracle-compatible DBMS_XMLGEN package.
 *
 * The query runs and the context handles live in the C bridge: a PL/iSQL
 * package body cannot execute dynamic SQL, and package-level array state is not
 * reliable there.  The package only forwards its arguments.
 *
 * contrib/ivorysql_ora/src/builtin_packages/dbms_xmlgen/dbms_xmlgen--1.0.sql
 *
 *-------------------------------------------------------------------------
 */

CREATE FUNCTION sys.ora_dbms_xmlgen_render(query_string text, max_rows integer,
										   skip_rows integer, rowset_tag text,
										   row_tag text)
RETURNS text
AS 'MODULE_PATHNAME', 'ora_dbms_xmlgen_render'
LANGUAGE C VOLATILE;

CREATE FUNCTION sys.ora_dbms_xmlgen_newcontext(query_string text)
RETURNS integer
AS 'MODULE_PATHNAME', 'ora_dbms_xmlgen_newcontext'
LANGUAGE C VOLATILE;

CREATE FUNCTION sys.ora_dbms_xmlgen_render_ctx(ctx_handle integer)
RETURNS text
AS 'MODULE_PATHNAME', 'ora_dbms_xmlgen_render_ctx'
LANGUAGE C VOLATILE;

CREATE FUNCTION sys.ora_dbms_xmlgen_set_maxrows(ctx_handle integer, max_rows integer)
RETURNS void
AS 'MODULE_PATHNAME', 'ora_dbms_xmlgen_set_maxrows'
LANGUAGE C VOLATILE;

CREATE FUNCTION sys.ora_dbms_xmlgen_set_skiprows(ctx_handle integer, skip_rows integer)
RETURNS void
AS 'MODULE_PATHNAME', 'ora_dbms_xmlgen_set_skiprows'
LANGUAGE C VOLATILE;

CREATE FUNCTION sys.ora_dbms_xmlgen_set_rowsettag(ctx_handle integer, rowset_tag text)
RETURNS void
AS 'MODULE_PATHNAME', 'ora_dbms_xmlgen_set_rowsettag'
LANGUAGE C VOLATILE;

CREATE FUNCTION sys.ora_dbms_xmlgen_set_rowtag(ctx_handle integer, row_tag text)
RETURNS void
AS 'MODULE_PATHNAME', 'ora_dbms_xmlgen_set_rowtag'
LANGUAGE C VOLATILE;

CREATE FUNCTION sys.ora_dbms_xmlgen_closecontext(ctx_handle integer)
RETURNS void
AS 'MODULE_PATHNAME', 'ora_dbms_xmlgen_closecontext'
LANGUAGE C VOLATILE;

CREATE FUNCTION sys.ora_dbms_xmlgen_numrows(ctx_handle integer)
RETURNS integer
AS 'MODULE_PATHNAME', 'ora_dbms_xmlgen_numrows'
LANGUAGE C STABLE;

CREATE OR REPLACE PACKAGE dbms_xmlgen IS
    FUNCTION GETXML(query_string VARCHAR2) RETURN TEXT;
    FUNCTION NEWCONTEXT(query_string VARCHAR2) RETURN NUMBER;
    FUNCTION GETXML(ctx_handle NUMBER) RETURN TEXT;
    PROCEDURE SETMAXROWS(ctx_handle NUMBER, max_rows NUMBER);
    PROCEDURE SETSKIPROWS(ctx_handle NUMBER, skip_rows NUMBER);
    PROCEDURE SETROWSETTAG(ctx_handle NUMBER, rowset_tag VARCHAR2);
    PROCEDURE SETROWTAG(ctx_handle NUMBER, row_tag VARCHAR2);
    PROCEDURE CLOSECONTEXT(ctx_handle NUMBER);
    FUNCTION GETNUMROWSPROCESSED(ctx_handle NUMBER) RETURN NUMBER;
END;

CREATE OR REPLACE PACKAGE BODY dbms_xmlgen IS

    FUNCTION GETXML(query_string VARCHAR2) RETURN TEXT IS
    BEGIN
        RETURN sys.ora_dbms_xmlgen_render(query_string::TEXT, NULL::INT4, 0::INT4,
                                          'ROWSET'::TEXT, 'ROW'::TEXT);
    END;

    FUNCTION NEWCONTEXT(query_string VARCHAR2) RETURN NUMBER IS
    BEGIN
        RETURN sys.ora_dbms_xmlgen_newcontext(query_string::TEXT);
    END;

    FUNCTION GETXML(ctx_handle NUMBER) RETURN TEXT IS
    BEGIN
        RETURN sys.ora_dbms_xmlgen_render_ctx(ctx_handle::INT4);
    END;

    PROCEDURE SETMAXROWS(ctx_handle NUMBER, max_rows NUMBER) IS
    BEGIN
        PERFORM sys.ora_dbms_xmlgen_set_maxrows(ctx_handle::INT4, max_rows::INT4);
    END;

    PROCEDURE SETSKIPROWS(ctx_handle NUMBER, skip_rows NUMBER) IS
    BEGIN
        PERFORM sys.ora_dbms_xmlgen_set_skiprows(ctx_handle::INT4, skip_rows::INT4);
    END;

    PROCEDURE SETROWSETTAG(ctx_handle NUMBER, rowset_tag VARCHAR2) IS
    BEGIN
        PERFORM sys.ora_dbms_xmlgen_set_rowsettag(ctx_handle::INT4, rowset_tag::TEXT);
    END;

    PROCEDURE SETROWTAG(ctx_handle NUMBER, row_tag VARCHAR2) IS
    BEGIN
        PERFORM sys.ora_dbms_xmlgen_set_rowtag(ctx_handle::INT4, row_tag::TEXT);
    END;

    PROCEDURE CLOSECONTEXT(ctx_handle NUMBER) IS
    BEGIN
        PERFORM sys.ora_dbms_xmlgen_closecontext(ctx_handle::INT4);
    END;

    FUNCTION GETNUMROWSPROCESSED(ctx_handle NUMBER) RETURN NUMBER IS
    BEGIN
        RETURN sys.ora_dbms_xmlgen_numrows(ctx_handle::INT4);
    END;

END;

GRANT EXECUTE ON PACKAGE dbms_xmlgen TO PUBLIC;
