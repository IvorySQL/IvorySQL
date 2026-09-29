/*
 * MEDIAN
 */
create table median_t (id int, salary number);
insert into median_t values (1, 100);
insert into median_t values (2, 200);
insert into median_t values (3, 300);
insert into median_t values (4, 400);
insert into median_t values (5, 500);

-- Odd count: the middle value
select median(salary) from median_t;

-- Even count: linear interpolation between the two middle values
delete from median_t where id = 5;
select median(salary) from median_t;

-- NULLs are ignored in the calculation
insert into median_t values (6, null);
insert into median_t values (7, 1000);
select median(salary) from median_t;

-- An all-null input returns NULL
select median(salary) from median_t where salary is null;

-- An empty input returns NULL
select median(salary) from median_t where id > 1000;

drop table median_t;

-- Duplicated values
create table median_dup (x number);
insert into median_dup values (7);
insert into median_dup values (7);
insert into median_dup values (7);
insert into median_dup values (7);
select median(x) from median_dup;
drop table median_dup;

-- Negative and fractional values
create table median_neg (x number);
insert into median_neg values (-5);
insert into median_neg values (-1.5);
insert into median_neg values (2);
select median(x) from median_neg;
drop table median_neg;

-- NUMBER interpolation stays exact in decimal arithmetic
create table median_big (x number);
insert into median_big values (0.123456789012345678901234567890);
insert into median_big values (0.123456789012345678901234567892);
select median(x) from median_big;
drop table median_big;

-- Large integer midpoints keep their fractional part: the interpolation
-- multiplies by 0.5 instead of dividing by 2, so the exact .5 midpoint of
-- two consecutive 21-digit integers is not rounded away
create table median_bigint (x number);
insert into median_bigint values (100000000000000000001);
insert into median_bigint values (100000000000000000002);
select median(x) from median_bigint;
drop table median_bigint;

-- Median per group (Oracle SQL Reference example: median salary per department)
create table median_emp (dept_id int, salary number);
insert into median_emp values (10, 4400);
insert into median_emp values (10, 4800);
insert into median_emp values (10, null);
insert into median_emp values (20, 9500);
insert into median_emp values (20, 10000);
insert into median_emp values (20, 10500);
insert into median_emp values (20, 11000);
insert into median_emp values (30, null);
select dept_id, median(salary) from median_emp group by dept_id order by dept_id;

-- Analytic form: the partition-wide median for every row
select dept_id, salary, median(salary) over (partition by dept_id) as median_sal
  from median_emp order by dept_id, salary;
drop table median_emp;

-- Calls on literals: numeric literals are NUMBER
select pg_typeof(median(42)) from dual;
select pg_typeof(median(42.5)) from dual;
select pg_typeof(median('42.5')) from dual;
select median(42) from dual;
select median(-3.5) from dual;

-- BINARY_FLOAT / BINARY_DOUBLE inputs resolve to the sys.number overload
-- (documented deviation: Oracle returns the argument type here; adding
-- those overloads would misroute plain numeric literals to BINARY_DOUBLE)
create table median_f (a binary_float, b binary_double);
insert into median_f values (1.5, 2.5);
insert into median_f values (2.5, 3.5);
select pg_typeof(median(a)), pg_typeof(median(b)) from median_f;
select median(a), median(b) from median_f;
drop table median_f;
