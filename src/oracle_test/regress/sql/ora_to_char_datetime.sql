--
-- ORA_TO_CHAR_DATETIME
-- Oracle-compatible TO_CHAR() output for datetime format elements
--
-- Oracle's SSSSS (seconds past midnight) is a five-character field: the value
-- is padded with leading zeroes.  SSSS is a PostgreSQL-only alias and keeps
-- the unpadded output.
--
SELECT TO_CHAR(TIMESTAMP '2024-02-29 00:00:00', 'SSSSS') AS midnight,
       TO_CHAR(TIMESTAMP '2024-02-29 00:00:05', 'SSSSS') AS five_seconds,
       TO_CHAR(TIMESTAMP '2024-02-29 01:02:03', 'SSSSS') AS one_am,
       TO_CHAR(TIMESTAMP '2024-02-29 13:04:05', 'SSSSS') AS afternoon;

-- DATE has the same five-character field
SELECT TO_CHAR(DATE '2024-02-29', 'SSSSS') AS from_date;

-- a non-zero time on a DATE
SELECT TO_CHAR(TO_DATE('2024-02-29 00:00:05', 'YYYY-MM-DD HH24:MI:SS'),
               'SSSSS') AS date_five_seconds;

-- the PostgreSQL-only alias stays unpadded
SELECT TO_CHAR(TIMESTAMP '2024-02-29 01:02:03', 'SSSS') AS pg_alias;

-- FM suppresses the padding of the field
SELECT TO_CHAR(TIMESTAMP '2024-02-29 00:00:05', 'FMSSSSS') AS fm_short,
       TO_CHAR(TIMESTAMP '2024-02-29 01:02:03', 'FMSSSSS') AS fm_one_am;

-- In Oracle, FM carries over to the following elements until another FM
-- toggles it off again
SELECT TO_CHAR(TIMESTAMP '2024-02-29 00:00:05', 'FMHH24:SSSSS') AS fm_carried,
       TO_CHAR(TIMESTAMP '2024-02-29 00:00:05', 'FMHH24:FMSSSSS') AS fm_toggled_off,
       TO_CHAR(TIMESTAMP '2024-02-29 00:00:05', 'HH24:SSSSS') AS no_fm;
