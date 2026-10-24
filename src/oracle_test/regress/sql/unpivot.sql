--
-- Oracle-compatible UNPIVOT tests
--

CREATE TABLE unpivot_t (
    id int,
    q1 int,
    q2 int,
    q3 int,
    memo text
);

INSERT INTO unpivot_t VALUES
    (1, 10, 20, NULL, 'row1'),
    (2, NULL, NULL, 30, 'row2'),
    (3, NULL, NULL, NULL, 'row3');

-- Default is EXCLUDE NULLS.
SELECT *
FROM unpivot_t
UNPIVOT (amount FOR quarter IN (q1, q2, q3))
ORDER BY id, quarter;

-- The source is scanned once for all UNPIVOT branches.
EXPLAIN (COSTS OFF)
SELECT * FROM unpivot_t
UNPIVOT (amount FOR quarter IN (q1, q2, q3));

-- Implicit labels uppercase unquoted columns but preserve quoted identifiers.
SELECT k, v
FROM (SELECT 1 AS "mixedCase", 2 AS plain) s
UNPIVOT (v FOR k IN ("mixedCase", plain))
ORDER BY k;

-- Explicit labels and EXCLUDE NULLS.
SELECT *
FROM unpivot_t
UNPIVOT EXCLUDE NULLS
    (amount FOR quarter IN (q1 AS 'FIRST',
                            q2 AS 'SECOND',
                            q3 AS 'THIRD'))
ORDER BY id, quarter;

-- INCLUDE NULLS generates rows for each input column.
SELECT *
FROM unpivot_t
UNPIVOT INCLUDE NULLS
    (amount FOR quarter IN (q1 AS 'FIRST',
                            q2 AS 'SECOND',
                            q3 AS 'THIRD'))
ORDER BY id, quarter;

-- A source alias belongs to the input; the post-UNPIVOT alias names output.
SELECT id, memo, quarter, amount
FROM unpivot_t s
UNPIVOT (amount FOR quarter IN (q1, q2)) u
ORDER BY id, quarter;

-- UNPIVOT is not reserved and can be used as an output alias.
SELECT unpivot.id, unpivot.memo
FROM unpivot_t
UNPIVOT (amount FOR quarter IN (q1, q2)) unpivot
ORDER BY unpivot.id;

-- UNPIVOT is also available as a column name.
SELECT unpivot FROM (SELECT 1 AS unpivot) s;

-- INCLUDE/EXCLUDE remain usable as ordinary target aliases.
SELECT unpivot include FROM (SELECT 1 AS unpivot) s;
SELECT unpivot exclude FROM (SELECT 1 AS unpivot) s;

-- UNPIVOT remains usable in other identifier positions followed by "(".
CREATE TABLE unpivot (id int);
INSERT INTO unpivot(id) VALUES (1);
SELECT * FROM unpivot;
DROP TABLE unpivot;

-- Contextual keyword lookahead also works inside a function call.
CREATE FUNCTION unpivot(anyelement) RETURNS anyelement
LANGUAGE sql IMMUTABLE AS $body$SELECT $1$body$;
/
SELECT unpivot((
    SELECT v
    FROM unpivot_t
    UNPIVOT (v FOR k IN (q1, q2))
    LIMIT 1
));
SELECT unpivot(unpivot(unpivot(unpivot(1))));
DROP FUNCTION unpivot(anyelement);

WITH unpivot(x) AS (SELECT 1)
SELECT * FROM unpivot;

SELECT * FROM generate_series(1, 2) AS unpivot(x);

SELECT id, k, v
FROM ONLY(unpivot_t)
UNPIVOT (v FOR k IN (q1, q2))
WHERE id = 1
ORDER BY k;

-- A subquery is a valid UNPIVOT source.
SELECT *
FROM (SELECT id, q1, q2, memo FROM unpivot_t) s
UNPIVOT (amount FOR quarter IN (q1 AS 'A', q2 AS 'B')) u
ORDER BY u.id, u.quarter;

-- Correlated subqueries can be used inside a LATERAL UNPIVOT result.
SELECT outer_t.id, u.k, u.v
FROM unpivot_t outer_t
CROSS JOIN LATERAL (
    SELECT *
    FROM (SELECT outer_t.id AS source_id,
                 outer_t.q1 AS outer_q1,
                 outer_t.q2 AS outer_q2) s
    UNPIVOT (v FOR k IN (outer_q1, outer_q2))
) u
WHERE outer_t.id = 1
ORDER BY u.k;

