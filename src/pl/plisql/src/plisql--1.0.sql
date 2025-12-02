/*
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
 */

/* src/pl/plisql/src/plisql--1.0.sql */
/* Portions Copyright (c) 2023-2025, IvorySQL Global Development Team */

-- The language object, but not the functions, can be owned by a non-superuser.
ALTER LANGUAGE plisql OWNER TO @extowner@;

COMMENT ON LANGUAGE plisql IS 'PL/iSQL procedural language';

--
-- DBMS_UTILITY Package
--
-- Oracle-compatible utility functions that require access to PL/iSQL internals.
-- These are installed as part of the PL/iSQL language extension.
--

-- C function wrapper for FORMAT_ERROR_BACKTRACE
CREATE FUNCTION sys.ora_format_error_backtrace() RETURNS TEXT
  AS 'MODULE_PATHNAME', 'ora_format_error_backtrace'
  LANGUAGE C VOLATILE STRICT;

COMMENT ON FUNCTION sys.ora_format_error_backtrace() IS 'Internal function for DBMS_UTILITY.FORMAT_ERROR_BACKTRACE';

--
-- DBMS_UTILITY Package Definition
--
-- Note: CREATE PACKAGE syntax requires Oracle compatibility mode.
-- In single-user mode (initdb), compatible_mode is automatically set to 'oracle'
-- when database_mode is 'oracle', so no manual mode switching is needed.
--

CREATE OR REPLACE PACKAGE dbms_utility IS
  FUNCTION FORMAT_ERROR_BACKTRACE RETURN TEXT;
END dbms_utility;

CREATE OR REPLACE PACKAGE BODY dbms_utility IS
  FUNCTION FORMAT_ERROR_BACKTRACE RETURN TEXT IS
  BEGIN
    RETURN sys.ora_format_error_backtrace();
  END;
END dbms_utility;

