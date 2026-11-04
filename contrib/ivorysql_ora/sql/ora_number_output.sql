-- NUMBER's precision and scale do not fix the default output width.
SELECT CAST(5 AS NUMBER(5,2)) AS n1,
       CAST(123.5 AS NUMBER(5,2)) AS n2,
       CAST(0 AS NUMBER(5,2)) AS n3,
       CAST(6.89 AS NUMBER(5,2)) AS n4;
SELECT CAST(5 AS NUMBER(5,3)), CAST(1.230 AS NUMBER(5,3)),
       CAST(-1.230 AS NUMBER(5,3)), CAST(100 AS NUMBER(5,2));
SELECT '1.2300'::sys.number, '-0.0000'::sys.number,
       '0.00000100'::sys.number;
SELECT CAST(12345 AS NUMBER(5,-2)), CAST(0.00120 AS NUMBER(3,5));
SELECT CAST('9999999999999999999999999999.1200000000' AS NUMBER(38,10));
SELECT ARRAY[CAST(5 AS NUMBER(5,2)), CAST(1.20 AS NUMBER(5,2)),
             CAST(0 AS NUMBER(5,2)), NULL::sys.number];

-- Retain the existing support for special values and NULLs.
SELECT 'NaN'::sys.number, 'Infinity'::sys.number, '-Infinity'::sys.number,
       NULL::sys.number;

CREATE TABLE number_output_test (id integer, val NUMBER(5,2));
INSERT INTO number_output_test VALUES (1, -1.23), (2, 5), (3, 6.89), (4, 123.5);
SELECT * FROM number_output_test ORDER BY id;

-- Explicit and implicit conversions share the default representation.
SELECT id, '[' || TO_CHAR(val) || ']' AS default_char,
       '[' || val || ']' AS implicit_char,
       '[' || CAST(val AS VARCHAR2(20)) || ']' AS varchar_char,
       '[' || TO_CHAR(val, 'FM9990.00') || ']' AS fixed_char
FROM number_output_test ORDER BY id;

-- LIKE must match the same representation that is displayed.
SELECT val FROM number_output_test WHERE val LIKE '1%' ORDER BY id;
SELECT val FROM number_output_test WHERE val LIKE '_' ORDER BY id;
SELECT val FROM number_output_test WHERE val NOT LIKE '_' ORDER BY id;
SELECT val FROM number_output_test WHERE val LIKE '%0' ORDER BY id;
SELECT val FROM number_output_test WHERE val LIKE '%.%' ORDER BY id;
SELECT val FROM number_output_test WHERE val NOT LIKE '%.%' ORDER BY id;

-- Output must not alter the stored scale or the binary representation.
SELECT id, val::pg_catalog.numeric AS numeric_value,
       pg_catalog.scale(val::pg_catalog.numeric) AS stored_scale,
       sys.number_send(val) = pg_catalog.numeric_send(val::pg_catalog.numeric)
         AS same_binary
FROM number_output_test ORDER BY id;
COPY number_output_test TO STDOUT;

-- Typmod rounding and overflow checks must still apply before output.
SELECT CAST(1.236 AS NUMBER(5,2)), CAST(-1.236 AS NUMBER(5,2));
SELECT CAST(999.994 AS NUMBER(5,2));
SELECT CAST(999.995 AS NUMBER(5,2));
SELECT CAST(-999.995 AS NUMBER(5,2));
INSERT INTO number_output_test VALUES (5, 1.236), (6, 999.994);
INSERT INTO number_output_test VALUES (7, 999.995);
SELECT * FROM number_output_test WHERE id >= 5 ORDER BY id;

-- PostgreSQL numeric retains its own scale, even in Oracle mode.
SELECT CAST(5 AS pg_catalog.numeric(5,2)),
       CAST(123.5 AS pg_catalog.numeric(5,2)),
       CAST(0 AS pg_catalog.numeric(5,2));

DROP TABLE number_output_test;
