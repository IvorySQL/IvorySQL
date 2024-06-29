/*
 * length/lengthb
 */
-- char
CREATE TABLE TEST_ORACHAR(a char(5 byte), b char(5 char));

INSERT INTO TEST_ORACHAR VALUES('aaa', 'bbb');

INSERT INTO TEST_ORACHAR VALUES('aaa ', 'bbb ');

SELECT a, b, LENGTH(a), LENGTH(b) FROM TEST_ORACHAR;

SELECT a, b, LENGTHB(a), LENGTHB(b) FROM TEST_ORACHAR;

--varchar2
CREATE TABLE TEST_ORAVARCHAR(a varchar2(5 char), b varchar2(5 byte));

INSERT INTO TEST_ORAVARCHAR VALUES('aaa', 'bbb');

INSERT INTO TEST_ORAVARCHAR VALUES('aaa ', 'bbb ');

SELECT a, b, LENGTH(a), LENGTH(b) FROM TEST_ORAVARCHAR;

SELECT a, b, LENGTHB(a), LENGTHB(b) FROM TEST_ORAVARCHAR;

-- drop table
DROP TABLE TEST_ORACHAR;
DROP TABLE TEST_ORAVARCHAR;

/*
 * ||
 */
--test bug#792
SET nls_date_format = 'DD-MON-YY';
SET nls_timestamp_format = 'DD-MON-YY HH24:MI:SS.US';
create table test_concat(id number,id2 integer,id3 timestamp,id4 date);

--insert a row
insert into test_concat values(1,2,'01-FEB-21','01-FEB-21');

--integer || number
select id || id2 from test_concat;

--integer || timestamp
select id || id3 from test_concat;

--timestamp || date
select id3 || id4 from test_concat;

--integer || number || timestamp || date
select id || id2 || id3 || id4 from test_concat;

--as a table column
create table test_concat1 as select id || id2 as test from test_concat;

--column type
select attname,atttypid from pg_attribute attr left join pg_class r on r.oid = attr.attrelid where r.relname='test_concat1' and attname='test' order by attname;

create table test_concat2 as select id|| id4 as test from test_concat;

select attname,atttypid from pg_attribute attr left join pg_class r on r.oid = attr.attrelid where r.relname='test_concat2' and attname='test' order by attname;

create table test_concat3 as select id3 || id4 as test from test_concat;

select attname,atttypid from pg_attribute attr left join pg_class r on r.oid = attr.attrelid where r.relname='test_concat3' and attname='test' order by attname;

insert into test_concat(id) values(2);

--integer || null
select id || id2 from test_concat;

--null || number
select  id2 || id from test_concat;

--clean data
drop table test_concat;
drop table test_concat1;
drop table test_concat2;
drop table test_concat3;

/*
 * concat
 */
-- table null_special
create table null_special
(
	id number not null,
	special_name varchar2(255),
	teacher varchar2(8),
	remark varchar2(255)
);

-- truncate table null_special;
insert into null_special(id,special_name,teacher) values (1,'语文','小王');
insert into null_special (id,special_name,remark)
	values (2,'体育','体育teacher IS NULL');
insert into null_special (id,special_name,teacher,remark)
	values (3,'音乐',' ','音乐teacher is 空了一格');
insert into null_special (id,special_name,teacher,remark)
	values (4,'英语','','英语teacher is empty');
insert into null_special (id,special_name,teacher) values (5,'数学','小刘');

-- table null_specialbk
create table null_specialbk
(
	id number not null,
	special_name varchar2(255),
	teacher varchar2(8),
	remark varchar2(255)
);

-- truncate table null_special;
insert into null_specialbk (id,special_name,teacher) values (1,'语文','小王');
insert into null_specialbk (id,special_name,teacher,remark)
values (2,'体育','','体育teacher ie empty');
insert into null_specialbk (id,special_name,teacher,remark)
values (3,'音乐',' ','音乐teacher is 空了一格');
insert into null_specialbk (id,special_name,remark)
values (4,'英语','英语teacher IS NULL');

-- query
select sp.* from
(
	select
		sp1.id, sp1.special_name, concat(sp1.teacher, sp2.teacher) tch, sp1.remark
	from null_special sp1, null_specialbk sp2
	where sp1.id = sp2.id
) sp where sp.tch is null;

-- other types
SET nls_date_format = 'DD-MON-YY';
SET nls_timestamp_format = 'DD-MON-YY HH24:MI:SS.US';
create table test_concat(id number,id2 integer,id3 timestamp,id4 date);

-- insert a row
insert into test_concat values(1,2,'01-FEB-21','01-FEB-21');

-- concat(integer, number)
select concat(id, id2) from test_concat;

-- concat(integer, timestamp)
select concat(id, id3) from test_concat;

-- concat(timestamp, date)
select concat(id3, id4) from test_concat;

-- concat(integer, concat(number, concat(timestamp, date)))
select concat(id, concat(id2, concat(id3, id4))) from test_concat;

-- as a table column
create table test_concat1 as select concat(id, id2) as test from test_concat;

-- column type
select attname,atttypid from pg_attribute attr
left join pg_class r on r.oid = attr.attrelid
where r.relname='test_concat1' and attname='test' order by attname;

create table test_concat2 as select concat(id, id4) as test from test_concat;

select attname,atttypid from pg_attribute attr
left join pg_class r on r.oid = attr.attrelid
where r.relname='test_concat2' and attname='test' order by attname;

create table test_concat3 as select concat(id3, id4) as test from test_concat;

select attname,atttypid from pg_attribute attr
left join pg_class r on r.oid = attr.attrelid
where r.relname='test_concat3' and attname='test' order by attname;

insert into test_concat(id) values(2);

-- concat(integer, null)
select concat(id, id2) from test_concat;

-- concat(null, number)
select concat(id2, id) from test_concat;

-- clean data
drop table test_concat;
drop table test_concat1;
drop table test_concat2;
drop table test_concat3;

/*
 * lpad/rpad
 */
--bug#997
--create test table
create table test_lpad(id integer);

--ok
select lpad('*', (select count(*) from test_lpad), '*') from dual;

--ok
select rpad('*', (select count(*) from test_lpad), '*') from dual;

--insert one row
insert into test_lpad values(1);

--*
select lpad('*', (select count(*) from test_lpad), '*') from dual;

--*
select rpad('*', (select count(*) from test_lpad), '*') from dual;

--insert another
insert into test_lpad values(2);

--1*
select lpad('*', (select count(*) from test_lpad), '1') from dual;

--*1
select rpad('*', (select count(*) from test_lpad), '1') from dual;

--x *welcome
select 'x' || lpad('*', (select count(*) from test_lpad)) ||'welceom' from dual;

--x* welcome
select 'x' || rpad('*', (select count(*) from test_lpad)) ||'welceom' from dual;

--001234
select lpad(1234,6,'0') from dual;

--123400
select rpad(1234,6,'0') from dual;

--null
select lpad(NULL,6,'0') from dual;

--null
select rpad(NULL,6,'0') from dual;

--create view
create table test_t(id varchar2(23));

insert into test_t values('sfljdsf');

create view test_view as select lpad('*', (select count(*) from test_lpad), '*') || id as name from test_t;

select *from test_view order by name;

