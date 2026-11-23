/***************************************************************
 *
 * DBMS_PROFILER Package
 *
 * Oracle-compatible PL/iSQL profiler package and profiler tables.
 *
 * contrib/ivorysql_ora/src/builtin_packages/dbms_profiler/dbms_profiler--1.0.sql
 *
 ***************************************************************/

-- Sequence for profiler runs
CREATE SEQUENCE IF NOT EXISTS sys.plsql_profiler_runnumber START WITH 1 INCREMENT BY 1;

-- Profiler repository tables
CREATE TABLE IF NOT EXISTS sys.plsql_profiler_runs (
    runid           bigint PRIMARY KEY,
    run_date        timestamptz,
    run_comment     varchar2(2047),
    run_total_time  bigint,
    run_system_info varchar2(2047),
    run_comment1    varchar2(2047)
);

CREATE TABLE IF NOT EXISTS sys.plsql_profiler_units (
    runid           bigint,
    unit_number     bigint,
    unit_type       varchar2(32),
    unit_owner      varchar2(128),
    unit_name       varchar2(128),
    unit_timestamp  timestamptz,
    total_time      bigint,
    PRIMARY KEY (runid, unit_number)
);

CREATE TABLE IF NOT EXISTS sys.plsql_profiler_data (
    runid           bigint,
    unit_number     bigint,
    line#           bigint,
    total_occur     bigint,
    total_time      bigint,
    min_time        bigint,
    max_time        bigint,
    PRIMARY KEY (runid, unit_number, line#)
);

-- Internal C resolvers
CREATE FUNCTION sys.dbms_profiler_start_profiler_internal(comment1 text DEFAULT '',
                                                          comment2 text DEFAULT '')
RETURNS integer
AS 'MODULE_PATHNAME', 'dbms_profiler_start_profiler_internal'
LANGUAGE C VOLATILE;

CREATE FUNCTION sys.dbms_profiler_get_run_number_internal()
RETURNS bigint
AS 'MODULE_PATHNAME', 'dbms_profiler_get_run_number_internal'
LANGUAGE C STABLE;

CREATE FUNCTION sys.dbms_profiler_stop_profiler_internal()
RETURNS integer
AS 'MODULE_PATHNAME', 'dbms_profiler_stop_profiler_internal'
LANGUAGE C VOLATILE;

CREATE FUNCTION sys.dbms_profiler_pause_profiler_internal()
RETURNS integer
AS 'MODULE_PATHNAME', 'dbms_profiler_pause_profiler_internal'
LANGUAGE C VOLATILE;

CREATE FUNCTION sys.dbms_profiler_resume_profiler_internal()
RETURNS integer
AS 'MODULE_PATHNAME', 'dbms_profiler_resume_profiler_internal'
LANGUAGE C VOLATILE;

CREATE FUNCTION sys.dbms_profiler_flush_data_internal()
RETURNS integer
AS 'MODULE_PATHNAME', 'dbms_profiler_flush_data_internal'
LANGUAGE C VOLATILE;

CREATE FUNCTION sys.dbms_profiler_get_version_internal()
RETURNS integer
AS 'MODULE_PATHNAME', 'dbms_profiler_get_version_internal'
LANGUAGE C IMMUTABLE PARALLEL SAFE;

/* Revoke PUBLIC execute on internal functions (CWE-862) */
REVOKE ALL ON FUNCTION sys.dbms_profiler_start_profiler_internal(text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION sys.dbms_profiler_get_run_number_internal() FROM PUBLIC;
REVOKE ALL ON FUNCTION sys.dbms_profiler_stop_profiler_internal() FROM PUBLIC;
REVOKE ALL ON FUNCTION sys.dbms_profiler_pause_profiler_internal() FROM PUBLIC;
REVOKE ALL ON FUNCTION sys.dbms_profiler_resume_profiler_internal() FROM PUBLIC;
REVOKE ALL ON FUNCTION sys.dbms_profiler_flush_data_internal() FROM PUBLIC;
REVOKE ALL ON FUNCTION sys.dbms_profiler_get_version_internal() FROM PUBLIC;

-- PL/iSQL package specification
CREATE OR REPLACE PACKAGE dbms_profiler AS

    -- Return codes
    success         CONSTANT INTEGER := 0;
    error_param     CONSTANT INTEGER := 1;
    error_io        CONSTANT INTEGER := 2;
    error_version   CONSTANT INTEGER := -1;

    -- Version constants
    major_version   CONSTANT INTEGER := 2;
    minor_version   CONSTANT INTEGER := 0;

    /*
     * START_PROFILER
     * Begins profiling session. Returns 0 on success.
     */
    FUNCTION start_profiler(run_comment IN VARCHAR2 DEFAULT '',
                            run_comment1 IN VARCHAR2 DEFAULT '') RETURN INTEGER;

    PROCEDURE start_profiler(run_comment IN VARCHAR2,
                             run_comment1 IN VARCHAR2,
                             run_number OUT NUMBER);

    /*
     * STOP_PROFILER
     * Stops profiling session and records total execution time.
     */
    FUNCTION stop_profiler RETURN INTEGER;

    PROCEDURE stop_profiler;

    /*
     * PAUSE_PROFILER
     * Pauses profiler data gathering.
     */
    FUNCTION pause_profiler RETURN INTEGER;

    /*
     * RESUME_PROFILER
     * Resumes profiler data gathering after pause.
     */
    FUNCTION resume_profiler RETURN INTEGER;

    /*
     * FLUSH_DATA
     * Flushes buffered profiler statistics to repository tables.
     */
    FUNCTION flush_data RETURN INTEGER;

    PROCEDURE flush_data;

    /*
     * GET_VERSION
     * Returns profiler major and minor versions via OUT parameters.
     */
    PROCEDURE get_version(major OUT NUMBER,
                          minor OUT NUMBER);

END dbms_profiler;

-- PL/iSQL package body
CREATE OR REPLACE PACKAGE BODY dbms_profiler AS

    FUNCTION start_profiler(run_comment IN VARCHAR2 DEFAULT '',
                            run_comment1 IN VARCHAR2 DEFAULT '') RETURN INTEGER IS
    BEGIN
        RETURN sys.dbms_profiler_start_profiler_internal(run_comment::text, run_comment1::text);
    END;

    PROCEDURE start_profiler(run_comment IN VARCHAR2,
                             run_comment1 IN VARCHAR2,
                             run_number OUT NUMBER) IS
        res INTEGER;
    BEGIN
        res := sys.dbms_profiler_start_profiler_internal(run_comment::text, run_comment1::text);
        IF res = success THEN
            run_number := sys.dbms_profiler_get_run_number_internal();
        ELSE
            run_number := 0;
        END IF;
    END;

    FUNCTION stop_profiler RETURN INTEGER IS
    BEGIN
        RETURN sys.dbms_profiler_stop_profiler_internal();
    END;

    PROCEDURE stop_profiler IS
        res INTEGER;
    BEGIN
        res := sys.dbms_profiler_stop_profiler_internal();
    END;

    FUNCTION pause_profiler RETURN INTEGER IS
    BEGIN
        RETURN sys.dbms_profiler_pause_profiler_internal();
    END;

    FUNCTION resume_profiler RETURN INTEGER IS
    BEGIN
        RETURN sys.dbms_profiler_resume_profiler_internal();
    END;

    FUNCTION flush_data RETURN INTEGER IS
    BEGIN
        RETURN sys.dbms_profiler_flush_data_internal();
    END;

    PROCEDURE flush_data IS
        res INTEGER;
    BEGIN
        res := sys.dbms_profiler_flush_data_internal();
    END;

    PROCEDURE get_version(major OUT NUMBER,
                          minor OUT NUMBER) IS
        v INTEGER;
    BEGIN
        v := sys.dbms_profiler_get_version_internal();
        major := v / 1000;
        minor := v % 1000;
    END;

END dbms_profiler;
