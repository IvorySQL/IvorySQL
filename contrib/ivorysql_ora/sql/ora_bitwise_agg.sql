--
-- ora_bitwise_agg.sql
--
-- Tests for the Oracle-compatible bitwise aggregates BIT_AND_AGG,
-- BIT_OR_AGG and BIT_XOR_AGG.  Expected values were verified against
-- Oracle 23ai.
--

-- ============================================================
-- Basic behaviour
-- ============================================================

CREATE TABLE bit_agg_t (n numeric);

INSERT INTO bit_agg_t VALUES (6), (3), (NULL);

-- 6&3=2, 6|3=7, 6^3=5; NULL inputs are skipped
SELECT bit_and_agg(n) AS and_r, bit_or_agg(n) AS or_r, bit_xor_agg(n) AS xor_r FROM bit_agg_t;

-- works with GROUP BY, including the all-NULL group (empty result is 0,
-- not NULL)
SELECT mod(n, 2) AS g, bit_and_agg(n) AS and_r, bit_or_agg(n) AS or_r,
       bit_xor_agg(n) AS xor_r
FROM bit_agg_t GROUP BY mod(n, 2) ORDER BY g;

DROP TABLE bit_agg_t;

-- ============================================================
-- Empty input and all-NULL input yield 0, as on Oracle 23ai
-- ============================================================

CREATE TABLE bit_agg_empty (n numeric);

SELECT bit_and_agg(n) AS and_r, bit_or_agg(n) AS or_r, bit_xor_agg(n) AS xor_r
FROM bit_agg_empty;

INSERT INTO bit_agg_empty VALUES (NULL), (NULL);

SELECT bit_and_agg(n) AS and_r, bit_or_agg(n) AS or_r, bit_xor_agg(n) AS xor_r
FROM bit_agg_empty;

DROP TABLE bit_agg_empty;

-- ============================================================
-- Negatives and non-integers: truncate toward zero, then apply the
-- bitwise operation on the two's-complement representation
-- ============================================================

CREATE TABLE bit_agg_num (n numeric);

INSERT INTO bit_agg_num VALUES (-1), (5), (2.9), (-2.9);

-- trunc(-2.9) = -2; with round() instead of truncate the xor would be 5,
-- Oracle 23ai answers 6
SELECT bit_and_agg(n) AS and_r, bit_or_agg(n) AS or_r, bit_xor_agg(n) AS xor_r
FROM bit_agg_num;

-- single row: the value truncated toward zero comes back unchanged
SELECT bit_and_agg(n) AS and_r, bit_or_agg(n) AS or_r, bit_xor_agg(n) AS xor_r
FROM bit_agg_num WHERE n = 5;

DROP TABLE bit_agg_num;

-- ============================================================
-- DISTINCT and ALL
-- ============================================================

CREATE TABLE bit_agg_d (n numeric);

INSERT INTO bit_agg_d VALUES (7), (7);

SELECT bit_xor_agg(DISTINCT n) AS xor_d, bit_xor_agg(ALL n) AS xor_a,
       bit_and_agg(DISTINCT n) AS and_d
FROM bit_agg_d;

DROP TABLE bit_agg_d;

-- ============================================================
-- Full 128-bit range
-- ============================================================

CREATE TABLE bit_agg_big (n numeric);

-- 2^127-1
INSERT INTO bit_agg_big VALUES (170141183460469231731687303715884105727);
-- 2^64 and 2^64-1
INSERT INTO bit_agg_big VALUES (18446744073709551616), (18446744073709551615);

SELECT bit_or_agg(n) AS or_r FROM bit_agg_big;

SELECT bit_and_agg(n) AS and_r, bit_xor_agg(n) AS xor_r FROM bit_agg_big;

DROP TABLE bit_agg_big;

-- values beyond the signed 128-bit range are rejected (Oracle 23ai does
-- not error but its answers for such inputs are internal artifacts)
SELECT bit_or_agg(x) FROM (VALUES (170141183460469231731687303715884105728::numeric)) v(x);

-- -2^127 is the valid lower boundary
SELECT bit_or_agg(x) AS or_r FROM (VALUES (-170141183460469231731687303715884105728::numeric)) v(x);

-- -2^127-1 underflows the signed 128-bit range
SELECT bit_or_agg(x) FROM (VALUES (-170141183460469231731687303715884105729::numeric)) v(x);

-- non-finite numerics cannot be truncated to an integer (numeric_out
-- emits no digits for them)
SELECT bit_or_agg(x) FROM (VALUES ('NaN'::numeric)) v(x);
SELECT bit_or_agg(x) FROM (VALUES ('Infinity'::numeric)) v(x);
SELECT bit_or_agg(x) FROM (VALUES ('-Infinity'::numeric)) v(x);

-- ============================================================
-- Implicit casts: integer and bigint inputs reach the numeric aggregate
-- ============================================================

SELECT bit_or_agg(x) AS int_in FROM (VALUES (1), (2), (4)) v(x);
SELECT bit_and_agg(x) AS bigint_in FROM (VALUES (12::bigint), (10::bigint)) v(x);

-- ============================================================
-- Window aggregation: OVER () uses the same transition state
-- ============================================================

CREATE TABLE bit_agg_win (n numeric);

INSERT INTO bit_agg_win VALUES (6), (3), (NULL);

SELECT n, bit_and_agg(n) OVER () AS and_r, bit_or_agg(n) OVER () AS or_r,
       bit_xor_agg(n) OVER () AS xor_r
FROM bit_agg_win ORDER BY n NULLS FIRST;

DROP TABLE bit_agg_win;

-- ============================================================
-- Parallel aggregation exercises serialize/deserialize of the
-- internal transition state
-- ============================================================

CREATE TABLE bit_agg_par (n numeric);

INSERT INTO bit_agg_par SELECT g FROM generate_series(1, 1000) g;

SET debug_parallel_query = on;
SET parallel_setup_cost = 0;
SET parallel_tuple_cost = 0;
SET min_parallel_table_scan_size = 0;

SELECT bit_and_agg(n) AS and_r, bit_or_agg(n) AS or_r, bit_xor_agg(n) AS xor_r
FROM bit_agg_par;

RESET debug_parallel_query;
RESET parallel_setup_cost;
RESET parallel_tuple_cost;
RESET min_parallel_table_scan_size;

DROP TABLE bit_agg_par;
