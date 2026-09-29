--
-- UTL_IDENT
--
-- Regression tests for Oracle-compatible UTL_IDENT package:
--   - IS_ORACLE_SERVER, IS_ORACLE_CLIENT, IS_TIMESTEN, IS_ORACLE_FORMS, IS_SATELLITE
--   - ORACLE_RELEASE, ORACLE_VERSION
--   - GET_ENVIRONMENT, CHECK_SERVER, GET_RELEASE, GET_VERSION, GET_VERSION_STRING, MATCHES_ENVIRONMENT
--   - Conditional compilation and branching simulation
--

-- Package constants
SELECT utl_ident.is_oracle_server;
SELECT utl_ident.is_oracle_client;
SELECT utl_ident.is_timesten;
SELECT utl_ident.is_oracle_forms;
SELECT utl_ident.is_satellite;
SELECT utl_ident.oracle_release;
SELECT utl_ident.oracle_version;

-- Environment inspection subprograms
SELECT utl_ident.get_environment();
SELECT utl_ident.check_server();
SELECT utl_ident.get_release();
SELECT utl_ident.get_version();
SELECT utl_ident.get_version_string();

-- Environment matching checks
SELECT utl_ident.matches_environment('ORACLE_SERVER');
SELECT utl_ident.matches_environment('oracle_server');
SELECT utl_ident.matches_environment('server');
SELECT utl_ident.matches_environment('TIMESTEN');
SELECT utl_ident.matches_environment(NULL);

-- Conditional branching using UTL_IDENT constants
DO $$
BEGIN
    IF utl_ident.is_oracle_server THEN
        RAISE INFO 'Running in Oracle Server compatible mode';
    ELSIF utl_ident.is_timesten THEN
        RAISE EXCEPTION 'Unexpected TimesTen environment';
    ELSE
        RAISE EXCEPTION 'Unexpected client environment';
    END IF;
END;
$$;

-- Version check assertions
DO $$
DECLARE
    rel INTEGER;
    ver INTEGER;
BEGIN
    rel := utl_ident.get_release();
    ver := utl_ident.get_version();
    IF rel != utl_ident.oracle_release OR ver != utl_ident.oracle_version THEN
        RAISE EXCEPTION 'Version constant mismatch: rel=%, ver=%', rel, ver;
    END IF;
    RAISE INFO 'Version assertions: ok';
END;
$$;

-- Verify internal functions execute privilege revoked from PUBLIC (CWE-862)
SELECT p.proname, has_function_privilege('public', p.oid, 'EXECUTE') AS public_can_execute
  FROM pg_catalog.pg_proc p
  JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'sys'
   AND p.proname IN ('utl_ident_is_oracle_server',
                     'utl_ident_is_oracle_client',
                     'utl_ident_is_timesten',
                     'utl_ident_is_oracle_forms',
                     'utl_ident_is_satellite',
                     'utl_ident_environment',
                     'utl_ident_get_release_major',
                     'utl_ident_get_release_minor',
                     'utl_ident_get_version_string',
                     'utl_ident_matches_environment')
 ORDER BY p.proname;
