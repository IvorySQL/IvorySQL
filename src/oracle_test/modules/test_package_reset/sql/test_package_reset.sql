-- Test: extension loads and functions are callable in PG mode
CREATE EXTENSION test_package_reset;

-- reset_all_packages() is callable even with no packages
SELECT test_package_reset.reset_all_packages();

-- reset_package_by_oid(0) → false when plisql is not yet loaded in this session
SELECT test_package_reset.reset_package_by_oid(0);

-- cleanup
DROP EXTENSION test_package_reset;