--clean data
drop view test_view;
drop table test_t;
drop table test_lpad;

/*
 * trim/ltrim/rtrim
 */
select rtrim('123 '::number);	--bug#796
SELECT LTRIM('<=====>BROWNING<=====>', '<>=') "LTRIM Example" FROM DUAL;
SELECT RTRIM('<=====>BROWNING<=====>', '<>=') "RTRIM Example" FROM DUAL;
--test bug#833
create table test_trim(id number);
select trim(id) from test_trim;
insert into test_trim values(124.35);
select trim(id) from test_trim;
select trim('35' from id) from test_trim;
--clean data
drop table test_trim;

/*
 * regexp_replace
 */
set ivorysql.enable_emptystring_to_null to on;
--Return empty

select regexp_replace('', '[0-9]+','') from  dual;

select regexp_replace(NULL, '[0-9]+',NULL) from  dual;

select regexp_replace('', '[0-9]+','A') from  dual;

select regexp_replace(NULL, '[0-9]+','A') from  dual;

select regexp_replace('', '[a-z]+','',1,3,'i') from  dual;

select regexp_replace(NULL, '[a-z]+',NULL,1,3,'i') from  dual;

select regexp_replace('', '[0-9]+', '', 1, 3, 'i') from  dual;

select regexp_replace(NULL, '[0-9]+', NULL, 1, 3, 'i') from  dual;

select regexp_replace('662 regEXP_REplaCe TEst 172', '[0-9]+', 'ZZZ', '') from  dual;

select regexp_replace('662 regEXP_REplaCe TEst 172', '[0-9]+', 'ZZZ', NULL) from  dual;

select regexp_replace('662 regEXP_REplaCe TEst 172', '[0-9]+', 'ZZZ', 1, '') from  dual;

select regexp_replace('662 regEXP_REplaCe TEst 172', '[0-9]+', 'ZZZ', 1, NULL) from  dual;

--Too few parameters

select regexp_replace('') from  dual;

select regexp_replace(NULL) from  dual;

select regexp_replace('662 regEXP_REplaCe TEst 172') from  dual;

--Return source string

select regexp_replace('662 regEXP_REplaCe TEst 172', '') from  dual;

select regexp_replace('662 regEXP_REplaCe TEst 172', NULL) from  dual;

select regexp_replace('662 regEXP_REplaCe TEst 172', '','AA',1,1,'i') from  dual;

select regexp_replace('662 regEXP_REplaCe TEst 172', NULL,'AA',1,1,'i') from  dual;

--Remove matching characters from the source string

select regexp_replace('662 regEXP_REplaCe TEst 172', '[0-9]+') from  dual;

select regexp_replace('662 regEXP_REplaCe TEst 172', '[0-9]+','') from  dual;

select regexp_replace('662 regEXP_REplaCe TEst 172', '[0-9]+', NULL) from  dual;

--Return source string

select regexp_replace('662 regEXP_REplaCe TEst 172', '', 'ZZZ') from  dual;

select regexp_replace('662 regEXP_REplaCe TEst 172', NULL, 'ZZZ') from  dual;

--Replace 2 or more spaces with a space

select regexp_replace('500   Oracle     Parkway,    Redwood  Shores, CA', '( ){2,}', ' ') from dual;

--Replace the matched substring with a new string

select regexp_replace('662 regEXP_REplaCe TEst 172', '[0-9]+', 'ZZZ') from  dual;

--Look backwards from the specified location 8

select regexp_replace('662 regEXP_REplaCe TEst 172', '[0-9]+', 'ZZZ', 8) from  dual;

--Remove matching characters from the source string

select regexp_replace('662 regEXP_REplaCe TEst 172', '[0-9]+', '', 8) from  dual;

select regexp_replace('662 regEXP_REplaCe TEst 172', '[0-9]+', NULL, 8) from  dual;

--Incorrect parameter type

select regexp_replace('662 regEXP_REplaCe TEst 172', '[0-9]+', '', a) from  dual;

select regexp_replace('662 regEXP_REplaCe TEst 172', '[0-9]+', NULL, a) from  dual;

--Searched position is less than 1 out of range

select regexp_replace('662 regEXP_REplaCe TEst 172', '[0-9]+', 'ZZZ', 0) from  dual;

--Replace all strings that match

select regexp_replace('662 regEXP_REplaCe TEst 172', '[0-9]+', 'ZZZ', 1, 0) from  dual;

--Replace the second matching string starting with the third character

select regexp_replace('662 regEXP_REplaCe TEst 172', '[0-9]+', 'ZZZ', 3, 2) from  dual;

--Match string is less than 0 out of range

select regexp_replace('662 regEXP_REplaCe TEst 172', '[0-9]+', 'ZZZ', 5, -1) from  dual;

--specifies case-insensitive matching

select regexp_replace('662 regEXP_REplaCe TEst 172', '[0-9]+', 'ZZZ', 1, 1, '') from  dual;

select regexp_replace('662 regEXP_REplaCe TEst 172', '[0-9]+', 'ZZZ', 1, 1, NULL) from  dual;

select regexp_replace('662 regEXP_REplaCe TEst 172', '[a-c]+', 'ZZZ', 1, 1, 'i')  from  dual;

--specifies case-sensitive matching.

select regexp_replace('662 regEXP_REplaCe TEst 172', '[0-9]+', 'ZZZ', 4, 3, 'c')  from  dual;

--allows the period (.), which is the match-any-character character

select regexp_replace('662 regEXP_REplaCe TEst 172', '[A-C]+', 'ZZZ', 1, 1, 'n')  from  dual;

--treats the source string as multiple lines

select regexp_replace('662 regEXP_REplaCe TEst 172', '[A-C]+', 'ZZZ', 1, 1, 'm')  from  dual;

--ignores whitespace characters

select regexp_replace('662 regEXP_REplaCe TEst 172', '[A-C]+', 'ZZZ', 1, 1, 'x')  from  dual;

--Match only the last character

select regexp_replace('662 regEXP_REplaCe TEst 172', '[A-C]+', 'ZZZ', 1, 1, 'ic')  from  dual;

--Wrong matching pattern

select regexp_replace('662 regEXP_REplaCe TEst 172', '[A-C]+', 'ZZZ', 1, 1, 'a')  from  dual;

--Too many parameters

select regexp_replace('662 regEXP_REplaCe TEst 172', '[A-C]+', 'ZZZ', 1, 1, 'ic',8)  from  dual;

--Replace all uppercase letters

select regexp_replace('regexp_REPLACE 4567', '[[:upper:]]', 'x-', 1, 0, 'ic')  from  dual;

--Replace all letters, numbers

select regexp_replace('regexp-23-replace 345', '[[:alnum:]]', 'x:') from  dual;

--Replace the specified string

select regexp_replace('for,forty,horse,morning,sport', 'or', '!') from  dual;

--Replace plus sign

select regexp_replace('(19 + 35 * 2 + 8 - 3) / 2', '\+', '-', 1, 1) from  dual;

--Separate each letter

select regexp_replace('australia', '(.)', '\1 ') from dual;

--Match to the specified format

select regexp_replace('515.123.4444 515.123.4888','([[:digit:]]{3})\.([[:digit:]]{3})\.([[:digit:]]{4})','(\1) \2-\3') from dual;

