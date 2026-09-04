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
 * dbms_random--1.0.sql
 *
 * Oracle-compatible DBMS_RANDOM package.
 *
 * The generator state is per-backend; INITIALIZE/SEED make the sequence
 * deterministic for a given seed, which is what migrated applications use
 * it for.  Sequences are not bit-for-bit identical to Oracle's proprietary
 * generator (nor are orafce's).
 *
 * contrib/ivorysql_ora/src/builtin_packages/dbms_random/dbms_random--1.0.sql
 *
 *-------------------------------------------------------------------------
 */

-- Register C functions for DBMS_RANDOM
CREATE FUNCTION sys.ora_dbms_random_initialize(seed NUMBER)
RETURNS VOID
AS 'MODULE_PATHNAME', 'ora_dbms_random_initialize'
LANGUAGE C VOLATILE STRICT;

CREATE FUNCTION sys.ora_dbms_random_seed_number(seed NUMBER)
RETURNS VOID
AS 'MODULE_PATHNAME', 'ora_dbms_random_seed_number'
LANGUAGE C VOLATILE STRICT;

CREATE FUNCTION sys.ora_dbms_random_seed_text(seed VARCHAR2)
RETURNS VOID
AS 'MODULE_PATHNAME', 'ora_dbms_random_seed_text'
LANGUAGE C VOLATILE STRICT;

CREATE FUNCTION sys.ora_dbms_random_terminate()
RETURNS VOID
AS 'MODULE_PATHNAME', 'ora_dbms_random_terminate'
LANGUAGE C VOLATILE;

CREATE FUNCTION sys.ora_dbms_random_normal()
RETURNS NUMBER
AS 'MODULE_PATHNAME', 'ora_dbms_random_normal'
LANGUAGE C VOLATILE;

CREATE FUNCTION sys.ora_dbms_random_random()
RETURNS NUMBER
AS 'MODULE_PATHNAME', 'ora_dbms_random_random'
LANGUAGE C VOLATILE;

CREATE FUNCTION sys.ora_dbms_random_string(opt VARCHAR2, len NUMBER)
RETURNS VARCHAR2
AS 'MODULE_PATHNAME', 'ora_dbms_random_string'
LANGUAGE C VOLATILE;

CREATE FUNCTION sys.ora_dbms_random_value()
RETURNS NUMBER
AS 'MODULE_PATHNAME', 'ora_dbms_random_value'
LANGUAGE C VOLATILE;

CREATE FUNCTION sys.ora_dbms_random_value_range(low NUMBER, high NUMBER)
RETURNS NUMBER
AS 'MODULE_PATHNAME', 'ora_dbms_random_value_range'
LANGUAGE C VOLATILE;

-- DBMS_RANDOM Package Definition
CREATE OR REPLACE PACKAGE dbms_random AUTHID CURRENT_USER IS

  PROCEDURE initialize(val IN NUMBER);
  PROCEDURE seed(val IN NUMBER);
  PROCEDURE seed(val IN VARCHAR2);
  PROCEDURE terminate;

  FUNCTION normal RETURN NUMBER;
  FUNCTION random RETURN NUMBER;
  FUNCTION string(opt IN CHAR, len IN NUMBER) RETURN VARCHAR2;
  FUNCTION value RETURN NUMBER;
  FUNCTION value(low IN NUMBER, high IN NUMBER) RETURN NUMBER;

END dbms_random;

CREATE OR REPLACE PACKAGE BODY dbms_random IS

  PROCEDURE initialize(val IN NUMBER) IS
  BEGIN
    PERFORM sys.ora_dbms_random_initialize(val);
  END;

  PROCEDURE seed(val IN NUMBER) IS
  BEGIN
    PERFORM sys.ora_dbms_random_seed_number(val);
  END;

  PROCEDURE seed(val IN VARCHAR2) IS
  BEGIN
    PERFORM sys.ora_dbms_random_seed_text(val);
  END;

  PROCEDURE terminate IS
  BEGIN
    PERFORM sys.ora_dbms_random_terminate();
  END;

  FUNCTION normal RETURN NUMBER IS
  BEGIN
    RETURN sys.ora_dbms_random_normal();
  END;

  FUNCTION random RETURN NUMBER IS
  BEGIN
    RETURN sys.ora_dbms_random_random();
  END;

  FUNCTION string(opt IN CHAR, len IN NUMBER) RETURN VARCHAR2 IS
  BEGIN
    RETURN sys.ora_dbms_random_string(opt, len);
  END;

  FUNCTION value RETURN NUMBER IS
  BEGIN
    RETURN sys.ora_dbms_random_value();
  END;

  FUNCTION value(low IN NUMBER, high IN NUMBER) RETURN NUMBER IS
  BEGIN
    RETURN sys.ora_dbms_random_value_range(low, high);
  END;

END dbms_random;

-- Packages default to no PUBLIC privileges at all (unlike plain FUNCTION/
-- PROCEDURE, which grant EXECUTE to PUBLIC by default) -- without this,
-- only the role that ran CREATE EXTENSION could call any subprogram here.
GRANT EXECUTE ON PACKAGE dbms_random TO PUBLIC;
