/* src/pl/plisql/src/plisql--1.0.sql */

-- The language object, but not the functions, can be owned by a non-superuser.
ALTER LANGUAGE plisql OWNER TO @extowner@;

COMMENT ON LANGUAGE plisql IS 'PL/iSQL procedural language';
