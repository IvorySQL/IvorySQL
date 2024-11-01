/*
 * DECODE
 */
SET nls_date_format = 'DD-MON-YY';
SET nls_timestamp_format = 'DD-MON-YY HH24:MI:SS.US';
SET nls_timestamp_tz_format = 'DD-MON-YY HH24:MI:SS.US TZ';
set default_text_search_config = 'pg_catalog.simple';

-- error
select decode(NULL, 1, 2018, 2, timestamp'2018-2-1 00:00:00', timestamp'2018-5-1 00:00:00');
select decode('abc', 123, 123,4, date'2018-8-1', 5) from dual;
select decode('abc', 123, 123,4, 5, date'2018-8-1', 5) from dual;
select decode('abc', 123, 123,4, 5, 6,timestamp'2018-08-1 00:00:00') from dual;
select decode('abc', date'2018-8-1', 5, 123, 123,4, 5) from dual;
select decode('abc', date'2018-8-1', 5, date'2018-8-2', date'2018-8-3',4, 5) from dual;
select decode('abc', 123, 123,4, 5, 6,timestamp'2018-08-1 00:00:00', interval'1-1' year to month) from dual;
select decode('abc', 123, 123,4, timestamp'2018-08-1 00:00:00', interval'1-1' year to month) from dual;
select decode('abc', 123, 123,4, 456, interval'1-1' year to month) from dual;
select decode('abc', 123, 123,4, '456', interval'1-1' year to month) from dual;
select decode('abc', 123, 123,4, '456', 456.7) from dual;
select decode('abc', 123, date'2018-8-1', '456', 456.7) from dual;
select decode(NULL, 1, interval'1-1' year to month, 2, timestamp'2018-2-1 00:00:00', date'2018-8-1');

-- ok
select decode('123', 123, date'2018-8-1', '456', timestamp'2018-08-1 00:00:00') from dual;
select decode(NULL, 1, '2018', 2, timestamp'2018-2-1 00:00:00', timestamp'2018-5-1 00:00:00');
--return type is number
create table tmp_decode as
  select decode('123', 123, 1, '456', '2018') as b from dual;
\d tmp_decode
drop table tmp_decode;
--return type is varchar
create table tmp_decode as
  select decode('123', 123, 'haha', '456', timestamp'2018-08-1 00:00:00') as b from dual;
\d tmp_decode
drop table tmp_decode;
--return type is date
create table tmp_decode as
  select decode(123, 123, date'2018-8-1', '456', timestamp'2018-08-1 00:00:00') as b from dual;
\d tmp_decode
drop table tmp_decode;
--return type is timestamp
create table tmp_decode as
  select decode(123, 123, timestamp'2018-8-1 00:00:00', '456', date'2018-08-1') as b from dual;
\d tmp_decode
drop table tmp_decode;
--return type is interval
create table tmp_decode as
  select decode(NULL, 1, interval'1-1' year to month, 2, interval'2-2' year to month, interval'3-3' year to month);
\d tmp_decode
drop table tmp_decode;
create table tmp_decode as
  select decode(NULL, 1, interval'1 1:1:1' day to second, 2, interval'2 2:2:2' day to second, interval'3 3:3:3' day to second);
\d tmp_decode
drop table tmp_decode;


--the second arg's type is number
create table tmp_decode as
  select decode('123', 123, 1, '456', '2018') as b from dual;
\d tmp_decode
drop table tmp_decode;
--the second arg's type is varchar
create table tmp_decode as
  select decode('123', 'abc', 'haha', '456', timestamp'2018-08-1 00:00:00') as b from dual;
\d tmp_decode
drop table tmp_decode;
--the second arg's type is date
create table tmp_decode as
  select decode(timestamp'2018-9-5 12:00:00', date'2018-9-5', date'2018-8-1', timestamp'2018-9-6 00:00:00', timestamp'2018-08-1 00:00:00') as b from dual;
\d tmp_decode
drop table tmp_decode;
--the second arg's type is timestamp
create table tmp_decode as
  select decode(date'2018-9-5', timestamp'2018-9-5 12:00:00', 1, timestamp'2018-9-6 12:00:00', 2) as b from dual;
\d tmp_decode
drop table tmp_decode;
--the second arg's type is interval
create table tmp_decode as
  select decode(NULL, interval'1-1' year to month, 1, interval'2-2' year to month, 2, 3);
\d tmp_decode
drop table tmp_decode;
create table tmp_decode as
  select decode(NULL, interval'1 1:1:1' day to second, 1, interval'2 2:2:2' day to second, 2, 3);
\d tmp_decode
drop table tmp_decode;


select decode(NULL, null, 2018, 2, 3);
select decode(NULL,1, 2018, null, 3);
select decode(NULL,1, 2018, 2, 3);
create table t_decode(a int, b int);
insert into t_decode values(null, null);
select decode(a, b, 2018, 2, 3) from t_decode;
select decode(a, 1, 2018, b, 3) from t_decode;
select decode(a, 1, 2018, 2, 3, 4) from t_decode;
drop table t_decode;

set nls_date_format = 'pg';
set nls_timestamp_format = 'pg';
set nls_timestamp_tz_format = 'pg';

--
--NVL
--

--expr1非空/expr2非空
SELECT NVL('sales', -1);
SELECT NVL(cos(0), -1);
SELECT NVL(cos(0), 'kueyhd');--报错
SELECT NVL(2*3, -1);
SELECT NVL(2*3, 'euywkg');--报错

create table test11(col1 varchar(10));
insert into test11 values('djoes');
insert into test11 values('9898');
insert into test11 values(NULL);
insert into test11 values(22);
insert into test11 values(NULL);
SELECT NVL(col1, 'aaaa') from test11;
SELECT NVL(col1,to_date('1998-10','YYYY-MM')) from test11;--报错

--expr1为空/expr2非空
SELECT NVL(NULL, -1);
SELECT NVL(NULL,cos(0));
SELECT NVL(NULL,2*3);
SELECT NVL(NULL,col1) from test11;

--expr1非空/expr2为空
SELECT NVL('sales', NULL);

--expr1为空/expr2为空
SELECT NVL(NULL, NULL);
SELECT NVL(' ', ' ');

--参数个数非法,报错
SELECT NVL('sales', -1,2);--报错
SELECT NVL('sales', -1,2,3,4);--报错
SELECT NVL( -1);--报错
SELECT NVL( );--报错

--参数expr1为任意数据类型
--数值类型
--1.smallint:
create table test1(col1 bigint,col2 int);
insert into test1 values(23,1);
select NVL (col1, NULL) from test1;
drop table test1;
--2.integer
create table test1(col1 int,col2  int);
insert into test1 values(23,1);
SELECT NVL (col1, NULL) from test1;
drop table test1;
--3.bigint:
create table test1(col1 bigint,col2  int);
insert into test1 values(23,1);
SELECT NVL (col1, NULL) from test1;
drop table test1;
--4.decimal:
create table test1(col1 decimal,col2  int);
insert into test1 values(23,1);
SELECT NVL (col1, NULL) from test1;
drop table test1;
--5.numeric:
create table test1(col1 numeric(5,2),col2  int);
insert into test1 values(23.225,1);
SELECT NVL (col1, NULL) from test1;
drop table test1;
--6.real:
create table test1(col1 real,col2  int);
insert into test1 values(23.225,1);
SELECT NVL (col1, NULL) from test1;
drop table test1;
--7.double precision:
create table test1(col1 double precision,col2  int);
insert into test1 values(23.225,1);
SELECT NVL (col1, NULL) from test1;
drop table test1;
--8.smallserial:
create table test1(col1 smallserial,col2  int);
insert into test1 values(23,1);
SELECT NVL (col1, NULL) from test1;
drop table test1;
--9.serial:
create table test1(col1 serial,col2  int);
insert into test1 values(23,1);
SELECT NVL (col1, NULL) from test1;
drop table test1;
--10.bigserial:
create table test1(col1 bigserial,col2  int);
insert into test1 values(23,1);
SELECT NVL (col1, NULL) from test1;
drop table test1;

--货币类型
--money:
create table test1(col1 money,col2  int);
insert into test1 values(23,1);
SELECT NVL (col1, NULL) from test1;
drop table test1;

--字符类型
--1.varchar:
create table test1(col1 varchar(10),col2  int);
insert into test1 values('sales',1);
SELECT NVL (col1, NULL) from test1;
drop table test1;
--2.char:
create table test1(col1 char(10),col2  int);
insert into test1 values('sales',1);
SELECT NVL (col1, NULL) from test1;
drop table test1;
--3.text:
create table test1(col1 text,col2  int);
insert into test1 values('sales',1);
SELECT NVL (col1, NULL) from test1;
drop table test1;

--二进制数据类型
create table test1(col1 bytea,col2  int);
insert into test1 values(E'\\001',1);
SELECT NVL (col1, NULL) from test1;
drop table test1;

--日期/时间类型
--1.timestamp:
create table test1(col1 timestamp,col2  int);
insert into test1 values('1999-1-5',1);
SELECT NVL (col1, NULL) from test1;
drop table test1;
--2.timestamp with time zone:
create table test1(col1 timestamp with time zone,col2  int);
insert into test1 values('1999-1-5 8:00:00',1);
SELECT NVL (col1, NULL) from test1;
drop table test1;
--3.date:
create table test1(col1 date,col2  int);
insert into test1 values('1999-01-05',1);
SELECT NVL (col1, NULL) from test1;
drop table test1;
--4.time:
create table test1(col1 time,col2  int);
insert into test1 values('14:12:50',1);
SELECT NVL (col1, NULL) from test1;
drop table test1;
--5.time with time zone:
create table test1(col1 time with time zone,col2  int);
insert into test1 values('14:12:50-8',1);
SELECT NVL (col1, NULL) from test1;
drop table test1;
--6.interval:
create table test1(col1 interval year to month,col2  int);
insert into test1 values('1-2',1);
SELECT NVL (col1, NULL) from test1;
drop table test1;

