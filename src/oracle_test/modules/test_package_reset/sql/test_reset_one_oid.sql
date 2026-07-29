-- Test: reset one package by OID works with multiple packages

CREATE EXTENSION test_package_reset;

-- Create 3 packages with get/set methods
CREATE PACKAGE pkg_x AS
    g_n NUMBER := 0;
    FUNCTION get_n RETURN NUMBER;
    FUNCTION set_n(n NUMBER) RETURN NUMBER;
END pkg_x;
/

CREATE PACKAGE BODY pkg_x AS
    FUNCTION get_n RETURN NUMBER AS
    BEGIN
        RETURN g_n;
    END;
    FUNCTION set_n(n NUMBER) RETURN NUMBER AS
    BEGIN
        g_n := n;
        RETURN n;
    END;
END pkg_x;
/

CREATE PACKAGE pkg_y AS
    g_n NUMBER := 0;
    FUNCTION get_n RETURN NUMBER;
    FUNCTION set_n(n NUMBER) RETURN NUMBER;
END pkg_y;
/

CREATE PACKAGE BODY pkg_y AS
    FUNCTION get_n RETURN NUMBER AS
    BEGIN
        RETURN g_n;
    END;
    FUNCTION set_n(n NUMBER) RETURN NUMBER AS
    BEGIN
        g_n := n;
        RETURN n;
    END;
END pkg_y;
/

CREATE PACKAGE pkg_z AS
    g_n NUMBER := 0;
    FUNCTION get_n RETURN NUMBER;
    FUNCTION set_n(n NUMBER) RETURN NUMBER;
END pkg_z;
/

CREATE PACKAGE BODY pkg_z AS
    FUNCTION get_n RETURN NUMBER AS
    BEGIN
        RETURN g_n;
    END;
    FUNCTION set_n(n NUMBER) RETURN NUMBER AS
    BEGIN
        g_n := n;
        RETURN n;
    END;
END pkg_z;
/

-- Init all 3 packages
SELECT pkg_x.set_n(100);
SELECT pkg_y.set_n(200);
SELECT pkg_z.set_n(300);

-- Get all vars
SELECT pkg_x.get_n AS x, pkg_y.get_n AS y, pkg_z.get_n AS z;

-- Reset pkg_x only — y and z must be untouched
DO $$
DECLARE
    v_oid OID;
BEGIN
    v_oid := (SELECT oid FROM pg_package WHERE pkgname = 'pkg_x');
    PERFORM test_package_reset.reset_package_by_oid(v_oid);
END $$;

-- Get all vars
SELECT pkg_x.get_n AS x, pkg_y.get_n AS y, pkg_z.get_n AS z;

-- Init all 3 packages
SELECT pkg_x.set_n(100);
SELECT pkg_y.set_n(200);
SELECT pkg_z.set_n(300);

-- Reset pkg_y only — x and z must be untouched
DO $$
DECLARE
    v_oid OID;
BEGIN
    v_oid := (SELECT oid FROM pg_package WHERE pkgname = 'pkg_y');
    PERFORM test_package_reset.reset_package_by_oid(v_oid);
END $$;

-- Get all vars
SELECT pkg_x.get_n AS x, pkg_y.get_n AS y, pkg_z.get_n AS z;

-- Init all 3 packages
SELECT pkg_x.set_n(100);
SELECT pkg_y.set_n(200);
SELECT pkg_z.set_n(300);

-- Reset pkg_z only — x and y must be untouched
DO $$
DECLARE
    v_oid OID;
BEGIN
    v_oid := (SELECT oid FROM pg_package WHERE pkgname = 'pkg_z');
    PERFORM test_package_reset.reset_package_by_oid(v_oid);
END $$;

-- Get all vars
SELECT pkg_x.get_n AS x, pkg_y.get_n AS y, pkg_z.get_n AS z;

-- Init all 3 packages
SELECT pkg_x.set_n(100);
SELECT pkg_y.set_n(200);
SELECT pkg_z.set_n(300);

-- Loop: reset each package by OID one at a time
DO $$
DECLARE
    v_oid OID;
BEGIN
    v_oid := (SELECT oid FROM pg_package WHERE pkgname = 'pkg_x');
    PERFORM test_package_reset.reset_package_by_oid(v_oid);

    v_oid := (SELECT oid FROM pg_package WHERE pkgname = 'pkg_y');
    PERFORM test_package_reset.reset_package_by_oid(v_oid);

    v_oid := (SELECT oid FROM pg_package WHERE pkgname = 'pkg_z');
    PERFORM test_package_reset.reset_package_by_oid(v_oid);
END $$;

-- Get all vars
SELECT pkg_x.get_n AS x, pkg_y.get_n AS y, pkg_z.get_n AS z;

-- Init all 3 packages
SELECT pkg_x.set_n(100);
SELECT pkg_y.set_n(200);
SELECT pkg_z.set_n(300);

-- Reset with NULL OID — STRICT function returns NULL, no side effects
SELECT test_package_reset.reset_package_by_oid(NULL);

-- Get all vars after NULL reset (should be unchanged — nothing to reset)
SELECT pkg_x.get_n AS x, pkg_y.get_n AS y, pkg_z.get_n AS z;

-- Cleanup
DROP PACKAGE pkg_x;
DROP PACKAGE pkg_y;
DROP PACKAGE pkg_z;

DROP EXTENSION test_package_reset;
