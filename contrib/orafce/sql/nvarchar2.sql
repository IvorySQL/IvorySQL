\set VERBOSITY terse
SET client_encoding = utf8;
set compatible_mode = 'oracle';
--test for original string type
drop table t2;
drop table t3;
drop table t4;
drop table t22;
drop table t33;
drop table t44;
show nls_length_semantics;

create table t2 (b varchar(6));
create table t3 (c char(7));

insert into t2 values('你好很快就分散吗');
insert into t2 values('nlsttd');
select * from t2;
insert into t3 values('nlsttdl');
insert into t3 values('你好很快就分散吗');
select * from t3;

drop table t2;
drop table t3;


--
-- test type modifier related rules
--

-- ERROR (typmod >= 1)
CREATE TABLE bar (a NVARCHAR2(0));

-- ERROR (number of typmods = 1)
CREATE TABLE bar (a NVARCHAR2(10, 1));

-- OK
CREATE TABLE bar (a VARCHAR(5000));

CREATE INDEX ON bar(a);

-- cleanup
DROP TABLE bar;

-- OK
CREATE TABLE bar (a NVARCHAR2(5));

--
-- test that no value longer than maxlen is allowed
--

-- ERROR (length > 5)
INSERT INTO bar VALUES ('abcdef');

-- ERROR (length > 5);
-- NVARCHAR2 does not truncate blank spaces on implicit coercion
INSERT INTO bar VALUES ('abcde  ');

-- OK
INSERT INTO bar VALUES ('abcde');

-- OK
INSERT INTO bar VALUES ('abcdef'::NVARCHAR2(5));

-- OK
INSERT INTO bar VALUES ('abcde  '::NVARCHAR2(5));

--OK
INSERT INTO bar VALUES ('abc'::NVARCHAR2(5));

--
-- test whitespace semantics on comparison
--

-- equal
SELECT 'abcde   '::NVARCHAR2(10) = 'abcde   '::NVARCHAR2(10);

-- not equal
SELECT 'abcde  '::NVARCHAR2(10) = 'abcde   '::NVARCHAR2(10);

-- null safe concat (disabled by default)
SELECT NULL || 'hello'::varchar2 || NULL;

SET orafce.varchar2_null_safe_concat TO true;
SELECT NULL || 'hello'::varchar2 || NULL;

--test for nls_length_semantics parameters

set nls_length_semantics to byte;

show nls_length_semantics;

create table t2 (b varchar(6));
\d+ t2
insert into t2 values('nlsttd');
select * from t2;
insert into t2 values('n好t');
select * from t2;
insert into t2 values('你好');
select * from t2;
insert into t2 values('你好吗');
select * from t2;

create table t3 (c char(7));
\d+ t3
insert into t3 values('nlsttdl');
select * from t3;
insert into t3 values('你好');
select * from t3;
insert into t3 values('李老师你好吗');
select * from t3;

create table t4 (d nvarchar2(8));
\d+ t4
insert into t4 values('nlsttdld');
select * from t4;
insert into t4 values('你好');
select * from t4;
insert into t4 values('李老师你好吗');
select * from t4;

set nls_length_semantics to char;

show nls_length_semantics;

insert into t2 values('nlsttd');
select * from t2;
insert into t2 values('你好吗李老师');
select * from t2;
insert into t2 values('你好吗小李老师');

insert into t3 values('nlsttdl');
select * from t3;
insert into t3 values('小李老师你好吗');
select * from t3;
insert into t3 values('小李老师你好再见');

insert into t4 values('nlsttdld');
select * from t4;
insert into t4 values('小张小李老师你好');
select * from t4;
insert into t4 values('小张小李老师你好吗');
select * from t4;

drop table t2;
drop table t3;
drop table t4;

set nls_length_semantics to byte;
show nls_length_semantics;
create table t2 (b varchar(1));
\d t2
insert into t2 values('李');
insert into t2 values('李老');
select * from t2;

create table t3 (c char(1));
\d t3
insert into t3 values('李');
insert into t3 values('李老');
select * from t3;
create table t4 (d nvarchar2(1));
\d t4
insert into t4 values('李');
insert into t4 values('李老');
select * from t4;

set nls_length_semantics to char;
show nls_length_semantics;
insert into t2 values('李');
insert into t2 values('李老');
select * from t2;

insert into t3 values('李');
insert into t3 values('李老');
select * from t3;

insert into t4 values('李');
insert into t4 values('李老');
select * from t4;

drop table t2;
drop table t3;
drop table t4;

set nls_length_semantics to none;
show nls_length_semantics;
create table t2 (b varchar(6));
create table t3 (c char(7));

create table t22 (bb varchar(20));
insert into t22 values ('你今天上学迟到');
CREATE OR REPLACE FUNCTION test2()
RETURNS varchar
AS $$
insert into t2 select bb from t22;
select * from t2;
$$ LANGUAGE sql;