/*
 * regexp_substr
 */
--Return empty
select regexp_substr('', '[0-9]+','') from  dual;

select regexp_substr(NULL, '[0-9]+',NULL) from  dual;

select regexp_substr('', '[0-9]+','') from  dual;

select regexp_substr(NULL, '[0-9]+','') from  dual;

select regexp_substr('', '[a-z]+',1,3,'i') from  dual;

select regexp_substr(NULL, '[a-z]+',1,3,'i') from  dual;

select regexp_substr('345 REGEXP_substr 789', '') from  dual;

select regexp_substr('345 REGEXP_substr 789', NULL) from  dual;

select regexp_substr('345 REGEXP_substr 789', '', 1) from  dual;

select regexp_substr('345 REGEXP_substr 789', NULL, 1) from  dual;

select regexp_substr('345 REGEXP_substr 789', '',1,1,'i') from  dual;

select regexp_substr('345 REGEXP_substr 789', NULL,1,1,'i') from  dual;

select regexp_substr('345 REGEXP_substr 789', '[0-9]+', '') from  dual;

select regexp_substr('345 REGEXP_substr 789', '[0-9]+', NULL) from  dual;

select regexp_substr('345 REGEXP_substr 789', '[0-9]+', 1, '') from  dual;

select regexp_substr('345 REGEXP_substr 789', '[0-9]+', 1, NULL) from  dual;

select regexp_substr('345 REGEXP_substr 789', '[0-9]+', 1, 1, 'i', '') from  dual;

select regexp_substr('345 REGEXP_substr 789', '[0-9]+', 1, 1, 'i', NULL) from  dual;

--Too few parameters

select regexp_substr('') from  dual;

select regexp_substr(NULL) from  dual;

select regexp_substr('345 REGEXP_substr 789') from  dual;

--Returns the first string matched

select regexp_substr('345 REGEXP_substr 789', '[0-9]+') from  dual;

--Return the first string that matches to the specified position

select regexp_substr('345 REGEXP_substr 789', '[0-9]+', 8) from  dual;

--Incorrect parameter type

select regexp_substr('345 REGEXP_substr 789', '[0-9]+',  a) from  dual;

--Searched position is less than 1 out of range

select regexp_substr('345 REGEXP_substr 789', '[0-9]+',  0) from  dual;

select regexp_substr('345 REGEXP_substr 789', '[0-9]+',  1, 0) from  dual;

select regexp_substr('345 REGEXP_substr 789', '[0-9]+', 5, -1) from  dual;

--specifies case-insensitive matching

select regexp_substr('345 REGEXP_substr 789', '[a-z]+', 1, 1, '') from  dual;

select regexp_substr('345 REGEXP_substr 789', '[a-z]+', 1, 1, NULL) from  dual;

select regexp_substr('345 REGEXP_substr 789', '[a-z]+', 1, 1, 'i')  from  dual;

--specifies case-sensitive matching.

select regexp_substr('345 REGEXP_substr 789', '[a-z]+', 4, 3, 'c')  from  dual;

--allows the period (.), which is the match-any-character character

select regexp_substr('345 REGEXP_substr 789', '[A-Z]+', 1, 1, 'n')  from  dual;

--treats the source string as multiple lines

select regexp_substr('345 REGEXP_substr 789', '[A-Z]+', 1, 1, 'm')  from  dual;

--ignores whitespace characters

select regexp_substr('345 REGEXP_substr 789', '[A-Z]+', 1, 1, 'x')  from  dual;

--Match only the last character

select regexp_substr('345 REGEXP_substr 789', '[A-Z]+', 1, 1, 'ic')  from  dual;

--Wrong matching pattern

select regexp_substr('345 REGEXP_substr 789', '[A-Z]+', 1, 1, 'a')  from  dual;

-- find the first uppercase letters

select regexp_substr('regexp_REPLACE 4567', '[[:upper:]]', 1, 1, 'ic')  from  dual;

--Return the first character found or this number

select regexp_substr('regexp-23-replace 345', '[[:alnum:]]') from  dual;

select regexp_substr('(19 + 35 * 2 + 8 - 3) / 2', '\+', 1, 1) from  dual;

select regexp_substr('australia', '(.)') from dual;

select regexp_substr('515.123.4444 515.123.4888','([[:digit:]]{3})\.([[:digit:]]{3})\.([[:digit:]]{4})') from dual;

--Returns the first string found by the regular expression

select regexp_substr('500 Oracle Parkway, Redwood Shores, CA',',[^,]+,') from dual;

select regexp_substr('http://www.example.com/products','http://([[:alnum:]]+\.?){3,4}/?') from dual;

--Use the subexpr argument to return a specific subexpression of pattern

select regexp_substr('barbar', 'b[^b]+',1,1,'i',0) from dual;

select regexp_substr('barbar', 'b[^b]+',1,1,'i',1) from dual;

select regexp_substr('barbar', '(b[^b]+)',1,1,'i',0) from dual;

select regexp_substr('barbar', '(b[^b]+)',1,1,'i',1) from dual;

select regexp_substr('foobarbequebazilbarfbonk', '(b[^b]+)(b[^b]+)', 1, 1, 'i',2) from dual;

select regexp_substr('345 REGEXP_substr 789', '[A-Z]+', 1, 1, 'ic',8)  from  dual;

select regexp_substr('foobarbequebazilbarfbonk', '(b[^b]+)(b[^b]+)', 1, 1, 'i',3) from dual;

select regexp_substr('123456789010', '(1(2)3)(4(5(6))(7(8))(9(0)(10)))', 1, 1, 'i',8) from dual;

select regexp_substr('123456789010', '(1(2)3)(4(5(6))(7(8))(9(0)(10)))', 1, 1, 'i',9) from dual;

--The number of submodes is more than 9 and returns empty

select regexp_substr('123456789010', '(1(2)3)(4(5(6))(7(8))(9(0)(10)))', 1, 1, 'i',10) from dual;

--Too many parameters

select regexp_substr('foobarbequebazilbarfbonk', '(b[^b]+)(b[^b]+)', 1, 1, 'i',2,8) from dual;


/*
 * regexp_instr
 */
--Return empty or error
----two parameters
select regexp_instr('', '[0-9]+') from dual;

select regexp_instr('345 REGEXP_instr 789', '') from dual;

select regexp_instr('345 REGEXP_instr 789', '') from dual;

select regexp_instr('345 REGEXP_instr 789', NULL) from dual;

----three parameters
select regexp_instr('345 REGEXP_instr 789', '[a-z]+',0) from dual;	--fail

select regexp_instr('345 REGEXP_instr 789', '[a-z]+',-1) from dual; --fail
 
select regexp_instr('', '[0-9]+','') from dual;

select regexp_instr(NULL, '[0-9]+',NULL) from dual;

select regexp_instr('', '[0-9]+',NULL) from dual;

select regexp_instr(NULL, '[0-9]+','') from dual;

select regexp_instr('345 REGEXP_instr 789', '', 1) from dual;

select regexp_instr('345 REGEXP_instr 789', NULL, 1) from dual;

select regexp_instr('345 REGEXP_instr 789', '[0-9]+', '') from dual;

select regexp_instr('345 REGEXP_instr 789', '[0-9]+', NULL) from dual;