--布尔类型
--boolean:
create table test1(col1 boolean,col2  int);
insert into test1 values(true,1);
SELECT NVL (col1, NULL) from test1;
drop table test1;

--枚举类型:
CREATE TYPE mood AS ENUM ('sad', 'ok', 'happy');
CREATE TABLE person_test (
    name text,
    current_mood mood
);
INSERT INTO person_test VALUES ('Moe', 'happy');
SELECT NVL ( current_mood, NULL) from person_test;
drop table person_test;
drop type mood;

--几何类型:
--1.point:
create table test1(col1 point,col2  int);
insert into test1 values(point(5,8),1);
SELECT NVL (col1, NULL) from test1;
drop table test1;
--2.line:
create table test1(col1 line,col2  int);
insert into test1 values(line(point '(-1,0)', point '(1,0)'),1);
SELECT NVL (col1, NULL) from test1;
drop table test1;
--3.lseg:
create table test1(col1 lseg,col2  int);
insert into test1 values(lseg(box '((-1,0),(1,0))'),1);
SELECT NVL (col1, NULL) from test1;
drop table test1;
--4.box:
create table test1(col1 box,col2  int);
insert into test1 values(box(point '(0,0)', point '(1,1)'),1);
SELECT NVL (col1, NULL) from test1;
drop table test1;
--5.path:
create table test1(col1 path,col2  int);
insert into test1 values(path(polygon '((0,0),(1,1),(2,0))'),1);
SELECT NVL (col1, NULL) from test1;
drop table test1;
--6.polygon:
create table test1(col1 polygon,col2  int);
insert into test1 values(polygon(box '((0,0),(1,1))'),1);
SELECT NVL (col1, NULL) from test1;
drop table test1;
--7.circle:
create table test1(col1 circle,col2  int);
insert into test1 values(circle(point '(0,0)', 2.0),1);
SELECT NVL (col1, NULL) from test1;
drop table test1;

--网络地址类型:
--1.cidr:
create table test1(col1 cidr,col2  int);
insert into test1 values('192.168.100.128/25',1);
SELECT NVL (col1, NULL) from test1;
drop table test1;
--2.inet:
create table test1(col1 inet,col2  int);
insert into test1 values('192.168.100.128/25',1);
SELECT NVL (col1, NULL) from test1;
drop table test1;
--3.macaddr:
create table test1(col1 macaddr,col2  int);
insert into test1 values('08:00:2b:01:02:03',1);
SELECT NVL (col1, NULL) from test1;
drop table test1;

--位串类型:
--1.bit(n):
create table test1(col1 bit(3),col2  int);
insert into test1 values(B'101',1);
SELECT NVL (col1, NULL) from test1;
drop table test1;
--2.bit varying(n):
create table test1(col1 bit varying(5),col2  int);
insert into test1 values(B'00',1);
SELECT NVL (col1, NULL) from test1;
drop table test1;

--文本搜索类型:
--1.tsvector:
create table test1(col1 tsvector,col2  int);
insert into test1 values(to_tsvector('english', 'The Fat Rats'),1);
SELECT NVL (col1, NULL) from test1;
drop table test1;
--2.tsquery:
create table test1(col1 tsquery,col2  int);
insert into test1 values(to_tsquery('Fat:ab & Cats'),1);
SELECT NVL (col1, NULL) from test1;
drop table test1;

--UUID类型:
create table test1(col1 UUID,col2  int);
insert into test1 values('a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11',1);
SELECT NVL (col1, NULL) from test1;
drop table test1;

--JSON类型:
create table test1(col1 JSON,col2  int);
insert into test1 values('5'::json,1);
SELECT NVL (col1, NULL) from test1;
drop table test1;

--Arrays:
create table test1(col1 int[],col2  int);
insert into test1 values(array[5,6],1);
SELECT NVL (col1, NULL) from test1;
drop table test1;

--参数expr2为任意数据类型
--数值类型:
--1.smallint:
create table test1(col1 smallint,col2  int);
insert into test1 values(23,1);
SELECT NVL (NULL, col1) from test1;
drop table test1;
--2.integer:
create table test1(col1 int,col2  int);
insert into test1 values(23,1);
SELECT NVL (NULL, col1) from test1;
drop table test1;
--3.bigint:
create table test1(col1 bigint,col2  int);
insert into test1 values(23,1);
SELECT NVL (NULL, col1) from test1;
drop table test1;
--4.decimal:
create table test1(col1 decimal,col2  int);
insert into test1 values(23,1);
SELECT NVL (NULL, col1) from test1;
drop table test1;
--5.numeric:
create table test1(col1 numeric(5,2),col2  int);
insert into test1 values(23.225,1);
SELECT NVL (NULL, col1) from test1;
drop table test1;
--6.real:
create table test1(col1 real,col2  int);
insert into test1 values(23.225,1);
SELECT NVL (NULL, col1) from test1;
drop table test1;
--7.double precision:
create table test1(col1 double precision,col2  int);
insert into test1 values(23.225,1);
SELECT NVL (NULL, col1) from test1;
drop table test1;
--8.smallserial:
create table test1(col1 smallserial,col2  int);
insert into test1 values(23,1);
SELECT NVL (NULL, col1) from test1;
drop table test1;
--9.serial:
create table test1(col1 serial,col2  int);
insert into test1 values(23,1);
SELECT NVL (NULL, col1) from test1;
drop table test1;
--10.bigserial:
create table test1(col1 bigserial,col2  int);
insert into test1 values(23,1);
SELECT NVL (NULL, col1) from test1;
drop table test1;

--货币类型:
--money:
create table test1(col1 money,col2  int);
insert into test1 values(23,1);
SELECT NVL (NULL, col1) from test1;
drop table test1;

--字符类型:
--1.varchar:
create table test1(col1 varchar(10),col2  int);
insert into test1 values('sales',1);
SELECT NVL (NULL, col1) from test1;
drop table test1;
--2.char:
create table test1(col1 char(10),col2  int);
insert into test1 values('sales',1);
SELECT NVL (NULL, col1) from test1;
drop table test1;
--3.text:
create table test1(col1 text,col2  int);
insert into test1 values('sales',1);
SELECT NVL (NULL, col1) from test1;
drop table test1;

--二进制数据类型:
create table test1(col1 bytea,col2  int);
insert into test1 values(E'\\001',1);
SELECT NVL (NULL, col1) from test1;
drop table test1;

--日期/时间类型:
--1.timestamp:
create table test1(col1 timestamp,col2  int);
insert into test1 values('1999-1-5',1);
SELECT NVL (NULL, col1) from test1;
drop table test1;
--2.timestamp with time zone:
create table test1(col1 timestamp with time zone,col2  int);
insert into test1 values('1999-1-5 8:00:00',1);
SELECT NVL (NULL, col1) from test1;
drop table test1;
--3.date:
create table test1(col1 date,col2  int);
insert into test1 values('1999-01-05',1);
SELECT NVL (NULL, col1) from test1;
drop table test1;
--4.time:
create table test1(col1 time,col2  int);
insert into test1 values('14:12:50',1);
SELECT NVL (NULL, col1) from test1;
drop table test1;
--5.time with time zone:
create table test1(col1 time with time zone,col2  int);
insert into test1 values('14:12:50-8',1);
SELECT NVL (NULL, col1) from test1;
drop table test1;
--6.interval:
create table test1(col1 interval year to month,col2  int);
insert into test1 values('1-2',1);
SELECT NVL (NULL, col1) from test1;
drop table test1;

--布尔类型:
--boolean:
create table test1(col1 boolean,col2  int);
insert into test1 values(true,1);
SELECT NVL (NULL, col1) from test1;
drop table test1;

--枚举类型:
CREATE TYPE mood AS ENUM ('sad', 'ok', 'happy');
CREATE TABLE person_test (
    name text,
    current_mood mood
);
INSERT INTO person_test VALUES ('Moe', 'happy');
SELECT NVL (NULL, current_mood) from person_test;
drop table person_test;
drop type mood;

--几何类型:
--1.point:
create table test1(col1 point,col2  int);
insert into test1 values(point(5,8),1);
SELECT NVL (NULL, col1) from test1;
drop table test1;
--2.line:
create table test1(col1 line,col2  int);
insert into test1 values(line(point '(-1,0)', point '(1,0)'),1);
SELECT NVL (NULL, col1) from test1;
drop table test1;
--3.lseg:
create table test1(col1 lseg,col2  int);
insert into test1 values(lseg(box '((-1,0),(1,0))'),1);
SELECT NVL (NULL, col1) from test1;
drop table test1;
--4.box:
create table test1(col1 box,col2  int);
insert into test1 values(box(point '(0,0)', point '(1,1)'),1);
SELECT NVL (NULL, col1) from test1;
drop table test1;
--5.path:
create table test1(col1 path,col2  int);
insert into test1 values(path(polygon '((0,0),(1,1),(2,0))'),1);
SELECT NVL (NULL, col1) from test1;
drop table test1;
--6.polygon:
create table test1(col1 polygon,col2  int);
insert into test1 values(polygon(box '((0,0),(1,1))'),1);
SELECT NVL (NULL, col1) from test1;
drop table test1;
--7.circle:
create table test1(col1 circle,col2  int);
insert into test1 values(circle(point '(0,0)', 2.0),1);
SELECT NVL (NULL, col1) from test1;
drop table test1;

--网络地址类型：
--1.cidr:
create table test1(col1 cidr,col2  int);
insert into test1 values('192.168.100.128/25',1);
SELECT NVL (NULL, col1) from test1;
drop table test1;
--2.inet:
create table test1(col1 inet,col2  int);
insert into test1 values('192.168.100.128/25',1);
SELECT NVL (NULL, col1) from test1;
drop table test1;
--3.macaddr:
create table test1(col1 macaddr,col2  int);
insert into test1 values('08:00:2b:01:02:03',1);
SELECT NVL (NULL, col1) from test1;
drop table test1;

