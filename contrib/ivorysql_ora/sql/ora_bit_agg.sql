--
-- ora_bit_agg.sql: test Oracle-compatible BIT_AND_AGG / BIT_OR_AGG / BIT_XOR_AGG
-- aggregate functions
--
CREATE TABLE bit_agg_test (grp VARCHAR2(10), val NUMBER);
INSERT INTO bit_agg_test VALUES ('A', 12);
INSERT INTO bit_agg_test VALUES ('A', 10);
INSERT INTO bit_agg_test VALUES ('A', 9);
INSERT INTO bit_agg_test VALUES ('B', 5);

-- Basic usage: 12 & 10 & 9 = 8, 12 | 10 | 9 = 15, 12 # 10 # 9 = 15
-- (bare NUMBER values need no cast -- they coerce implicitly, same as
-- passing a plain integer to LENGTH()/LENGTHB() needs none)
SELECT bit_and_agg(val) FROM bit_agg_test WHERE grp = 'A';
SELECT bit_or_agg(val) FROM bit_agg_test WHERE grp = 'A';
SELECT bit_xor_agg(val) FROM bit_agg_test WHERE grp = 'A';

-- GROUP BY usage
SELECT grp, bit_and_agg(val), bit_or_agg(val), bit_xor_agg(val)
  FROM bit_agg_test GROUP BY grp ORDER BY grp;

-- Single value: identity
SELECT bit_and_agg(val), bit_or_agg(val), bit_xor_agg(val)
  FROM bit_agg_test WHERE grp = 'B';

-- NULL handling: NULLs are ignored
INSERT INTO bit_agg_test VALUES ('A', NULL);
SELECT bit_and_agg(val) FROM bit_agg_test WHERE grp = 'A';
SELECT bit_or_agg(val) FROM bit_agg_test WHERE grp = 'A';
SELECT bit_xor_agg(val) FROM bit_agg_test WHERE grp = 'A';

-- All-NULL input returns 0, not NULL (confirmed against a real Oracle
-- instance; some published docs suggest NULL, but that is not what Oracle
-- actually does).
SELECT bit_and_agg(val), bit_or_agg(val), bit_xor_agg(val)
  FROM bit_agg_test WHERE val IS NULL;

-- Empty set likewise returns 0, not NULL.
SELECT bit_and_agg(val), bit_or_agg(val), bit_xor_agg(val)
  FROM bit_agg_test WHERE grp = 'NONE';

-- Result type is NUMBER
SELECT pg_typeof(bit_and_agg(val)), pg_typeof(bit_xor_agg(val))
  FROM bit_agg_test WHERE grp = 'A';

