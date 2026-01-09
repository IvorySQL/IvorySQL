/*-------------------------------------------------------------------------
 * Copyright 2025 IvorySQL Global Development Team
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
 * dbms_output--1.0.sql
 *
 * Oracle-compatible DBMS_OUTPUT package.
 * Provides PUT_LINE, PUT, NEW_LINE, GET_LINE, and GET_LINES functions.
 *
 * contrib/ivorysql_ora/src/builtin_packages/dbms_output/dbms_output--1.0.sql
 *
 *-------------------------------------------------------------------------
 */

-- Register C functions for DBMS_OUTPUT
CREATE FUNCTION sys.ora_dbms_output_enable(buffer_size INTEGER DEFAULT 20000)
RETURNS VOID
AS 'MODULE_PATHNAME', 'ora_dbms_output_enable'
LANGUAGE C VOLATILE;

CREATE FUNCTION sys.ora_dbms_output_disable()
RETURNS VOID
AS 'MODULE_PATHNAME', 'ora_dbms_output_disable'
LANGUAGE C VOLATILE;

CREATE FUNCTION sys.ora_dbms_output_put_line(a TEXT)
RETURNS VOID
AS 'MODULE_PATHNAME', 'ora_dbms_output_put_line'
LANGUAGE C VOLATILE;

CREATE FUNCTION sys.ora_dbms_output_put(a TEXT)
RETURNS VOID
AS 'MODULE_PATHNAME', 'ora_dbms_output_put'
LANGUAGE C VOLATILE;

CREATE FUNCTION sys.ora_dbms_output_new_line()
RETURNS VOID
AS 'MODULE_PATHNAME', 'ora_dbms_output_new_line'
LANGUAGE C VOLATILE;

-- Create composite types for GET_LINE and GET_LINES return values
CREATE TYPE sys.dbms_output_line AS (
    line TEXT,
    status INTEGER
);

CREATE TYPE sys.dbms_output_lines AS (
    lines TEXT[],
    numlines INTEGER
);

CREATE FUNCTION sys.ora_dbms_output_get_line()
RETURNS sys.dbms_output_line
AS 'MODULE_PATHNAME', 'ora_dbms_output_get_line'
LANGUAGE C VOLATILE;

CREATE FUNCTION sys.ora_dbms_output_get_lines(numlines INTEGER)
RETURNS sys.dbms_output_lines
AS 'MODULE_PATHNAME', 'ora_dbms_output_get_lines'
LANGUAGE C VOLATILE;

-- Create DBMS_OUTPUT package
CREATE OR REPLACE PACKAGE dbms_output IS
    PROCEDURE enable(buffer_size INTEGER DEFAULT 20000);
    PROCEDURE disable;
    PROCEDURE put_line(a TEXT);
    PROCEDURE put(a TEXT);
    PROCEDURE new_line;
    PROCEDURE get_line(line OUT TEXT, status OUT INTEGER);
    PROCEDURE get_line(line OUT VARCHAR2, status OUT INTEGER);
    PROCEDURE get_lines(lines OUT TEXT[], numlines IN OUT INTEGER);
    PROCEDURE get_lines(lines OUT VARCHAR2[], numlines IN OUT INTEGER);
END dbms_output;

CREATE OR REPLACE PACKAGE BODY dbms_output IS

    PROCEDURE enable(buffer_size INTEGER DEFAULT 20000) IS
    BEGIN
        PERFORM sys.ora_dbms_output_enable(buffer_size);
    END;

    PROCEDURE disable IS
    BEGIN
        PERFORM sys.ora_dbms_output_disable();
    END;

    PROCEDURE put_line(a TEXT) IS
    BEGIN
        PERFORM sys.ora_dbms_output_put_line(a);
    END;

    PROCEDURE put(a TEXT) IS
    BEGIN
        PERFORM sys.ora_dbms_output_put(a);
    END;

    PROCEDURE new_line IS
    BEGIN
        PERFORM sys.ora_dbms_output_new_line();
    END;

    PROCEDURE get_line(line OUT TEXT, status OUT INTEGER) IS
        result sys.dbms_output_line;
    BEGIN
        SELECT * INTO result FROM sys.ora_dbms_output_get_line();
        line := result.line;
        status := result.status;
    END;

    PROCEDURE get_line(line OUT VARCHAR2, status OUT INTEGER) IS
        result sys.dbms_output_line;
    BEGIN
        SELECT * INTO result FROM sys.ora_dbms_output_get_line();
        line := result.line;
        status := result.status;
    END;

    PROCEDURE get_lines(lines OUT TEXT[], numlines IN OUT INTEGER) IS
        result sys.dbms_output_lines;
    BEGIN
        SELECT * INTO result FROM sys.ora_dbms_output_get_lines(numlines);
        lines := result.lines;
        numlines := result.numlines;
    END;

    PROCEDURE get_lines(lines OUT VARCHAR2[], numlines IN OUT INTEGER) IS
        result sys.dbms_output_lines;
    BEGIN
        SELECT * INTO result FROM sys.ora_dbms_output_get_lines(numlines);
        lines := result.lines;
        numlines := result.numlines;
    END;

END dbms_output;
