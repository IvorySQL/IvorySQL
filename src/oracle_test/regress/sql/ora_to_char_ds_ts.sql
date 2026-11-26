--
-- ORA_TO_CHAR_DS_TS
-- Oracle's DS (short date) and TS (time) format elements.
--
-- DS prints month/day/year without leading zeroes, TS prints a 12-hour clock
-- with a bare hour.  Both are accepted in lower case as well.
--

SELECT TO_CHAR(DATE '2024-02-29', 'DS') AS ds_feb,
       TO_CHAR(DATE '2024-01-05', 'DS') AS ds_jan,
       TO_CHAR(DATE '2024-12-31', 'DS') AS ds_dec;

SELECT TO_CHAR(DATE '2024-02-29', 'ds') AS ds_lower;

SELECT TO_CHAR(TIMESTAMP '2024-02-29 00:00:00', 'TS') AS ts_midnight,
       TO_CHAR(TIMESTAMP '2024-02-29 12:00:00', 'TS') AS ts_noon;

SELECT TO_CHAR(TIMESTAMP '2024-02-29 13:45:56', 'TS') AS ts_pm,
       TO_CHAR(TIMESTAMP '2024-02-29 23:59:59', 'TS') AS ts_last_minute;

SELECT TO_CHAR(TIMESTAMP '2024-02-29 13:45:56', 'ts') AS ts_lower;

-- both elements combine with the ordinary ones
SELECT TO_CHAR(TIMESTAMP '2024-02-29 13:45:56', 'DS TS') AS combined;

-- PostgreSQL mode keeps treating them as literal text
SET ivorysql.compatible_mode = pg;
SELECT TO_CHAR(DATE '2024-02-29', 'DS') AS pg_ds,
       TO_CHAR(TIMESTAMP '2024-02-29 13:45:56', 'TS') AS pg_ts;
RESET ivorysql.compatible_mode;
