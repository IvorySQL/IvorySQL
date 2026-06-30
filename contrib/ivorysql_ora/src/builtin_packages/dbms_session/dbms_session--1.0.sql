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
 * dbms_session--1.0.sql
 *
 * Oracle-compatible DBMS_SESSION package (application context subset):
 * SET_CONTEXT, CLEAR_CONTEXT, CLEAR_ALL_CONTEXT and LIST_CONTEXT.
 * Context values set here are readable through SYS_CONTEXT and can therefore
 * drive row-level security predicates.
 *
 * contrib/ivorysql_ora/src/builtin_packages/dbms_session/dbms_session--1.0.sql
 *
 *-------------------------------------------------------------------------
 */

-- Record type returned by LIST_CONTEXT
CREATE TYPE sys.dbms_session_context_record AS (
    namespace TEXT,
    attribute TEXT,
    value     TEXT
);

-- Register C functions for DBMS_SESSION
CREATE FUNCTION sys.ora_dbms_session_set_context(namespace TEXT, attribute TEXT, value TEXT)
RETURNS VOID
AS 'MODULE_PATHNAME', 'ora_dbms_session_set_context'
LANGUAGE C VOLATILE;

CREATE FUNCTION sys.ora_dbms_session_clear_context(namespace TEXT, attribute TEXT DEFAULT NULL)
RETURNS VOID
AS 'MODULE_PATHNAME', 'ora_dbms_session_clear_context'
LANGUAGE C VOLATILE;

CREATE FUNCTION sys.ora_dbms_session_clear_all_context(namespace TEXT)
RETURNS VOID
AS 'MODULE_PATHNAME', 'ora_dbms_session_clear_all_context'
LANGUAGE C VOLATILE;

CREATE FUNCTION sys.ora_dbms_session_get_context(namespace TEXT, attribute TEXT)
RETURNS TEXT
AS 'MODULE_PATHNAME', 'ora_dbms_session_get_context'
LANGUAGE C STABLE;

CREATE FUNCTION sys.ora_dbms_session_list_context()
RETURNS SETOF sys.dbms_session_context_record
AS 'MODULE_PATHNAME', 'ora_dbms_session_list_context'
LANGUAGE C VOLATILE;

CREATE FUNCTION sys.ora_dbms_session_reset_package()
RETURNS VOID
AS 'MODULE_PATHNAME', 'ora_dbms_session_reset_package'
LANGUAGE C VOLATILE;

/*
 * LIST_CONTEXT entry point.
 *
 * Oracle exposes LIST_CONTEXT as a package procedure with an OUT collection
 * argument.  PL/iSQL packages cannot return/forward a SETOF, so we expose the
 * listing as a standalone set-returning function instead, callable as
 *   SELECT * FROM dbms_session_list_context();
 */
CREATE FUNCTION sys.dbms_session_list_context()
RETURNS SETOF sys.dbms_session_context_record
AS $$ SELECT * FROM sys.ora_dbms_session_list_context() $$
LANGUAGE SQL VOLATILE;

-- Create DBMS_SESSION package
CREATE OR REPLACE PACKAGE dbms_session IS
    PROCEDURE set_context(namespace VARCHAR2, attribute VARCHAR2, value VARCHAR2);
    PROCEDURE clear_context(namespace VARCHAR2, attribute VARCHAR2 DEFAULT NULL);
    PROCEDURE clear_all_context(namespace VARCHAR2);
    PROCEDURE reset_package;
END dbms_session;

CREATE OR REPLACE PACKAGE BODY dbms_session IS

    PROCEDURE set_context(namespace VARCHAR2, attribute VARCHAR2, value VARCHAR2) IS
    BEGIN
        PERFORM sys.ora_dbms_session_set_context(namespace, attribute, value);
    END;

    PROCEDURE clear_context(namespace VARCHAR2, attribute VARCHAR2 DEFAULT NULL) IS
    BEGIN
        PERFORM sys.ora_dbms_session_clear_context(namespace, attribute);
    END;

    PROCEDURE clear_all_context(namespace VARCHAR2) IS
    BEGIN
        PERFORM sys.ora_dbms_session_clear_all_context(namespace);
    END;

    PROCEDURE reset_package IS
    BEGIN
        PERFORM sys.ora_dbms_session_reset_package();
    END;

END dbms_session;
