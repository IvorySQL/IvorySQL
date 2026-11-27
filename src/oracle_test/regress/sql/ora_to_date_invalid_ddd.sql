--
-- ORA_TO_DATE_INVALID_DDD
-- Test that Oracle-compatible TO_DATE / TO_TIMESTAMP reject day-of-year 0
-- (ORA-01848), instead of silently keeping the default date.
--

-- day of year 000 is not a valid day of year
SELECT to_date('2026-000', 'YYYY-DDD');
SELECT to_timestamp('2026-000 10:20:30', 'YYYY-DDD HH24:MI:SS');
-- a day of year supplied on its own
SELECT to_date('000', 'DDD');
-- the check also applies when the month and day are supplied
SELECT to_date('2026-01-15-000', 'YYYY-MM-DD-DDD');
-- ISO day of year 000 is rejected as well
SELECT to_date('2026-000', 'IYYY-IDDD');

-- valid boundaries still work
SELECT to_char(to_date('2026-001', 'YYYY-DDD'), 'YYYY-MM-DD');
SELECT to_char(to_date('2026-365', 'YYYY-DDD'), 'YYYY-MM-DD');
SELECT to_char(to_date('2024-366', 'YYYY-DDD'), 'YYYY-MM-DD');
SELECT to_char(to_date('2026-059', 'YYYY-DDD'), 'YYYY-MM-DD');
SELECT to_char(to_date('2026-001', 'IYYY-IDDD'), 'YYYY-MM-DD');

-- out-of-range values are still rejected by the date validation
SELECT to_date('2026-366', 'YYYY-DDD');
