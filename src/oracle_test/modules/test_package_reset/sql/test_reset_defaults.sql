-- Test: RESET_PACKAGE restores declared defaults, not NULL

CREATE EXTENSION test_package_reset;

CREATE PACKAGE pkg_defaults_test AS
    g_with_default NUMBER := 42;
    g_no_default NUMBER;
    g_text_default VARCHAR2(100) := 'hello';
    FUNCTION get_with_default RETURN NUMBER;
    FUNCTION get_no_default RETURN NUMBER;
    FUNCTION get_text_default RETURN VARCHAR2;
    PROCEDURE set_with_default(n NUMBER);
    PROCEDURE set_no_default(n NUMBER);
    PROCEDURE set_text_default(s VARCHAR2);
END;
/

CREATE PACKAGE BODY pkg_defaults_test AS
    FUNCTION get_with_default RETURN NUMBER AS
    BEGIN
        RETURN g_with_default;
    END;
    FUNCTION get_no_default RETURN NUMBER AS
    BEGIN
        RETURN g_no_default;
    END;
    FUNCTION get_text_default RETURN VARCHAR2 AS
    BEGIN
        RETURN g_text_default;
    END;
    PROCEDURE set_with_default(n NUMBER) AS
    BEGIN
        g_with_default := n;
    END;
    PROCEDURE set_no_default(n NUMBER) AS
    BEGIN
        g_no_default := n;
    END;
    PROCEDURE set_text_default(s VARCHAR2) AS
    BEGIN
        g_text_default := s;
    END;
END;
/

-- 1. Verify initial defaults
SELECT pkg_defaults_test.get_with_default;
SELECT pkg_defaults_test.get_no_default;
SELECT pkg_defaults_test.get_text_default;

-- 2. Mutate all variables
CALL pkg_defaults_test.set_with_default(999);
CALL pkg_defaults_test.set_no_default(888);
CALL pkg_defaults_test.set_text_default('world');

-- 3. Verify mutation took effect
SELECT pkg_defaults_test.get_with_default;
SELECT pkg_defaults_test.get_no_default;
SELECT pkg_defaults_test.get_text_default;

-- 4. Reset all packages
SELECT test_package_reset.reset_all_packages();

-- 5. After reset: declared defaults restored, not NULL
SELECT pkg_defaults_test.get_with_default;
SELECT pkg_defaults_test.get_no_default;
SELECT pkg_defaults_test.get_text_default;

DROP PACKAGE BODY pkg_defaults_test;
DROP PACKAGE pkg_defaults_test;

-- 6. Expanded-object (array) global.
CREATE PACKAGE pkg_arr_defaults AS
    g_arr integer[] := ARRAY[1, 2, 3];
    FUNCTION get_arr_len RETURN NUMBER;
    FUNCTION get_arr_first RETURN NUMBER;
    PROCEDURE set_arr(a integer[]);
    PROCEDURE set_elem(i integer, v integer);
END;
/

CREATE PACKAGE BODY pkg_arr_defaults AS
    FUNCTION get_arr_len RETURN NUMBER AS
    BEGIN
        RETURN cardinality(g_arr);
    END;
    FUNCTION get_arr_first RETURN NUMBER AS
    BEGIN
        RETURN g_arr[1];
    END;
    PROCEDURE set_arr(a integer[]) AS
    BEGIN
        g_arr := a;
    END;
    PROCEDURE set_elem(i integer, v integer) AS
    BEGIN
        g_arr[i] := v;
    END;
END;
/

SELECT pkg_arr_defaults.get_arr_len AS len, pkg_arr_defaults.get_arr_first AS first;

CALL pkg_arr_defaults.set_elem(2, 99);
CALL pkg_arr_defaults.set_arr(ARRAY[10, 20, 30, 40]);
SELECT pkg_arr_defaults.get_arr_len AS len, pkg_arr_defaults.get_arr_first AS first;

SELECT test_package_reset.reset_all_packages();

SELECT pkg_arr_defaults.get_arr_len AS len, pkg_arr_defaults.get_arr_first AS first;

-- Cleanup
DROP PACKAGE BODY pkg_arr_defaults;
DROP PACKAGE pkg_arr_defaults;

DROP EXTENSION test_package_reset;
