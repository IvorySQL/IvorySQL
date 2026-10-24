--
-- DBMS_TTS
--
-- Regression tests for Oracle-compatible DBMS_TTS package:
--   - Package constants
--   - TRANSPORT_SET_CHECK with valid tablespace (pg_default)
--   - TRANSPORT_SET_CHECK with non-existent tablespaces (violations recorded)
--   - IS_PLATFORM_SUPPORTED
--   - GET_ENDIANNESS
--   - CHECK_VERSION
--   - DOWNGRADE procedure
--   - Error handling (NULL parameter checks)
--   - Internal function execute privilege revoked from PUBLIC (CWE-862)
--

-- Package constants
SELECT dbms_tts.big_endian;
SELECT dbms_tts.little_endian;

-- TRANSPORT_SET_CHECK with valid tablespace
CALL dbms_tts.transport_set_check('pg_default');
SELECT COUNT(*) FROM sys.transport_set_violations;

-- TRANSPORT_SET_CHECK with non-existent tablespaces
CALL dbms_tts.transport_set_check('non_existent_ts1, non_existent_ts2');
SELECT violation FROM sys.transport_set_violations ORDER BY violation;

-- Platform verification functions
SELECT dbms_tts.is_platform_supported('Linux x86 64-bit');
SELECT dbms_tts.is_platform_supported('Microsoft Windows 64-bit');
SELECT dbms_tts.is_platform_supported('Unknown OS 128-bit');

SELECT dbms_tts.get_endianness('Linux x86 64-bit');
SELECT dbms_tts.get_endianness('AIX-Based Systems (64-bit)');

SELECT dbms_tts.check_version('19.0.0.0.0');
SELECT dbms_tts.check_version('8.1.7.0.0');

-- DOWNGRADE procedure
CALL dbms_tts.downgrade();

-- Error handling: NULL parameter
SELECT sys.dbms_tts_transport_set_check_internal(NULL, false, false);
SELECT sys.dbms_tts_is_platform_supported_internal(NULL);
SELECT sys.dbms_tts_get_endianness_internal(NULL);
SELECT sys.dbms_tts_check_version_internal(NULL);

-- Verify internal functions execute privilege revoked from PUBLIC (CWE-862)
SELECT p.proname, has_function_privilege('public', p.oid, 'EXECUTE') AS public_can_execute
  FROM pg_catalog.pg_proc p
  JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'sys'
   AND p.proname IN ('dbms_tts_transport_set_check_internal',
                     'dbms_tts_downgrade_internal',
                     'dbms_tts_is_platform_supported_internal',
                     'dbms_tts_get_endianness_internal',
                     'dbms_tts_check_version_internal')
 ORDER BY p.proname;

-- Clean up
DELETE FROM sys.transport_set_violations;
