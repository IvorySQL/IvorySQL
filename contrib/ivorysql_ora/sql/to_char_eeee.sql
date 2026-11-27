-- Tests for EEEE exponent-casing behavior of to_char() in both
-- compatibility modes: in oracle mode the exponent separator is
-- uppercase E, in pg mode the native lowercase form is preserved.
SET ivorysql.compatible_mode = oracle;
SELECT to_char(1.234e+10, '9.999EEEE') AS ora_pos;
SELECT to_char(1.234e-10, '9.999EEEE') AS ora_neg;
SELECT to_char(0, '9.9EEEE') AS ora_zero;

SET ivorysql.compatible_mode = pg;
SELECT to_char(1.234e+10, '9.999EEEE') AS pg_pos;
SELECT to_char(1.234e-10, '9.999EEEE') AS pg_neg;
SELECT to_char(0, '9.9EEEE') AS pg_zero;
