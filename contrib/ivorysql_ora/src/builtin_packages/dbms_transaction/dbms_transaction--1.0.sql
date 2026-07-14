/***************************************************************
 *
 * DBMS_TRANSACTION Package
 *
 * Oracle-compatible DBMS_TRANSACTION package provides access to SQL transaction statements from stored procedures.
 *
 * contrib/ivorysql_ora/src/builtin_packages/dbms_transaction/dbms_transaction--1.0.sql
 *
 ***************************************************************/

-- All subprograms are listed at: 
-- https://docs.oracle.com/en/database/oracle/oracle-database/26/arpls/DBMS_TRANSACTION.html
--
-- 1   ADVISE_COMMIT
-- 2   ADVISE_NOTHING
-- 3   ADVISE_ROLLBACK
-- 4   COMMIT
-- 5   COMMIT_COMMENT
-- 6   COMMIT_FORCE
-- 7   GET_TRANSACTION_ID
-- 8   GET_TRANSACTION_TIMEOUT
-- 9   GET_TRANSACTION_TYPE
-- 10  LOCAL_TRANSACTION_ID
-- 11  PURGE_LOST_DB_ENTRY
-- 12  PURGE_MIXED
-- 13  READ_ONLY
-- 14  READ_WRITE
-- 15  ROLLBACK
-- 16  ROLLBACK_FORCE
-- 17  ROLLBACK_SAVEPOINT
-- 18  SAVEPOINT
-- 19  START_TRANSACTION
-- 20  STEP_ID
-- 21  SUSPEND_TRANSACTION
-- 22  USE_ROLLBACK_SEGMENT

-- Create DBMS_TRANSACTION package
CREATE OR REPLACE PACKAGE dbms_transaction IS                   -- 4
    PROCEDURE commit;
    PROCEDURE rollback;
END dbms_transaction;

CREATE OR REPLACE PACKAGE BODY dbms_transaction IS              -- 15
    PROCEDURE commit IS
    BEGIN
        COMMIT;
    END;

    PROCEDURE rollback IS
    BEGIN
        ROLLBACK;
    END;
END dbms_transaction;