-- Negative numbers (two's complement semantics via int8)
SELECT bit_and_agg(val), bit_or_agg(val), bit_xor_agg(val)
  FROM (SELECT -1 AS val FROM dual UNION ALL SELECT -2 FROM dual) v;

-- Oracle truncates fractional NUMBER values toward zero before the bitwise
-- op (it does not round): trunc(2.7)=2, trunc(3.2)=3, so 2&3=2, 2|3=3, 2#3=1.
SELECT bit_and_agg(val), bit_or_agg(val), bit_xor_agg(val)
  FROM (SELECT 2.7 AS val FROM dual UNION ALL SELECT 3.2 FROM dual) v;

-- Truncation toward zero also applies to negative fractions: trunc(-2.7)=-2.
SELECT bit_and_agg(val) FROM (SELECT -2.7 AS val FROM dual) v;

DROP TABLE bit_agg_test;

--
-- Boundary values
--

-- Zero is a valid operand: it's the OR/XOR identity element and forces AND to 0.
SELECT bit_and_agg(val), bit_or_agg(val), bit_xor_agg(val)
  FROM (SELECT 0 AS val FROM dual UNION ALL SELECT 5 FROM dual) v;

-- Exact int8 boundary (2^63-1 and -2^63) must work without overflowing,
-- and without silently losing precision through an unintended cast to
-- double precision along the way (trunc(NUMBER) is ambiguous between
-- trunc(numeric) and trunc(double precision); this implementation forces
-- the numeric overload).
CREATE TABLE bit_agg_bounds (val NUMBER);
INSERT INTO bit_agg_bounds VALUES (9223372036854775807);
INSERT INTO bit_agg_bounds VALUES (-9223372036854775808);
SELECT bit_and_agg(val), bit_or_agg(val), bit_xor_agg(val) FROM bit_agg_bounds;
DROP TABLE bit_agg_bounds;

--
-- Out-of-range / non-finite input: this implementation supports the int8
-- range (-2^63 to 2^63-1). Real Oracle's BIT_AND_AGG/BIT_OR_AGG/BIT_XOR_AGG
-- support a wider 128-bit signed range (-2^127 to 2^127-1) and would only
-- error beyond that; a NUMBER outside int8 range but within 128 bits is a
-- known, accepted gap here. NUMBER never holds NaN/Infinity in real Oracle,
-- so there is no Oracle behavior to match for those inputs -- as long as
-- they fail clearly (rather than silently miscompute), that is acceptable.
-- CAST(... AS NUMBER), not the PostgreSQL-only "::" operator, is used here
-- since these values need an explicit, portable typed literal.
--

-- One beyond the positive int8 boundary
SELECT bit_and_agg(val) FROM (SELECT CAST(9223372036854775808 AS number) AS val FROM dual) v;

-- One beyond the negative int8 boundary
SELECT bit_and_agg(val) FROM (SELECT CAST(-9223372036854775809 AS number) AS val FROM dual) v;

-- NaN and Infinity: NUMBER is built on PostgreSQL's numeric type, which can
-- represent these even though Oracle NUMBER cannot; they must fail cleanly
-- rather than misbehave.
SELECT bit_and_agg(val) FROM (SELECT CAST('NaN' AS number) AS val FROM dual) v;
SELECT bit_or_agg(val) FROM (SELECT CAST('Infinity' AS number) AS val FROM dual) v;
SELECT bit_xor_agg(val) FROM (SELECT CAST('-Infinity' AS number) AS val FROM dual) v;

-- A value that cannot be parsed as a NUMBER at all fails at cast time,
-- before ever reaching the aggregate.
SELECT bit_and_agg(val) FROM (SELECT CAST('abc' AS number) AS val FROM dual) v;

--
-- DISTINCT: XOR is sensitive to repeated values (a value XORed with itself
-- cancels out), so DISTINCT changes the result -- unlike AND/OR, which are
-- idempotent and unaffected by duplicates.
--
SELECT bit_xor_agg(val), bit_xor_agg(DISTINCT val)
  FROM (SELECT 3 AS val FROM dual UNION ALL SELECT 3 FROM dual UNION ALL SELECT 5 FROM dual) v;

--
-- FILTER clause (standard SQL, works generically for any aggregate)
--
SELECT bit_and_agg(val) FILTER (WHERE val > 0)
  FROM (SELECT -1 AS val FROM dual UNION ALL SELECT 6 FROM dual UNION ALL SELECT 4 FROM dual) v;

--
-- Analytic/window usage: Oracle documents these as usable both as
-- aggregate and analytic functions.
--
CREATE TABLE bit_agg_window (grp VARCHAR2(10), val NUMBER);
INSERT INTO bit_agg_window VALUES ('A', 12);
INSERT INTO bit_agg_window VALUES ('A', 10);
INSERT INTO bit_agg_window VALUES ('A', 9);
INSERT INTO bit_agg_window VALUES ('B', 5);
INSERT INTO bit_agg_window VALUES ('B', 1);
SELECT grp, val, bit_and_agg(val) OVER (PARTITION BY grp)
  FROM bit_agg_window ORDER BY grp, val;
DROP TABLE bit_agg_window;

--
-- Parallel aggregation: cross-check against PostgreSQL's native
-- bit_and/bit_or/bit_xor over the same underlying int8 values, with
-- settings that make a parallel plan (Partial Aggregate + Gather +
-- Finalize Aggregate, exercising COMBINEFUNC) likely on machines with
-- spare worker slots. The comparison is against core's own result rather
-- than a hardcoded constant, so the expected output is stable regardless
-- of whether this particular environment actually goes parallel.
-- generate_series()/bit_and()/bit_or()/bit_xor() are plain PostgreSQL,
-- used here only as bulk test-data plumbing and as an independent oracle
-- to check against -- not part of the Oracle compatibility surface under
-- test, so they are not rewritten into Oracle idiom.
--
CREATE TABLE bit_agg_xcheck AS
SELECT CAST(g % 4096 AS number) AS val, CAST(g % 4096 AS int8) AS val8
  FROM generate_series(1, 50000) g;
SET parallel_setup_cost = 0;
SET parallel_tuple_cost = 0;
SET min_parallel_table_scan_size = 0;
SET max_parallel_workers_per_gather = 4;
SELECT bit_and_agg(val) = bit_and(val8) AS and_matches,
       bit_or_agg(val) = bit_or(val8) AS or_matches,
       bit_xor_agg(val) = bit_xor(val8) AS xor_matches
  FROM bit_agg_xcheck;
RESET parallel_setup_cost;
RESET parallel_tuple_cost;
RESET min_parallel_table_scan_size;
RESET max_parallel_workers_per_gather;
DROP TABLE bit_agg_xcheck;

------------------------------------------------------------------------
-- Oracle-Compatible tests
-- Following sqls are alse tested against Oracle 26ai
------------------------------------------------------------------------

CREATE TABLE bit_agg_check_user_perms (
  user_id   NUMBER,
  dept_id   NUMBER,
  perm_mask NUMBER,
  flag_raw  RAW(4)
);

INSERT INTO bit_agg_check_user_perms VALUES (1, 10, 12,   HEXTORAW('0000000C'));  -- 1100
INSERT INTO bit_agg_check_user_perms VALUES (2, 10, 14,   HEXTORAW('0000000E'));  -- 1110
INSERT INTO bit_agg_check_user_perms VALUES (3, 10, 10,   HEXTORAW('0000000A'));  -- 1010
INSERT INTO bit_agg_check_user_perms VALUES (4, 20,  7,   HEXTORAW('00000007'));  -- 0111
INSERT INTO bit_agg_check_user_perms VALUES (5, 20,  3,   HEXTORAW('00000003'));  -- 0011
INSERT INTO bit_agg_check_user_perms VALUES (6, 20, NULL, NULL);
COMMIT;

-- basical table agg
SELECT BIT_AND_AGG(perm_mask) AS common_bits
FROM   bit_agg_check_user_perms;

-- with GROUP BY
SELECT dept_id,
       BIT_AND_AGG(perm_mask) AS dept_common_bits
FROM   bit_agg_check_user_perms
GROUP  BY dept_id;

-- with HAVING
SELECT dept_id, BIT_AND_AGG(perm_mask) AS m
FROM   bit_agg_check_user_perms
GROUP  BY dept_id
HAVING BIT_AND_AGG(perm_mask) > 0;

-- mixed
SELECT dept_id,
       BIT_AND_AGG(perm_mask) AS all_have,
       BIT_OR_AGG (perm_mask) AS any_have,
       BIT_XOR_AGG(perm_mask) AS parity
FROM   bit_agg_check_user_perms
GROUP  BY dept_id;

-- empty OVER
SELECT user_id, dept_id, perm_mask,
       BIT_AND_AGG(perm_mask) OVER () AS global_and
FROM   bit_agg_check_user_perms;

-- with PARTITION BY
SELECT user_id, dept_id, perm_mask,
       BIT_AND_AGG(perm_mask) OVER (PARTITION BY dept_id) AS dept_and
FROM   bit_agg_check_user_perms;

-- windowed
SELECT user_id, dept_id, perm_mask,
       BIT_AND_AGG(perm_mask) OVER (
         PARTITION BY dept_id
         ORDER BY user_id
         ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
       ) AS running_and
FROM   bit_agg_check_user_perms;

-- sliding window
SELECT user_id, perm_mask,
       BIT_AND_AGG(perm_mask) OVER (
         ORDER BY user_id
         ROWS BETWEEN 1 PRECEDING AND 1 FOLLOWING
       ) AS win3_and
FROM   bit_agg_check_user_perms;

-- ROLLUP / GROUPING SETS
SELECT dept_id,
       BIT_AND_AGG(perm_mask) AS m,
       GROUPING(dept_id)      AS is_total
FROM   bit_agg_check_user_perms
GROUP  BY ROLLUP(dept_id);

-- RAW type
SELECT dept_id,
       BIT_AND_AGG(flag_raw) AS raw_and
FROM   bit_agg_check_user_perms
GROUP  BY dept_id;

-- CASE
SELECT BIT_AND_AGG(CASE WHEN perm_mask IS NULL THEN 4294967295
                        ELSE perm_mask END) AS and_with_null_as_allones
FROM   bit_agg_check_user_perms;
SELECT BIT_AND_AGG(TRUNC(perm_mask / 2)) FROM bit_agg_check_user_perms;

-- compare with BITAND
SELECT BITAND(12, 14)      AS two_args,
       BITAND(BITAND(12,14), 10) AS three_vals
FROM dual;
SELECT BIT_AND_AGG(m) FROM (SELECT 12 m FROM dual UNION ALL
                            SELECT 14 FROM dual UNION ALL
                            SELECT 10 FROM dual);

-- real case: check if all has specific flag
SELECT dept_id,
       CASE WHEN BITAND(BIT_AND_AGG(perm_mask), 8) = 8
            THEN 'Y' ELSE 'N' END AS all_have_bit3
FROM   bit_agg_check_user_perms
GROUP  BY dept_id;