--位串类型：
--1.bit(n):
create table test1(col1 bit(3),col2  int);
insert into test1 values(B'101',1);
SELECT NVL (NULL, col1) from test1;
drop table test1;
--2.bit varying(n):
create table test1(col1 bit varying(5),col2  int);
insert into test1 values(B'00',1);
SELECT NVL (NULL, col1) from test1;
drop table test1;

--文本搜索类型：
--1.tsvector：
create table test1(col1 tsvector,col2  int);
insert into test1 values(to_tsvector('english', 'The Fat Rats'),1);
SELECT NVL (NULL, col1) from test1;
drop table test1;
--2.tsquery：
create table test1(col1 tsquery,col2  int);
insert into test1 values(to_tsquery('Fat:ab & Cats'),1);
SELECT NVL (NULL, col1) from test1;
drop table test1;

--UUID类型：
create table test1(col1 UUID,col2  int);
insert into test1 values('a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11',1);
SELECT NVL (NULL, col1) from test1;
drop table test1;

--JSON类型：
create table test1(col1 JSON,col2  int);
insert into test1 values('5'::json,1);
SELECT NVL (NULL, col1) from test1;
drop table test1;

--Arrays:
create table test1(col1 int[],col2  int);
insert into test1 values(array[5,6],1);
SELECT NVL (NULL, col1) from test1;
drop table test1;

