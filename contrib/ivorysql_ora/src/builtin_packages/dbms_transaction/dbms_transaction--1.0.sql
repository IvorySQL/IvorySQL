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
 * dbms_transaction--1.0.sql
 *
 * Oracle-compatible DBMS_TRANSACTION package.
 *
 * COMMIT/ROLLBACK reuse PL/iSQL's native COMMIT/ROLLBACK statements (only
 * valid when the package procedure is invoked as a top-level CALL, exactly
 * like a bare COMMIT/ROLLBACK would be).  SAVEPOINT/ROLLBACK_SAVEPOINT call
 * into a small C bridge (dbms_transaction.c) that reaches directly into
 * PostgreSQL's DefineSavepoint()/RollbackToSavepoint(), since PL/iSQL has no
 * native savepoint statement.  READ_ONLY/READ_WRITE and the metadata readers
 * are thin wrappers around existing SQL facilities.
 *
 * AUTHID CURRENT_USER: Oracle's own documentation for DBMS_TRANSACTION says
 * "All subprograms in the DBMS_TRANSACTION package run with the privileges
 * of the calling user, rather than the package owner SYS" -- i.e. invoker's
 * rights, not the CREATE PACKAGE default of definer's rights.  EXECUTE is
 * also granted to PUBLIC below, matching Oracle's catalog scripts granting
 * SYS.DBMS_TRANSACTION to PUBLIC at database creation, so that ordinary
 * users can call it without a DBA having to GRANT it per-role first.
 *
 * contrib/ivorysql_ora/src/builtin_packages/dbms_transaction/dbms_transaction--1.0.sql
 *
 *-------------------------------------------------------------------------
 */

-- Register C functions for the named-savepoint operations
CREATE FUNCTION sys.ora_dbms_transaction_savepoint(name TEXT)
RETURNS VOID
AS 'MODULE_PATHNAME', 'ora_dbms_transaction_savepoint'
LANGUAGE C VOLATILE;

CREATE FUNCTION sys.ora_dbms_transaction_rollback_savepoint(name TEXT)
RETURNS VOID
AS 'MODULE_PATHNAME', 'ora_dbms_transaction_rollback_savepoint'
LANGUAGE C VOLATILE;

CREATE OR REPLACE PACKAGE dbms_transaction AUTHID CURRENT_USER IS

    PROCEDURE commit;
    PROCEDURE rollback;
    PROCEDURE savepoint(savept IN VARCHAR2);
    PROCEDURE rollback_savepoint(savept IN VARCHAR2);

    PROCEDURE read_only;
    PROCEDURE read_write;
    FUNCTION local_transaction_id(create_transaction IN BOOLEAN DEFAULT FALSE) RETURN VARCHAR2;

END dbms_transaction;

CREATE OR REPLACE PACKAGE BODY dbms_transaction IS

    PROCEDURE commit IS
    BEGIN
        COMMIT;
    END;

    PROCEDURE rollback IS
    BEGIN
        ROLLBACK;
    END;

    PROCEDURE savepoint(savept IN VARCHAR2) IS
    BEGIN
        PERFORM sys.ora_dbms_transaction_savepoint(savept);
    END;

    PROCEDURE rollback_savepoint(savept IN VARCHAR2) IS
    BEGIN
        PERFORM sys.ora_dbms_transaction_rollback_savepoint(savept);
    END;

    PROCEDURE read_only IS
    BEGIN
        EXECUTE 'SET TRANSACTION READ ONLY';
    END;

    PROCEDURE read_write IS
    BEGIN
        EXECUTE 'SET TRANSACTION READ WRITE';
    END;

    FUNCTION local_transaction_id(create_transaction IN BOOLEAN DEFAULT FALSE) RETURN VARCHAR2 IS
        xid_text VARCHAR2(32);
    BEGIN
        IF create_transaction THEN
            SELECT pg_current_xact_id()::text INTO xid_text;
        ELSE
            SELECT pg_current_xact_id_if_assigned()::text INTO xid_text;
        END IF;
        RETURN xid_text;
    END;

END dbms_transaction;

-- Packages default to no PUBLIC privileges at all (unlike plain FUNCTION/
-- PROCEDURE, which grant EXECUTE to PUBLIC by default) -- without this,
-- only the role that ran CREATE EXTENSION could call any subprogram here.
GRANT EXECUTE ON PACKAGE dbms_transaction TO PUBLIC;
