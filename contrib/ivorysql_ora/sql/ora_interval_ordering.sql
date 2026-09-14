-- Large interval comparisons must agree with exact arithmetic, including
-- values on both sides of the signed 64-bit microsecond boundary.
CREATE TABLE interval_ordering_ds (
    id integer,
    value interval day(9) to second(6),
    micros numeric
);
INSERT INTO interval_ordering_ds VALUES
    (1, '-999999999 23:59:59.999999', -86400000000000000000 + 1),
    (2, '-213503982 08:01:49.551616', -18446744073709551616),
    (3, '-106751992 00:00:00', -9223372108800000000),
    (4, '-106751991 04:00:54.775808', -9223372036854775808),
    (5, '-1 00:00:00', -86400000000),
    (6, '-0 00:00:00.000001', -1),
    (7, '0 00:00:00', 0),
    (8, '0 00:00:00.000001', 1),
    (9, '1 00:00:00', 86400000000),
    (10, '106751991 04:00:54.775807', 9223372036854775807),
    (11, '106751992 00:00:00', 9223372108800000000),
    (12, '213503982 08:01:49.551616', 18446744073709551616),
    (13, '999999999 23:59:59.999999', 86400000000000000000 - 1);

CREATE TABLE interval_ordering_ym (
    id integer,
    value interval year(9) to month,
    months numeric
);
INSERT INTO interval_ordering_ym VALUES
    (1, '-178956970-7', -2147483647),
    (2, '-596524-0', -7158288),
    (3, '-298262-0', -3579144),
    (4, '-298261-7', -3579139),
    (5, '-0-1', -1),
    (6, '0-0', 0),
    (7, '0-1', 1),
    (8, '298261-7', 3579139),
    (9, '298262-0', 3579144),
    (10, '596524-0', 7158288),
    (11, '178956970-7', 2147483647);

-- Exercise every comparison operator with independent numeric expectations.
SELECT bool_and((a.value = b.value) = (a.micros = b.micros)) AS eq,
       bool_and((a.value <> b.value) = (a.micros <> b.micros)) AS ne,
       bool_and((a.value < b.value) = (a.micros < b.micros)) AS lt,
       bool_and((a.value <= b.value) = (a.micros <= b.micros)) AS le,
       bool_and((a.value > b.value) = (a.micros > b.micros)) AS gt,
       bool_and((a.value >= b.value) = (a.micros >= b.micros)) AS ge,
       bool_and(sys.dsinterval_cmp(a.value, b.value) =
                sign(a.micros - b.micros)) AS cmp
FROM interval_ordering_ds a CROSS JOIN interval_ordering_ds b;
SELECT bool_and((a.value = b.value) = (a.months = b.months)) AS eq,
       bool_and((a.value <> b.value) = (a.months <> b.months)) AS ne,
       bool_and((a.value < b.value) = (a.months < b.months)) AS lt,
       bool_and((a.value <= b.value) = (a.months <= b.months)) AS le,
       bool_and((a.value > b.value) = (a.months > b.months)) AS gt,
       bool_and((a.value >= b.value) = (a.months >= b.months)) AS ge,
       bool_and(sys.yminterval_cmp(a.value, b.value) =
                sign(a.months - b.months)) AS cmp
FROM interval_ordering_ym a CROSS JOIN interval_ordering_ym b;

-- A span of exactly 2^64 microseconds used to compare equal to zero.
-- Both unique-index construction and distinct aggregation must retain it.
CREATE UNIQUE INDEX interval_ordering_ds_unique ON interval_ordering_ds(value);
CREATE UNIQUE INDEX interval_ordering_ym_unique ON interval_ordering_ym(value);
SELECT count(DISTINCT value) = 13 AS distinct_values FROM interval_ordering_ds;
SELECT count(DISTINCT value) = 11 AS distinct_values FROM interval_ordering_ym;
SELECT array_agg(id ORDER BY value) = array_agg(id ORDER BY micros) AS sorted
FROM interval_ordering_ds;
SELECT array_agg(id ORDER BY value) = array_agg(id ORDER BY months) AS sorted
FROM interval_ordering_ym;
SELECT min(value) = (SELECT value FROM interval_ordering_ds WHERE id = 1) AS minimum,
       max(value) = (SELECT value FROM interval_ordering_ds WHERE id = 13) AS maximum
FROM interval_ordering_ds;
SELECT min(value) = (SELECT value FROM interval_ordering_ym WHERE id = 1) AS minimum,
       max(value) = (SELECT value FROM interval_ordering_ym WHERE id = 11) AS maximum
FROM interval_ordering_ym;

-- Preserve the historical low-64-bit hash input, including genuine hash
-- collisions, so existing hash indexes and hash partition routing remain valid.
SELECT bool_and(sys.dsinterval_hash(value) = pg_catalog.hashint8(
           (mod(mod(micros + 9223372036854775808, 18446744073709551616)
                    + 18446744073709551616, 18446744073709551616)
            - 9223372036854775808)::bigint)) AS hash_compatible
FROM interval_ordering_ds;
SELECT bool_and(sys.yminterval_hash(value) = pg_catalog.hashint8(
           (mod(mod(months * 2592000000000 + 9223372036854775808,
                    18446744073709551616) + 18446744073709551616,
                    18446744073709551616) - 9223372036854775808)::bigint))
       AS hash_compatible
