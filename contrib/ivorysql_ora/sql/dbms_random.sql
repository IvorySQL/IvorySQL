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

-- low > high is rejected
select dbms_random.value(20, 10) from dual;

--
-- STRING: deterministic with a seed, honors the character class
--
call dbms_random.seed(cast(1234 as number));
select dbms_random.string('U', 8) as upper_only;
select dbms_random.string('L', 8) as lower_only;
select dbms_random.string('A', 8) as alpha_mixed;
select dbms_random.string('X', 8) as upper_alnum;
select dbms_random.string('P', 8) as printable;

-- string of length 0 is empty
select length(dbms_random.string('U', 0)) as empty_len;

-- invalid character class and negative length are rejected
select dbms_random.string('Z', 4) from dual;
select dbms_random.string('UU', 4) from dual;
select dbms_random.string('U', -1) from dual;

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