-- A CTE is a valid UNPIVOT source.
WITH source AS MATERIALIZED (
    SELECT id, q1, q2, memo FROM unpivot_t WHERE id = 1
)
SELECT *
FROM source
UNPIVOT (amount FOR quarter IN (q1, q2))
ORDER BY quarter;

-- A view is a valid UNPIVOT source.
CREATE VIEW unpivot_input_v AS
SELECT id, q1, q2, memo FROM unpivot_t;
SELECT *
FROM unpivot_input_v
UNPIVOT (amount FOR quarter IN (q1, q2))
WHERE id = 1
ORDER BY quarter;

-- Repeated input columns are valid and produce repeated output rows.
SELECT id, quarter, amount
FROM unpivot_t
UNPIVOT (amount FOR quarter IN (q1, q1, q2))
WHERE id = 1
ORDER BY quarter, amount;

-- A direct join is a valid UNPIVOT source.
CREATE TABLE unpivot_dim (id int, note text);
INSERT INTO unpivot_dim VALUES (1, 'dim1'), (2, 'dim2');
SELECT *
FROM unpivot_t JOIN unpivot_dim USING (id)
UNPIVOT (amount FOR quarter IN (q1, q2, q3)) u
ORDER BY id, quarter;

-- An aliased parenthesized join is a valid UNPIVOT source.
SELECT u.id, u.note, u.quarter, u.amount
FROM (unpivot_t JOIN unpivot_dim USING (id)) j
UNPIVOT (amount FOR quarter IN (q1, q2, q3)) u
WHERE u.id = 1
ORDER BY u.quarter;

-- Multiple measures and descriptors.
CREATE TABLE unpivot_multi (
    id numeric,
    q1_qty numeric,
    q1_amt numeric,
    q2_qty numeric,
    q2_amt numeric,
    note text
);

INSERT INTO unpivot_multi VALUES
    (1, 10, 100.5, 20, NULL, 'partial'),
    (2, NULL, NULL, 30, 300, 'full2'),
    (3, NULL, NULL, NULL, NULL, 'allnull'),
    (4, 40, NULL, NULL, 400, 'partial2');

SELECT *
FROM unpivot_multi
UNPIVOT (
    (qty, amt) FOR (year, quarter) IN (
        (q1_qty, q1_amt) AS (2024, 'Q1'),
        (q2_qty, q2_amt) AS (2024, 'Q2')
    )
)
ORDER BY id, year, quarter;

SELECT *
FROM unpivot_multi
UNPIVOT INCLUDE NULLS (
    (qty, amt) FOR (year, quarter) IN (
        (q1_qty, q1_amt) AS (2024, 'Q1'),
        (q2_qty, q2_amt) AS (2024, 'Q2')
    )
)
ORDER BY id, year, quarter;

-- Tuple inputs without AS use a combined implicit label.
SELECT id, year, quarter
FROM unpivot_multi
UNPIVOT (
    (qty, amt) FOR (year, quarter) IN (
        (q1_qty, q1_amt),
        (q2_qty, q2_amt)
    )
)
WHERE id = 1
ORDER BY quarter;

-- Explicit NULL labels are valid for SELECT.
SELECT id, quarter, amount, pg_typeof(quarter)
FROM unpivot_t
UNPIVOT (amount FOR quarter IN (q1 AS NULL, q2 AS NULL))
WHERE id = 1
ORDER BY amount;

-- Oracle does not permit zero-length descriptor columns in CTAS.
CREATE TABLE unpivot_null_ctas AS
SELECT id, quarter, amount
FROM unpivot_t
UNPIVOT (amount FOR quarter IN (q1 AS NULL, q2 AS NULL));

-- A zero-length descriptor used only for ordering is not a CTAS output column.
CREATE TABLE unpivot_resjunk_ctas AS
SELECT id, amount
FROM unpivot_t
UNPIVOT (amount FOR quarter IN (q1 AS NULL, q2 AS NULL))
ORDER BY quarter, id;
SELECT * FROM unpivot_resjunk_ctas ORDER BY id, amount;