select test2();

DO LANGUAGE PLPGSQL $$
DECLARE
	str varchar(6);
BEGIN
	insert into t2 select bb from t22;
	select b from t2 into str;
	raise notice '%', str;
END$$;

create table t33 (cc char(20));
insert into t33 values ('你今天上学迟到了');
CREATE OR REPLACE FUNCTION test3()
RETURNS char(20)
AS $$
insert into t3 select cc from t33;
select * from t3;
$$ LANGUAGE sql;

select test3();

DO LANGUAGE PLPGSQL $$
DECLARE
	str char(7);
BEGIN
	insert into t3 select cc from t33;
	select c from t3 into str;
	raise notice '%', str;
END$$;

drop table t2;
drop table t3;

set nls_length_semantics to byte;
show nls_length_semantics;
create table t2 (b varchar(6));
create table t3 (c char(7));
create table t4 (d nvarchar2(8));

select test2();
select test3();

create table t44 (dd nvarchar2(20));
insert into t44 values ('今天什么天气');
CREATE OR REPLACE FUNCTION test4()
RETURNS nvarchar2(20)
AS $$
insert into t4 select dd from t44;
select * from t4;
$$ LANGUAGE sql;

select test4();

DO LANGUAGE PLPGSQL $$
DECLARE
	str varchar(6);
BEGIN
	insert into t2 select bb from t22;
	select b from t2 into str;
	raise notice '%', str;
END$$;

DO LANGUAGE PLPGSQL $$
DECLARE
	str char(7);
BEGIN
	insert into t3 select cc from t33;
	select c from t3 into str;
	raise notice '%', str;
END$$;

DO LANGUAGE PLPGSQL $$
DECLARE
	str nvarchar2(8);
BEGIN
	insert into t4 select dd from t44;
	select d from t4 into str;
	raise notice '%', str;
END$$;

set nls_length_semantics to char;
show nls_length_semantics;

delete from t22;
delete from t33;
delete from t44;

insert into t22 values ('今天的天气不好');
insert into t33 values ('今天的天气好不好');
insert into t44 values ('今天的天气好不好呢');

select test2();
select test3();
select test4();

DO LANGUAGE PLPGSQL $$
DECLARE
	str varchar(6);
BEGIN
	insert into t2 select bb from t22;
	select b from t2 into str;
	raise notice '%', str;
END$$;

DO LANGUAGE PLPGSQL $$
DECLARE
	str char(7);
BEGIN
	insert into t3 select cc from t33;
	select c from t3 into str;
	raise notice '%', str;
END$$;

DO LANGUAGE PLPGSQL $$
DECLARE
	str nvarchar2(8);
BEGIN
	insert into t4 select dd from t44;
	select d from t4 into str;
	raise notice '%', str;
END$$;

drop table t2;
drop table t3;
drop table t4;
drop table t22;
drop table t33;
drop table t44;

drop function test2();
drop function test3();
drop function test4();

create domain domainchar char(5);
create domain domainvarchar varchar(5);
create domain domainnvarchar2 nvarchar2(5);

-- Test tables using domains
create table basictestchar
           ( testchar domainchar
           );

-- Test tables using domains
create table basictestvarchar
           ( testchar domainvarchar
           );

-- Test tables using domains
create table basictestnvarchar2
           ( testchar domainnvarchar2
           );

-- Test copy
set nls_length_semantics to char;
COPY basictestchar (testchar) FROM stdin;
张老师
\.
COPY basictestchar (testchar) FROM stdin;
张老师你好吗
\.
select * from basictestchar;
set nls_length_semantics to byte;
COPY basictestchar (testchar) FROM stdin;
张
\.
COPY basictestchar (testchar) FROM stdin;
老师你好吗
\.
select * from basictestchar;

-- Test copy
set nls_length_semantics to char;
COPY basictestvarchar (testchar) FROM stdin;
张老师
\.
COPY basictestvarchar (testchar) FROM stdin;
张老师你好吗
\.
select * from basictestvarchar;
set nls_length_semantics to byte;
COPY basictestvarchar (testchar) FROM stdin;
张
\.
COPY basictestvarchar (testchar) FROM stdin;
老师你好吗
\.
select * from basictestvarchar;

-- Test copy
set nls_length_semantics to char;
COPY basictestnvarchar2 (testchar) FROM stdin;
张老师
\.
COPY basictestnvarchar2 (testchar) FROM stdin;
张老师你好吗
\.
select * from basictestnvarchar2;
set nls_length_semantics to byte;
COPY basictestnvarchar2 (testchar) FROM stdin;
张
\.
COPY basictestnvarchar2 (testchar) FROM stdin;
老师你好吗
\.
select * from basictestnvarchar2;
