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
 * dbms_sql--1.0.sql
 *    Session-local dynamic SQL handles, scalar binds and streaming results.
 *
 * Statement/bind/define state belongs to a backend memory context. Result
 * portals belong to a transaction and notify their handle when destroyed.
 * No privileged execution, SQL string interpolation, or shared cursor state.
 *-------------------------------------------------------------------------
 */

-- C entry points run as the invoking user. Polymorphic values keep the actual
-- scalar type, including typed NULL values; SQL text never contains bind data.
CREATE FUNCTION sys.ora_dbms_sql_open_cursor(security_level integer)
RETURNS integer AS 'MODULE_PATHNAME', 'ora_dbms_sql_open_cursor' LANGUAGE C VOLATILE PARALLEL UNSAFE;
CREATE FUNCTION sys.ora_dbms_sql_is_open(c integer)
RETURNS boolean AS 'MODULE_PATHNAME', 'ora_dbms_sql_is_open' LANGUAGE C VOLATILE PARALLEL UNSAFE;
CREATE FUNCTION sys.ora_dbms_sql_close_cursor(c integer)
RETURNS void AS 'MODULE_PATHNAME', 'ora_dbms_sql_close_cursor' LANGUAGE C VOLATILE PARALLEL UNSAFE;
CREATE FUNCTION sys.ora_dbms_sql_parse(c integer, statement text, language_flag integer)
RETURNS void AS 'MODULE_PATHNAME', 'ora_dbms_sql_parse' LANGUAGE C VOLATILE PARALLEL UNSAFE;
CREATE FUNCTION sys.ora_dbms_sql_bind_variable(c integer, name text, value anyelement)
RETURNS void AS 'MODULE_PATHNAME', 'ora_dbms_sql_bind_variable' LANGUAGE C VOLATILE PARALLEL UNSAFE;
CREATE FUNCTION sys.ora_dbms_sql_define_column(c integer, column_position integer, value anyelement, column_size integer)
RETURNS void AS 'MODULE_PATHNAME', 'ora_dbms_sql_define_column' LANGUAGE C VOLATILE PARALLEL UNSAFE;
CREATE FUNCTION sys.ora_dbms_sql_execute(c integer)
RETURNS integer AS 'MODULE_PATHNAME', 'ora_dbms_sql_execute' LANGUAGE C VOLATILE PARALLEL UNSAFE;
CREATE FUNCTION sys.ora_dbms_sql_fetch_rows(c integer)
RETURNS integer AS 'MODULE_PATHNAME', 'ora_dbms_sql_fetch_rows' LANGUAGE C VOLATILE PARALLEL UNSAFE;
CREATE FUNCTION sys.ora_dbms_sql_column_value(c integer, column_position integer, value anyelement)
RETURNS anyelement AS 'MODULE_PATHNAME', 'ora_dbms_sql_column_value' LANGUAGE C VOLATILE PARALLEL UNSAFE;
CREATE FUNCTION sys.ora_dbms_sql_last_row_count()
RETURNS numeric AS 'MODULE_PATHNAME', 'ora_dbms_sql_last_row_count' LANGUAGE C VOLATILE PARALLEL UNSAFE;

CREATE OR REPLACE PACKAGE dbms_sql AUTHID CURRENT_USER IS
  native CONSTANT INTEGER := 1;
  FUNCTION open_cursor(security_level INTEGER DEFAULT 1) RETURN INTEGER;
  FUNCTION is_open(c INTEGER) RETURN BOOLEAN;
  PROCEDURE close_cursor(c IN OUT INTEGER);
  PROCEDURE parse(c INTEGER, statement VARCHAR2, language_flag INTEGER);
  FUNCTION execute(c INTEGER) RETURN INTEGER;
  FUNCTION fetch_rows(c INTEGER) RETURN INTEGER;
  FUNCTION last_row_count RETURN NUMBER;
  PROCEDURE bind_variable(c INTEGER, name VARCHAR2, value INTEGER);
  PROCEDURE bind_variable(c INTEGER, name VARCHAR2, value NUMBER);
  PROCEDURE define_column(c INTEGER, position INTEGER, value NUMBER);
  PROCEDURE column_value(c INTEGER, position INTEGER, value OUT NUMBER);
  PROCEDURE bind_variable(c INTEGER, name VARCHAR2, value VARCHAR2);
  PROCEDURE define_column(c INTEGER, position INTEGER, value VARCHAR2, column_size INTEGER);
  PROCEDURE column_value(c INTEGER, position INTEGER, value OUT VARCHAR2);
  PROCEDURE bind_variable(c INTEGER, name VARCHAR2, value DATE);
  PROCEDURE define_column(c INTEGER, position INTEGER, value DATE);
  PROCEDURE column_value(c INTEGER, position INTEGER, value OUT DATE);
