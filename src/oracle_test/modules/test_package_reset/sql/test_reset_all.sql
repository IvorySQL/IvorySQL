-- Oracle mode test: reset_all_packages resets every package

CREATE EXTENSION test_package_reset;

-- Create 3 packages with get/set methods
CREATE OR REPLACE PACKAGE pkg_x AS
    g_n NUMBER := 0;
    FUNCTION get_n RETURN NUMBER;
    FUNCTION set_n(n NUMBER) RETURN NUMBER;
END pkg_x;
/

CREATE OR REPLACE PACKAGE BODY pkg_x AS
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

CREATE OR REPLACE PACKAGE pkg_y AS
    g_n NUMBER := 0;
    FUNCTION get_n RETURN NUMBER;
    FUNCTION set_n(n NUMBER) RETURN NUMBER;
END pkg_y;
/

CREATE OR REPLACE PACKAGE BODY pkg_y AS
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

CREATE OR REPLACE PACKAGE pkg_z AS
    g_n NUMBER := 0;
    FUNCTION get_n RETURN NUMBER;
    FUNCTION set_n(n NUMBER) RETURN NUMBER;
END pkg_z;
/

CREATE OR REPLACE PACKAGE BODY pkg_z AS
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

-- Reset all (clean slate)
SELECT test_package_reset.reset_all_packages();

-- Init 1 single var on a single package
SELECT pkg_x.set_n(100);

-- Get all vars
SELECT pkg_x.get_n AS x, pkg_y.get_n AS y, pkg_z.get_n AS z;

-- Reset all
SELECT test_package_reset.reset_all_packages();

-- Get all vars
SELECT pkg_x.get_n AS x, pkg_y.get_n AS y, pkg_z.get_n AS z;

-- Init all 3 packages
SELECT pkg_x.set_n(100);
SELECT pkg_y.set_n(200);
SELECT pkg_z.set_n(300);

-- Get all vars
SELECT pkg_x.get_n AS x, pkg_y.get_n AS y, pkg_z.get_n AS z;

-- Reset all
SELECT test_package_reset.reset_all_packages();

-- Get all vars
SELECT pkg_x.get_n AS x, pkg_y.get_n AS y, pkg_z.get_n AS z;

-- Cleanup
DROP PACKAGE pkg_x;
DROP PACKAGE pkg_y;
DROP PACKAGE pkg_z;

DROP EXTENSION test_package_reset;
