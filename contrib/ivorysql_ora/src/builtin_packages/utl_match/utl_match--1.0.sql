/***************************************************************
 *
 * UTL_MATCH Package
 *
 * Oracle-compatible string matching functions
 * (Oracle PL/SQL Packages and Types Reference, UTL_MATCH).
 *
 * contrib/ivorysql_ora/src/builtin_packages/utl_match/utl_match--1.0.sql
 *
 ***************************************************************/

-- C function wrappers (NULL in -> NULL out, matching Oracle semantics)
CREATE FUNCTION sys.ora_utl_match_edit_distance(s1 text, s2 text)
RETURNS integer
AS 'MODULE_PATHNAME', 'ora_utl_match_edit_distance'
LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION sys.ora_utl_match_edit_distance_similarity(s1 text, s2 text)
RETURNS integer
AS 'MODULE_PATHNAME', 'ora_utl_match_edit_distance_similarity'
LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION sys.ora_utl_match_jaro_winkler(s1 text, s2 text)
RETURNS float8
AS 'MODULE_PATHNAME', 'ora_utl_match_jaro_winkler'
LANGUAGE C IMMUTABLE STRICT;

CREATE FUNCTION sys.ora_utl_match_jaro_winkler_similarity(s1 text, s2 text)
RETURNS integer
AS 'MODULE_PATHNAME', 'ora_utl_match_jaro_winkler_similarity'
LANGUAGE C IMMUTABLE STRICT;

-- UTL_MATCH Package Definition
-- EDIT_DISTANCE           : minimum number of edits to transform s1 into s2
-- EDIT_DISTANCE_SIMILARITY: 0..100, based on edit distance
-- JARO_WINKLER            : 0..1, Jaro-Winkler similarity (case-sensitive)
-- JARO_WINKLER_SIMILARITY : 0..100, ROUND(JARO_WINKLER * 100)
CREATE OR REPLACE PACKAGE UTL_MATCH IS
    FUNCTION EDIT_DISTANCE(s1 IN VARCHAR2, s2 IN VARCHAR2) RETURN INTEGER;
    FUNCTION EDIT_DISTANCE_SIMILARITY(s1 IN VARCHAR2, s2 IN VARCHAR2) RETURN INTEGER;
    FUNCTION JARO_WINKLER(s1 IN VARCHAR2, s2 IN VARCHAR2) RETURN BINARY_DOUBLE;
    FUNCTION JARO_WINKLER_SIMILARITY(s1 IN VARCHAR2, s2 IN VARCHAR2) RETURN INTEGER;
END UTL_MATCH;

CREATE OR REPLACE PACKAGE BODY UTL_MATCH IS
    FUNCTION EDIT_DISTANCE(s1 IN VARCHAR2, s2 IN VARCHAR2) RETURN INTEGER IS
    BEGIN
        RETURN sys.ora_utl_match_edit_distance(s1, s2);
    END;

    FUNCTION EDIT_DISTANCE_SIMILARITY(s1 IN VARCHAR2, s2 IN VARCHAR2) RETURN INTEGER IS
    BEGIN
        RETURN sys.ora_utl_match_edit_distance_similarity(s1, s2);
    END;

    FUNCTION JARO_WINKLER(s1 IN VARCHAR2, s2 IN VARCHAR2) RETURN BINARY_DOUBLE IS
    BEGIN
        RETURN sys.ora_utl_match_jaro_winkler(s1, s2);
    END;

    FUNCTION JARO_WINKLER_SIMILARITY(s1 IN VARCHAR2, s2 IN VARCHAR2) RETURN INTEGER IS
    BEGIN
        RETURN sys.ora_utl_match_jaro_winkler_similarity(s1, s2);
    END;
END UTL_MATCH;