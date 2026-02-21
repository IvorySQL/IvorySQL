/***************************************************************
 *
 * DBMS_LOCK Package
 *
 ***************************************************************
*/

CREATE FUNCTION dbms_lock_allocate_unique(text)
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
returns void 
AS 'MODULE_PATHNAME', 'ivorysql_dbms_lock_sleep'
LANGUAGE C STRICT;

-- PL/iSQL package wrapper
CREATE PACKAGE dbms_lock AS

    -- lock modes
    s_mode   CONSTANT INTEGER := 4;
    x_mode   CONSTANT INTEGER := 6;

    -- return codes
    success           CONSTANT INTEGER := 0;
    timeout           CONSTANT INTEGER := 1;
    deadlock          CONSTANT INTEGER := 2;
    parameter_error   CONSTANT INTEGER := 3;
    already_owned     CONSTANT INTEGER := 4;
    illegal_handle    CONSTANT INTEGER := 5;

    
    PROCEDURE allocate_unique(lockname text, lockname_handle OUT text); 

    FUNCTION request(lockname_handle text, mode integer, timeout integer)
        RETURN int;

    FUNCTION release(lockname_handle text)
        RETURN int;

    PROCEDURE sleep(seconds double precision);
END;

CREATE PACKAGE BODY dbms_lock AS

    PROCEDURE allocate_unique(lockname text, lockname_handle OUT text) IS
       v_handle text;
    BEGIN
       v_handle := dbms_lock_allocate_unique(lockname);
       lockname_handle := v_handle;  
    END;

    FUNCTION request(lockname_handle text, mode integer, timeout integer)
    RETURN int IS
    BEGIN
        RETURN dbms_lock_request(lockname_handle, mode, timeout);
    END;

    FUNCTION release(lockname_handle text)
    RETURN int IS
    BEGIN
        RETURN dbms_lock_release(lockname_handle);
    END;

    PROCEDURE sleep(seconds double precision) IS
    BEGIN
        PERFORM dbms_lock_sleep(seconds);
    END;
END;