----four parameters
select regexp_instr('345 REGEXP_instr 789', '[a-z]+',1,0) from dual;	--fail

select regexp_instr('345 REGEXP_instr 789', '[a-z]+',1,-1) from dual;	--fail

select regexp_instr('345 REGEXP_instr 789', '[0-9]+', 1, '') from dual;

select regexp_instr('345 REGEXP_instr 789', '[0-9]+', 1, NULL) from dual;

----five parameters
select regexp_instr('345 REGEXP_instr 789', '[a-z]+', 1, 1, -1) from dual; --fail

select regexp_instr('345 REGEXP_instr 789', '[a-z]+', 1, 1, -2) from dual; --fail

select regexp_instr('345 REGEXP_instr 789', '[a-z]+', 1, 1, -100) from dual; --fail

select regexp_instr('345 REGEXP_instr 789', '[a-z]+', 1, 1, '') from dual;

select regexp_instr('345 REGEXP_instr 789', '[a-z]+', 1, 1, NULL) from dual;

----six parameters
select regexp_instr('345 REGEXP_instr 789', '[a-z]+', 1, 1, 0, 'q') from dual;	--fail

select regexp_instr('', '[a-z]+', 1, 1, 0, 'i') from dual;

select regexp_instr(NULL, '[a-z]+', 1, 1, 0, 'i') from dual;

select regexp_instr('345 REGEXP_instr 789', '', 1, 1, 0, 'i') from dual;

select regexp_instr('345 REGEXP_instr 789', NULL, 1, 1, 0, 'i') from dual;

----seven parameters
select regexp_instr('345 REGEXP_instr 789', '[0-9]+', 1, 1, 0, 'i', -1) from dual; --fail

select regexp_instr('345 REGEXP_instr 789', '[0-9]+', 1, 1, 0, 'i', '') from dual;

select regexp_instr('345 REGEXP_instr 789', '[0-9]+', 1, 1, 0, 'i', NULL) from dual;

select regexp_instr('', '[0-9]+', 1, 1, 0, 'i', 1) from dual;

select regexp_instr(NULL, '[0-9]+', 1, 1, 0, 'i', 1) from dual;

select regexp_instr('345 REGEXP_instr 789', '', 1, 1, 0, 'i', 1) from dual;

select regexp_instr('345 REGEXP_instr 789', NULL, 1, 1, 0, 'i', 1) from dual;


--Too few parameters
select regexp_instr('') from dual;	--fail

select regexp_instr(NULL) from dual;--fail

select regexp_instr('345 REGEXP_instr 789') from dual;


--Returns the first string location matched
select regexp_instr('345 REGEXP_instr 789', '[0-9]+') from dual;


--Return the first string location that matches to the specified position
select regexp_instr('345 REGEXP_instr 789', '[0-9]+', 8) from dual;


--Incorrect parameter type
select regexp_instr('345 REGEXP_instr 789', '[0-9]+',  a) from dual;	  --fail


--Searched position is less than 1 out of range
select regexp_instr('345 REGEXP_instr 789', '[0-9]+',  0) from dual;	  --fail

select regexp_instr('345 REGEXP_instr 789', '[0-9]+',  -1) from dual;	  --fail

select regexp_instr('345 REGEXP_instr 789', '[0-9]+',  1, 0) from dual;   --fail

select regexp_instr('345 REGEXP_instr 789', '[0-9]+', 5, -1) from dual;	  --fail


--verify case-insensitive matching
select regexp_instr('345 REGEXP_instr 789', '[a-z]+', 1, 1, 0, '') from dual;

select regexp_instr('345 REGEXP_instr 789', '[a-z]+', 1, 1, 0, NULL) from dual;

select regexp_instr('345 REGEXP_instr 789', '[a-z]+', 1, 1, 0, 'i') from dual;


--specifies case-sensitive matching.
select regexp_instr('345 REGEXP_instr 789', '[a-z]+', 1, 1, 0, 'c') from dual;


--allows the period (.), which is the match-any-character character
select regexp_instr('345 REGEXP_instr 789', '[A-Z]+', 1, 1, 0, 'n') from dual;


--treats the source string as multiple lines
select regexp_instr('345 REG^EX$P_instr 789', '[A-Z]+', 1, 1, 0, 'm')  from dual;

select regexp_instr('34^5 REG$EXP_instr 789', '[A-Z]+', 1, 1, 0, 'm')  from dual;


--ignores whitespace characters
select regexp_instr('345 REGEXP_instr 789', '[a-z]+', 1, 1, 0, 'x')  from dual;


--If specify multiple contradictory values, then Match only the last character.
select regexp_instr('345 REGEXP_instr 789', '[a-z]+', 1, 1, 0, 'ic')  from dual;

select regexp_instr('345 REGEXP_instr 789', '[a-z]+', 1, 1, 0, 'ci')  from dual;


--Wrong matching pattern
select regexp_instr('345 REGEXP_instr 789', '[A-Z]+', 1, 1, 0, 'a')  from dual;	--fail


--Too many parameters
select regexp_instr('foobarbequebazilbarfbonk', '(b[^b]+)(b[^b]+)', 1, 1, 0, 'i', 0, 3) from dual;	--fail


--Returns the character or number location about string found by the regular expression
select regexp_instr('500 Oracle Parkway, Redwood Shores, CA',',[^,]+,') from dual;

select regexp_instr('http://www.example.com/products','/([[:alnum:]]+\.?){3,4}/?') from dual;

select regexp_instr('515.123.4444 515.123.4888','([[:digit:]]{3})\.([[:digit:]]{3})', 1, 2, 0) from dual;


--If the number of subexpression is more than 9, then returns zero
select regexp_instr('123456789010', '(1(2)3)(4(5(6))(7(8))(9(0)(10)))', 1, 1, 0, 'i',10) from dual;


--Use the subexpr argument to return a specific subexpression of pattern
select regexp_instr('barbar', 'b[^b]+', 1, 1, 0, 'i',0) from dual;

select regexp_instr('barbar', 'b[^b]+', 1, 1, 1, 'i',0) from dual;

select regexp_instr('barbar', '(b[^b]+)', 1, 2, 0, 'i',0) from dual;

select regexp_instr('barbar', '(b[^b]+)', 1, 2, 1, 'i',0) from dual;

select regexp_instr('foobarbequebazilbarfbonk', '(b[^b]+)(b[^b]+)', 1, 1, 0, 'i') from dual;

select regexp_instr('345 REGEXP_instr 789', '[A-Z]+', 1, 1, 0, 'ic')  from dual;

select regexp_instr('123456789010', '(1(2)3)(4(5(6))(7(8))(9(0)(10)))', 1, 1, 0, 'i',8) from dual;

select regexp_instr('123456789010', '(1(2)3)(4(5(6))(7(8))(9(0)(10)))', 1, 1, 0, 'i',9) from dual;

/*
 * regexp_like
 */
create table t_regexp_like
(
  id varchar(4),
  value varchar(10)
);