END dbms_sql;

CREATE OR REPLACE PACKAGE BODY dbms_sql IS
  FUNCTION open_cursor(security_level INTEGER DEFAULT 1) RETURN INTEGER IS
  BEGIN
    RETURN sys.ora_dbms_sql_open_cursor(security_level);
  END;
  FUNCTION is_open(c INTEGER) RETURN BOOLEAN IS
  BEGIN
    RETURN sys.ora_dbms_sql_is_open(c);
  END;
  PROCEDURE close_cursor(c IN OUT INTEGER) IS
  BEGIN
    PERFORM sys.ora_dbms_sql_close_cursor(c);
    c := NULL;
  END;
  PROCEDURE parse(c INTEGER, statement VARCHAR2, language_flag INTEGER) IS
  BEGIN
    PERFORM sys.ora_dbms_sql_parse(c, statement, language_flag);
  END;
  FUNCTION execute(c INTEGER) RETURN INTEGER IS
  BEGIN
    RETURN sys.ora_dbms_sql_execute(c);
  END;
  FUNCTION fetch_rows(c INTEGER) RETURN INTEGER IS
  BEGIN
    RETURN sys.ora_dbms_sql_fetch_rows(c);
  END;
  FUNCTION last_row_count RETURN NUMBER IS
  BEGIN
    RETURN sys.ora_dbms_sql_last_row_count();
  END;
  -- Select the numeric overload for PostgreSQL integer literals without
  -- changing PL/iSQL's general overload-resolution rules.
  PROCEDURE bind_variable(c INTEGER, name VARCHAR2, value INTEGER) IS
  BEGIN
    PERFORM sys.ora_dbms_sql_bind_variable(c, name, CAST(value AS NUMBER));
  END;
  PROCEDURE bind_variable(c INTEGER, name VARCHAR2, value NUMBER) IS
  BEGIN
    PERFORM sys.ora_dbms_sql_bind_variable(c, name, value);
  END;
  PROCEDURE define_column(c INTEGER, position INTEGER, value NUMBER) IS
  BEGIN
    PERFORM sys.ora_dbms_sql_define_column(c, position, value, NULL::integer);
  END;
  PROCEDURE column_value(c INTEGER, position INTEGER, value OUT NUMBER) IS
  BEGIN
    value := sys.ora_dbms_sql_column_value(c, position, value);
  END;
  PROCEDURE bind_variable(c INTEGER, name VARCHAR2, value VARCHAR2) IS
  BEGIN
    PERFORM sys.ora_dbms_sql_bind_variable(c, name, value);
  END;
  PROCEDURE define_column(c INTEGER, position INTEGER, value VARCHAR2, column_size INTEGER) IS
  BEGIN
    PERFORM sys.ora_dbms_sql_define_column(c, position, value, column_size);
  END;
  PROCEDURE column_value(c INTEGER, position INTEGER, value OUT VARCHAR2) IS
  BEGIN
    value := sys.ora_dbms_sql_column_value(c, position, value);
  END;
  PROCEDURE bind_variable(c INTEGER, name VARCHAR2, value DATE) IS
  BEGIN
    PERFORM sys.ora_dbms_sql_bind_variable(c, name, value);
  END;
  PROCEDURE define_column(c INTEGER, position INTEGER, value DATE) IS
  BEGIN
    PERFORM sys.ora_dbms_sql_define_column(c, position, value, NULL::integer);
  END;
  PROCEDURE column_value(c INTEGER, position INTEGER, value OUT DATE) IS
  BEGIN
    value := sys.ora_dbms_sql_column_value(c, position, value);
  END;
END dbms_sql;

GRANT EXECUTE ON PACKAGE dbms_sql TO PUBLIC;
