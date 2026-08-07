/* src/oracle_test/modules/test_package_reset/test_package_reset--1.0.sql */

-- Test extension for PLiSQL package reset API

CREATE FUNCTION test_package_reset.reset_package_by_oid(oid)
RETURNS bool
AS 'MODULE_PATHNAME', 'test_package_reset_reset_package_by_oid'
LANGUAGE C STRICT;

COMMENT ON FUNCTION test_package_reset.reset_package_by_oid(oid)
IS 'Reset a single PLiSQL package by its oid (from pg_package.oid). Returns true if package was reset, false if nothing to do.';

CREATE FUNCTION test_package_reset.reset_all_packages()
RETURNS int4
AS 'MODULE_PATHNAME', 'test_package_reset_reset_all_packages'
LANGUAGE C STRICT;

COMMENT ON FUNCTION test_package_reset.reset_all_packages()
IS 'Reset all PLiSQL packages in the current session. Returns number of packages actually reset, or -1 if PL/iSQL is not loaded.';