insert into t_regexp_like values ('1','1234560');
insert into t_regexp_like values ('2','1234560');
insert into t_regexp_like values ('3','1b3b560');
insert into t_regexp_like values ('4','abc');
insert into t_regexp_like values ('5','abcde');
insert into t_regexp_like values ('6','ADREasx');
insert into t_regexp_like values ('7','123  45');
insert into t_regexp_like values ('8','adc  de');
insert into t_regexp_like values ('9','adc,.de');
insert into t_regexp_like values ('10','1B');
insert into t_regexp_like values ('10','abcbvbnb');
insert into t_regexp_like values ('11','11114560');
insert into t_regexp_like values ('11','11124560');
-------------------------------------------------------
select * from t_regexp_like where regexp_like(value,'ABC', 'i');
select * from t_regexp_like where regexp_like(value,'ABC', 'n');
select * from t_regexp_like where regexp_like(value,'ABC', 'p');
select * from t_regexp_like where regexp_like(value,'ABC', 'c');
select * from t_regexp_like where regexp_like(value,'a b c', 'x');
select * from t_regexp_like where value like '1____60';
select * from t_regexp_like where regexp_like(value,'1....60');
select * from t_regexp_like where regexp_like(value,'1[0-9]{4}60');
select * from t_regexp_like where regexp_like(value,'1[[:digit:]]{4}60');
select * from t_regexp_like where regexp_like(value, '^[[:digit:]]+[[:alpha:]]+.*[[:digit:]]+$');
select * from t_regexp_like where regexp_like(value,'^[^[:digit:]]+$');
select * from t_regexp_like where regexp_like(value,'^1[2b]','i');
select * from t_regexp_like where regexp_like(value,'^1[2B]');
select * from t_regexp_like where regexp_like(value,'[[:space:]]');
select * from t_regexp_like where regexp_like(value,'^([a-z]+|[0-9]+)$');
select * from t_regexp_like where regexp_like(value,'[[:punct:]]');

select * from t_regexp_like where regexp_like('','');
select * from t_regexp_like where regexp_like(null, '');
select * from t_regexp_like where regexp_like('', null);
select * from t_regexp_like where regexp_like(null, null);
select * from t_regexp_like where regexp_like(null, null, null);

DROP table t_regexp_like;

/*
 * regexp_count
 */
--following test cases from Oracle.
SELECT REGEXP_COUNT('123123123123123', '(12)3', 1, 'i') REGEXP_COUNT FROM DUAL;
SELECT REGEXP_COUNT('123123123123', '123', 3, 'i') COUNT FROM DUAL;
select regexp_count('ABC123', '[A-Z]'), regexp_count('A1B2C3', '[A-Z]') from dual;
select regexp_count('ABC123', '[A-Z][0-9]'), regexp_count('A1B2C3', '[A-Z][0-9]') from dual;
select regexp_count('ABC123', '^[A-Z][0-9]'), regexp_count('A1B2C3', '^[A-Z][0-9]') from dual;
select regexp_count('ABC123', '[A-Z][0-9]{2}'), regexp_count('A1B2C3', '[A-Z][0-9]{2}') from dual;
select regexp_count('ABC123', '([A-Z][0-9]){2}'), regexp_count('A1B2C3', '([A-Z][0-9]){2}') from dual;
select regexp_count('ABC123', '[A-Z]') Match_char_ABC_count, regexp_count('A1B2C3', '[A-Z]') Match_char_ABC_count from dual;
select regexp_count('ABC123', '[A-Z][0-9]') Match_string_C1_count, regexp_count('A1B2C3', '[A-Z][0-9]')  Match_strings_A1_B2_C3_count from dual;
select regexp_count('ABC123A5', '^[A-Z][0-9]') Char_num_like_A1_at_start, regexp_count('A1B2C3', '^[A-Z][0-9]') Char_num_like_A1_at_start from dual;
select regexp_count('ABC123', '[A-Z][0-9]{2}') Char_num_like_A12_anywhere, regexp_count('A1B2C34', '[A-Z][0-9]{2}') Char_num_like_A12_anywhere from dual;
select regexp_count('ABC12D3', '([A-Z][0-9]){2}') Char_num_within_2_places, regexp_count('A1B2C3', '([A-Z][0-9]){2}') Char_num_within_2_places from dual;

CREATE TABLE regexp_temp(empName varchar2(20));
INSERT INTO regexp_temp (empName) VALUES ('John Doe');
INSERT INTO regexp_temp (empName) VALUES ('Jane Doe');

SELECT empName, REGEXP_COUNT(empName, 'e', 1, 'c') "CASE_SENSITIVE_E" From regexp_temp;
SELECT empName, REGEXP_COUNT(empName, 'o', 1, 'c') "CASE_SENSITIVE_O" From regexp_temp;
SELECT empName, REGEXP_COUNT(empName, 'E', 1, 'i') "CASE_INSENSITIVE_E" From regexp_temp;
SELECT empName, REGEXP_COUNT(empName, 'do', 1, 'i') "CASE_INSENSITIVE_STRING" From regexp_temp;
SELECT empName, REGEXP_COUNT(empName, 'an', 1, 'c') "CASE_SENSITIVE_STRING" From regexp_temp;

DROP TABLE regexp_temp;

/*
 * substrb
 */
SELECT SUBSTRB('ABCDEFG',5,4.2) "Substring with bytes" FROM DUAL;
SELECT SUBSTRB('ABCDEFG',5) "Substring with bytes" FROM DUAL;

/*
 * instrb
 */
SELECT INSTRB('CORPORATE FLOOR','OR',5,2) "Instring in bytes" FROM DUAL;
SELECT INSTRB('CORPORATE FLOOR','OR',5) "Instring in bytes" FROM DUAL;
SELECT INSTRB('CORPORATE FLOOR','OR') "Instring in bytes" FROM DUAL;

/*
 * replace
 */
SELECT REPLACE('JACK and JUE','J','BL') "Changes" FROM DUAL;
SELECT REPLACE('JACK and JUE','J') "Changes" FROM DUAL;


/*
 * REGEXP_COUNT
 */
set ivorysql.enable_emptystring_to_NULL to on;

SELECT REGEXP_COUNT(1231, 123::int2, 1::int2, 'c'::char) REGEXP_COUNT FROM DUAL;
SELECT REGEXP_COUNT(123123::int4, 2312::int4, 1::int4, 'cd') REGEXP_COUNT FROM DUAL;
SELECT REGEXP_COUNT(12312312312, 231, 1, 'c') REGEXP_COUNT FROM DUAL;
SELECT REGEXP_COUNT(1231.2312312312355, 1.23, 4.9, 'c') REGEXP_COUNT FROM DUAL;
SELECT REGEXP_COUNT('12312312312312355', '123', 4.9, 'c') REGEXP_COUNT FROM DUAL;
SELECT REGEXP_COUNT(123123123::int, 123::int, 4.9, 'c') REGEXP_COUNT FROM DUAL;

SELECT REGEXP_COUNT('ABCabcabcABCABC'::text, 'abc'::text, 3::int, 'c') COUNT FROM DUAL;
SELECT REGEXP_COUNT('ABCabcabcABCABC'::text, 'abc'::text, 3::int, 'i') COUNT FROM DUAL;
SELECT REGEXP_COUNT('ABCabcabcABCABC'::text, 'abc'::text, 6::int, 'i') COUNT FROM DUAL;
SELECT REGEXP_COUNT('ABCabcabcABCABC'::text, 'abcd'::text, 3::int, 'i') COUNT FROM DUAL;