-- An untyped NULL label adopts the type of the other labels.
SELECT id, quarter, amount
FROM unpivot_t
UNPIVOT (amount FOR quarter IN (q1 AS NULL, q2 AS 2))
WHERE id = 1
ORDER BY amount;

-- Duplicate labels are valid and produce duplicate descriptor values.
SELECT id, quarter, amount
FROM unpivot_t
UNPIVOT (amount FOR quarter IN (q1 AS 'SAME', q2 AS 'SAME'))
WHERE id = 1
ORDER BY amount;

-- Descriptor and measure list sizes must agree with FOR and the output names.
SELECT id, v
FROM unpivot_t
UNPIVOT (v FOR (k1, k2) IN (q1 AS 'one', q2 AS 'two'));

SELECT id, v
FROM unpivot_t
UNPIVOT ((v) FOR k IN ((q1, q2)));

-- IN items must be simple unqualified column names.
SELECT id, v
FROM unpivot_t
UNPIVOT (v FOR k IN (unpivot_t.q1, unpivot_t.q2));

-- Labels may be foldable constant expressions.
SELECT id, quarter, amount
FROM unpivot_t
UNPIVOT (
    amount FOR quarter IN (
        q1 AS UPPER('first'),
        q2 AS UPPER('second'),
        q3 AS UPPER('third')
    )
)
ORDER BY id, quarter;

SELECT pg_typeof(quarter)
FROM unpivot_t
UNPIVOT (
    amount FOR quarter IN (
        q1 AS UPPER('first'),
        q2 AS UPPER('second'),
        q3 AS UPPER('third')
    )
)
LIMIT 1;

SELECT id, quarter, amount
FROM unpivot_t
UNPIVOT (
    amount FOR quarter IN (
        q1 AS 1 + 1,
        q2 AS 2 + 2,
        q3 AS 3 + 3
    )
)
ORDER BY id, quarter;

SELECT id, quarter, amount
FROM unpivot_t
UNPIVOT (
    amount FOR quarter IN (
        q1 AS DATE '2024-01-01',
        q2 AS DATE '2024-04-01',
        q3 AS DATE '2024-07-01'
    )
)
ORDER BY id, quarter;

-- Labels must be constant and belong to one type group.
SELECT id, amount
FROM unpivot_t
UNPIVOT (amount FOR quarter IN (q1 AS SYSDATE, q2 AS SYSDATE));

SELECT id, amount
FROM unpivot_t
UNPIVOT (amount FOR quarter IN (q1 AS q1 + 1, q2 AS q2 + 1));

SELECT id, amount
FROM unpivot_t
UNPIVOT (amount FOR quarter IN (q1 AS count(*), q2 AS count(*)));

SELECT id, amount
FROM unpivot_t
UNPIVOT (
    amount FOR quarter IN (
        q1 AS generate_series(1, 2),
        q2 AS generate_series(1, 2)
    )
);

SELECT id, amount
FROM unpivot_t
UNPIVOT (
    amount FOR quarter IN (
        q1 AS row_number() OVER (),
        q2 AS row_number() OVER ()
    )
);

SELECT id, amount
FROM unpivot_t
UNPIVOT (amount FOR quarter IN (q1 AS 'ONE', q2 AS 2));

-- Measure types are merged according to the Oracle type group.
CREATE TABLE unpivot_types (
    id int,
    n1 number,
    n2 number,
    f1 binary_float,
    s1 char(3),
    s2 varchar2(10),
    d1 date,
    d2 timestamp
);

INSERT INTO unpivot_types VALUES
    (1, 1, 2, 3.5, 'one', 'two', DATE '2024-01-01', TIMESTAMP '2024-01-02 03:04:05'),
    (2, 4, 5, 6.5, 'six', 'seven', DATE '2024-02-01', TIMESTAMP '2024-02-02 03:04:05');

SELECT pg_typeof(v_num), pg_typeof(v_float), pg_typeof(v_char), pg_typeof(v_date)
FROM unpivot_types
UNPIVOT (
    (v_num, v_float, v_char, v_date) FOR k IN (
        (n1, n1, s1, d1),
        (n2, f1, s2, d2)
    )
)
LIMIT 1;

SELECT pg_typeof(v)
FROM unpivot_types
UNPIVOT (v FOR k IN (n1, f1))
LIMIT 1;

