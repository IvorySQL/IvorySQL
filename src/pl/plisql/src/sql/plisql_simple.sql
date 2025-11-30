--
-- Tests for plisql's handling of "simple" expressions
--

-- Check that changes to an inline-able function are handled correctly
create function simplesql(int) returns int language sql
as 'select $1';
/

create function simplecaller() returns int language plisql
as $$
declare
  sum int := 0;
begin
  for n in 1..10 loop
    sum := sum + simplesql(n);
    if n = 5 then
      create or replace function simplesql(int) returns int language sql
      as 'select $1 + 100';
    end if;
  end loop;
  return sum;
end$$;
/

select simplecaller();


-- Check that changes in search path are dealt with correctly
create schema simple1;

create function simple1.simpletarget(int) returns int language plisql
as $$begin return $1; end$$;
/

create function simpletarget(int) returns int language plisql
as $$begin return $1 + 100; end$$;
/

create or replace function simplecaller() returns int language plisql
as $$
declare
  sum int := 0;
begin
  for n in 1..10 loop
    sum := sum + simpletarget(n);
    if n = 5 then
      set local search_path = 'simple1';
    end if;
  end loop;
  return sum;
end$$;
/

select simplecaller();

-- try it with non-volatile functions, too
alter function simple1.simpletarget(int) immutable;
alter function simpletarget(int) immutable;

select simplecaller();

-- make sure flushing local caches changes nothing
\c -

select simplecaller();


-- Check case where first attempt to determine if it's simple fails

create function simplesql() returns int language sql
as $$select 1 / 0$$;
/

create or replace function simplecaller() returns int language plisql
as $$
declare x int;
begin
  select simplesql() into x;
  return x;
end$$;
/

select simplecaller();  -- division by zero occurs during simple-expr check

create or replace function simplesql() returns int language sql
as $$select 2 + 2$$;
/

select simplecaller();


-- Check case where called function changes from non-SRF to SRF (bug #18497)

create or replace function simplecaller() returns int language plpgsql
as $$
declare x int;
begin
  x := simplesql();
  return x;
end$$;
/

select simplecaller();

drop function simplesql();

create function simplesql() returns setof int language sql
as $$select 22 + 22$$;
/

select simplecaller();

select simplecaller();

-- Check handling of simple expression in a scrollable cursor (bug #18859)

do $$
declare
 p_CurData refcursor;
 val int;
begin
 open p_CurData scroll for select 42;
 fetch p_CurData into val;
 raise notice 'val = %', val;
end; $$;

-- Check SELECT INTO with parenthesized expressions (IvorySQL issue #981)

do $$
declare
 x int := 50;
 result numeric;
begin
 -- Test parenthesized expression at start of SELECT list
 select (100 - x) * 0.01 into result from dual;
 raise notice 'Test 1 (parentheses): %', result;

 -- Test without parentheses (should still work)
 select 100 - x into result from dual;
 raise notice 'Test 2 (no parentheses): %', result;

 -- Test multiple parenthesized expressions
 select (100 - x) * (0.01 + x) into result from dual;
 raise notice 'Test 3 (multiple parentheses): %', result;

 -- Test nested parentheses
 select ((100 - x) * 0.01) into result from dual;
 raise notice 'Test 4 (nested parentheses): %', result;
end; $$;

-- Edge case: nested SELECT with parenthesized expressions
do $$
declare
 result int;
begin
 select (select (10 + 5) from dual) into result from dual;
 raise notice 'Nested SELECT: %', result;
end; $$;

-- Edge case: function call in parentheses (not just arithmetic)
create function test_func(int) returns int language plisql
as $$begin return $1 * 2; end$$;
/

do $$
declare
 result int;
begin
 select (test_func(25)) into result from dual;
 raise notice 'Function in parens: %', result;
end; $$;

-- Edge case: CASE expression in parentheses
do $$
declare
 x int := 10;
 result int;
begin
 select (case when x > 5 then x * 2 else x end) into result from dual;
 raise notice 'CASE in parens: %', result;
end; $$;

-- Edge case: SELECT with CAST in parentheses
do $$
declare
 result varchar;
begin
 select (cast(123 as varchar)) into result from dual;
 raise notice 'CAST in parens: %', result;
end; $$;

-- Edge case: Complex nested expression
do $$
declare
 x int := 10;
 y int := 5;
 result numeric;
begin
 select ((x + y) * (x - y)) / 2.0 into result from dual;
 raise notice 'Complex expression: %', result;
end; $$;