SELECT REGEXP_COUNT('Abcdefg'::text, 'c'::varchar, 2, 'c') REGEXP_COUNT FROM DUAL;
SELECT REGEXP_COUNT('Abcdefg'::varchar2, 'c'::text, 2, 'c') REGEXP_COUNT FROM DUAL;
SELECT REGEXP_COUNT('Abcacdefg'::text, 'cd'::char, 2, 'c') REGEXP_COUNT FROM DUAL;
SELECT REGEXP_COUNT('Abcacdefg'::text, 'cd'::char(2), 2, 'c') REGEXP_COUNT FROM DUAL;
SELECT REGEXP_COUNT('Abcacdefg'::text, 'cd'::text, '2', 'c') REGEXP_COUNT FROM DUAL;

set datestyle to ISO,YMD;
alter session set NLS_TIMESTAMP_FORMAT='YYYY-MM-DD HH24.MI.SS.FF';
SELECT REGEXP_COUNT(to_date('2019-12-12','yy-MM-dd'), to_date('2019-12-12','yy-MM-dd'), 1.9::number, 'c'::char) REGEXP_COUNT FROM DUAL;
SELECT REGEXP_COUNT(to_date('2019-12-12','yy-MM-dd'), to_date('2019-12-12','yy-MM-dd'), 1::int, 'c'::char) REGEXP_COUNT FROM DUAL;
SELECT REGEXP_COUNT('2019-12-12 00:00:00'::timestamp, '2019-12-12 00:00:00'::timestamp, 1::int, 'c'::char) REGEXP_COUNT FROM DUAL;
reset NLS_TIMESTAMP_FORMAT;
SELECT REGEXP_COUNT('ABCabcabcABCABC', 'abc', 4, 'c') COUNT FROM DUAL;
SELECT REGEXP_COUNT('ABCabcabcABCABC', 'abc', 4) COUNT FROM DUAL;
SELECT REGEXP_COUNT('ABCabcabcABCABC', 'abc', 1, 'c') COUNT FROM DUAL;
SELECT REGEXP_COUNT('ABCabcabcABCABC', 'abc') COUNT FROM DUAL;

SELECT REGEXP_COUNT(null, null) COUNT FROM DUAL;
SELECT REGEXP_COUNT(null, null, null) COUNT FROM DUAL;
SELECT REGEXP_COUNT(null, null, null, null) COUNT FROM DUAL;

SELECT REGEXP_COUNT('', '') COUNT FROM DUAL;
SELECT REGEXP_COUNT(' ', ' ') COUNT FROM DUAL;

SELECT REGEXP_COUNT('', '', 0) COUNT FROM DUAL;
SELECT REGEXP_COUNT('', '', 0.99) COUNT FROM DUAL;
SELECT REGEXP_COUNT('', '', -0.9) COUNT FROM DUAL;
SELECT REGEXP_COUNT('', '', -100) COUNT FROM DUAL;
SELECT REGEXP_COUNT('', '', 100) COUNT FROM DUAL;
SELECT REGEXP_COUNT(' ', ' ', 0) COUNT FROM DUAL;
SELECT REGEXP_COUNT(' ', ' ', 0.99) COUNT FROM DUAL;
SELECT REGEXP_COUNT(' ', ' ', -0.9) COUNT FROM DUAL;
SELECT REGEXP_COUNT(' ', ' ', -100) COUNT FROM DUAL;
SELECT REGEXP_COUNT(' ', ' ', 100) COUNT FROM DUAL;

SELECT REGEXP_COUNT('', '', 1, '') COUNT FROM DUAL;
SELECT REGEXP_COUNT('', '', 1, ' ') COUNT FROM DUAL;
SELECT REGEXP_COUNT('', '', 1, '0') COUNT FROM DUAL;
SELECT REGEXP_COUNT('', '', 1, 'x') COUNT FROM DUAL;
SELECT REGEXP_COUNT('', '', 1, 'm') COUNT FROM DUAL;
SELECT REGEXP_COUNT('', '', 1, 'i') COUNT FROM DUAL;
SELECT REGEXP_COUNT('', '', 1, 'c') COUNT FROM DUAL;
SELECT REGEXP_COUNT('', '', 1, 'n') COUNT FROM DUAL;
SELECT REGEXP_COUNT('', '', 1, 't') COUNT FROM DUAL;
SELECT REGEXP_COUNT('', '', 1, 'dc') COUNT FROM DUAL;
SELECT REGEXP_COUNT('', '', 1, 'ie') COUNT FROM DUAL;
SELECT REGEXP_COUNT('', '', 1, '-100') COUNT FROM DUAL;
SELECT REGEXP_COUNT('', '', 1, '100') COUNT FROM DUAL;
SELECT REGEXP_COUNT('', '', 1, '1') COUNT FROM DUAL;

SELECT REGEXP_COUNT(' ', ' ', 1, ' ') COUNT FROM DUAL;
SELECT REGEXP_COUNT(' ', ' ', 1, '0') COUNT FROM DUAL;
SELECT REGEXP_COUNT(' ', ' ', 1, 'x') COUNT FROM DUAL;
SELECT REGEXP_COUNT(' ', ' ', 1, 'm') COUNT FROM DUAL;
SELECT REGEXP_COUNT(' ', ' ', 1, 'i') COUNT FROM DUAL;
SELECT REGEXP_COUNT(' ', ' ', 1, 'c') COUNT FROM DUAL;
SELECT REGEXP_COUNT(' ', ' ', 1, 'n') COUNT FROM DUAL;
SELECT REGEXP_COUNT(' ', ' ', 1, 't') COUNT FROM DUAL;
SELECT REGEXP_COUNT(' ', ' ', 1, 'dc') COUNT FROM DUAL;
SELECT REGEXP_COUNT(' ', ' ', 1, 'ie') COUNT FROM DUAL;
SELECT REGEXP_COUNT(' ', ' ', 1, '-100') COUNT FROM DUAL;
SELECT REGEXP_COUNT(' ', ' ', 1, '100') COUNT FROM DUAL;
SELECT REGEXP_COUNT(' ', ' ', 1, '1') COUNT FROM DUAL;

SELECT REGEXP_COUNT('ABCabcabcABCABC', 'abc', 0, 'c') COUNT FROM DUAL;
SELECT REGEXP_COUNT('ABCabcabcABCABC', 'abc', 4, 'gg') COUNT FROM DUAL;
SELECT REGEXP_COUNT('ABCabcabcABCABC', 'abc', 2147483648, 'c') COUNT FROM DUAL;
SELECT REGEXP_COUNT('ABCabcabcABCABC', 'abc', 4, 'o') COUNT FROM DUAL;