CREATE TABLE unpivot_time (t1 time, t2 time);
INSERT INTO unpivot_time VALUES ('10:00', '11:00');
SELECT pg_typeof(v), v, k
FROM unpivot_time
UNPIVOT (v FOR k IN (t1, t2))
ORDER BY k;

CREATE TABLE unpivot_type_ctas AS
SELECT v_char, k
FROM unpivot_types
UNPIVOT (
    v_char FOR k IN (s1, s2)
);
SELECT attname, format_type(atttypid, atttypmod)
FROM pg_attribute
WHERE attrelid = 'unpivot_type_ctas'::regclass AND attnum > 0
ORDER BY attnum;

-- Incompatible measure types are rejected during parse analysis.
SELECT id, v
FROM unpivot_types
UNPIVOT (v FOR k IN (n1, s1));

-- Datetime measures preserve LOCAL TIME ZONE and the largest precision.
CREATE TABLE unpivot_datetime_types (
    id int,
    tl1 timestamp with local time zone,
    tl2 timestamp with local time zone,
    ts1 timestamp(3),
    ts2 timestamp(0)
);

INSERT INTO unpivot_datetime_types VALUES (
    1,
    TIMESTAMP '2024-01-02 03:04:05.678901',
    TIMESTAMP '2024-02-03 04:05:06.789012',
    TIMESTAMP '2024-01-02 03:04:05.678',
    TIMESTAMP '2024-02-03 04:05:06'
);

SELECT pg_typeof(v), v, k
FROM unpivot_datetime_types
UNPIVOT (v FOR k IN (tl1, tl2))
ORDER BY k;

CREATE TABLE unpivot_timestamp_ctas AS
SELECT v
FROM unpivot_datetime_types
UNPIVOT (v FOR k IN (ts1, ts2));
SELECT attname, format_type(atttypid, atttypmod)
FROM pg_attribute
WHERE attrelid = 'unpivot_timestamp_ctas'::regclass AND attnum > 0
ORDER BY attnum;

-- LOB and bounded character values belong to different UNPIVOT type groups.
CREATE TABLE unpivot_lobs (
    id int,
    c1 clob,
    c2 clob,
    v varchar2(10)
);
INSERT INTO unpivot_lobs VALUES (1, 'one', 'two', 'three');

SELECT pg_typeof(amount), amount, k
FROM unpivot_lobs
UNPIVOT (amount FOR k IN (c1, c2))
ORDER BY k;

SELECT id, amount
FROM unpivot_lobs
UNPIVOT (amount FOR k IN (c1, v));

-- NCHAR-family values are incompatible with the database character set.
CREATE TABLE unpivot_nchar_types (
    id int,
    c1 char(3),
    n1 nchar(3),
    nv1 nchar varying(10)
);
INSERT INTO unpivot_nchar_types VALUES (1, 'abc', 'xyz', 'uvw');

SELECT pg_typeof(v), pg_collation_for(v), v, k
FROM unpivot_nchar_types
UNPIVOT (v FOR k IN (n1, nv1))
ORDER BY k;

SELECT id, v
FROM unpivot_nchar_types
UNPIVOT (v FOR k IN (c1, n1));

SELECT pg_collation_for(CAST('abc' AS nchar(3)));

ALTER TABLE unpivot_nchar_types ALTER COLUMN c1 TYPE nchar(3);
SELECT attcollation::regcollation
FROM pg_attribute
WHERE attrelid = 'unpivot_nchar_types'::regclass AND attname = 'c1';

-- Oracle binary and interval type families have distinct merge rules.
CREATE TABLE unpivot_binary (
    id int,
    r1 raw(5),
    r2 raw(10),
    b1 blob,
    b2 blob,
    ym1 interval year(4) to month,
    ym2 interval year(6) to month,
    ds1 interval day(4) to second(3),
    ds2 interval day(6) to second(6)
);
INSERT INTO unpivot_binary VALUES (
    1, 'aa', 'bbbb', 'cc', 'dd',
    '1-2', '3-4', '1 02:03:04.123', '2 03:04:05.123456'
);

CREATE TABLE unpivot_raw_ctas AS
SELECT v
FROM unpivot_binary
UNPIVOT (v FOR k IN (r1, r2));
SELECT format_type(atttypid, atttypmod)
FROM pg_attribute
WHERE attrelid = 'unpivot_raw_ctas'::regclass AND attnum = 1;

