\set VERBOSITY terse
SET client_encoding = utf8;
set compatible_mode = 'oracle';

--test for nls_length_semantics and varchar2 type
drop table t1;
drop table t2;
drop table t3;
drop table t11;
drop table t22;
drop table t33;
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
CREATE TABLE foo (a VARCHAR2(0));

-- ERROR (number of typmods = 1)
CREATE TABLE foo (a VARCHAR2(10, 1));

-- OK
CREATE TABLE foo (a VARCHAR(5000));

-- cleanup
DROP TABLE foo;

-- OK
CREATE TABLE foo (a VARCHAR2(5));

CREATE INDEX ON foo(a);

--
-- test that no value longer than maxlen is allowed
--

-- ERROR (length > 5)
INSERT INTO foo VALUES ('abcdef');

-- ERROR (length > 5);
-- VARCHAR2 does not truncate blank spaces on implicit coercion
INSERT INTO foo VALUES ('abcde  ');

-- OK
INSERT INTO foo VALUES ('abcde');

-- OK
INSERT INTO foo VALUES ('abcdef'::VARCHAR2(5));

-- OK
INSERT INTO foo VALUES ('abcde  '::VARCHAR2(5));

--OK
INSERT INTO foo VALUES ('abc'::VARCHAR2(5));

--
-- test whitespace semantics on comparison
--

-- equal
SELECT 'abcde   '::VARCHAR2(10) = 'abcde   '::VARCHAR2(10);

-- not equal
SELECT 'abcde  '::VARCHAR2(10) = 'abcde   '::VARCHAR2(10);

--
-- test string functions created for varchar2
--

-- substrb(varchar2, int, int)
SELECT substrb('ABCありがとう'::VARCHAR2, 7, 6);

-- returns 'f' (emtpy string is not NULL)
SELECT substrb('ABCありがとう'::VARCHAR2, 7, 0) IS NULL;

-- If the starting position is zero or less, then return from the start
-- of the string adjusting the length to be consistent with the "negative start"
-- per SQL.
SELECT substrb('ABCありがとう'::VARCHAR2, 0, 4);

-- substrb(varchar2, int)
SELECT substrb('ABCありがとう', 5);

-- strposb(varchar2, varchar2)
SELECT strposb('ABCありがとう', 'りが');

-- returns 1 (start of the source string)
SELECT strposb('ABCありがとう', '');

-- returns 0
SELECT strposb('ABCありがとう', 'XX');

-- returns 't'
SELECT strposb('ABCありがとう', NULL) IS NULL;

-- lengthb(varchar2)
SELECT lengthb('ABCありがとう');

-- returns 0
SELECT lengthb('');

-- returs 't'
SELECT lengthb(NULL) IS NULL;

-- null safe concat (disabled by default)
SELECT NULL || 'hello'::varchar2 || NULL;

SET orafce.varchar2_null_safe_concat TO true;
SELECT NULL || 'hello'::varchar2 || NULL;

--test for nls_length_semantics parameters

set nls_length_semantics to byte;

show nls_length_semantics;

create table t1 (a varchar2(5));
\d+ t1
insert into t1 values('nlstt');
select * from t1;
insert into t1 values('你');
select * from t1;
insert into t1 values('你好吗');
select * from t1;

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

set nls_length_semantics to char;

show nls_length_semantics;

insert into t1 values('nlstt');
select * from t1;
insert into t1 values('你好吗老师');
select * from t1;
insert into t1 values('你好吗李老师');

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

drop table t1;
drop table t2;
drop table t3;

set nls_length_semantics to byte;
show nls_length_semantics;
create table t1 (a varchar2(1));
\d t1
insert into t1 values('李');
insert into t1 values('李老');
select * from t1;
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

set nls_length_semantics to char;
show nls_length_semantics;
insert into t1 values('李');
insert into t1 values('李老');
select * from t1;

insert into t2 values('李');
insert into t2 values('李老');
select * from t2;

insert into t3 values('李');
insert into t3 values('李老');
select * from t3;

drop table t1;
drop table t2;
drop table t3;

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

create table t1 (a varchar2(5));
create table t2 (b varchar(6));
create table t3 (c char(7));

create table t11 (aa varchar2(20));
insert into t11 values ('今天的天气');
CREATE OR REPLACE FUNCTION test1()
RETURNS varchar2
AS $$
insert into t1 select aa from t11;
select * from t1;
$$ LANGUAGE sql;

select test1();
select test2();
select test3();

DO LANGUAGE PLPGSQL $$
DECLARE
	str varchar2(5);
BEGIN
	insert into t1 select aa from t11;
	select a from t1 into str;
	raise notice '%', str;
END$$;

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

set nls_length_semantics to char;
show nls_length_semantics;

delete from t11;
delete from t22;
delete from t33;

insert into t11 values ('今天的天气好');
insert into t22 values ('今天的天气不好');
insert into t33 values ('今天的天气好不好');

select test1();
select test2();
select test3();

DO LANGUAGE PLPGSQL $$
DECLARE
	str varchar2(5);
BEGIN
	insert into t1 select aa from t11;
	select a from t1 into str;
	raise notice '%', str;
END$$;

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

drop table t1;
drop table t2;
drop table t3;
drop table t11;
drop table t22;
drop table t33;

drop function test1();
drop function test2();
drop function test3();

create domain domainchar char(5);
create domain domainvarchar varchar(5);
create domain domainvarchar2 varchar2(5);

-- Test tables using domains
create table basictestchar
           ( testchar domainchar
           );

-- Test tables using domains
create table basictestvarchar
           ( testchar domainvarchar
           );

-- Test tables using domains
create table basictestvarchar2
           ( testchar domainvarchar2
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
COPY basictestvarchar2 (testchar) FROM stdin;
张老师
\.
COPY basictestvarchar2 (testchar) FROM stdin;
张老师你好吗
\.
select * from basictestvarchar2;
set nls_length_semantics to byte;
COPY basictestvarchar2 (testchar) FROM stdin;
张
\.
COPY basictestvarchar2 (testchar) FROM stdin;
老师你好吗
\.
select * from basictestvarchar2;
create table test_var(c1 varchar2, c2 varchar2);
insert into test_var values('1', 'test1'),('1', 'test1'),('2', 'test1'),('2', 'test2');
create table test_tmp(c1 varchar2, c2 varchar2);
insert into test_tmp values('1', 'test1'),('2', 'test1');
select * from test_var where(c1, c2) not in (select * from test_tmp);