--expr1/expr2输入非法
--1.Expr1输入非法字符：
SELECT NVL (@@, NULL);--报错
SELECT NVL ($#!, NULL);--报错
--2.expr2输入非法字符：
SELECT NVL (NULL, ￥%*&);--报错
SELECT NVL (NULL, ()$!~);--报错


--
--NVL2
--
--expr1为空
SELECT NVL2(null,1,-2);
SELECT NVL2(NULL, 1,cos(0));
SELECT NVL2(NULL, 1,2*3); 
SELECT NVL2(NULL,'sales',col1) from test11;

--expr1非空
--expr1表达式为常量的情况：
SELECT NVL2('sales',1,-2);
SELECT NVL2('sales',2*4,-2);
SELECT NVL2('sales',cos(0),-2);
SELECT NVL2('sales',col1,-2) from test11;
--expr1表达式为函数的情况：
SELECT NVL2(cos(0), 1,-2);
SELECT NVL2(cos(0),to_date('1998','YYYY'),'iruyw');--报错
--expr1表达式为计算式的情况：
SELECT NVL2(2*3, 1,-2);
SELECT NVL2(2*3, to_date('1998','YYYY'),'i2ywh');--报错
--expr1表达式为列值的情况：
SELECT NVL2(col1, 'aaaa','ueywh') from test11;
SELECT NVL2(col1,111,to_date('1998','YYYY')) from test11;--报错
DROP TABLE test11;

--参数个数非法，报错
SELECT NVL2(null,1);--报错
SELECT NVL2();--报错
SELECT NVL2(null,1,2,3);--报错
SELECT NVL2(null,1,2,3,4,5);--报错

--参数expr1为任意数据类型
--数值类型：
--1.smallint:
create table test1(col1 smallint,col2  int);
insert into test1 values(23,1);
SELECT NVL2 (col1, 1,2) from test1;
drop table test1;
--2.integer:
create table test1(col1 int,col2  int);
insert into test1 values(23,1);
SELECT NVL2 (col1, 1,2) from test1;
drop table test1;
--3.bigint:
create table test1(col1 bigint,col2  int);
insert into test1 values(23,1);
SELECT NVL2 (col1, 1,2) from test1;
drop table test1;
--4.decimal:
create table test1(col1 decimal,col2  int);
insert into test1 values(23,1);
SELECT NVL2 (col1, 1,2) from test1;
drop table test1;
--5.numeric:
create table test1(col1 numeric(5,2),col2  int);
insert into test1 values(23.225,1);
SELECT NVL2 (col1, 1,2) from test1;
drop table test1;
--6.real:
create table test1(col1 real,col2  int);
insert into test1 values(23.225,1);
SELECT NVL2 (col1, 1,2) from test1;
drop table test1;
--7.double precision:
create table test1(col1 double precision,col2  int);
insert into test1 values(23.225,1);
SELECT  NVL2 (col1, 1,2) from test1;
drop table test1;
--8.smallserial;
create table test1(col1 smallserial,col2  int);
insert into test1 values(23,1);
SELECT NVL2 (col1, 1,2) from test1;
drop table test1;
--9.serial:
create table test1(col1 serial,col2  int);
insert into test1 values(23,1);
SELECT NVL2 (col1, 1,2) from test1;
drop table test1;
--10.bigserial:
create table test1(col1 bigserial,col2  int);
insert into test1 values(23,1);
SELECT  NVL2 (col1, 1,2) from test1;
drop table test1;

--货币类型：
--money：
create table test1(col1 money,col2  int);
insert into test1 values(23,1);
SELECT NVL2 (col1,1,2) from test1;
drop table test1;

--字符类型：
--1.varchar:
create table test1(col1 varchar(10),col2  int);
insert into test1 values('sales',1);
SELECT  NVL2 (col1,1::text,2::text) from test1;
drop table test1;
--2.char:
create table test1(col1 char(10),col2  int);
insert into test1 values('sales',1);
SELECT  NVL2 (col1,1::text,2::text) from test1;
drop table test1;
--3.text:
create table test1(col1 text,col2  int);
insert into test1 values('sales',1);
SELECT  NVL2 (col1,1::text,2::text) from test1;
drop table test1;

--二进制数据类型:
create table test1(col1 bytea,col2  int);
insert into test1 values(E'\\001',1);
SELECT NVL2 (col1, 1,2) from test1;
drop table test1;

--日期/时间类型：
--1.timestamp:
create table test1(col1 timestamp,col2  int);
insert into test1 values('1999-1-5',1);
SELECT NVL2 (col1, 1,2) from test1;
drop table test1;
--2.timestamp with time zone:
create table test1(col1 timestamp with time zone,col2  int);
insert into test1 values('1999-1-5 8:00:00',1);
SELECT NVL2 (col1, 1,2) from test1;
drop table test1;
--3.date:
create table test1(col1 date,col2  int);
insert into test1 values('1999-01-05',1);
SELECT NVL2 (col1, 1,2) from test1;
drop table test1;
--4.time:
create table test1(col1 time,col2  int);
insert into test1 values('14:12:50',1);
SELECT NVL2 (col1, 1,2) from test1;
drop table test1;
--5.time with time zone:
create table test1(col1 time with time zone,col2  int);
insert into test1 values('14:12:50-8',1);
SELECT NVL2 (col1, 1,2) from test1;
drop table test1;
--6.interval:
create table test1(col1 interval year to month,col2  int);
insert into test1 values('1-2',1);
SELECT NVL2 (col1, 1,2) from test1;
drop table test1;

--布尔类型:
--boolean:
create table test1(col1 boolean,col2  int);
insert into test1 values(true,1);
SELECT NVL2 (col1, 1,2) from test1;
drop table test1;

--枚举类型：
CREATE TYPE mood AS ENUM ('sad', 'ok', 'happy');
CREATE TABLE person_test (
    name text,
    current_mood mood
);
INSERT INTO person_test VALUES ('Moe', 'happy');
SELECT NVL2( current_mood, 1,2) from person_test;
drop table person_test;
drop type mood;

--几何类型：
--1.point:
create table test1(col1 point,col2  int);
insert into test1 values(point(5,8),1);
SELECT NVL2 (col1, 1,2) from test1;
drop table test1;
--2.line:
create table test1(col1 line,col2  int);
insert into test1 values(line(point '(-1,0)', point '(1,0)'),1);
SELECT NVL2 (col1, 1,2) from test1;
drop table test1;
--3.lseg:
create table test1(col1 lseg,col2  int);
insert into test1 values(lseg(box '((-1,0),(1,0))'),1);
SELECT NVL2 (col1, 1,2) from test1;
drop table test1;
--4.box:
create table test1(col1 box,col2  int);
insert into test1 values(box(point '(0,0)', point '(1,1)'),1);
SELECT NVL2 (col1, 1,2) from test1;
drop table test1;
--5.path:
create table test1(col1 path,col2  int);
insert into test1 values(path(polygon '((0,0),(1,1),(2,0))'),1);
SELECT NVL2 (col1, 1,2) from test1;
drop table test1;
--6.polygon:
create table test1(col1 polygon,col2  int);
insert into test1 values(polygon(box '((0,0),(1,1))'),1);
SELECT NVL2 (col1, 1,2) from test1;
drop table test1;
--7.circle:
create table test1(col1 circle,col2  int);
insert into test1 values(circle(point '(0,0)', 2.0),1);
SELECT NVL2 (col1, 1,2) from test1;
drop table test1;

--网络地址类型：
--1.cidr:
create table test1(col1 cidr,col2  int);
insert into test1 values('192.168.100.128/25',1);
SELECT NVL2 (col1, 1,2) from test1;
drop table test1;
--2.inet:
create table test1(col1 inet,col2  int);
insert into test1 values('192.168.100.128/25',1);
SELECT NVL2 (col1, 1,2) from test1;
drop table test1;
--3.macaddr:
create table test1(col1 macaddr,col2  int);
insert into test1 values('08:00:2b:01:02:03',1);
SELECT NVL2 (col1, 1,2) from test1;
drop table test1;

--位串类型：
--1.bit(n):
create table test1(col1 bit(3),col2  int);
insert into test1 values(B'101',1);
SELECT NVL2 (col1, 1,2) from test1;
drop table test1;
--2.bit varying(n):
create table test1(col1 bit varying(5),col2  int);
insert into test1 values(B'00',1);
SELECT NVL2 (col1, 1,2) from test1;
drop table test1;

--文本搜索类型：
--1.tsvector：
create table test1(col1 tsvector,col2  int);
insert into test1 values(to_tsvector('english', 'The Fat Rats'),1);
SELECT NVL2 (col1, 1,2) from test1;
drop table test1;
--2.tsquery：
create table test1(col1 tsquery,col2  int);
insert into test1 values(to_tsquery('Fat:ab & Cats'),1);
SELECT NVL2 (col1, 1,2) from test1;
drop table test1;

--UUID类型：
create table test1(col1 UUID,col2  int);
insert into test1 values('a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11',1);
SELECT NVL2 (col1, 1,2) from test1;
drop table test1;

--JSON类型：
create table test1(col1 JSON,col2  int);
insert into test1 values('5'::json,1);
SELECT NVL2 (col1, 1,2) from test1;
drop table test1;

--Arrays:
create table test1(col1 int[],col2  int);
insert into test1 values(array[5,6],1);
SELECT NVL2 (col1, 1,2) from test1;
drop table test1;

--参数expr2为任意数据类型
--数值类型：
--1.smallint:
create table test1(col1 smallint,col2  int);
insert into test1 values(23,1);
SELECT NVL2 ('sales',col1, NULL) from test1;
drop table test1;
--2.integer:
create table test1(col1 int,col2  int);
insert into test1 values(23,1);
SELECT NVL2 ('sales',col1, NULL) from test1;
drop table test1;
--3.bigint:
create table test1(col1 bigint,col2  int);
insert into test1 values(23,1);
SELECT NVL2 ('sales',col1, NULL) from test1;
drop table test1;
--4.decimal:
create table test1(col1 decimal,col2  int);
insert into test1 values(23,1);
SELECT NVL2 ('sales',col1, NULL)from test1;
drop table test1;
--5.numeric:
create table test1(col1 numeric(5,2),col2  int);
insert into test1 values(23.225,1);
SELECT NVL2 ('sales',col1, NULL) from test1;
drop table test1;
--6.real:
create table test1(col1 real,col2  int);
insert into test1 values(23.225,1);
SELECT NVL2 ('sales',col1, NULL) from test1;
drop table test1;
--7.double precision:
create table test1(col1 double precision,col2  int);
insert into test1 values(23.225,1);
SELECT NVL2 ('sales',col1, NULL) from test1;
drop table test1;
--8.smallserial;
create table test1(col1 smallserial,col2  int);
insert into test1 values(23,1);
SELECT NVL2 ('sales',col1, NULL) from test1;
drop table test1;
--9.serial:
create table test1(col1 serial,col2  int);
insert into test1 values(23,1);
SELECT NVL2 ('sales',col1, NULL)from test1;
drop table test1;
--10.bigserial:
create table test1(col1 bigserial,col2  int);
insert into test1 values(23,1);
SELECT NVL2 ('sales',col1, NULL) from test1;
drop table test1;

--货币类型：
--money：
create table test1(col1 money,col2  int);
insert into test1 values(23,1);
SELECT NVL2 ('sales',col1, NULL) from test1;
drop table test1;

--字符类型：
--1.varchar:
create table test1(col1 varchar(10),col2  int);
insert into test1 values('sales',1);
SELECT NVL2 ('sales',col1, NULL) from test1;
drop table test1;
--2.char:
create table test1(col1 char(10),col2  int);
insert into test1 values('sales',1);
SELECT NVL2 ('sales',col1, NULL) from test1;
drop table test1;
--3.text:
create table test1(col1 text,col2  int);
insert into test1 values('sales',1);
SELECT NVL2 ('sales',col1, NULL)from test1;
drop table test1;

--二进制数据类型:
create table test1(col1 bytea,col2  int);
insert into test1 values(E'\\001',1);
SELECT NVL2 ('sales',col1, NULL) from test1;
drop table test1;

--日期/时间类型：
--1.timestamp:
create table test1(col1 timestamp,col2  int);
insert into test1 values('1999-1-5',1);
SELECT NVL2 ('sales',col1, NULL) from test1;
drop table test1;
--2.timestamp with time zone:
create table test1(col1 timestamp with time zone,col2  int);
insert into test1 values('1999-1-5 8:00:00',1);
SELECT NVL2 ('sales',col1, NULL) from test1;
drop table test1;
--3.date:
create table test1(col1 date,col2  int);
insert into test1 values('1999-01-05',1);
SELECT NVL2 ('sales',col1, NULL) from test1;
drop table test1;
--4.time:
create table test1(col1 time,col2  int);
insert into test1 values('14:12:50',1);
SELECT NVL2 ('sales',col1, NULL)from test1;
drop table test1;
--5.time with time zone:
create table test1(col1 time with time zone,col2  int);
insert into test1 values('14:12:50-8',1);
SELECT NVL2 ('sales',col1, NULL) from test1;
drop table test1;
--6.interval:
create table test1(col1 interval year to month,col2  int);
insert into test1 values('1-2',1);
SELECT NVL2 ('sales',col1, NULL) from test1;
drop table test1;

--布尔类型：
--boolean:
create table test1(col1 boolean,col2  int);
insert into test1 values(true,1);
SELECT NVL2 ('sales',col1, NULL) from test1;
drop table test1;

--枚举类型：
CREATE TYPE mood AS ENUM ('sad', 'ok', 'happy');
CREATE TABLE person_test (
    name text,
    current_mood mood
);
INSERT INTO person_test VALUES ('Moe', 'happy');
SELECT NVL2 ( 'sales',current_mood, NULL) from person_test;
drop table person_test;
drop type mood;

--几何类型：
--1.point:
create table test1(col1 point,col2  int);
insert into test1 values(point(5,8),1);
SELECT NVL2 ('sales',col1, NULL) from test1;
drop table test1;
--2.line:
create table test1(col1 line,col2  int);
insert into test1 values(line(point '(-1,0)', point '(1,0)'),1);
SELECT NVL2 ('sales',col1, NULL) from test1;
drop table test1;
--3.lseg:
create table test1(col1 lseg,col2  int);
insert into test1 values(lseg(box '((-1,0),(1,0))'),1);
SELECT NVL2 ('sales',col1, NULL) from test1;
drop table test1;
--4.box:
create table test1(col1 box,col2  int);
insert into test1 values(box(point '(0,0)', point '(1,1)'),1);
SELECT NVL2 ('sales',col1, NULL)from test1;
drop table test1;
--5.path:
create table test1(col1 path,col2  int);
insert into test1 values(path(polygon '((0,0),(1,1),(2,0))'),1);
SELECT NVL2 ('sales',col1, NULL)from test1;
drop table test1;
--6.polygon:
create table test1(col1 polygon,col2  int);
insert into test1 values(polygon(box '((0,0),(1,1))'),1);
SELECT NVL2 ('sales',col1, NULL) from test1;
drop table test1;
--7.circle:
create table test1(col1 circle,col2  int);
insert into test1 values(circle(point '(0,0)', 2.0),1);
SELECT NVL2 ('sales',col1, NULL)from test1;
drop table test1;

--网络地址类型：
--1.cidr:
create table test1(col1 cidr,col2  int);
insert into test1 values('192.168.100.128/25',1);
SELECT NVL2 ('sales',col1, NULL) from test1;
drop table test1;
--2.inet:
create table test1(col1 inet,col2  int);
insert into test1 values('192.168.100.128/25',1);
SELECT NVL2 ('sales',col1, NULL) from test1;
drop table test1;
--3.macaddr:
create table test1(col1 macaddr,col2  int);
insert into test1 values('08:00:2b:01:02:03',1);
SELECT NVL2 ('sales',col1, NULL) from test1;
drop table test1;

--位串类型：
--1.bit(n):
create table test1(col1 bit(3),col2  int);
insert into test1 values(B'101',1);
SELECT NVL2 ('sales',col1, NULL) from test1;
drop table test1;
--2.bit varying(n):
create table test1(col1 bit varying(5),col2  int);
insert into test1 values(B'00',1);
SELECT NVL2 ('sales',col1, NULL) from test1;
drop table test1;

--文本搜索类型：
--1.tsvector：
create table test1(col1 tsvector,col2  int);
insert into test1 values(to_tsvector('english', 'The Fat Rats'),1);
SELECT NVL2 ('sales',col1, NULL) from test1;
drop table test1;
--2.tsquery：
create table test1(col1 tsquery,col2  int);
insert into test1 values(to_tsquery('Fat:ab & Cats'),1);
SELECT NVL2 ('sales',col1, NULL) from test1;
drop table test1;

--UUID类型：
create table test1(col1 UUID,col2  int);
insert into test1 values('a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11',1);
SELECT NVL2 ('sales',col1, NULL) from test1;
drop table test1;

--JSON类型：
create table test1(col1 JSON,col2  int);
insert into test1 values('5'::json,1);
SELECT NVL2 ('sales',col1, NULL) from test1;
drop table test1;

--Arrays:
create table test1(col1 int[],col2  int);
insert into test1 values(array[5,6],1);
SELECT NVL2 ('sales',col1, NULL) from test1;
drop table test1;

--参数expr3为任意数据类型
--数值类型：
--1.smallint:
create table test1(col1 smallint,col2  int);
insert into test1 values(23,1);
SELECT NVL2 (NULL,1, col1) from test1;
drop table test1;
--2.integer:
create table test1(col1 int,col2  int);
insert into test1 values(23,1);
SELECT NVL2 (NULL,1, col1) from test1;
drop table test1;
--3.bigint:
create table test1(col1 bigint,col2  int);
insert into test1 values(23,1);
SELECT NVL2 (NULL,1, col1) from test1;
drop table test1;
--4.decimal:
create table test1(col1 decimal,col2  int);
insert into test1 values(23,1);
SELECT NVL2 (NULL,1, col1)from test1;
drop table test1;
--5.numeric:
create table test1(col1 numeric(5,2),col2  int);
insert into test1 values(23.225,1);
SELECT NVL2 (NULL,1, col1) from test1;
drop table test1;
--6.real:
create table test1(col1 real,col2  int);
insert into test1 values(23.225,1);
SELECT NVL2 (NULL,1, col1) from test1;
drop table test1;
--7.double precision:
create table test1(col1 double precision,col2  int);
insert into test1 values(23.225,1);
SELECT NVL2 (NULL,1, col1) from test1;
drop table test1;
--8.smallserial;
create table test1(col1 smallserial,col2  int);
insert into test1 values(23,1);
SELECT NVL2 (NULL,1, col1) from test1;
drop table test1;
--9.serial:
create table test1(col1 serial,col2  int);
insert into test1 values(23,1);
SELECT NVL2 (NULL,1, col1)from test1;
drop table test1;
--10.bigserial:
create table test1(col1 bigserial,col2  int);
insert into test1 values(23,1);
SELECT NVL2 (NULL,1, col1) from test1;
drop table test1;

--货币类型：
--money：
create table test1(col1 money,col2  int);
insert into test1 values(23,1);
SELECT NVL2 (NULL,1, col1) from test1;
drop table test1;

--字符类型：
--1.varchar:
create table test1(col1 varchar(10),col2  int);
insert into test1 values('sales',1);
SELECT NVL2 (NULL,1, col1) from test1;
drop table test1;
--2.char:
create table test1(col1 char(10),col2  int);
insert into test1 values('sales',1);
SELECT NVL2 (NULL,1, col1) from test1;
drop table test1;
--3.text:
create table test1(col1 text,col2  int);
insert into test1 values('sales',1);
SELECT NVL2 (NULL,1, col1)from test1;
drop table test1;

--二进制数据类型:
create table test1(col1 bytea,col2  int);
insert into test1 values(E'\\001',1);
SELECT NVL2 (NULL,1, col1) from test1;
drop table test1;

--日期/时间类型：
--1.timestamp:
create table test1(col1 timestamp,col2  int);
insert into test1 values('1999-1-5',1);
SELECT NVL2 (NULL,1, col1) from test1;
drop table test1;
--2.timestamp with time zone:
create table test1(col1 timestamp with time zone,col2  int);
insert into test1 values('1999-1-5 8:00:00',1);
SELECT NVL2 (NULL,1, col1) from test1;
drop table test1;
--3.date:
create table test1(col1 date,col2  int);
insert into test1 values('1999-01-05',1);
SELECT NVL2 (NULL,1, col1)from test1;
drop table test1;
--4.time:
create table test1(col1 time,col2  int);
insert into test1 values('14:12:50',1);
SELECT NVL2 (NULL,1, col1)from test1;
drop table test1;
--5.time with time zone:
create table test1(col1 time with time zone,col2  int);
insert into test1 values('14:12:50-8',1);
SELECT NVL2 (NULL,1, col1) from test1;
drop table test1;
--6.interval:
create table test1(col1 interval year to month,col2  int);
insert into test1 values('1-2',1);
SELECT NVL2 (NULL,1, col1) from test1;
drop table test1;

--布尔类型：
--boolean:
create table test1(col1 boolean,col2  int);
insert into test1 values(true,1);
SELECT NVL2 (NULL,1, col1) from test1;
drop table test1;

--枚举类型：
CREATE TYPE mood AS ENUM ('sad', 'ok', 'happy');
CREATE TABLE person_test (
    name text,
    current_mood mood
);
INSERT INTO person_test VALUES ('Moe', 'happy');
SELECT NVL2 ( NULL,NULL,current_mood) from person_test;
drop table person_test;
drop type mood;

--几何类型：
--1.point:
create table test1(col1 point,col2  int);
insert into test1 values(point(5,8),1);
SELECT NVL2 (NULL,1, col1) from test1;
drop table test1;
--2.line:
create table test1(col1 line,col2  int);
insert into test1 values(line(point '(-1,0)', point '(1,0)'),1);
SELECT NVL2 (NULL,1, col1) from test1;
drop table test1;
--3.lseg:
create table test1(col1 lseg,col2  int);
insert into test1 values(lseg(box '((-1,0),(1,0))'),1);
SELECT NVL2 (NULL,1, col1)from test1;
drop table test1;
--4.box:
create table test1(col1 box,col2  int);
insert into test1 values(box(point '(0,0)', point '(1,1)'),1);
SELECT NVL2 (NULL,1, col1)from test1;
drop table test1;
--5.path:
create table test1(col1 path,col2  int);
insert into test1 values(path(polygon '((0,0),(1,1),(2,0))'),1);
SELECT NVL2 (NULL,1, col1)from test1;
drop table test1;
--6.polygon:
create table test1(col1 polygon,col2  int);
insert into test1 values(polygon(box '((0,0),(1,1))'),1);
SELECT NVL2 (NULL,1, col1) from test1;
drop table test1;
--7.circle:
create table test1(col1 circle,col2  int);
insert into test1 values(circle(point '(0,0)', 2.0),1);
SELECT NVL2 (NULL,1, col1)from test1;
drop table test1;

--网络地址类型：
--1.cidr:
create table test1(col1 cidr,col2  int);
insert into test1 values('192.168.100.128/25',1);
SELECT NVL2 (NULL,1, col1)from test1;
drop table test1;
--2.inet:
create table test1(col1 inet,col2  int);
insert into test1 values('192.168.100.128/25',1);
SELECT NVL2 (NULL,1, col1) from test1;
drop table test1;
--3.macaddr:
create table test1(col1 macaddr,col2  int);
insert into test1 values('08:00:2b:01:02:03',1);
SELECT NVL2 (NULL,1, col1) from test1;
drop table test1;

--位串类型：
--1.bit(n):
create table test1(col1 bit(3),col2  int);
insert into test1 values(B'101',1);
SELECT NVL2 (NULL,1, col1)from test1;
drop table test1;
--2.bit varying(n):
create table test1(col1 bit varying(5),col2  int);
insert into test1 values(B'00',1);
SELECT NVL2 (NULL,1, col1) from test1;
drop table test1;

--文本搜索类型：
--1.tsvector：
create table test1(col1 tsvector,col2  int);
insert into test1 values(to_tsvector('english', 'The Fat Rats'),1);
SELECT NVL2 (NULL,1, col1) from test1;
drop table test1;
--2.tsquery：
create table test1(col1 tsquery,col2  int);
insert into test1 values(to_tsquery('Fat:ab & Cats'),1);
SELECT NVL2 (NULL,1, col1) from test1;
drop table test1;

--UUID类型：
create table test1(col1 UUID,col2  int);
insert into test1 values('a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11',1);
SELECT NVL2 (NULL,1, col1)from test1;
drop table test1;

--JSON类型：
create table test1(col1 JSON,col2  int);
insert into test1 values('5'::json,1);
SELECT NVL2 (NULL,1, col1)from test1;
drop table test1;

--Arrays:
create table test1(col1 int[],col2  int);
insert into test1 values(array[5,6],1);
SELECT NVL2 (NULL,1, col1)from test1;
drop table test1;

--expr1/expr2/expr3输入非法
--1.expr1输入非法字符：
SELECT NVL2 (@@, 1,2);--报错
SELECT NVL2 ($#!, 1,2);--报错
--2.expr2输入非法字符：
SELECT NVL2 (1, ￥%*&,2);--报错
SELECT NVL2 (1, ()$!~,2);--报错
--3.expr3输入非法字符：
SELECT NVL2 (NULL,1, ￥%*&);--报错
SELECT NVL2 (NULL,1, ()$!~);--报错


--
--DECODE
--

--expr非空
select decode(2,1,'south',2,'north','east');
select decode(3,1,'south',2,'north');
select decode(3,1,'south',2,'north','east');

--expr为空
select decode(NULL,1,'south',2,'north',null,'west',null,'east');
select decode(NULL,1,'south',2,'north');
select decode(NULL,1,'south',2,'north','west');

--参数非法
select decode(NULL,1);--报错
select decode();--报错

--参数个数>3，<255
select decode(5,1,'south',2,'north',null,'west',null,'east',4,'beijing',5,'changsha');

--参数个数>255
select decode(256,1,'test1',
2,'test2',
3,'test3',
4,'test4',
5,'test5',
6,'test6',
7,'test7',
8,'test8',
9,'test9',
10,'test10',
11,'test11',
12,'test12',
13,'test13',
14,'test14',
15,'test15',
16,'test16',
17,'test17',
18,'test18',
19,'test19',
20,'test20',
21,'test21',
22,'test22',
23,'test23',
24,'test24',
25,'test25',
26,'test26',
27,'test27',
28,'test28',
29,'test29',
30,'test30',
31,'test31',
32,'test32',
33,'test33',
34,'test34',
35,'test35',
36,'test36',
37,'test37',
38,'test38',
39,'test39',
40,'test40',
41,'test41',
42,'test42',
43,'test43',
44,'test44',
45,'test45',
46,'test46',
47,'test47',
48,'test48',
49,'test49',
50,'test50',
51,'test51',
52,'test52',
53,'test53',
54,'test54',
55,'test55',
56,'test56',
57,'test57',
58,'test58',
59,'test59',
60,'test60',
61,'test61',
62,'test62',
63,'test63',
64,'test64',
65,'test65',
66,'test66',
67,'test67',
68,'test68',
69,'test69',
70,'test70',
71,'test71',
72,'test72',
73,'test73',
74,'test74',
75,'test75',
76,'test76',
77,'test77',
78,'test78',
79,'test79',
80,'test80',
81,'test81',
82,'test82',
83,'test83',
84,'test84',
85,'test85',
86,'test86',
87,'test87',
88,'test88',
89,'test89',
90,'test90',
91,'test91',
92,'test92',
93,'test93',
94,'test94',
95,'test95',
96,'test96',
97,'test97',
98,'test98',
99,'test99',
100,'test100',
101,'test101',
102,'test102',
103,'test103',
104,'test104',
105,'test105',
106,'test106',
107,'test107',
108,'test108',
109,'test109',
110,'test110',
111,'test111',
112,'test112',
113,'test113',
114,'test114',
115,'test115',
116,'test116',
117,'test117',
118,'test118',
119,'test119',
120,'test120',
121,'test121',
122,'test122',
123,'test123',
124,'test124',
125,'test125',
126,'test126',
127,'test127',
128,'test128',
129,'test129',
130,'test130',
131,'test131',
132,'test132',
133,'test133',
134,'test134',
135,'test135',
136,'test136',
137,'test137',
138,'test138',
139,'test139',
140,'test140',
141,'test141',
142,'test142',
143,'test143',
144,'test144',
145,'test145',
146,'test146',
147,'test147',
148,'test148',
149,'test149',
150,'test150',
151,'test151',
152,'test152',
153,'test153',
154,'test154',
155,'test155',
156,'test156',
157,'test157',
158,'test158',
159,'test159',
160,'test160',
161,'test161',
162,'test162',
163,'test163',
164,'test164',
165,'test165',
166,'test166',
167,'test167',
168,'test168',
169,'test169',
170,'test170',
171,'test171',
172,'test172',
173,'test173',
174,'test174',
175,'test175',
176,'test176',
177,'test177',
178,'test178',
179,'test179',
180,'test180',
181,'test181',
182,'test182',
183,'test183',
184,'test184',
185,'test185',
186,'test186',
187,'test187',
188,'test188',
189,'test189',
190,'test190',
191,'test191',
192,'test192',
193,'test193',
194,'test194',
195,'test195',
196,'test196',
197,'test197',
198,'test198',
199,'test199',
200,'test200',
201,'test201',
202,'test202',
203,'test203',
204,'test204',
205,'test205',
206,'test206',
207,'test207',
208,'test208',
209,'test209',
210,'test210',
211,'test211',
212,'test212',
213,'test213',
214,'test214',
215,'test215',
216,'test216',
217,'test217',
218,'test218',
219,'test219',
220,'test220',
221,'test221',
222,'test222',
223,'test223',
224,'test224',
225,'test225',
226,'test226',
227,'test227',
228,'test228',
229,'test229',
230,'test230',
231,'test231',
232,'test232',
233,'test233',
234,'test234',
235,'test235',
236,'test236',
237,'test237',
238,'test238',
239,'test239',
240,'test240',
241,'test241',
242,'test242',
243,'test243',
244,'test244',
245,'test245',
246,'test246',
247,'test247',
248,'test248',
249,'test249',
250,'test250',
251,'test251',
252,'test252',253,'test253',254,'test254',255,'test255',256,'test256');

--数据类型非法
--1.expr值输入非法值：
select decode(@$￥,1,'south',2,'north',4,'changsha');--报错
--2.search输入非法值：
select decode(5,%^*&,'south',2,'north',4,'changsha');--报错
--3.result输入非法值：
select decode(5,1,'south',2,'north',3,&%￥#,4,'changsha');--报错

--参数expr为任意数据类型，且expr和search类型一致
--数值类型：
--1.smallint:
create table test1(col1 smallint,col2  int);
insert into test1 values(23,1);
SELECT decode (col1, 20,NULL,23,'sales') from test1;
drop table test1;
--2.integer:
create table test1(col1 int,col2  int);
insert into test1 values(23,1);
SELECT decode (col1, 20,NULL,23,'sales') from test1;
drop table test1;
--3.bigint:
create table test1(col1 bigint,col2  int);
insert into test1 values(23,1);
SELECT decode (col1, 20,NULL,23,'sales') from test1;
drop table test1;
--4.decimal:
create table test1(col1 decimal,col2  int);
insert into test1 values(23,1);
SELECT decode (col1, 20,NULL,23,'sales') from test1;
drop table test1;
--5.numeric:
create table test1(col1 numeric(5,2),col2  int);
insert into test1 values(23.225,1);
SELECT decode (col1, 20,NULL,23,'sales') from test1;
drop table test1;
--6.real:
create table test1(col1 real,col2  int);
insert into test1 values(23.225,1);
SELECT decode (col1, 20,NULL,23,'sales') from test1;
drop table test1;
--7.double precision:
create table test1(col1 double precision,col2  int);
insert into test1 values(23.225,1);
SELECT decode (col1, 20,NULL,23,'sales') from test1;
drop table test1;
--8.smallserial:
create table test1(col1 smallserial,col2  int);
insert into test1 values(23,1);
SELECT decode (col1, 20,NULL,23,'sales')  from test1;
drop table test1;
--9.serial:
create table test1(col1 serial,col2  int);
insert into test1 values(23,1);
SELECT decode (col1, 20,NULL,23,'sales') from test1;
drop table test1;
--10.bigserial:
create table test1(col1 bigserial,col2  int);
insert into test1 values(23,1);
SELECT decode (col1, 20,NULL,23,'sales')  from test1;
drop table test1;

--字符类型：
--1.varchar:
create table test1(col1 varchar(10),col2  int);
insert into test1 values('sales',1);
SELECT decode (col1,NULL,0,'sales',7000) from test1;
drop table test1;
--2.char:
create table test1(col1 char(10),col2  int);
insert into test1 values('sales',1);
SELECT decode(col1,NULL,0,'sales',7000)from test1;
drop table test1;
--3.text:
create table test1(col1 text,col2  int);
insert into test1 values('sales',1);
SELECT decode (col1,NULL,0,'sales',7000)from test1;
drop table test1;

--货币类型：
create table test1(col1 money,col2  int);
insert into test1 values(8000,1);
SELECT decode (col1,NULL,0,8000::money,7000) from test1;  
drop table test1;

--二进制数据类型:
create table test1(col1 bytea,col2  int);
insert into test1 values(E'\\001',1);
SELECT decode (col1,NULL,0,E'\\001',7000) from test1;
drop table test1;

--日期/时间类型:
--1.timestamp:
create table test1(col1 timestamp,col2  int);
insert into test1 values('1999-1-5 00:00:00',1);
SELECT decode (col1,NULL,0,'1999-1-5',7000)from test1;  
drop table test1;
--2.timestamp with time zone:
create table test1(col1 timestamp with time zone,col2  int);
insert into test1 values('1999-1-5 8:00:00',1);
SELECT decode (col1,NULL,0,'1999-1-5 8:00:00',7000)from test1;  
drop table test1;
--3.date:
create table test1(col1 date,col2  int);
insert into test1 values('1999-01-05',1);
SELECT decode (col1,NULL,0,'1999-01-05',7000)from test1;  
drop table test1;
--4.time:
create table test1(col1 time,col2  int);
insert into test1 values('14:12:50',1);
SELECT decode (col1,NULL,0,'14:12:50',7000)from test1;  
drop table test1;
--5.time with time zone:
create table test1(col1 time with time zone,col2  int);
insert into test1 values('14:12:50-8',1);
SELECT decode (col1,NULL,0,'14:12:50-8',7000)from test1; 
drop table test1;
--6.interval:
create table test1(col1 interval year to month,col2  int);
insert into test1 values('1-2',1);
SELECT decode (col1,NULL,0,'1-2',7000)from test1; 
drop table test1;

--布尔类型：
--boolean:
create table test1(col1 boolean,col2  int);
insert into test1 values(true,1);
SELECT decode (col1,NULL,0,true,7000)from test1;    
drop table test1;

--枚举类型：
CREATE TYPE mood AS ENUM ('sad', 'ok', 'happy');
CREATE TABLE person_test (
    name text,
    current_mood mood
);
INSERT INTO person_test VALUES ('Moe', 'happy');
SELECT decode (current_mood,NULL,0,'happy',7000)from person_test; 
drop table person_test;
drop type mood;

--几何类型：
--1.point，不支持
create table test1(col1 point,col2  int);
insert into test1 values(point'(5,8)',1);
SELECT decode (col1,NULL,0,point'(5,8)',7000)from test1;--报错 
drop table test1;
--2.line:
create table test1(col1 line,col2  int);
insert into test1 values(line(point '(-1,0)', point '(1,0)'),1);
SELECT decode (col1,NULL,0,line(point '(-1,0)', point '(1,0)'),7000)from test1;     
drop table test1;
--3.lseg:
create table test1(col1 lseg,col2  int);
insert into test1 values(lseg(box '((-1,0),(1,0))'),1);
SELECT decode (col1,NULL,0,lseg(box '((-1,0),(1,0))'),7000)from test1;   
drop table test1;
--4.box:
create table test1(col1 box,col2  int);
insert into test1 values(box(point '(0,0)', point '(1,1)'),1);
SELECT decode (col1,NULL,0,box(point '(0,0)', point '(1,1)'),7000)from test1;    
drop table test1;
--5.path:
create table test1(col1 path,col2  int);
insert into test1 values(path(polygon '((0,0),(1,1),(2,0))'),1);
SELECT decode (col1,NULL,0,path(polygon '((0,0),(1,1),(2,0))'),7000)from test1;   
drop table test1;
--6.polygon，不支持
create table test1(col1 polygon,col2  int);
insert into test1 values(polygon(box '((0,0),(1,1))'),1);
SELECT decode (col1,NULL,0,polygon(box '((0,0),(1,1))'),7000)from test1;--报错  
drop table test1;
--7.circle:
create table test1(col1 circle,col2  int);
insert into test1 values(circle(point '(0,0)', 2.0),1);
SELECT decode (col1,NULL,0,circle(point '(0,0)', 2.0),7000)from test1;   
drop table test1;

--网络地址类型：
--1.cidr:
create table test1(col1 cidr,col2  int);
insert into test1 values('192.168.100.128/25',1);
SELECT decode (col1,NULL,0,'192.168.100.128/25',7000)from test1; 
drop table test1;
--2.inet:
create table test1(col1 inet,col2  int);
insert into test1 values('192.168.100.128/25',1);
SELECT decode (col1,NULL,0,'192.168.100.128/25',7000)from test1;    
drop table test1;
--3.macaddr:
create table test1(col1 macaddr,col2  int);
insert into test1 values('08:00:2b:01:02:03',1);
SELECT decode (col1,NULL,0,'08:00:2b:01:02:03',7000)from test1;  
drop table test1;

--位串类型：
--1.bit(n):
create table test1(col1 bit(3),col2  int);
insert into test1 values(B'101',1);
SELECT decode (col1,NULL,0,B'101',7000)from test1;    
drop table test1;
--2.bit varying(n):
create table test1(col1 bit varying(5),col2  int);
insert into test1 values(B'00',1);
SELECT decode (col1,NULL,0,B'00',7000)from test1;     
drop table test1;

--文本搜索类型：
--1.tsvector：
create table test1(col1 tsvector,col2  int);
insert into test1 values(to_tsvector('english', 'The Fat Rats'),1);
SELECT decode (col1,NULL,0,to_tsvector('english', 'The Fat Rats'),7000)from test1;     
drop table test1;
--2.tsquery：
create table test1(col1 tsquery,col2  int);
insert into test1 values(to_tsquery('Fat:ab & Cats'),1);
SELECT decode (col1,NULL,0,to_tsquery('Fat:ab & Cats'),7000)from test1; 
drop table test1;

--UUID类型：
create table test1(col1 UUID,col2  int);
insert into test1 values('a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11',1);
SELECT decode (col1,NULL,0,'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11',7000)from test1;  
drop table test1;

--JSON类型，不支持
create table test1(col1 JSON,col2  int);
insert into test1 values('5'::json,1);
SELECT decode (col1,NULL,0,'5'::json,7000)from test1;--报错
drop table test1;

--Arrays:
create table test1(col1 int[],col2  int);
insert into test1 values(array[5,6],1);
SELECT decode (col1,NULL,0,array[5,6],7000)from test1; 
drop table test1;

--参数search为任意数据类型，且expr和search类型一致
--数值类型：
--1.smallint:
create table test1(col1 smallint,col2  int);
insert into test1 values(23,1);
SELECT decode (23, 20,NULL,col1,'sales') from test1;
drop table test1;
--2.integer:
create table test1(col1 int,col2  int);
insert into test1 values(23,1);
SELECT decode (23, 20,NULL,col1,'sales')  from test1;
drop table test1;
--3.bigint:
create table test1(col1 bigint,col2  int);
insert into test1 values(23,1);
SELECT decode (23, 20,NULL,col1,'sales')  from test1;
drop table test1;
--4.decimal:
create table test1(col1 decimal,col2  int);
insert into test1 values(23,1);
SELECT decode (23, 20,NULL,col1,'sales') from test1;
drop table test1;
--5.numeric:
create table test1(col1 numeric(5,2),col2  int);
insert into test1 values(23.225,1);
SELECT decode (23, 20,NULL,col1,'sales')  from test1;
drop table test1;
--6.real:
create table test1(col1 real,col2  int);
insert into test1 values(23.225,1);
SELECT decode (23, 20,NULL,col1,'sales')  from test1;
drop table test1;
--7.double precision:
create table test1(col1 double precision,col2  int);
insert into test1 values(23.225,1);
SELECT decode (23, 20,NULL,col1,'sales')  from test1;
drop table test1;
--8.smallserial;
create table test1(col1 smallserial,col2  int);
insert into test1 values(23,1);
SELECT decode (23, 20,NULL,col1,'sales')  from test1;
drop table test1;
--9.serial:
create table test1(col1 serial,col2  int);
insert into test1 values(23,1);
SELECT decode (23, 20,NULL,col1,'sales')  from test1;
drop table test1;
--10.bigserial:
create table test1(col1 bigserial,col2  int);
insert into test1 values(23,1);
SELECT decode (23, 20,NULL,col1,'sales')  from test1;
drop table test1;

--字符类型：
--1.varchar:
create table test1(col1 varchar(10),col2  int);
insert into test1 values('sales',1);
SELECT decode ('sales',NULL,0,col1,7000) from test1;
drop table test1;
--2.char:
create table test1(col1 char(10),col2  int);
insert into test1 values('sales',1);
SELECT decode ('sales',NULL,0,col1,7000) from test1;
drop table test1;
--3.text:
create table test1(col1 text,col2  int);
insert into test1 values('sales',1);
SELECT decode ('sales',NULL,0,col1,7000) from test1;
drop table test1;

--货币类型：
create table test1(col1 money,col2  int);
insert into test1 values(8000,1);
SELECT decode (8000::money,NULL,0,col1,7000) from test1; 
drop table test1;

--二进制数据类型:
create table test1(col1 bytea,col2  int);
insert into test1 values(E'\\001',1);
SELECT decode (E'\\001',NULL,0,col1,7000) from test1; 
drop table test1;

--日期/时间类型:
--1.timestamp:
create table test1(col1 timestamp,col2  int);
insert into test1 values('1999-1-5 00:00:00',1);
SELECT decode ('1999-1-5',NULL,0,col1,7000)from test1;  
drop table test1;
--2.timestamp with time zone:
create table test1(col1 timestamp with time zone,col2  int);
insert into test1 values('1999-1-5 8:00:00',1);
SELECT decode ('1999-1-5 8:00:00',NULL,0,col1,7000)from test1; 
drop table test1;
--3.date:
create table test1(col1 date,col2  int);
insert into test1 values('1999-01-05',1);
SELECT decode ('1999-01-05',NULL,0,col1,7000)from test1; 
drop table test1;
--4.time:
create table test1(col1 time,col2  int);
insert into test1 values('14:12:50',1);
SELECT decode ('14:12:50',NULL,0,col1,7000)from test1;  
drop table test1;
--5.time with time zone:
create table test1(col1 time with time zone,col2  int);
insert into test1 values('14:12:50-8',1);
SELECT decode ('14:12:50-8',NULL,0,col1,7000)from test1; 
drop table test1;
--6.interval:
create table test1(col1 interval year to month,col2  int);
insert into test1 values('1-2',1);
SELECT decode ('1-2',NULL,0,col1,7000)from test1;  
drop table test1;

--布尔类型：
--boolean:
create table test1(col1 boolean,col2  int);
insert into test1 values(true,1);
SELECT decode ('true',NULL,0,col1,7000)from test1;    
drop table test1;

--枚举类型：
CREATE TYPE mood AS ENUM ('sad', 'ok', 'happy');
CREATE TABLE person_test (
    name text,
    current_mood mood
);
INSERT INTO person_test VALUES ('Moe', 'happy');
SELECT decode ( 'happy',NULL,0,current_mood,7000)from person_test;    
drop table person_test;
drop type mood;

--几何类型：
--1.point,不支持
create table test1(col1 point,col2  int);
insert into test1 values(point(5,8),1);
SELECT decode (point(5,8),NULL,0,col1,7000)from test1;--报错
drop table test1;
--2.line:
create table test1(col1 line,col2  int);
insert into test1 values(line(point '(-1,0)', point '(1,0)'),1);
SELECT decode (line(point '(-1,0)', point '(1,0)'),NULL,0,col1,7000)from test1;   
drop table test1;
--3.lseg:
create table test1(col1 lseg,col2  int);
insert into test1 values(lseg(box '((-1,0),(1,0))'),1);
SELECT decode (lseg(box '((-1,0),(1,0))'),NULL,0,col1,7000)from test1; 
drop table test1;
--4.box:
create table test1(col1 box,col2  int);
insert into test1 values(box(point '(0,0)', point '(1,1)'),1);
SELECT decode (box(point '(0,0)', point '(1,1)'),NULL,0,col1,7000)from test1; 
drop table test1;
--5.path:
create table test1(col1 path,col2  int);
insert into test1 values(path(polygon '((0,0),(1,1),(2,0))'),1);
SELECT decode (path(polygon '((0,0),(1,1),(2,0))'),NULL,0,col1,7000)from test1;   
drop table test1;
--6.polygon，不支持
create table test1(col1 polygon,col2  int);
insert into test1 values(polygon(box '((0,0),(1,1))'),1);
SELECT decode (polygon(box '((0,0),(1,1))'),NULL,0,col1,7000)from test1;--报错
drop table test1;
--7.circle:
create table test1(col1 circle,col2  int);
insert into test1 values(circle(point '(0,0)', 2.0),1);
SELECT decode (circle(point '(0,0)', 2.0),NULL,0,col1,7000)from test1; 
drop table test1;

--网络地址类型：
--1.cidr:
create table test1(col1 cidr,col2  int);
insert into test1 values('192.168.100.128/25',1);
SELECT decode ('192.168.100.128/25',NULL,0,col1,7000)from test1;  
drop table test1;
--2.inet:
create table test1(col1 inet,col2  int);
insert into test1 values('192.168.100.128/25',1);
SELECT decode ('192.168.100.128/25',NULL,0,col1,7000)from test1;  
drop table test1;
--3.macaddr:
create table test1(col1 macaddr,col2  int);
insert into test1 values('08:00:2b:01:02:03',1);
SELECT decode ('08:00:2b:01:02:03',NULL,0,col1,7000)from test1;    
drop table test1;

--位串类型：
--1.bit(n):
create table test1(col1 bit(3),col2  int);
insert into test1 values(B'101',1);
SELECT decode (B'101',NULL,0,col1,7000)from test1;    
drop table test1;
--2.bit varying(n):
create table test1(col1 bit varying(5),col2  int);
insert into test1 values(B'00',1);
SELECT decode (B'00',NULL,0,col1,7000)from test1;     
drop table test1;

--文本搜索类型：
--1.tsvector：
create table test1(col1 tsvector,col2  int);
insert into test1 values(to_tsvector('english', 'The Fat Rats'),1);
SELECT decode (to_tsvector('english', 'The Fat Rats'),NULL,0,col1,7000)from test1;     
drop table test1;
--2.tsquery：
create table test1(col1 tsquery,col2  int);
insert into test1 values(to_tsquery('Fat:ab & Cats'),1);
SELECT decode (to_tsquery('Fat:ab & Cats'),NULL,0,col1,7000)from test1; 
drop table test1;

--UUID类型：
create table test1(col1 UUID,col2  int);
insert into test1 values('a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11',1);
SELECT decode ('a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11',NULL,0,col1,7000)from test1;     
drop table test1;

--JSON类型，不支持
create table test1(col1 JSON,col2  int);
insert into test1 values('5'::json,1);
SELECT decode ('5'::json,NULL,0,col1,7000)from test1;--报错
drop table test1;

--Arrays:
create table test1(col1 int[],col2  int);
insert into test1 values(array[5,6],1);
SELECT decode (array[5,6],NULL,0,col1,7000)from test1;   
drop table test1;

--expr和search数据类型不同，报错
create table test1(col1 int,col2  varchar(10));
insert into test1 values(23,'sales');
SELECT decode (col1, 20,NULL,col2,'sales') from test1;--报错
drop table test1;
create table test1(col1 varchar(10),col2 int);
insert into test1 values('sales',23);
SELECT decode (col1, 20,NULL,col2,'sales') from test1;--报错
drop table test1;

--result和default为任意数据类型，且类型一致
--数值类型：
--1.smallint:
create table test1(col1 smallint,col2  int);
insert into test1 values(23,1);
SELECT decode (23, 20,NULL,23,col1,col1) from test1;
drop table test1;
--2.integer:
create table test1(col1 int,col2  int);
insert into test1 values(23,1);
SELECT decode (23, 20,NULL,23,col1,col1) from test1;
drop table test1;
--3.bigint:
create table test1(col1 bigint,col2  int);
insert into test1 values(23,1);
SELECT decode (23, 20,NULL,23,col1,col1) from test1;
drop table test1;
--4.decimal:
create table test1(col1 decimal,col2  int);
insert into test1 values(23,1);
SELECT decode (23, 20,NULL,23,col1,col1) from test1;
drop table test1;
--5.numeric:
create table test1(col1 numeric(5,2),col2  int);
insert into test1 values(23.225,1);
SELECT decode (23, 20,NULL,23,col1,col1) from test1;
drop table test1;
--6.real:
create table test1(col1 real,col2  int);
insert into test1 values(23.225,1);
SELECT decode (23, 20,NULL,23,col1,col1) from test1;
drop table test1;
--7.double precision:
create table test1(col1 double precision,col2  int);
insert into test1 values(23.225,1);
SELECT decode (23, 20,NULL,23,col1,col1) from test1;
drop table test1;
--8.smallserial:
create table test1(col1 smallserial,col2  int);
insert into test1 values(23,1);
SELECT decode (23, 20,NULL,23,col1,col1) from test1;
drop table test1;
--9.serial:
create table test1(col1 serial,col2  int);
insert into test1 values(23,1);
SELECT decode (23, 20,NULL,23,col1,col1) from test1;
drop table test1;
--10.bigserial:
create table test1(col1 bigserial,col2  int);
insert into test1 values(23,1);
SELECT decode (23, 20,NULL,23,col1,col1) from test1;
drop table test1;

--字符类型：
--1.varchar:
create table test1(col1 varchar(10),col2  int);
insert into test1 values('sales',1);
SELECT decode (23, 20,NULL,23,col1,col1) from test1;
drop table test1;
--2.char:
create table test1(col1 char(10),col2  int);
insert into test1 values('sales',1);
SELECT decode (23, 20,NULL,23,col1,col1) from test1;
drop table test1;
--3.text:
create table test1(col1 text,col2  int);
insert into test1 values('sales',1);
SELECT decode (23, 20,NULL,23,col1,col1) from test1;
drop table test1;

--货币类型：
create table test1(col1 money,col2  int);
insert into test1 values(8000,1);
SELECT decode (23, 20,NULL,23,col1,col1) from test1;  
drop table test1;

--二进制数据类型:
create table test1(col1 bytea,col2  int);
insert into test1 values(E'\\001',1);
SELECT decode (23, 20,NULL,23,col1,col1) from test1;
drop table test1;

--日期/时间类型:
--1.timestamp:
create table test1(col1 timestamp,col2  int);
insert into test1 values('1999-1-5 00:00:00',1);
SELECT decode (23, 20,NULL,23,col1,col1) from test1;
drop table test1;
--2.timestamp with time zone:
create table test1(col1 timestamp with time zone,col2  int);
insert into test1 values('1999-1-5 8:00:00',1);
SELECT decode (23, 20,NULL,23,col1,col1) from test1; 
drop table test1;
--3.date:
create table test1(col1 date,col2  int);
insert into test1 values('1999-01-05',1);
SELECT decode (23, 20,NULL,23,col1,col1) from test1; 
drop table test1;
--4.time:
create table test1(col1 time,col2  int);
insert into test1 values('14:12:50',1);
SELECT decode (23, 20,NULL,23,col1,col1) from test1; 
drop table test1;
--5.time with time zone:
create table test1(col1 time with time zone,col2  int);
insert into test1 values('14:12:50-8',1);
SELECT decode (23, 20,NULL,23,col1,col1) from test1;
drop table test1;
--6.interval:
create table test1(col1 interval year to month,col2  int);
insert into test1 values('1-2',1);
SELECT decode (23, 20,NULL,23,col1,col1) from test1;
drop table test1;

--布尔类型：
--boolean:
create table test1(col1 boolean,col2  int);
insert into test1 values(true,1);
SELECT decode (23, 20,NULL,23,col1,col1) from test1;  
drop table test1;

--枚举类型：
CREATE TYPE mood AS ENUM ('sad', 'ok', 'happy');
CREATE TABLE person_test (
    name text,
    current_mood mood
);
INSERT INTO person_test VALUES ('Moe', 'happy');
SELECT decode (23, 20,NULL,23,current_mood,current_mood) from person_test;
drop table person_test;
drop type mood;

--几何类型：
--1.point:
create table test1(col1 point,col2  int);
insert into test1 values(point(5,8),1);
SELECT decode (23, 20,NULL,23,col1,col1) from test1;  
drop table test1;
--2.line:
create table test1(col1 line,col2  int);
insert into test1 values(line(point '(-1,0)', point '(1,0)'),1);
SELECT decode (23, 20,NULL,23,col1,col1) from test1;  
drop table test1;
--3.lseg:
create table test1(col1 lseg,col2  int);
insert into test1 values(lseg(box '((-1,0),(1,0))'),1);
SELECT decode (23, 20,NULL,23,col1,col1) from test1;   
drop table test1;
--4.box:
create table test1(col1 box,col2  int);
insert into test1 values(box(point '(0,0)', point '(1,1)'),1);
SELECT decode (23, 20,NULL,23,col1,col1) from test1;   
drop table test1;
--5.path:
create table test1(col1 path,col2  int);
insert into test1 values(path(polygon '((0,0),(1,1),(2,0))'),1);
SELECT decode (23, 20,NULL,23,col1,col1) from test1;   
drop table test1;
--6.polygon:
create table test1(col1 polygon,col2  int);
insert into test1 values(polygon(box '((0,0),(1,1))'),1);
SELECT decode (23, 20,NULL,23,col1,col1) from test1;    
drop table test1;
--7.circle:
create table test1(col1 circle,col2  int);
insert into test1 values(circle(point '(0,0)', 2.0),1);
SELECT decode (23, 20,NULL,23,col1,col1) from test1;  
drop table test1;

--网络地址类型：
--1.cidr:
create table test1(col1 cidr,col2  int);
insert into test1 values('192.168.100.128/25',1);
SELECT decode (23, 20,NULL,23,col1,col1) from test1;   
drop table test1;
--2.inet:
create table test1(col1 inet,col2  int);
insert into test1 values('192.168.100.128/25',1);
SELECT decode (23, 20,NULL,23,col1,col1) from test1;   
drop table test1;
--3.macaddr:
create table test1(col1 macaddr,col2  int);
insert into test1 values('08:00:2b:01:02:03',1);
SELECT decode (23, 20,NULL,23,col1,col1) from test1;   
drop table test1;

--位串类型：
--1.bit(n):
create table test1(col1 bit(3),col2  int);
insert into test1 values(B'101',1);
SELECT decode (23, 20,NULL,23,col1,col1) from test1;   
drop table test1;
--2.bit varying(n):
create table test1(col1 bit varying(5),col2  int);
insert into test1 values(B'00',1);
SELECT decode (23, 20,NULL,23,col1,col1) from test1;       
drop table test1;

--文本搜索类型：
--1.tsvector：
create table test1(col1 tsvector,col2  int);
insert into test1 values(to_tsvector('english', 'The Fat Rats'),1);
SELECT decode (23, 20,NULL,23,col1,col1) from test1;    
drop table test1;
--2.tsquery：
create table test1(col1 tsquery,col2  int);
insert into test1 values(to_tsquery('Fat:ab & Cats'),1);
SELECT decode (23, 20,NULL,23,col1,col1) from test1;   
drop table test1;

--UUID类型：
create table test1(col1 UUID,col2  int);
insert into test1 values('a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11',1);
SELECT decode (23, 20,NULL,23,col1,col1) from test1;   
drop table test1;

--JSON类型：
create table test1(col1 JSON,col2  int);
insert into test1 values('5'::json,1);
SELECT decode (23, 20,NULL,23,col1,col1) from test1;    
drop table test1;

--Arrays:
create table test1(col1 int[],col2  int);
insert into test1 values(array[5,6],1);
SELECT decode (23, 20,NULL,23,col1,col1) from test1;  
drop table test1;

--result和default数据类型不同，报错
create table test1(col1 int,col2  varchar(10));
insert into test1 values(23,'sales');
SELECT decode (23, 20,NULL,23,col1,col2) from test1;--报错
drop table test1;
create table test1(col1 varchar(10),col2 int);
insert into test1 values('sales',23);
SELECT decode (23, 20,NULL,23,col1,col2) from test1;--报错
drop table test1;

create table t_bug0000331(aname character varying(10),
   dname character varying(10),
   cstcode character varying(10) NOT NULL);
insert into t_bug0000331 values(NULL, 'a1', 'a2');
select decode(nvl(c.aname,c.dname),null,c.cstcode,'a') CUSTSHORTNAME  from t_bug0000331 c;
select nvl(decode(c.aname, '30', c.cstcode), c.dname) from t_bug0000331 c;

create table t_bug589(a varchar(10));
insert into t_bug589 values(null);
select lengthb(decode(a, null, ' ',a)) from t_bug589;
drop table t_bug589;

drop table t_bug0000331;

reset nls_date_format;
reset nls_timestamp_format;
reset nls_timestamp_tz_format;
reset default_text_search_config;
