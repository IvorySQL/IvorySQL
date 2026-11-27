--
-- ORA_TO_CHAR_DL
-- Oracle's DL (long date) format element: day name, month name, zero-padded
-- day and the year, e.g. 'Thursday, February 29, 2024'.
--

SELECT TO_CHAR(DATE '2024-02-29', 'DL') AS dl_feb,
       TO_CHAR(DATE '2024-07-04', 'DL') AS dl_jul,
       TO_CHAR(DATE '2023-01-01', 'DL') AS dl_jan;

-- accepted in lower case as well
SELECT TO_CHAR(DATE '2024-02-29', 'dl') AS dl_lower;

-- combines with the ordinary elements
SELECT TO_CHAR(TIMESTAMP '2024-02-29 13:45:56', 'DL HH24:MI') AS combined;

-- PostgreSQL mode keeps treating it as literal text
SET ivorysql.compatible_mode = pg;
SELECT TO_CHAR(DATE '2024-02-29', 'DL') AS pg_dl;
RESET ivorysql.compatible_mode;
