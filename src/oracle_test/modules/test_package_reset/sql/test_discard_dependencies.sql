-- DISCARD PACKAGE handles layered and cyclic package dependencies.

CREATE PACKAGE dep_leaf AS
    FUNCTION value RETURN NUMBER;
END dep_leaf;
/

CREATE PACKAGE BODY dep_leaf AS
    FUNCTION value RETURN NUMBER AS
    BEGIN
        RETURN 1;
    END;
END dep_leaf;
/

CREATE PACKAGE dep_left AS
    FUNCTION value RETURN NUMBER;
END dep_left;
/

CREATE PACKAGE BODY dep_left AS
    FUNCTION value RETURN NUMBER AS
    BEGIN
        RETURN dep_leaf.value() + 10;
    END;
END dep_left;
/

CREATE PACKAGE dep_right AS
    FUNCTION value RETURN NUMBER;
END dep_right;
/

CREATE PACKAGE BODY dep_right AS
    FUNCTION value RETURN NUMBER AS
    BEGIN
        RETURN dep_leaf.value() + 20;
    END;
END dep_right;
/

CREATE PACKAGE dep_root AS
    FUNCTION value RETURN NUMBER;
END dep_root;
/

CREATE PACKAGE BODY dep_root AS
    FUNCTION value RETURN NUMBER AS
    BEGIN
        RETURN dep_left.value() + dep_right.value();
    END;
END dep_root;
/

CREATE PACKAGE dep_independent AS
    FUNCTION value RETURN NUMBER;
END dep_independent;
/

CREATE PACKAGE BODY dep_independent AS
    FUNCTION value RETURN NUMBER AS
    BEGIN
        RETURN 100;
    END;
END dep_independent;
/

SELECT dep_root.value() AS layered_value,
       dep_independent.value() AS independent_value
FROM dual;

CREATE OR REPLACE FUNCTION dep_consumer RETURN NUMBER IS
BEGIN
    RETURN dep_root.value();
END;
/

SELECT dep_consumer() AS dependent_function_value FROM dual;

DISCARD PACKAGE;

-- Packages and dependent functions must compile and execute again.
SELECT dep_consumer() AS dependent_function_value FROM dual;

SELECT dep_root.value() AS layered_value,
       dep_independent.value() AS independent_value
FROM dual;

CREATE PACKAGE dep_cycle_a AS
    FUNCTION value(p_depth NUMBER) RETURN NUMBER;
END dep_cycle_a;
/

CREATE PACKAGE dep_cycle_b AS
    FUNCTION value(p_depth NUMBER) RETURN NUMBER;
END dep_cycle_b;
/

CREATE PACKAGE BODY dep_cycle_a AS
    FUNCTION value(p_depth NUMBER) RETURN NUMBER AS
    BEGIN
        IF p_depth = 0 THEN
            RETURN 1;
        END IF;
        RETURN dep_cycle_b.value(p_depth - 1) + 1;
    END;
END dep_cycle_a;
/

CREATE PACKAGE BODY dep_cycle_b AS
    FUNCTION value(p_depth NUMBER) RETURN NUMBER AS
    BEGIN
        IF p_depth = 0 THEN
            RETURN 1;
        END IF;
        RETURN dep_cycle_a.value(p_depth - 1) + 1;
    END;
END dep_cycle_b;
/

SELECT dep_cycle_a.value(2) AS cycle_value FROM dual;

DISCARD PACKAGE;

-- Cycles retain the old fallback ordering and remain safe to discard.
SELECT dep_cycle_b.value(3) AS cycle_value FROM dual;

DROP PACKAGE dep_root;
DROP PACKAGE dep_left;
DROP PACKAGE dep_right;
DROP PACKAGE dep_leaf;
DROP PACKAGE dep_independent;
DROP PACKAGE dep_cycle_a;
DROP PACKAGE dep_cycle_b;
DROP FUNCTION dep_consumer;
