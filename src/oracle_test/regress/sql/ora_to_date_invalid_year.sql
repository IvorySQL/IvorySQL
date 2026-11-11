--
-- ORA_TO_DATE_INVALID_YEAR
-- Test that Oracle-compatible TO_DATE / TO_TIMESTAMP reject year 0
-- (ORA-01841), instead of silently replacing it with the default year.
--

-- year 0000 is not a valid full year
SELECT to_date('0000-01-01', 'YYYY-MM-DD');
SELECT to_timestamp('0000-01-01', 'YYYY-MM-DD');
SELECT to_timestamp('0000-01-01 12:34:56', 'YYYY-MM-DD HH24:MI:SS');
-- a year supplied on its own
SELECT to_date('0000', 'YYYY');
-- the ISO year picture is checked the same way
SELECT to_date('0000-01-01', 'IYYY-MM-DD');

-- the signed picture already rejected year 0; keep it that way
SELECT to_date('0000-01-01', 'SYYYY-MM-DD');

-- legitimate boundary years still work
SELECT to_date('0001-01-01', 'YYYY-MM-DD');
SELECT to_date('9999-12-31', 'YYYY-MM-DD');
SELECT to_char(to_date('2026-11-10', 'YYYY-MM-DD'), 'YYYY-MM-DD');
SELECT to_char(to_timestamp('2026-11-10 12:34:56', 'YYYY-MM-DD HH24:MI:SS'),
               'YYYY-MM-DD HH24:MI:SS');

-- PostgreSQL mode keeps the historical behaviour: year 0 means 1 BC
SET ivorysql.compatible_mode = pg;
SELECT to_date('0000-01-01', 'YYYY-MM-DD');
SET ivorysql.compatible_mode = oracle;
