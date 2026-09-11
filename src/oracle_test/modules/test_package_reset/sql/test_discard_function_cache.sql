-- Cached callers and plans must survive repeated package cache resets.

CREATE PACKAGE discard_cache_pkg AS
    FUNCTION value RETURN NUMBER;
END discard_cache_pkg;
/

CREATE PACKAGE BODY discard_cache_pkg AS
    FUNCTION value RETURN NUMBER AS
    BEGIN
        RETURN 42;
    END;
END discard_cache_pkg;
/

CREATE OR REPLACE FUNCTION discard_cache_consumer RETURN NUMBER IS
BEGIN
    RETURN discard_cache_pkg.value();
END;
/

SELECT discard_cache_consumer() AS cached_caller_value FROM dual;
PREPARE discard_package_call AS
    SELECT discard_cache_pkg.value() AS cached_plan_value FROM dual;
EXPLAIN (ANALYZE, COSTS OFF, SUMMARY OFF, TIMING OFF, BUFFERS OFF)
EXECUTE discard_package_call;

DISCARD PACKAGE;

SELECT discard_cache_consumer() AS cached_caller_value FROM dual;
EXPLAIN (ANALYZE, COSTS OFF, SUMMARY OFF, TIMING OFF, BUFFERS OFF)
EXECUTE discard_package_call;

-- A second reset checks that rebuilt dependency lists do not retain stale links.
DISCARD PACKAGE;
SELECT discard_cache_consumer() AS cached_caller_value FROM dual;
EXPLAIN (ANALYZE, COSTS OFF, SUMMARY OFF, TIMING OFF, BUFFERS OFF)
EXECUTE discard_package_call;

DEALLOCATE discard_package_call;
DROP FUNCTION discard_cache_consumer;
DROP PACKAGE discard_cache_pkg;