--20
select regexp_count('
hello
Hello.hello
good', '.', 1, 'i') from dual; 

--25
select regexp_count('
hello

Hello hello
good
','.',1,'n') from dual;

--1
select regexp_count('gooddd', '^', 1, 'm') from dual;

--4
select regexp_count('
hello
Hello.hello
good
', '^', 1, 'm') from dual;

--3
select regexp_count('hello
Hello.hello
good', '$', 1, 'm') from dual;

--23
select regexp_count('hello

Hello.hello
good', '.', 1, 'n') from dual;


/*
 * length
 */
alter session set nls_timestamp_format = 'YYYY-MM-DD HH24:MI:SS';
alter session set nls_date_format = 'YYYY-MM-DD HH24:MI:SS';

select length(192) from dual;
select length(cast(192 as int2)) from dual;
select length(cast(192 as int4)) from dual;
select length(cast(192 as int8)) from dual;
select length(192.922) from dual;
select length(cast(192.922 as numeric)) from dual;
select length('192') from dual;
select length('Highgo DB!') from dual;
select length('今天') from dual;
select sys.length('明天') from dual;
select length(cast('Highgo DB!' as char(10))) from dual;
select length(cast('Highgo DB!' as char(20))) from dual;
select length(cast('Highgo DB!' as varchar(20))) from dual;
select length(cast('Highgo DB!' as oravarcharchar(20))) from dual;
select length(cast('Highgo DB!' as oravarcharchar(20))) from dual;
select length(cast('Highgo DB!' as text)) from dual;
select length(cast('今天' as text)) from dual;
select length(cast('今天是Monday' as char(20))) from dual;
select length(cast('2019-12-12' as date)) from dual;
select length(cast('2019-12-12' as timestamp)) from dual;
select length(null) from dual;
select length('') from dual;
select length(' ') from dual;
select length(0::int) from dual;
select length(-2::int) from dual;
select length(123.14) from dual;
select length(cast('2020-06-18 14:40:20' as date)) from dual;
select length(cast('2020-06-18 14:40:20' as timestamp)) from dual;

/*
 * lengthb
 */
select lengthb(192) from dual;
--select lengthb(192::int2) from dual;
select lengthb(192::int4) from dual;
--select lengthb(192::int8) from dual;
select lengthb(192.922) from dual;
select lengthb(cast(192.922 as numeric)) from dual;
select lengthb(cast(192.922 as number)) from dual;
select lengthb('192') from dual;
select lengthb('Highgo DB!') from dual;
select lengthb('今天') from dual;
select lengthb(cast('Highgo DB!' as char(10))) from dual;
select lengthb(cast('Highgo DB!' as char(20))) from dual;
select lengthb(cast('Highgo DB!' as varchar(20))) from dual;
select lengthb(cast('Highgo DB!' as varchar2(20))) from dual;
--select lengthb('Highgo DB!'::nvarchar2(20)) from dual;
select lengthb(cast('Highgo DB!' as text)) from dual;
select lengthb(cast('今天' as text)) from dual;
select lengthb(cast('今天是Monday' as char(20))) from dual;
select lengthb(cast('2019-12-12' as date)) from dual;
select lengthb(cast('2019-12-12' as timestamp)) from dual;
select lengthb(null) from dual;
select lengthb('') from dual;
select lengthb(' ') from dual;
select lengthb(0::int) from dual;
select lengthb(-2::int) from dual;
select  lengthb(1234.123) from dual;
select lengthb(cast('2020-06-18 14:40:20' as date)) from dual;
select lengthb(cast('2020-06-18 14:40:20' as timestamp)) from dual;

/*
 * round
 */
select round(cast(1.234 as double precision), 2), trunc(cast(1.234 as double precision), 2) from dual;
select round(cast(1.234 as float), 2), trunc(cast(1.234 as float), 2) from dual;
select round(cast('1.2345' as oravarcharchar)), trunc(cast('1.2345' as oravarcharchar)) from dual;
select round(cast('1.2345' as oravarcharchar), 3), trunc(cast('1.2345' as oravarcharchar), 3) from dual;
select round(cast('1.2345' as oravarcharchar), 6), trunc(cast('1.2345' as oravarcharchar), 6) from dual;
select round(cast('-1.2345' as oravarcharchar)), trunc(cast('-1.2345' as oravarcharchar)) from dual;
select round(cast('-1.2345' as oravarcharchar), 3), trunc(cast('-1.2345' as oravarcharchar), 3) from dual;
select round(cast('-1.2345' as oravarcharbyte), 6), trunc(cast('-1.2345' as oravarcharbyte), 6) from dual;
select round(cast('12345.12345' as text), -1), trunc(cast('12345.12345' as text), -1) from dual;
select round('123456') from dual;

/*
 * trunc
 */
select trunc('123456') from dual;

/*
 * to_char
 */
select to_char(22) from dual;
select to_char(cast(99 as smallint)) from dual;
select to_char(-44444) from dual;
select to_char(cast(1234567890123456 as bigint)) from dual;
select to_char(cast(123.456 as real)) from dual;
select to_char(cast(1234.5678 as double precision)) from dual;
select to_char(cast(12345678901234567890 as numeric)) from dual;
select to_char(1234567890.12345) from dual;
select to_char(cast('4.00' as numeric)) from dual;
select to_char(cast('4.0010' as numeric)) from dual;
select to_char(cast('4.0010' as number)) from dual;
select to_char('4.0010') from dual;
set nls_date_format='YY-MonDD HH24:MI:SS';
select to_char(to_date('14-Jan08 11:44:49')) from dual;
set nls_date_format='YY-DDMon HH24:MI:SS';
select to_char(to_date('14-08Jan 11:44:49')) from dual;
set nls_date_format='DDMMYYYY HH24:MI:SS';
select to_char(to_date('21052014 12:13:44')) from dual;
set nls_date_format='DDMMYY HH24:MI:SS';
select to_char(to_date('210514 12:13:44')) from dual;
set nls_date_format='DDMMYYYY HH24:MI:SS';
select to_char(to_date('2014/04/25 10:13', 'YYYY/MM/DD HH:MI')) from dual;
set nls_date_format='YY-DDMon HH24:MI:SS';
select to_char(to_date('16-Feb-09 10:11:11', 'DD-Mon-YY HH:MI:SS')) from dual;
set nls_date_format='YY-DDMon HH24:MI:SS';
select to_char(to_date('02/16/09 04:12:12', 'MM/DD/YY HH24:MI:SS')) from dual;
set nls_date_format='YY-MonDD HH24:MI:SS';
select to_char(to_date('021609 111213', 'MMDDYY HHMISS')) from dual;
set nls_date_format='DDMMYYYY HH24:MI:SS';
select to_char(to_date('16-Feb-09 11:12:12', 'DD-Mon-YY HH:MI:SS')) from dual;
set nls_date_format='DDMMYYYY HH24:MI:SS';
select to_char(to_date('Feb/16/09 11:21:23', 'Mon/DD/YY HH:MI:SS')) from dual;
set nls_date_format='DDMMYYYY HH24:MI:SS';
select to_char(to_date('February.16.2009 10:11:12', 'Month.DD.YYYY HH:MI:SS')) from dual;
set nls_date_format='YY-MonDD HH24:MI:SS';
select to_char(to_date('20020315111212', 'yyyymmddhh12miss')) from dual;
set nls_date_format='DDMMYYYY HH24:MI:SS';
select to_char(to_date('January 15, 1989, 11:00 A.M.','Month dd, YYYY, HH:MI A.M.')) from dual;
set nls_date_format='DDMMYY HH24:MI:SS';
select to_char(to_date('14-Jan08 11:44:49' ,'YY-MonDD HH24:MI:SS')) from dual;
set nls_date_format='DDMMYYYY HH24:MI:SS';
select to_char(to_date('14-08Jan 11:44:49','YY-DDMon HH24:MI:SS')) from dual;
set nls_date_format='YY-MonDD HH24:MI:SS';
select to_char(to_date('21052014 12:13:44','DDMMYYYY HH24:MI:SS')) from dual;
set nls_date_format='DDMMYY HH24:MI:SS';
select to_char(to_date('210514 12:13:44','DDMMYY HH24:MI:SS')) from dual;
select to_char(1234567890123456) from dual;
select to_char(1234.123456789012) from dual;

/*
 * to_number
 */
SELECT to_number(cast('123' as text)) from dual;
SELECT to_number(cast('123.456' as text)) from dual;
SELECT to_number(123) from dual;
SELECT to_number(cast(123 as smallint)) from dual;
SELECT to_number(cast(123 as int)) from dual;
SELECT to_number(cast(123 as bigint)) from dual;
SELECT to_number(cast(123 as numeric)) from dual;
SELECT to_number(123.456) from dual;
SELECT to_number(1210.7, 9999.99) from dual;
SELECT to_number(1210.73, 9999.99) from dual;
SELECT to_number(1210.733, 9999.99) from dual; --err
SELECT to_number(cast(1210 as smallint), cast(9999 as smallint)) from dual;
SELECT to_number(cast(1210 as int), cast(9999 as int)) from dual;
SELECT to_number(cast(1210 as bigint), cast(9999 as bigint)) from dual;
SELECT to_number(cast(1210.73 as numeric), cast(9999.99 as numeric)) from dual;
--select to_number('$12345.67', '$99999999.99') from dual;
--select to_number('1,2,6,7,8', '99,99,99,9,999') from dual;
select to_number('1;2;6;7;8', '99,99,99,9,999') from dual; --error
select to_number('1.1,2,6,7,8', '9999,99,99,9,999') from dual; --error
select to_number('1.1,2,6,77,8', '9999,99,99,9,999') from dual; --error
select to_number(123) from dual;
SELECT to_number(12.34) from dual;

/*
 * instrb
 */
select instrb(1, 1) from dual;
select instrb('a', 1) from dual;
SELECT instrb(20121209, cast(12 as int), cast(1 as text), 2, 4) "instrb" FROM DUAL; --err
SELECT instrb(20121209, cast(12 as int), cast(1 as varchar2), '2') "instrb" FROM DUAL;
SELECT instrb(20121209, cast(12 as int), cast(1 as text), 2, '4', 5) "instrb" FROM DUAL; --err
SELECT instrb(20121209) "instrb" FROM DUAL;
SELECT instrb(20121209,12, 1, 2) "instrb" FROM DUAL;
SELECT instrb(20121209,12, 1) "instrb" FROM DUAL;
SELECT instrb(20121209,12) "instrb" FROM DUAL;
SELECT instrb(cast(2012 as int2), cast(12 as int2), cast(1 as int2), cast(2 as int2)) "instrb" FROM DUAL;
SELECT instrb(cast(2012 as int2), cast(12 as int2), cast(1 as int2)) "instrb" FROM DUAL;
SELECT instrb(cast(2012 as int2), cast(12 as int2)) "instrb" FROM DUAL;
SELECT instrb(cast(20121209 as int), cast(12 as int), cast(1.9 as int), cast(2.99 as int)) "instrb" FROM DUAL;
SELECT instrb(cast(20121209 as int), cast(12 as int), cast(1.9 as int)) "instrb" FROM DUAL;
SELECT instrb(cast(20121209 as int), cast(12 as int)) "instrb" FROM DUAL;
SELECT instrb(cast(20121212 as int8), cast(1212 as int8), cast(1.9 as int8), cast(1.99 as int8)) "instrb" FROM DUAL;
SELECT instrb(cast(20121212 as int8), cast(1212 as int8), cast(1.9 as int8)) "instrb" FROM DUAL;
SELECT instrb(cast(20121212 as int8), cast(1212 as int8)) "instrb" FROM DUAL;
SELECT instrb(cast(201212.09 as int),cast(12.9 as int), cast(1.9 as numeric), 2.99::numeric) "instrb" FROM DUAL;
SELECT instrb(cast(201212.12 as numeric),cast(12.12 as numeric), cast(1.9 as int), cast(1.99 as int)) "instrb" FROM DUAL;
SELECT instrb(cast(201212.12 as numeric),cast(12.12 as numeric), cast(1.9 as numeric), cast(1.99 as numeric)) "instrb" FROM DUAL;
SELECT instrb(cast(201212.12 as numeric),cast(12.12 as numeric), cast(1.9 as numeric)) "instrb" FROM DUAL;
SELECT instrb(cast(201212.12 as numeric),cast(12.12 as numeric)) "instrb" FROM DUAL;
SELECT instrb(null,null,null,null) FROM DUAL;
SELECT instrb(null,null,null) FROM DUAL;
SELECT instrb(null,null) FROM DUAL;
select instrb(1, 1) from dual;
select instrb('a', 1) from dual;

reset nls_timestamp_format;
reset nls_date_format;

select instrb(cast('2022-09-27' as date), 2) from dual;

/*
 * decode
 */
 
select  decode('b', null, 2018, 111) from dual; --expect:111
select  decode(1, null, 2018, 111, 2222, 3333, 22, 1, 99, 5) from dual; --expect:99
select  decode(null, 1, 2018, 111, 2222, 3333, 22, 1, 99, 5) from dual; --expect:5
select  decode(null, 1, 2018, 111, 2222, 3333, 22, 1, null, 5) from dual; --expect:5

create table test_decode(a int, b int);
insert into test_decode values(null, null);
select decode(a, b, 2018, 2, 3) from test_decode;
select decode(a, 1, 2018, b, 3) from test_decode;
select decode(a, 1, 2018, 2, 3, 4) from test_decode;
insert into test_decode values(1, 1);
insert into test_decode values(1, null);
insert into test_decode values(null, 1);
select * from test_decode;
select decode(a, b, 2018, 2, 3) from test_decode;
select decode(a, b, 2018, 1, 3) from test_decode;
select decode(a, null, 2018, 1, 3) from test_decode;
select decode(a, null, 2018, 2, 3) from test_decode;
select decode(null, a, 2018, 2, 3) from test_decode;
select decode(null, b, 2018, 2, 3) from test_decode;
select decode(null, null, 2018, 2, 3) from test_decode; --expect:all

drop table test_decode;


/*
 * asciistr
 */
  
 -- string with only ascii chars
 select asciistr('Hello, World!') from dual;
 select asciistr('Hello\nWorld') from dual;
 select asciistr('') from dual;

 -- string with non-ascii chars
 select asciistr('こんにちは') from dual;
 select asciistr('你好') from dual;
 select asciistr('😊👍') from dual;

 -- string with mixed ascii and non-ascii
 select asciistr('ABÄCDE') from dual;
 select asciistr('ABCÄÊ') from dual;
 select asciistr('ABCÕØ') from dual;
 select asciistr('ABCÄÊÍÕØ') from dual;
 select asciistr('Hello, こんにちは!') from dual;
 select asciistr('Café') from dual;
 select asciistr('Αλφάβητο') from dual;
 select asciistr('Привет') from dual;