SELECT pg_typeof(v)
FROM unpivot_binary
UNPIVOT (v FOR k IN (b1, b2))
LIMIT 1;

SELECT id, v
FROM unpivot_binary
UNPIVOT (v FOR k IN (r1, b1));

CREATE TABLE unpivot_ym_ctas AS
SELECT v
FROM unpivot_binary
UNPIVOT (v FOR k IN (ym1, ym2));
SELECT format_type(atttypid, atttypmod)
FROM pg_attribute
WHERE attrelid = 'unpivot_ym_ctas'::regclass AND attnum = 1;

CREATE TABLE unpivot_ds_ctas AS
SELECT v
FROM unpivot_binary
UNPIVOT (v FOR k IN (ds1, ds2));
SELECT format_type(atttypid, atttypmod)
FROM pg_attribute
WHERE attrelid = 'unpivot_ds_ctas'::regclass AND attnum = 1;

SELECT id, v
FROM unpivot_binary
UNPIVOT (v FOR k IN (ym1, ds1));

-- Domains over Oracle domain-backed types retain their UNPIVOT family.
CREATE DOMAIN unpivot_raw_domain AS raw(10);
CREATE DOMAIN unpivot_blob_domain AS blob;
CREATE DOMAIN unpivot_ym_domain AS interval year(4) to month;
CREATE TABLE unpivot_domain_types (
    id int,
    r1 unpivot_raw_domain,
    r2 unpivot_raw_domain,
    b1 unpivot_blob_domain,
    b2 unpivot_blob_domain,
    y1 unpivot_ym_domain,
    y2 unpivot_ym_domain
);
INSERT INTO unpivot_domain_types VALUES
    (1, 'aa', 'bbbb', 'cc', 'dd', '1-2', '3-4');

SELECT pg_typeof(v), v, k
FROM unpivot_domain_types
UNPIVOT (v FOR k IN (r1, r2))
ORDER BY k;

CREATE TABLE unpivot_domain_raw_ctas AS
SELECT v
FROM unpivot_domain_types
UNPIVOT (v FOR k IN (r1, r2));
SELECT format_type(atttypid, atttypmod)
FROM pg_attribute
WHERE attrelid = 'unpivot_domain_raw_ctas'::regclass AND attnum = 1;

SELECT pg_typeof(v), v, k
FROM unpivot_domain_types
UNPIVOT (v FOR k IN (b1, b2))
ORDER BY k;

CREATE TABLE unpivot_domain_ym_ctas AS
SELECT v
FROM unpivot_domain_types
UNPIVOT (v FOR k IN (y1, y2));
SELECT format_type(atttypid, atttypmod)
FROM pg_attribute
WHERE attrelid = 'unpivot_domain_ym_ctas'::regclass AND attnum = 1;

-- Character length semantics also apply to the merged descriptor and measure.
SET nls_length_semantics = char;
SELECT pg_typeof(v), length(v), v, k
FROM unpivot_types
UNPIVOT (v FOR k IN (s1, s2))
WHERE id = 1
ORDER BY k;

CREATE TABLE unpivot_nls_char_ctas AS
SELECT v
FROM unpivot_types
UNPIVOT (v FOR k IN (s1, s2));
SELECT format_type(atttypid, atttypmod)
FROM pg_attribute
WHERE attrelid = 'unpivot_nls_char_ctas'::regclass AND attnum = 1;
RESET nls_length_semantics;

-- Chained UNPIVOT clauses use the previous output and expose only the final alias.
SELECT *
FROM unpivot_t
UNPIVOT (amount FOR quantity IN (q1, q2)) u
UNPIVOT (x FOR y IN (amount, q3)) v
ORDER BY v.id, v.y, v.quantity;

-- The intermediate alias in a chain is not visible to the surrounding query.
SELECT u.id
FROM unpivot_t
UNPIVOT (amount FOR quantity IN (q1, q2)) u
UNPIVOT (x FOR y IN (amount, q3)) v;

-- Long chains must use linear parse analysis rather than re-analyzing the source.
CREATE TABLE unpivot_chain (
    a int, b int,
    c3 int, c4 int, c5 int, c6 int, c7 int, c8 int,
    c9 int, c10 int, c11 int, c12 int, c13 int, c14 int, c15 int
);
INSERT INTO unpivot_chain VALUES
    (1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15);

