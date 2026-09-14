-- GiST comparisons must use the same wide interval ordering as ivorysql_ora.
CREATE TABLE gist_interval_ordering_ds (
    id integer,
    value interval day(9) to second(6)
);
INSERT INTO gist_interval_ordering_ds VALUES
    (1, '-999999999 00:00:00'),
    (2, '-213503982 08:01:49.551616'),
    (3, '-106751992 00:00:00'),
    (4, '-1 00:00:00'),
    (5, '0 00:00:00'),
    (6, '1 00:00:00'),
    (7, '106751992 00:00:00'),
    (8, '213503982 08:01:49.551616'),
    (9, '999999999 00:00:00');

CREATE TABLE gist_interval_ordering_ym (
    id integer,
    value interval year(9) to month
);
INSERT INTO gist_interval_ordering_ym VALUES
    (1, '-178956970-7'),
    (2, '-596524-0'),
    (3, '-298262-0'),
    (4, '-0-1'),
    (5, '0-0'),
    (6, '0-1'),
    (7, '298262-0'),
    (8, '596524-0'),
    (9, '178956970-7');

CREATE INDEX gist_interval_ordering_ds_idx ON gist_interval_ordering_ds USING gist(value);
CREATE INDEX gist_interval_ordering_ym_idx ON gist_interval_ordering_ym USING gist(value);
SET enable_seqscan = off;
SET enable_bitmapscan = off;
EXPLAIN (COSTS OFF)
SELECT id FROM gist_interval_ordering_ds WHERE value > INTERVAL '0' DAY;
EXPLAIN (COSTS OFF)
SELECT id FROM gist_interval_ordering_ym WHERE value > INTERVAL '0' YEAR;

-- Exercise the operator strategies, including the old 2^64 hash collision.
SELECT array_agg(id ORDER BY id) FROM gist_interval_ordering_ds
WHERE value < INTERVAL '0' DAY;
SELECT array_agg(id ORDER BY id) FROM gist_interval_ordering_ds
WHERE value <= INTERVAL '0' DAY;
SELECT array_agg(id ORDER BY id) FROM gist_interval_ordering_ds
WHERE value = INTERVAL '0' DAY;
SELECT array_agg(id ORDER BY id) FROM gist_interval_ordering_ds
WHERE value >= INTERVAL '0' DAY;
SELECT array_agg(id ORDER BY id) FROM gist_interval_ordering_ds
WHERE value > INTERVAL '0' DAY;
SELECT array_agg(id ORDER BY id) FROM gist_interval_ordering_ds
WHERE value <> INTERVAL '0' DAY;
SELECT array_agg(id ORDER BY id) FROM gist_interval_ordering_ds
WHERE value = INTERVAL '213503982 08:01:49.551616' DAY(9) TO SECOND(6);
SELECT array_agg(id ORDER BY id) FROM gist_interval_ordering_ym
WHERE value < INTERVAL '0' YEAR;
SELECT array_agg(id ORDER BY id) FROM gist_interval_ordering_ym
WHERE value <= INTERVAL '0' YEAR;
SELECT array_agg(id ORDER BY id) FROM gist_interval_ordering_ym
WHERE value = INTERVAL '0' YEAR;
SELECT array_agg(id ORDER BY id) FROM gist_interval_ordering_ym
WHERE value >= INTERVAL '0' YEAR;
SELECT array_agg(id ORDER BY id) FROM gist_interval_ordering_ym
WHERE value > INTERVAL '0' YEAR;
SELECT array_agg(id ORDER BY id) FROM gist_interval_ordering_ym
WHERE value <> INTERVAL '0' YEAR;

-- Insert after index creation to exercise incremental union and splits.
INSERT INTO gist_interval_ordering_ds
SELECT 10 + i, CAST((i::bigint * 1000000)::text || ' 00:00:00'
                   AS interval day(9) to second(6))
FROM generate_series(-500, 500) AS g(i);
INSERT INTO gist_interval_ordering_ym
SELECT 10 + i, CAST((i::bigint * 10000)::text || '-0'
                   AS interval year(9) to month)
FROM generate_series(-500, 500) AS g(i);
SELECT count(*) FROM gist_interval_ordering_ds WHERE value > INTERVAL '0' DAY;
SELECT count(*) FROM gist_interval_ordering_ds WHERE value < INTERVAL '0' DAY;
SELECT count(*) FROM gist_interval_ordering_ym WHERE value > INTERVAL '0' YEAR;
SELECT count(*) FROM gist_interval_ordering_ym WHERE value < INTERVAL '0' YEAR;
RESET enable_seqscan;
RESET enable_bitmapscan;

-- Values with an old overflowing comparison must remain distinct in an
-- exclusion constraint, while an actual duplicate still conflicts.
CREATE TABLE gist_interval_distinct (
    value interval day(9) to second(6),
    EXCLUDE USING gist (value WITH =)
);
INSERT INTO gist_interval_distinct VALUES ('0 00:00:00');
INSERT INTO gist_interval_distinct VALUES ('213503982 08:01:49.551616');
SELECT count(*) FROM gist_interval_distinct;
INSERT INTO gist_interval_distinct VALUES ('0 00:00:00');

DROP TABLE gist_interval_distinct;
DROP TABLE gist_interval_ordering_ds;
DROP TABLE gist_interval_ordering_ym;
