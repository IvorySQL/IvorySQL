--
-- Test that PostgreSQL special datetime keywords keep working in Oracle
-- mode.
--
-- In Oracle mode the datetime types map to sys.oratimestamp /
-- sys.oratimestamptz / sys.oratimestampltz / sys.oradate, whose input
-- routines normally parse every string with the NLS format mask, which
-- does not understand the PostgreSQL special datetime keywords:
--
--     epoch, now, today, yesterday, tomorrow, infinity, +infinity and
--     -infinity
--
-- These keywords must still be accepted exactly like in PostgreSQL mode,
-- and ordinary date/time strings must continue to be parsed with the NLS
-- format mask.  The explicit conversion functions (to_date/to_timestamp/
-- to_char) keep their format-driven semantics.
--
SET ivorysql.compatible_mode = oracle;

-- ---------------------------------------------------------------------------
-- Typed literal input of the special keywords
-- ---------------------------------------------------------------------------
SELECT timestamp 'epoch';
SELECT date 'epoch';
SELECT timestamptz 'epoch';
SELECT timestamp 'infinity', timestamp '-infinity', timestamp '+infinity';
SELECT date 'infinity', date '-infinity';
SELECT timestamptz 'infinity';

-- ---------------------------------------------------------------------------
-- Casts on every Oracle datetime type
-- ---------------------------------------------------------------------------
SELECT 'epoch'::timestamp, 'epoch'::timestamptz, 'epoch'::date;
SELECT 'epoch'::"sys".oratimestampltz;
SELECT 'infinity'::timestamp, '+infinity'::timestamp, '-infinity'::timestamp;
SELECT 'infinity'::timestamptz, 'infinity'::date;

-- ---------------------------------------------------------------------------
-- Value semantics match PostgreSQL
-- ---------------------------------------------------------------------------
SELECT timestamp 'yesterday' < timestamp 'today'
       AND timestamp 'today' < timestamp 'tomorrow';
SELECT timestamp 'yesterday' < timestamp 'now'
       AND timestamp 'now' < timestamp 'tomorrow';
SELECT timestamp '-infinity' < timestamp 'epoch'
       AND timestamp 'epoch' < timestamp 'infinity';
SELECT timestamp 'epoch' = '1970-01-01 00:00:00'::timestamp;
SELECT date 'now' >= date 'epoch';
SELECT 'now'::timestamp IS NOT NULL, 'now'::timestamptz IS NOT NULL;

-- ---------------------------------------------------------------------------
-- typmod still applies on the special values
-- ---------------------------------------------------------------------------
SELECT 'epoch'::timestamp(3), 'epoch'::timestamp(0);
SELECT 'infinity'::timestamp(3);

-- ---------------------------------------------------------------------------
-- Keyword matching is case- and whitespace-insensitive, as in PostgreSQL
-- ---------------------------------------------------------------------------
SELECT 'EPOCH'::timestamp, 'Epoch'::timestamp, '  epoch  '::timestamp;
SELECT 'INFINITY'::timestamp, 'Infinity'::timestamp;

-- ---------------------------------------------------------------------------
-- Round trip through a table (input and output of finite and infinite
-- values, deterministically ordered: -infinity < epoch < infinity)
-- ---------------------------------------------------------------------------
CREATE TEMP TABLE epoch_oracle_tbl (ts timestamp, tstz timestamptz, d date);
INSERT INTO epoch_oracle_tbl VALUES
    ('-infinity', '-infinity', '-infinity'),
    ('epoch',     'epoch',     'epoch'),
    ('infinity',  'infinity',  'infinity');
SELECT ts, tstz, d FROM epoch_oracle_tbl ORDER BY ts;
DROP TABLE epoch_oracle_tbl;

-- ---------------------------------------------------------------------------
-- Keywords are independent of the NLS format mask configuration
-- ---------------------------------------------------------------------------
SET nls_timestamp_format TO 'YYYY/MM/DD HH24:MI:SS';
SELECT timestamp 'epoch', '2024/01/01 10:30:00'::timestamp;
RESET nls_timestamp_format;

-- ...and keep working when NLS input parsing is bypassed entirely
-- (ORATIMESTAMP_MASK: nls input is ignored for oratimestamp)
SET ivorysql.datetime_ignore_nls_mask = 2;
SELECT 'epoch'::timestamp, '2024-01-01 10:30:00'::timestamp;
RESET ivorysql.datetime_ignore_nls_mask;

-- ---------------------------------------------------------------------------
-- Ordinary strings are still parsed with the (default) NLS format mask
-- ---------------------------------------------------------------------------
SELECT '2024-01-01 10:30:00'::timestamp;

-- ---------------------------------------------------------------------------
-- A keyword embedded in a larger string is NOT special-cased
-- ---------------------------------------------------------------------------
SELECT timestamp '1995-08-06 epoch';
SELECT 'epoch 01:01:01'::timestamp;

-- ---------------------------------------------------------------------------
-- Explicit conversion functions are unaffected
-- ---------------------------------------------------------------------------
SELECT to_timestamp('epoch', 'YYYY-MM-DD HH24:MI:SS');
SELECT to_date('epoch', 'YYYY-MM-DD');
SELECT to_char('infinity'::timestamptz, 'YYYY-MM-DD');

-- ---------------------------------------------------------------------------
-- PostgreSQL mode is unaffected: the same keywords work natively there
-- ---------------------------------------------------------------------------
SET ivorysql.compatible_mode = pg;
SELECT timestamp 'epoch', date 'epoch', timestamp 'infinity';