SELECT count(*)
FROM unpivot_chain
UNPIVOT (v1 FOR k1 IN (a, b))
UNPIVOT (v2 FOR k2 IN (v1, c3))
UNPIVOT (v3 FOR k3 IN (v2, c4))
UNPIVOT (v4 FOR k4 IN (v3, c5))
UNPIVOT (v5 FOR k5 IN (v4, c6))
UNPIVOT (v6 FOR k6 IN (v5, c7))
UNPIVOT (v7 FOR k7 IN (v6, c8))
UNPIVOT (v8 FOR k8 IN (v7, c9))
UNPIVOT (v9 FOR k9 IN (v8, c10))
UNPIVOT (v10 FOR k10 IN (v9, c11))
UNPIVOT (v11 FOR k11 IN (v10, c12))
UNPIVOT (v12 FOR k12 IN (v11, c13))
UNPIVOT (v13 FOR k13 IN (v12, c14))
UNPIVOT (v14 FOR k14 IN (v13, c15));

-- Oracle bind variables inside an UNPIVOT source remain discoverable.
SELECT *
FROM get_parameter_description(
    'SELECT * FROM (SELECT :id AS id, q1, q2 FROM unpivot_t) s
     UNPIVOT (amount FOR quarter IN (q1, q2))'
);

-- WHERE, GROUP BY, ORDER BY and CTAS operate on the unpivoted result.
SELECT quarter, count(*), sum(amount)
FROM unpivot_t
UNPIVOT (amount FOR quarter IN (q1, q2, q3)) u
WHERE amount > 10
GROUP BY quarter
ORDER BY quarter;

CREATE TABLE unpivot_ctas AS
SELECT id, quarter, amount
FROM unpivot_t
UNPIVOT (amount FOR quarter IN (q1, q2, q3)) u;
SELECT * FROM unpivot_ctas ORDER BY id, quarter;

-- A view exposes the unpivoted result.
CREATE VIEW unpivot_v AS
SELECT id, memo, quarter, amount
FROM unpivot_t
UNPIVOT (amount FOR quarter IN (q1, q2, q3)) u;
SELECT *
FROM unpivot_v
ORDER BY id, quarter;

-- Unknown input columns are rejected.
SELECT *
FROM unpivot_t
UNPIVOT (amount FOR quarter IN (missing));

-- Output column names must be unique.
SELECT *
FROM unpivot_t
UNPIVOT (amount FOR id IN (q1, q2));

-- Table aliases after AS are not part of Oracle's UNPIVOT syntax.
SELECT u.id
FROM unpivot_t AS u
UNPIVOT (amount FOR quarter IN (q1, q2));

-- LATERAL views cannot be unpivoted.
SELECT *
FROM LATERAL (SELECT id, q1, q2 FROM unpivot_t) s
UNPIVOT (amount FOR quarter IN (q1, q2));

-- The extended syntax is unavailable in PostgreSQL parser mode.
SET ivorysql.compatible_mode = pg;
SELECT *
FROM unpivot_t
UNPIVOT (amount FOR quarter IN (q1, q2));
SET ivorysql.compatible_mode = oracle;

DROP VIEW unpivot_v;
DROP VIEW unpivot_input_v;
DROP TABLE unpivot_ctas;
DROP TABLE unpivot_type_ctas;
DROP TABLE unpivot_resjunk_ctas;
DROP TABLE unpivot_raw_ctas;
DROP TABLE unpivot_ym_ctas;
DROP TABLE unpivot_ds_ctas;
DROP TABLE unpivot_domain_raw_ctas;
DROP TABLE unpivot_domain_ym_ctas;
DROP TABLE unpivot_nls_char_ctas;
DROP TABLE unpivot_domain_types;
DROP DOMAIN unpivot_raw_domain;
DROP DOMAIN unpivot_blob_domain;
DROP DOMAIN unpivot_ym_domain;
DROP TABLE unpivot_binary;
DROP TABLE unpivot_time;
DROP TABLE unpivot_nchar_types;
DROP TABLE unpivot_timestamp_ctas;
DROP TABLE unpivot_datetime_types;
DROP TABLE unpivot_types;
DROP TABLE unpivot_lobs;
DROP TABLE unpivot_multi;
DROP TABLE unpivot_dim;
DROP TABLE unpivot_chain;
DROP TABLE unpivot_t;
