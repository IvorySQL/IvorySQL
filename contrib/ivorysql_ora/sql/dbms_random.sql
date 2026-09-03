--
-- dbms_random.sql
--
-- tests for the DBMS_RANDOM package:
--   INITIALIZE / SEED / TERMINATE / NORMAL / RANDOM / STRING / VALUE
-- Seeded sequences are deterministic, so exact values can be asserted.
--

--
-- Deterministic sequence after INITIALIZE
--
call dbms_random.initialize(42);
select dbms_random.random() as r1,
       dbms_random.random() as r2,
       dbms_random.random() as r3;

-- reseeding with the same value replays the same sequence
call dbms_random.seed(cast(42 as number));
select dbms_random.random() as r1_replayed,
       dbms_random.random() as r2_replayed;

-- text seeds are hashed
call dbms_random.seed('hello world');
select dbms_random.random() as from_text_seed;

--
-- VALUE: [0, 1)
--
call dbms_random.seed(cast(7 as number));
select dbms_random.value() >= 0 and dbms_random.value() < 1 as value_in_unit_range;

-- VALUE(low, high) stays within the requested bounds
call dbms_random.seed(cast(99 as number));
select min(v) >= 10 and max(v) < 20 as range_ok
from (select dbms_random.value(10, 20) as v
      from generate_series(1, 200) t) s;

-- empty or inverted VALUE ranges are rejected
select dbms_random.value(20, 10) from dual;
select dbms_random.value(10, 10) from dual;

-- VALUE retains NUMBER bounds that cannot be represented exactly as float8
call dbms_random.seed(cast(99 as number));
select min(v) >= 10000000000000001 and max(v) < 10000000000000002 as large_range_ok
from (select dbms_random.value(10000000000000001, 10000000000000002) as v
      from generate_series(1, 200) t) s;

--
-- STRING: deterministic with a seed, honors the character class
--
call dbms_random.seed(cast(1234 as number));
select dbms_random.string('U', 8) as upper_only;
select dbms_random.string('L', 8) as lower_only;
select dbms_random.string('A', 8) as alpha_mixed;
select dbms_random.string('X', 8) as upper_alnum;
select dbms_random.string('P', 8) as printable;

-- Oracle-compatible STRING NULL, length, and option behavior
select dbms_random.string(null, null) from dual;
select dbms_random.string(null, -1) is null as null_opt_negative_len_is_null from dual;
select dbms_random.string('U', 0) is null as zero_len_is_null from dual;
select dbms_random.string(null, 5) ~ '^[A-Z]{5}$' as null_opt_is_upper from dual;
select dbms_random.string('', 5) ~ '^[A-Z]{5}$' as empty_opt_is_upper from dual;
select length(dbms_random.string('U', '12')) as text_len;
select length(dbms_random.string('U', 1e2)) as exponent_len;
select length(dbms_random.string('U', '1e2')) as text_exponent_len;
select length(dbms_random.string('U', 11.22)) as fractional_len;
select length(dbms_random.string('U', '32767')) as capped_text_len;
select length(dbms_random.string('U', '32768')) as capped_text_len_over;

-- unknown character classes default to uppercase; malformed input is rejected
select dbms_random.string('Z', 4) ~ '^[A-Z]{4}$' as unknown_class_is_upper from dual;
select dbms_random.string('UU', 4) from dual;

-- NULL numeric seeds do not enter the C numeric conversion path
call dbms_random.initialize(cast(NULL as number));
select dbms_random.random() is not null as works_after_null_initialize;
call dbms_random.seed(cast(NULL as number));
select dbms_random.random() is not null as works_after_null_seed;

--
-- RANDOM stays in BINARY_INTEGER range; NORMAL is a plain number
--
call dbms_random.seed(cast(-5 as number));
select dbms_random.random() between -2147483648 and 2147483647 as random_in_range;
select dbms_random.normal() is not null as normal_is_number;

-- TERMINATE is a no-op that keeps working afterwards
call dbms_random.terminate();
select dbms_random.value() >= 0 as works_after_terminate;

--
-- The generator state is reset by DISCARD ALL, so the next value comes
-- from a fresh entropy-seeded state (cannot be asserted exactly).
--
call dbms_random.seed(cast(1 as number));
discard all;
select dbms_random.value() >= 0 as works_after_discard;
