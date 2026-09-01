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
 * dbms_assert--1.0.sql
 *
 * Oracle-compatible DBMS_ASSERT package: identifier validation and
 * quoting interfaces for safely building dynamic SQL.
 *
 * contrib/ivorysql_ora/src/builtin_packages/dbms_assert/dbms_assert--1.0.sql
 *
 *-------------------------------------------------------------------------
 */

-- Register C functions for DBMS_ASSERT
CREATE FUNCTION sys.ora_dbms_assert_enquote_literal(str VARCHAR2)
RETURNS VARCHAR2
AS 'MODULE_PATHNAME', 'ora_dbms_assert_enquote_literal'
LANGUAGE C VOLATILE STRICT;

CREATE FUNCTION sys.ora_dbms_assert_enquote_name(str VARCHAR2, capitalize BOOLEAN DEFAULT TRUE)
RETURNS VARCHAR2
AS 'MODULE_PATHNAME', 'ora_dbms_assert_enquote_name'
LANGUAGE C VOLATILE STRICT;

CREATE FUNCTION sys.ora_dbms_assert_noop(str VARCHAR2)
RETURNS VARCHAR2
AS 'MODULE_PATHNAME', 'ora_dbms_assert_noop'
LANGUAGE C VOLATILE STRICT;

CREATE FUNCTION sys.ora_dbms_assert_qualified_sql_name(str VARCHAR2)
RETURNS VARCHAR2
AS 'MODULE_PATHNAME', 'ora_dbms_assert_qualified_sql_name'
LANGUAGE C VOLATILE STRICT;

CREATE FUNCTION sys.ora_dbms_assert_schema_name(str VARCHAR2)
RETURNS VARCHAR2
AS 'MODULE_PATHNAME', 'ora_dbms_assert_schema_name'
LANGUAGE C VOLATILE STRICT;

CREATE FUNCTION sys.ora_dbms_assert_simple_sql_name(str VARCHAR2)
RETURNS VARCHAR2
AS 'MODULE_PATHNAME', 'ora_dbms_assert_simple_sql_name'
LANGUAGE C VOLATILE STRICT;

CREATE FUNCTION sys.ora_dbms_assert_object_name(str VARCHAR2)
RETURNS VARCHAR2
AS 'MODULE_PATHNAME', 'ora_dbms_assert_object_name'
LANGUAGE C VOLATILE STRICT;

-- DBMS_ASSERT Package Definition
CREATE OR REPLACE PACKAGE dbms_assert IS

  FUNCTION enquote_literal(str VARCHAR2) RETURN VARCHAR2;
  FUNCTION enquote_name(str VARCHAR2, capitalize BOOLEAN DEFAULT TRUE) RETURN VARCHAR2;
  FUNCTION noop(str VARCHAR2) RETURN VARCHAR2;
  FUNCTION qualified_sql_name(str VARCHAR2) RETURN VARCHAR2;
  FUNCTION schema_name(str VARCHAR2) RETURN VARCHAR2;
  FUNCTION simple_sql_name(str VARCHAR2) RETURN VARCHAR2;
  FUNCTION object_name(str VARCHAR2) RETURN VARCHAR2;
  FUNCTION sql_object_name(str VARCHAR2) RETURN VARCHAR2;

END dbms_assert;

CREATE OR REPLACE PACKAGE BODY dbms_assert IS

  FUNCTION enquote_literal(str VARCHAR2) RETURN VARCHAR2 IS
  BEGIN
    RETURN sys.ora_dbms_assert_enquote_literal(str);
  END;

  FUNCTION enquote_name(str VARCHAR2, capitalize BOOLEAN DEFAULT TRUE) RETURN VARCHAR2 IS
  BEGIN
    RETURN sys.ora_dbms_assert_enquote_name(str, capitalize);
  END;

  FUNCTION noop(str VARCHAR2) RETURN VARCHAR2 IS
  BEGIN
    RETURN sys.ora_dbms_assert_noop(str);
  END;

  FUNCTION qualified_sql_name(str VARCHAR2) RETURN VARCHAR2 IS
  BEGIN
    RETURN sys.ora_dbms_assert_qualified_sql_name(str);
  END;

  FUNCTION schema_name(str VARCHAR2) RETURN VARCHAR2 IS
  BEGIN
    RETURN sys.ora_dbms_assert_schema_name(str);
  END;

  FUNCTION simple_sql_name(str VARCHAR2) RETURN VARCHAR2 IS
  BEGIN
    RETURN sys.ora_dbms_assert_simple_sql_name(str);
  END;

  FUNCTION object_name(str VARCHAR2) RETURN VARCHAR2 IS
  BEGIN
    RETURN sys.ora_dbms_assert_object_name(str);
  END;

  FUNCTION sql_object_name(str VARCHAR2) RETURN VARCHAR2 IS
  BEGIN
    RETURN sys.ora_dbms_assert_object_name(str);
  END;

END dbms_assert;

-- Packages default to no PUBLIC privileges at all (unlike plain FUNCTION/
-- PROCEDURE, which grant EXECUTE to PUBLIC by default) -- without this,
-- only the role that ran CREATE EXTENSION could call any subprogram here.
GRANT EXECUTE ON PACKAGE dbms_assert TO PUBLIC;
