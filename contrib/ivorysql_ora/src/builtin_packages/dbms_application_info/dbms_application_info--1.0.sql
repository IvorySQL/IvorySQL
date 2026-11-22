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
 * dbms_application_info--1.0.sql
 *
 * Oracle-compatible DBMS_APPLICATION_INFO package.
 *
 * contrib/ivorysql_ora/src/builtin_packages/dbms_application_info/dbms_application_info--1.0.sql
 *
 *-------------------------------------------------------------------------
 */

CREATE FUNCTION sys.ora_dbms_application_info_set_module(module_name TEXT, action_name TEXT)
RETURNS VOID
AS 'MODULE_PATHNAME', 'ora_dbms_application_info_set_module'
LANGUAGE C VOLATILE;

CREATE FUNCTION sys.ora_dbms_application_info_set_action(action_name TEXT)
RETURNS VOID
AS 'MODULE_PATHNAME', 'ora_dbms_application_info_set_action'
LANGUAGE C VOLATILE;

CREATE FUNCTION sys.ora_dbms_application_info_set_client_info(client_info TEXT)
RETURNS VOID
AS 'MODULE_PATHNAME', 'ora_dbms_application_info_set_client_info'
LANGUAGE C VOLATILE;

CREATE TYPE sys.dbms_application_info_module AS (
    module_name TEXT,
    action_name TEXT
);

CREATE TYPE sys.dbms_application_info_client AS (
    client_info TEXT
);

CREATE TYPE sys.dbms_application_info_longops_handle AS (
    rindex INTEGER,
    slno   INTEGER
);

CREATE TYPE sys.dbms_application_info_longops_row AS (
    sid        BIGINT,
    rindex     INTEGER,
    slno       INTEGER,
    op_name    TEXT,
    target     INTEGER,
    context    INTEGER,
    sofar      DOUBLE PRECISION,
    totalwork  DOUBLE PRECISION,
    units      TEXT,
    start_time TIMESTAMPTZ,
    time_remaining DOUBLE PRECISION,
    message    TEXT
);

CREATE FUNCTION sys.ora_dbms_application_info_read_module()
RETURNS sys.dbms_application_info_module
AS 'MODULE_PATHNAME', 'ora_dbms_application_info_read_module'
LANGUAGE C VOLATILE;

CREATE FUNCTION sys.ora_dbms_application_info_read_client_info()
RETURNS sys.dbms_application_info_client
AS 'MODULE_PATHNAME', 'ora_dbms_application_info_read_client_info'
LANGUAGE C VOLATILE;

CREATE FUNCTION sys.ora_set_session_longops(rindex INTEGER, slno INTEGER, op_name TEXT, target INTEGER, context INTEGER, sofar DOUBLE PRECISION, totalwork DOUBLE PRECISION, units TEXT)
RETURNS sys.dbms_application_info_longops_handle
AS 'MODULE_PATHNAME', 'ora_set_session_longops'
LANGUAGE C VOLATILE;

CREATE FUNCTION sys.ora_session_longops()
RETURNS SETOF sys.dbms_application_info_longops_row
AS 'MODULE_PATHNAME', 'ora_session_longops'
LANGUAGE C VOLATILE;

CREATE OR REPLACE PACKAGE dbms_application_info AS
    PROCEDURE set_module(module_name VARCHAR2, action_name VARCHAR2);
    PROCEDURE set_action(action_name VARCHAR2);
    PROCEDURE set_client_info(client_info VARCHAR2);
    PROCEDURE read_module(module_name OUT VARCHAR2, action_name OUT VARCHAR2);
    PROCEDURE read_client_info(client_info OUT VARCHAR2);
    PROCEDURE set_session_longops(rindex IN OUT INTEGER, slno IN OUT INTEGER, op_name VARCHAR2, target INTEGER DEFAULT 0, context INTEGER DEFAULT 0, sofar NUMBER, totalwork NUMBER, units VARCHAR2);
END dbms_application_info;

CREATE OR REPLACE PACKAGE BODY dbms_application_info IS

    PROCEDURE set_module(module_name VARCHAR2, action_name VARCHAR2) IS
    BEGIN
        PERFORM sys.ora_dbms_application_info_set_module(module_name, action_name);
    END;

    PROCEDURE set_action(action_name VARCHAR2) IS
    BEGIN
        PERFORM sys.ora_dbms_application_info_set_action(action_name);
    END;

    PROCEDURE set_client_info(client_info VARCHAR2) IS
    BEGIN
        PERFORM sys.ora_dbms_application_info_set_client_info(client_info);
    END;

    PROCEDURE read_module(module_name OUT VARCHAR2, action_name OUT VARCHAR2) IS
        result sys.dbms_application_info_module;
    BEGIN
        SELECT * INTO result FROM sys.ora_dbms_application_info_read_module();
        module_name := result.module_name;
        action_name := result.action_name;
    END;

    PROCEDURE read_client_info(client_info OUT VARCHAR2) IS
        result sys.dbms_application_info_client;
    BEGIN
        SELECT * INTO result FROM sys.ora_dbms_application_info_read_client_info();
        client_info := result.client_info;
    END;

    PROCEDURE set_session_longops(rindex IN OUT INTEGER, slno IN OUT INTEGER, op_name VARCHAR2, target INTEGER DEFAULT 0, context INTEGER DEFAULT 0, sofar NUMBER, totalwork NUMBER, units VARCHAR2) IS
        result sys.dbms_application_info_longops_handle;
    BEGIN
        SELECT * INTO result FROM sys.ora_set_session_longops(rindex, slno, op_name, target, context, sofar, totalwork, units);
        rindex := result.rindex;
        slno := result.slno;
    END;

END dbms_application_info;

-- Compatibility view: Oracle sessions monitor long-running operations
-- through V$SESSION_LONGOPS; rows registered via SET_SESSION_LONGOPS are
-- per-session (backend) state.
CREATE VIEW sys.v$session_longops AS
    SELECT * FROM sys.ora_session_longops();
