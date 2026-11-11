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
 *-------------------------------------------------------------------------
 */

CREATE OR REPLACE PACKAGE dbms_transaction AUTHID CURRENT_USER IS

    PROCEDURE commit;
    PROCEDURE rollback;
    PROCEDURE savepoint(savept IN VARCHAR2);
    PROCEDURE rollback_savepoint(savept IN VARCHAR2);

    PROCEDURE read_only;
    PROCEDURE read_write;
    FUNCTION local_transaction_id(create_transaction IN BOOLEAN DEFAULT FALSE)
        RETURN VARCHAR2;

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

    FUNCTION local_transaction_id(create_transaction IN BOOLEAN DEFAULT FALSE)
        RETURN VARCHAR2 IS
    BEGIN
        -- Return the full, epoch-aware IvorySQL XID as an opaque string.
        IF create_transaction THEN
            RETURN pg_catalog.pg_current_xact_id()::text;
        END IF;

        RETURN pg_catalog.pg_current_xact_id_if_assigned()::text;
    END;

END dbms_transaction;
