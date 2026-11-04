# Selecting calendar occurrences with DBMS_SCHEDULER

`BYSETPOS` selects one or more occurrences from a monthly or yearly calendar.
For example, this job runs at 18:00 on the last Monday-through-Friday date of
each month:

```sql
BEGIN
  dbms_scheduler.create_job(
    job_name => 'month_end_close',
    job_type => 'PLSQL_BLOCK',
    job_action => 'BEGIN close_month(); END;',
    start_date => TIMESTAMP '2026-01-01 18:00:00 +00:00',
    repeat_interval =>
      'FREQ=MONTHLY;BYDAY=MON,TUE,WED,THU,FRI;BYHOUR=18;BYMINUTE=0;BYSECOND=0;BYSETPOS=-1',
    enabled => TRUE);
END;
/
```

Create `close_month` before enabling this example, and configure background
scheduling as usual. Monday through Friday does not exclude public holidays.

## Position rules

- Use `FREQ=MONTHLY` or `FREQ=YEARLY`. Other frequencies reject `BYSETPOS`.
- Positions range from `1` to `9999`, or from `-1` to `-9999`. Positive values
  count from the beginning; negative values count from the end. Zero is invalid.
- A comma-separated list selects several occurrences. Repeated values and
  overlapping positive/negative selections do not add duplicate occurrences.
- All supported date and time filters are applied first. Positions refer to
  **timestamps**, so `BYHOUR=9,17;BYSETPOS=-1` selects the last date at 17:00,
  rather than both execution times on that date.
- Ranking starts at the beginning of the complete month/year. Only afterward
  are occurrences before `start_date` or at/before the evaluation cutoff removed.
  A mid-period cutoff never renumbers the remaining occurrences.
- `INTERVAL` skips months/years; it does not enlarge the ranking period.
- Positions beyond the candidate count select nothing in that period. The
  evaluator proceeds to later periods under its existing 4000-period search
  limit and reports its usual no-match error if the search is exhausted.

For example, `FREQ=MONTHLY;BYDAY=MON,TUE,FRI;BYSETPOS=1,3` selects January 2 and
January 6 in 2004. Evaluating it after January 15 proceeds to February; it does
not select the first and third matching dates remaining in January.

For a yearly calendar spanning several months, specify those months explicitly
or use `BYDATE`, for example:

```text
FREQ=YEARLY;BYMONTH=1,4,7,10;BYMONTHDAY=1;BYSETPOS=2,-1
```

This selects April 1 and October 1 in each year. Missing components continue
to use the existing evaluator's defaults from `start_date`.

## Supported integration and limits

The clause works with `EVALUATE_CALENDAR_STRING`, inline job repeat intervals,
and `CREATE_SCHEDULE` calendars referenced by jobs. Creation validates syntax;
enabling and background rescheduling use the same evaluator.

This addition retains the existing engine's session-timezone interpretation and
local-time conversion for ambiguous/nonexistent wall times. Transition periods
are ranked as sorted, distinct absolute timestamps, including collisions caused
by clock jumps. It does not introduce Oracle's preservation of the start date's
named time zone or change gap/fold conversion. These differences matter when
migrating schedules across time zones.

Named-calendar set operations (`INCLUDE`, `EXCLUDE`, `INTERSECT`), user-defined
frequencies, and additional calendar clauses remain unsupported. In particular,
referencing a named schedule as a job's `schedule_name` does not enable those
set operations. Existing YEARLY weekday ordinal/default rules are unchanged.

Constant-offset periods use direct indexing into the date/time Cartesian product;
even an every-second leap-year pattern does not allocate 31 million timestamps.
Periods containing a time-zone transition enumerate candidates with interrupt
checks and bounded heaps holding at most the largest requested positive and
negative position counts (9999 each), plus their hash membership tables.

The position contract follows the [Oracle 19c DBMS_SCHEDULER reference](https://docs.oracle.com/en/database/oracle/oracle-database/19/arpls/DBMS_SCHEDULER.html).
The regression tests compare deterministic examples and independently enumerated
timestamp sets; they do not claim live Oracle-instance equivalence.

## Tests

```sh
make -C contrib/ivorysql_ora oracle-installcheck
```

The `dbms_scheduler_bysetpos` regression covers selection, validation, object
creation, dense calendars, and time-zone transitions. With TAP enabled,
`t/002_scheduler_bysetpos.pl` also exercises background execution, restart,
and advancement to the next frequency period for inline and named schedules.
