/***************************************************************
 *
 * DBMS_LOCK Package
 *
 ***************************************************************
*/

CREATE FUNCTION dbms_lock_allocate_unique(text, integer)
RETURNS text 
AS 'MODULE_PATHNAME', 'ivorysql_dbms_lock_allocate_unique'
LANGUAGE C STRICT;

CREATE FUNCTION dbms_lock_request(text, int, int)
RETURNS int
AS 'MODULE_PATHNAME', 'ivorysql_dbms_lock_request'
LANGUAGE C STRICT;

CREATE FUNCTION dbms_lock_release(text)
RETURNS int
AS 'MODULE_PATHNAME', 'ivorysql_dbms_lock_release'
LANGUAGE C STRICT;

CREATE FUNCTION dbms_lock_sleep(float8)
returns int
AS 'MODULE_PATHNAME', 'ivorysql_dbms_lock_sleep'
LANGUAGE C STRICT;

-- PL/iSQL package wrapper
CREATE PACKAGE dbms_lock AS

    -- lock modes
    s_mode   CONSTANT INTEGER := 1;
    x_mode   CONSTANT INTEGER := 2;

    -- return codes
    success           CONSTANT INTEGER := 0;
    timeout           CONSTANT INTEGER := 1;
    deadlock          CONSTANT INTEGER := 2;
    parameter_error   CONSTANT INTEGER := 3;
    already_owned     CONSTANT INTEGER := 4;
    illegal_handle    CONSTANT INTEGER := 5;

    
    PROCEDURE allocate_unique(lockname text, lockname_handle OUT text, expiration_secs integer); 

    FUNCTION request(lockname text, mode integer, timeout integer)
        RETURN int;

    FUNCTION release(lockname text)
        RETURN int;

    PROCEDURE sleep(seconds double precision);
END;

CREATE PACKAGE BODY dbms_lock AS

    PROCEDURE allocate_unique(lockname text, lockname_handle OUT text, expiration_secs integer) IS
    BEGIN
	lockname_handle := dbms_lock_allocate_unique(lockname, expiration_secs);
    END;

    FUNCTION request(lockname text, mode integer, timeout integer)
    RETURN int IS
    BEGIN
        RETURN dbms_lock_request(lockname, mode, timeout);
    END;

    FUNCTION release(lockname text)
    RETURN int IS
    BEGIN
        RETURN dbms_lock_release(lockname);
    END;

    PROCEDURE sleep(seconds double precision) IS
    BEGIN
        PERFORM dbms_lock_sleep(seconds);
    END;
END;