FROM interval_ordering_ym;
SELECT bool_and(sys.dsinterval_hash_extended(value, seed) =
       pg_catalog.hashint8extended(
           (mod(mod(micros + 9223372036854775808, 18446744073709551616)
                    + 18446744073709551616, 18446744073709551616)
            - 9223372036854775808)::bigint, seed)) AS seeded_hash_compatible
FROM interval_ordering_ds CROSS JOIN (VALUES (0::bigint), (42::bigint), (-1::bigint)) s(seed);
SELECT bool_and(sys.yminterval_hash_extended(value, seed) =
       pg_catalog.hashint8extended(
           (mod(mod(months * 2592000000000 + 9223372036854775808,
                    18446744073709551616) + 18446744073709551616,
                    18446744073709551616) - 9223372036854775808)::bigint, seed))
       AS seeded_hash_compatible
FROM interval_ordering_ym CROSS JOIN (VALUES (0::bigint), (42::bigint), (-1::bigint)) s(seed);

-- Validate all four frame-boundary directions against exact arithmetic.
-- The largest boundaries deliberately exceed the stored interval range.
SELECT bool_and(sys.dsin_range(v.value, b.value, o.value, sub, less) =
       CASE WHEN less THEN v.micros <= b.micros + CASE WHEN sub THEN -o.micros ELSE o.micros END
            ELSE v.micros >= b.micros + CASE WHEN sub THEN -o.micros ELSE o.micros END END)
       AS all_frame_boundaries
FROM interval_ordering_ds v CROSS JOIN interval_ordering_ds b
CROSS JOIN interval_ordering_ds o
CROSS JOIN (VALUES (false), (true)) s(sub)
CROSS JOIN (VALUES (false), (true)) l(less)
WHERE o.micros >= 0;
SELECT bool_and(sys.ymin_range(v.value, b.value, o.value, sub, less) =
       CASE WHEN less THEN v.months <= b.months + CASE WHEN sub THEN -o.months ELSE o.months END
            ELSE v.months >= b.months + CASE WHEN sub THEN -o.months ELSE o.months END END)
       AS all_frame_boundaries
FROM interval_ordering_ym v CROSS JOIN interval_ordering_ym b
CROSS JOIN interval_ordering_ym o
CROSS JOIN (VALUES (false), (true)) s(sub)
CROSS JOIN (VALUES (false), (true)) l(less)
WHERE o.months >= 0;

-- Check executor RANGE frames, not only their support functions.
SELECT id, count(*) OVER (ORDER BY value RANGE BETWEEN
       INTERVAL '106751992' DAY(9) PRECEDING AND CURRENT ROW) AS preceding_count
FROM interval_ordering_ds ORDER BY id;
SELECT id, count(*) OVER (ORDER BY value RANGE BETWEEN CURRENT ROW AND
       INTERVAL '298262' YEAR(9) FOLLOWING) AS following_count
FROM interval_ordering_ym ORDER BY id;

-- Record client-visible errors for large negative offsets.
SELECT sys.dsin_range(INTERVAL '0' DAY, INTERVAL '0' DAY,
                      INTERVAL '-106751992' DAY(9), false, true);
SELECT sys.ymin_range(INTERVAL '0' YEAR, INTERVAL '0' YEAR,
                      INTERVAL '-298262' YEAR(9), false, true);

-- Verify ordered index scans agree with the numeric reference.
SET enable_seqscan = off;
SELECT id FROM interval_ordering_ds WHERE value > INTERVAL '0' DAY ORDER BY value;
SELECT id FROM interval_ordering_ym WHERE value < INTERVAL '0' YEAR ORDER BY value;
RESET enable_seqscan;

DROP INDEX interval_ordering_ds_unique;
DROP INDEX interval_ordering_ym_unique;
CREATE INDEX interval_ordering_ds_hash ON interval_ordering_ds USING hash(value);
CREATE INDEX interval_ordering_ym_hash ON interval_ordering_ym USING hash(value);
SET enable_seqscan = off;
SELECT id FROM interval_ordering_ds WHERE value = INTERVAL '0' DAY;
SELECT id FROM interval_ordering_ds
WHERE value = INTERVAL '213503982 08:01:49.551616' DAY(9) TO SECOND(6);
SELECT id FROM interval_ordering_ym WHERE value = INTERVAL '298262' YEAR(9);
RESET enable_seqscan;

DROP INDEX interval_ordering_ds_hash;
DROP INDEX interval_ordering_ym_hash;
CREATE INDEX interval_ordering_ds_brin ON interval_ordering_ds USING brin(value);
CREATE INDEX interval_ordering_ym_brin ON interval_ordering_ym USING brin(value);
SET enable_seqscan = off;
SET enable_indexscan = off;
SELECT id FROM interval_ordering_ds WHERE value > INTERVAL '0' DAY ORDER BY id;
SELECT id FROM interval_ordering_ym WHERE value < INTERVAL '0' YEAR ORDER BY id;
RESET enable_seqscan;
RESET enable_indexscan;

DROP TABLE interval_ordering_ds;
DROP TABLE interval_ordering_ym;
